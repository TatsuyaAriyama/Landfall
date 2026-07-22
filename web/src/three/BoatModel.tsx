import { useRef } from "react";
import * as THREE from "three";
import { useFrame } from "@react-three/fiber";
import type { BoatParts } from "../symbols";

// 船の3Dモデル。BoatStudio(船スタジオ)とVoyageScene(目的地の航海)で共有する。
// 低ポリ+flatShadingのフラットな質感で、2DのBoatSvgと同じ配色契約(boatProps)に従う。

const WOOD = "#5A2A15";

/// 舳先の上がった三日月型の船体。側面プロフィールを押し出し、
/// 端に向かって幅を絞って(plan view も船形に)低ポリの丸みはベベルで作る。
function makeHullGeometry(): THREE.BufferGeometry {
  const s = new THREE.Shape();
  s.moveTo(-1.02, 0.42); // 船尾の上端
  s.quadraticCurveTo(-1.2, 0.1, -0.88, -0.14); // 船尾の丸み
  s.quadraticCurveTo(-0.02, -0.46, 0.86, -0.14); // 竜骨
  s.quadraticCurveTo(1.18, 0.02, 1.32, 0.58); // 迫り上がる舳先
  s.lineTo(1.14, 0.58);
  s.quadraticCurveTo(0.18, 0.2, -1.02, 0.42); // 中央がたわむ舷縁
  const geo = new THREE.ExtrudeGeometry(s, {
    depth: 0.5,
    steps: 1,
    curveSegments: 9,
    bevelEnabled: true,
    bevelThickness: 0.22,
    bevelSize: 0.13,
    bevelSegments: 2,
  });
  geo.translate(0, 0, -0.25);
  // 端(舳先・船尾)へ向けて幅を絞り、上から見ても船形にする。
  const pos = geo.getAttribute("position");
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i);
    const n = Math.min(Math.max((Math.abs(x - 0.1) - 0.35) / 1.0, 0), 1);
    pos.setZ(i, pos.getZ(i) * (1 - 0.55 * n * n));
  }
  geo.computeVertexNormals();
  return geo;
}

/// 三角帆。まっすぐなラフ(前縁)+湾曲したリーチ(後縁)+中央の膨らみを
/// 粗いグリッドで作る。flatShadingで面が立ち、布の張りが出る。
function makeSailGeometry(
  width: number,
  height: number,
  bulge: number,
  shear: number,
): THREE.BufferGeometry {
  const cols = 7;
  const rows = 9;
  const positions: number[] = [];
  const indices: number[] = [];
  for (let r = 0; r <= rows; r++) {
    const v = r / rows;
    const w = width * (1 - v * 0.97); // 頂点へ向けて幅を絞る
    const leech = 1 + 0.18 * Math.sin(Math.PI * v); // 後縁のふくらみ
    for (let c = 0; c <= cols; c++) {
      const u = c / cols;
      positions.push(
        -shear * v - u * w * leech,
        v * height,
        bulge * Math.sin(Math.PI * u) * Math.sin(Math.PI * Math.min(v * 0.9 + 0.08, 1)),
      );
    }
  }
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const a = r * (cols + 1) + c;
      const b = a + 1;
      const d = a + cols + 1;
      indices.push(a, d, b, b, d, d + 1);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
  geo.setIndex(indices);
  geo.computeVertexNormals();
  return geo;
}

function makeFlagGeometry(kind: "pennant" | "swallow" | "kraken"): THREE.BufferGeometry {
  const s = new THREE.Shape();
  if (kind === "pennant") {
    s.moveTo(0, 0);
    s.lineTo(0, 0.22);
    s.lineTo(-0.5, 0.11);
  } else if (kind === "swallow") {
    s.moveTo(0, 0);
    s.lineTo(0, 0.22);
    s.lineTo(-0.52, 0.22);
    s.lineTo(-0.33, 0.11);
    s.lineTo(-0.52, 0);
  } else {
    // 港の試練の戦利品。触腕を思わせる、曲線の二叉。
    s.moveTo(0, 0);
    s.lineTo(0, 0.22);
    s.quadraticCurveTo(-0.36, 0.28, -0.56, 0.21);
    s.quadraticCurveTo(-0.36, 0.16, -0.27, 0.11);
    s.quadraticCurveTo(-0.36, 0.06, -0.56, 0.01);
    s.quadraticCurveTo(-0.36, -0.06, 0, 0);
  }
  s.closePath();
  return new THREE.ShapeGeometry(s);
}

// ジオメトリは色に依存しないので、モジュール読み込み時に一度だけ作る。
const HULL_GEO = makeHullGeometry();
const MAIN_SAIL_GEO = makeSailGeometry(1.0, 1.8, 0.16, 0);
const JIB_GEO = makeSailGeometry(0.72, 1.5, 0.1, 0.92);
const DECK_GEO = new THREE.CylinderGeometry(1, 1, 0.06, 14);
const MAST_GEO = new THREE.CylinderGeometry(0.035, 0.028, 2.3, 8);
const BOOM_GEO = new THREE.CylinderGeometry(0.024, 0.024, 1.15, 8);
const STRIPE_GEO = new THREE.TorusGeometry(1, 0.05, 8, 40);
const PENNANT_GEO = makeFlagGeometry("pennant");
const SWALLOW_GEO = makeFlagGeometry("swallow");
const KRAKEN_FLAG_GEO = makeFlagGeometry("kraken");
const KRAKEN_FLAG_EYE_GEO = new THREE.CircleGeometry(0.028, 8);

const FLAG_GEOS: Record<string, THREE.BufferGeometry> = {
  pennant: PENNANT_GEO,
  swallow: SWALLOW_GEO,
  kraken: KRAKEN_FLAG_GEO,
};
const FLAG_COLORS: Record<string, string> = {
  pennant: "#F5822A",
  swallow: "#F0997B",
  kraken: "#1A1130",
};

/// 船本体。ゆっくり上下+ロール+微ピッチで、錨泊中の揺れを再現する。
export default function BoatModel({ parts, animate }: { parts: BoatParts; animate: boolean }) {
  const sail = parts.sail ?? "#EADEBD";
  const jib = parts.jib ?? "#EADEBD";
  const hull = parts.hull ?? "#EADEBD";
  const stripe = parts.stripe ?? "none";
  const flag = parts.flag ?? "none";
  const deck = new THREE.Color(hull).multiplyScalar(0.72);
  const group = useRef<THREE.Group>(null);
  const flagGroup = useRef<THREE.Group>(null);

  useFrame(({ clock }) => {
    if (!animate) return;
    const time = clock.elapsedTime;
    const g = group.current;
    if (g) {
      g.position.y = Math.sin(time * 0.8) * 0.06;
      g.rotation.z = Math.sin(time * 0.6) * 0.03;
      g.rotation.x = Math.sin(time * 0.5 + 1.2) * 0.015;
    }
    if (flagGroup.current) flagGroup.current.rotation.y = Math.sin(time * 5.2) * 0.22;
  });

  return (
    <group ref={group}>
      {/* 船体 */}
      <mesh geometry={HULL_GEO}>
        <meshStandardMaterial color={hull} flatShading roughness={0.85} />
      </mesh>
      {/* デッキ(少し暗い同系色の薄い蓋) */}
      <mesh geometry={DECK_GEO} position={[0.05, 0.47, 0]} scale={[0.82, 1, 0.3]}>
        <meshStandardMaterial color={deck} flatShading roughness={0.9} />
      </mesh>
      {/* マスト */}
      <mesh geometry={MAST_GEO} position={[0.1, 1.42, 0]}>
        <meshStandardMaterial color={WOOD} flatShading roughness={0.8} />
      </mesh>
      {/* ブーム+メインセイル(わずかに開いたトリム) */}
      <group position={[0.1, 0, 0]} rotation={[0, 0.16, 0]}>
        <mesh geometry={BOOM_GEO} position={[-0.55, 0.68, 0]} rotation={[0, 0, Math.PI / 2]}>
          <meshStandardMaterial color={WOOD} flatShading roughness={0.8} />
        </mesh>
        <mesh geometry={MAIN_SAIL_GEO} position={[0, 0.72, 0]}>
          <meshStandardMaterial
            color={sail}
            flatShading
            roughness={0.95}
            side={THREE.DoubleSide}
          />
        </mesh>
      </group>
      {/* ジブ(前帆): 舳先からマスト頂へ斜めのラフ */}
      <mesh geometry={JIB_GEO} position={[1.1, 0.62, 0]} rotation={[0, 0.12, 0]}>
        <meshStandardMaterial color={jib} flatShading roughness={0.95} side={THREE.DoubleSide} />
      </mesh>
      {/* 船体のライン(喫水近くの細い帯) */}
      {stripe !== "none" && (
        <mesh
          geometry={STRIPE_GEO}
          position={[0.06, 0.2, 0]}
          rotation={[Math.PI / 2, 0, 0]}
          scale={[0.93, 0.47, 0.5]}
        >
          <meshStandardMaterial color={stripe} flatShading roughness={0.85} />
        </mesh>
      )}
      {/* 旗(マスト頂ではためく) */}
      {flag in FLAG_GEOS && (
        <group ref={flagGroup} position={[0.1, 2.34, 0]}>
          <mesh geometry={FLAG_GEOS[flag]}>
            <meshStandardMaterial
              color={FLAG_COLORS[flag]}
              flatShading
              roughness={0.9}
              side={THREE.DoubleSide}
            />
          </mesh>
          {/* 海獣の旗には returnOrange の小さな目を添える(2Dの図案と同じ) */}
          {flag === "kraken" && (
            <mesh geometry={KRAKEN_FLAG_EYE_GEO} position={[-0.12, 0.11, 0.002]}>
              <meshBasicMaterial color="#F5822A" side={THREE.DoubleSide} />
            </mesh>
          )}
        </group>
      )}
    </group>
  );
}
