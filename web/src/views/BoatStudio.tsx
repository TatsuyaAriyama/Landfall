import { useRef, useState } from "react";
import * as THREE from "three";
import { Canvas, useFrame } from "@react-three/fiber";
import { OrbitControls, Stars } from "@react-three/drei";
import type { UserData } from "../data";
import type { BoatParts } from "../symbols";
import {
  BOAT_OPTIONS,
  boatPartId,
  boatProps,
  setBoatPart,
  totalMinutes,
  type BoatPart,
} from "../boat";
import { lang, t, unlockAtLabel, type I18nKey } from "../i18n";

// 船スタジオ。夜の海に浮かぶ自分の船を、three.jsで360度眺めながら着せ替える。
// 低ポリ+flatShadingのフラットな質感で、2DのBoatSvgと同じ配色契約(boatProps)に従う。

const NIGHT_BG = "#123830";
const SEA_COLOR = "#1E5348";
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

function makeFlagGeometry(kind: "pennant" | "swallow"): THREE.BufferGeometry {
  const s = new THREE.Shape();
  if (kind === "pennant") {
    s.moveTo(0, 0);
    s.lineTo(0, 0.22);
    s.lineTo(-0.5, 0.11);
  } else {
    s.moveTo(0, 0);
    s.lineTo(0, 0.22);
    s.lineTo(-0.52, 0.22);
    s.lineTo(-0.33, 0.11);
    s.lineTo(-0.52, 0);
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
const MOON_GEO = new THREE.SphereGeometry(1.1, 20, 14);
const SEA_GEO = new THREE.CircleGeometry(30, 48);
const RIPPLE_GEO = new THREE.RingGeometry(0.9, 1.0, 48);

/// 船本体。ゆっくり上下+ロール+微ピッチで、錨泊中の揺れを再現する。
function BoatModel({ parts, animate }: { parts: BoatParts; animate: boolean }) {
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
      {(flag === "pennant" || flag === "swallow") && (
        <group ref={flagGroup} position={[0.1, 2.34, 0]}>
          <mesh geometry={flag === "pennant" ? PENNANT_GEO : SWALLOW_GEO}>
            <meshStandardMaterial
              color={flag === "pennant" ? "#F5822A" : "#F0997B"}
              flatShading
              roughness={0.9}
              side={THREE.DoubleSide}
            />
          </mesh>
        </group>
      )}
    </group>
  );
}

/// 波紋。船の周りをゆっくり広がって消えるリングを、位相をずらして3つ。
const RIPPLE_COUNT = 3;
const RIPPLE_PERIOD = 7;

function Ripples({ animate }: { animate: boolean }) {
  const meshes = useRef<(THREE.Mesh | null)[]>([]);
  const mats = useRef<(THREE.MeshBasicMaterial | null)[]>([]);

  useFrame(({ clock }) => {
    if (!animate) return;
    for (let i = 0; i < RIPPLE_COUNT; i++) {
      const mesh = meshes.current[i];
      const mat = mats.current[i];
      if (!mesh || !mat) continue;
      const phase = (clock.elapsedTime / RIPPLE_PERIOD + i / RIPPLE_COUNT) % 1;
      const s = 0.8 + phase * 5.5;
      mesh.scale.set(s, s, 1);
      mat.opacity = Math.sin(Math.min(phase * 3, 1) * (Math.PI / 2)) * (1 - phase) * 0.2;
    }
  });

  return (
    <group>
      {Array.from({ length: RIPPLE_COUNT }, (_, i) => (
        <mesh
          key={i}
          ref={(m) => {
            meshes.current[i] = m;
          }}
          geometry={RIPPLE_GEO}
          rotation={[-Math.PI / 2, 0, 0]}
          position={[0, 0.02 + i * 0.004, 0]}
          scale={[1.5 + i * 1.6, 1.5 + i * 1.6, 1]}
        >
          <meshBasicMaterial
            ref={(m) => {
              mats.current[i] = m;
            }}
            color="#7FB8A6"
            transparent
            opacity={0.12 - i * 0.03}
            depthWrite={false}
          />
        </mesh>
      ))}
    </group>
  );
}

/// 夜の海のシーン一式。背景・霧・星・月・海・波紋・船・カメラ操作。
function NightSea({ parts, animate }: { parts: BoatParts; animate: boolean }) {
  const [autoRotate, setAutoRotate] = useState(true);
  return (
    <>
      <color attach="background" args={[NIGHT_BG]} />
      <fog attach="fog" args={[NIGHT_BG, 11, 30]} />
      {/* 月光: sand色のdirectional+暖色の弱いambient+海色の弱いfill。影は使わない。 */}
      <ambientLight color="#ffe9c8" intensity={0.45} />
      <directionalLight color="#EADEBD" intensity={1.15} position={[-6, 8, -5]} />
      <directionalLight color="#5DCAA5" intensity={0.2} position={[5, 3, 6]} />
      <Stars
        radius={42}
        depth={18}
        count={900}
        factor={2.2}
        saturation={0}
        fade
        speed={animate ? 0.6 : 0}
      />
      {/* 月(遠景の発光球。霧に沈まないようfogを切る) */}
      <mesh geometry={MOON_GEO} position={[-8.5, 5.6, -14]}>
        <meshStandardMaterial
          color={NIGHT_BG}
          emissive="#EADEBD"
          emissiveIntensity={0.95}
          fog={false}
        />
      </mesh>
      {/* 海(大きな円盤。縁は霧で夜に溶ける) */}
      <mesh geometry={SEA_GEO} rotation={[-Math.PI / 2, 0, 0]}>
        <meshBasicMaterial color={SEA_COLOR} />
      </mesh>
      <Ripples animate={animate} />
      <BoatModel parts={parts} animate={animate} />
      <OrbitControls
        target={[0, 0.7, 0]}
        enablePan={false}
        enableDamping
        minDistance={3.4}
        maxDistance={9}
        minPolarAngle={Math.PI * 0.18}
        maxPolarAngle={Math.PI * 0.52}
        autoRotate={autoRotate && animate}
        autoRotateSpeed={0.6}
        onStart={() => setAutoRotate(false)}
      />
    </>
  );
}

/// 船タブ。上が3Dステージ、下が部位ごとのカスタマイズ。
export default function BoatStudio({ data }: { data: UserData }) {
  const [, setTick] = useState(0);
  const [animate] = useState(
    () => !window.matchMedia("(prefers-reduced-motion: reduce)").matches,
  );
  const total = totalMinutes(data.sessions);
  const totalLabel =
    lang === "ja" ? `${Math.floor(total / 60)}時間` : `${Math.floor(total / 60)}h`;
  const parts = boatProps();

  return (
    <div>
      <h1 className="page-title">{t("boatStudioTitle")}</h1>
      <div className="boat-studio-stage">
        <Canvas
          dpr={[1, 2]}
          frameloop={animate ? "always" : "demand"}
          camera={{ position: [3.1, 1.7, 4.3], fov: 40 }}
        >
          <NightSea parts={parts} animate={animate} />
        </Canvas>
      </div>
      <p className="boat-studio-hint">{t("boatHint")}</p>
      <p className="boat-studio-total">
        {t("totalVoyage")}: {totalLabel}
      </p>
      {(
        [
          ["sail", "sailColor"],
          ["jib", "jibLabel"],
          ["hull", "hullLabel"],
          ["stripe", "stripeLabel"],
          ["flag", "flagLabel"],
        ] as [BoatPart, I18nKey][]
      ).map(([part, labelKey]) => (
        <div key={part}>
          <p className="row-sub" style={{ margin: "14px 0 6px" }}>
            {t(labelKey)}
          </p>
          <div className="chip-row">
            {BOAT_OPTIONS[part].map((o) => {
              const locked = total < o.unlockMinutes;
              const selected = boatPartId(part) === o.id;
              if (o.color) {
                return (
                  <button
                    key={o.id}
                    className={`swatch${selected ? " selected" : ""}`}
                    style={{ background: o.color, opacity: locked ? 0.3 : 1 }}
                    disabled={locked}
                    title={locked ? unlockAtLabel(o.unlockMinutes / 60) : o.id}
                    onClick={() => {
                      setBoatPart(part, o.id);
                      setTick((n) => n + 1);
                    }}
                    aria-label={o.id}
                  />
                );
              }
              const label = t(
                (o.id === "none"
                  ? "flagNone"
                  : o.id === "pennant"
                    ? "flagPennant"
                    : "flagSwallow") as I18nKey,
              );
              return (
                <button
                  key={o.id}
                  className={`chip${selected ? " selected" : ""}`}
                  disabled={locked}
                  style={locked ? { opacity: 0.4 } : undefined}
                  onClick={() => {
                    setBoatPart(part, o.id);
                    setTick((n) => n + 1);
                  }}
                >
                  {label}
                  {locked ? ` · ${unlockAtLabel(o.unlockMinutes / 60)}` : ""}
                </button>
              );
            })}
          </div>
        </div>
      ))}
    </div>
  );
}
