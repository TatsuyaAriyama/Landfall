import { useEffect, useMemo, useRef } from "react";
import * as THREE from "three";
import { useFrame } from "@react-three/fiber";

// 航海士フェニックス(プレイヤーキャラクター)。
// 紋章を「体」ではなく「衣装のモチーフ」として着せた、小さな旅の航海士:
//  - 尖ったフード = 紋章の冠羽
//  - 燕尾のケープ = 紋章の翼と二叉の尾(背中に紋章のシルエットが宿る)
//  - 胸の留め具   = 紋章の丸い目穴(sandの環+midnightの芯)
//  - 手に提げるランタン = この世界の「今日の灯」
// フードの闇に sand の両目が灯る。体は低ポリの体積で作り、どの角度でも成立する。
// 品質言語は船と同じ(低ポリ+flatShading・フラット配色・影なし)。
//
// 原点=接地点(足元 y=0)、前方=+X(船の舳先と同じ向き)。全高≈1.35。
//
// ゲーム内のサイズ目安:
//  - HarborWorld の船(scale 0.45)の甲板に立たせるなら scale 0.20〜0.24
//    (全高 0.27〜0.32 ≒ マストの半分弱。舳先寄り +0.6, デッキ上 y≈0.32)
//  - BoatStudio のような単体ステージなら scale 0.9〜1.1
// 首・両肩・ケープ・ランタンはピボットグループ — 将来の歩行・手振りにも使える。
// 360度ビューアは URL ハッシュ #phoenix(PhoenixViewer.tsx)。

const CORAL = "#F0997B"; // コート・ケープ・フード(紋章の主色)
const RUST = "#7A3B22"; // 深い錆(コートの裾陰・ランタンの枠)
const RUST_DEEP = "#4A1B0C"; // ブーツ・手袋
const SAND = "#EADEBD"; // 襟巻き・目・留め具の環
const MIDNIGHT = "#1A1130"; // フードの闇(顔)・留め具の芯
const LANTERN = "#F3C065"; // ランタンの灯(船のランタンと同色)

// ---- マント(布の格子メッシュ) ----
// 紋章の背景色(midnight)の一枚布。押し出し板ではなく、肩から垂れる
// パラメトリックな格子を毎フレーム波で変位させて「ひらひらと靡く」を作る。
// マントだけはスムースシェーディング(flatShading無し)で、ポリゴンの
// 角を見せない。裾は紋章の名残 — 左右の翼の先端が長く、中央が浅い燕尾。

const CAPE_ROWS = 16; // 縦(肩→裾)
const CAPE_COLS = 13; // 横(左端→右端)

/// マントの一点。u:-1..1(左→右)、v:0..1(肩→裾)。
/// out に位置を書き込む。time で裾ほど大きく波打つ。
function capePoint(
  u: number,
  v: number,
  time: number,
  out: { x: number; y: number; z: number },
) {
  const width = 0.16 + 0.21 * Math.pow(v, 1.15); // 裾へ向かって広がる
  const length = 0.38 + 0.19 * Math.pow(Math.abs(u), 1.4); // 端が長い=燕尾の裾
  const flutter = Math.pow(v, 1.5); // 肩は固定、裾ほど自由に
  out.x = u * width + flutter * Math.sin(time * 1.3 + v * 2.0) * 0.02;
  out.y = -v * length + flutter * Math.sin(u * 2.4 + time * 1.9) * 0.012;
  out.z =
    -0.02 -
    0.24 * Math.pow(v, 1.1) + // コートの背面より外側を通って後ろへ膨らむ基本カーブ
    flutter *
      (Math.sin(v * 5.2 - time * 2.1) * 0.05 + Math.sin(u * 2.6 + time * 1.5) * 0.04);
}

/// マントの格子ジオメトリ(位置は後で capeUpdate が書く)。
function buildCapeGeometry(): THREE.BufferGeometry {
  const geo = new THREE.BufferGeometry();
  const positions = new Float32Array(CAPE_ROWS * CAPE_COLS * 3);
  geo.setAttribute("position", new THREE.BufferAttribute(positions, 3));
  const indices: number[] = [];
  for (let r = 0; r < CAPE_ROWS - 1; r++) {
    for (let c = 0; c < CAPE_COLS - 1; c++) {
      const a = r * CAPE_COLS + c;
      const b = a + 1;
      const d = a + CAPE_COLS;
      const e = d + 1;
      indices.push(a, d, b, b, d, e);
    }
  }
  geo.setIndex(indices);
  return geo;
}

const capeScratch = { x: 0, y: 0, z: 0 };

/// マントの全頂点を時刻 time の波で書き直す(168頂点なので毎フレームでも軽い)。
function updateCape(geo: THREE.BufferGeometry, time: number) {
  const attr = geo.getAttribute("position") as THREE.BufferAttribute;
  let i = 0;
  for (let r = 0; r < CAPE_ROWS; r++) {
    const v = r / (CAPE_ROWS - 1);
    for (let c = 0; c < CAPE_COLS; c++) {
      const u = (c / (CAPE_COLS - 1)) * 2 - 1;
      capePoint(u, v, time, capeScratch);
      attr.setXYZ(i++, capeScratch.x, capeScratch.y, capeScratch.z);
    }
  }
  attr.needsUpdate = true;
  geo.computeVertexNormals();
}

/// コート。裾へ向かって広がる袍(ローブ)。低ポリのラースで体積を出す。
function makeCoatGeometry(): THREE.BufferGeometry {
  const pts = [
    new THREE.Vector2(0.235, 0.3),
    new THREE.Vector2(0.205, 0.44),
    new THREE.Vector2(0.165, 0.62),
    new THREE.Vector2(0.135, 0.78),
    new THREE.Vector2(0.105, 0.92),
  ];
  return new THREE.LatheGeometry(pts, 9);
}

// ジオメトリと材質は状態に依存しないので、モジュール読み込み時に一度だけ作る
// (マントだけは毎フレーム頂点を書くため、コンポーネント内で個別に作る)。
const COAT_GEO = makeCoatGeometry();
const CHEST_GEO = new THREE.SphereGeometry(0.13, 9, 7);
const HOOD_GEO = new THREE.ConeGeometry(0.125, 0.3, 8);
const FACE_GEO = new THREE.SphereGeometry(0.075, 8, 6);
const EYE_GEO = new THREE.SphereGeometry(0.015, 6, 5);
const SCARF_GEO = new THREE.TorusGeometry(0.105, 0.034, 6, 9);
const ARM_GEO = new THREE.CylinderGeometry(0.038, 0.046, 0.3, 7);
const HAND_GEO = new THREE.SphereGeometry(0.052, 7, 6);
const LEG_GEO = new THREE.CylinderGeometry(0.048, 0.055, 0.24, 7);
const BOOT_GEO = new THREE.SphereGeometry(0.085, 8, 6);
const CLASP_RING_GEO = new THREE.TorusGeometry(0.036, 0.011, 5, 10);
const CLASP_PIN_GEO = new THREE.CylinderGeometry(0.019, 0.019, 0.02, 8);
// ランタンは開放型(上蓋+灯+底皿)。灯が枠に隠れず、どの角度からも見える。
const LANTERN_CAP_GEO = new THREE.ConeGeometry(0.058, 0.05, 6);
const LANTERN_BASE_GEO = new THREE.CylinderGeometry(0.045, 0.05, 0.02, 6);
const LANTERN_GLOW_GEO = new THREE.SphereGeometry(0.042, 8, 6);
const LANTERN_HANDLE_GEO = new THREE.CylinderGeometry(0.008, 0.008, 0.06, 5);

const CORAL_MAT = new THREE.MeshStandardMaterial({
  color: CORAL,
  flatShading: true,
  roughness: 0.8,
});
const RUST_MAT = new THREE.MeshStandardMaterial({
  color: RUST,
  flatShading: true,
  roughness: 0.85,
});
const RUST_DEEP_MAT = new THREE.MeshStandardMaterial({
  color: RUST_DEEP,
  flatShading: true,
  roughness: 0.9,
});
const SAND_MAT = new THREE.MeshStandardMaterial({
  color: SAND,
  flatShading: true,
  roughness: 0.85,
});
const FACE_MAT = new THREE.MeshStandardMaterial({
  color: MIDNIGHT,
  flatShading: true,
  roughness: 0.6,
});
/// マント: 紋章の背景色。布だけはスムースシェーディング+両面描画で、
/// 角のないひらひらとした流れを見せる。
const CAPE_MAT = new THREE.MeshStandardMaterial({
  color: MIDNIGHT,
  flatShading: false,
  roughness: 0.9,
  side: THREE.DoubleSide,
});
/// フードの闇に灯る両目。夜でも読めるよう、ごく弱い自照を持たせる。
const EYE_MAT = new THREE.MeshStandardMaterial({
  color: SAND,
  flatShading: true,
  roughness: 0.7,
  emissive: new THREE.Color(SAND),
  emissiveIntensity: 0.55,
  fog: false,
});
/// ランタンの灯。船のランタンと同じ色・同じゆらぎ(同時に1体なので共有で良い)。
const LANTERN_GLOW_MAT = new THREE.MeshStandardMaterial({
  color: LANTERN,
  flatShading: true,
  roughness: 0.8,
  emissive: new THREE.Color(LANTERN),
  emissiveIntensity: 1.5,
  fog: false,
});

/// 小さな航海士。ローブの体積+燕尾のケープ+尖ったフード+提げたランタンで、
/// 「夜の海を渡ってきた旅の相棒」を2.5頭身に凝縮する。
/// 待機: 呼吸、ケープと襟巻きの揺れ、水平線を見渡す首、ランタンの振り子。
export default function PhoenixModel({ animate = true }: { animate?: boolean }) {
  const core = useRef<THREE.Group>(null); // ブーツ以外(呼吸)
  const head = useRef<THREE.Group>(null);
  const armR = useRef<THREE.Group>(null);
  const armL = useRef<THREE.Group>(null);
  const lantern = useRef<THREE.Group>(null);

  // マントの布。頂点を毎フレーム書くのでインスタンスごとに持ち、離れる時に破棄する。
  const capeGeo = useMemo(() => {
    const geo = buildCapeGeometry();
    updateCape(geo, 0); // 静止時(reduced-motion)もこの初期形で成立させる
    return geo;
  }, []);
  useEffect(() => () => capeGeo.dispose(), [capeGeo]);

  useFrame(({ clock }) => {
    if (!animate) return;
    const time = clock.elapsedTime;
    // マント: 布の波。裾ほど大きく靡く。
    updateCape(capeGeo, time);
    // 呼吸: 体だけがゆっくり上下。足は甲板に植わったまま(重なりで吸収)。
    if (core.current) {
      core.current.position.y = Math.sin(time * 0.85) * 0.018;
      core.current.rotation.x = Math.sin(time * 0.85 + 0.9) * 0.01;
    }
    // 首: 水平線をゆっくり見渡す。
    if (head.current) {
      head.current.rotation.y = Math.sin(time * 0.3) * 0.14;
      head.current.rotation.z = Math.sin(time * 0.85 + 2.1) * 0.02;
    }
    // 腕: わずかな重心移動。右腕はランタンの重みでほんの少し遅れる。
    if (armR.current) armR.current.rotation.x = Math.sin(time * 0.85 + 0.4) * 0.03;
    if (armL.current) armL.current.rotation.x = Math.sin(time * 0.85 + 1.1) * 0.025;
    // ランタン: 手元から下がる振り子。灯は船のランタンと同じゆらぎ。
    if (lantern.current) {
      lantern.current.rotation.x = Math.sin(time * 0.9) * 0.1;
      lantern.current.rotation.z = Math.sin(time * 0.7 + 0.6) * 0.12;
    }
    LANTERN_GLOW_MAT.emissiveIntensity = 1.5 + Math.sin(time * 2.1) * 0.3;
  });

  return (
    // 形は正面=+Zで組み、グループごと+X向きへ(船の舳先と同じ向き)。
    <group rotation={[0, Math.PI / 2, 0]}>
      {/* 脚+ブーツ(接地したまま動かない)。裾に隠れる短い脚 */}
      {[1, -1].map((s) => (
        <group key={s} position={[s * 0.085, 0, 0.01]}>
          <mesh geometry={LEG_GEO} material={RUST_DEEP_MAT} position={[0, 0.21, 0]} />
          <mesh
            geometry={BOOT_GEO}
            material={RUST_DEEP_MAT}
            position={[0, 0.055, 0.02]}
            scale={[1.05, 0.6, 1.3]}
          />
        </group>
      ))}

      {/* 体(呼吸のまとまり) */}
      <group ref={core}>
        {/* コート: 裾へ広がる袍。裾の内側に深錆の縁で重さを出す */}
        <mesh geometry={COAT_GEO} material={CORAL_MAT} />
        <mesh geometry={COAT_GEO} material={RUST_MAT} position={[0, -0.02, 0]} scale={[0.97, 0.35, 0.97]} />
        {/* 肩・胸 */}
        <mesh geometry={CHEST_GEO} material={CORAL_MAT} position={[0, 0.9, 0]} scale={[1.1, 0.78, 1.05]} />
        {/* 留め具: 紋章の丸い目穴(sandの環+midnightの芯) */}
        <group position={[0, 0.885, 0.148]}>
          <mesh geometry={CLASP_RING_GEO} material={SAND_MAT} />
          <mesh geometry={CLASP_PIN_GEO} material={FACE_MAT} rotation={[Math.PI / 2, 0, 0]} />
        </group>

        {/* 襟巻き: sandの環+背に垂れる端 */}
        <mesh geometry={SCARF_GEO} material={SAND_MAT} position={[0, 0.96, 0]} rotation={[Math.PI / 2 + 0.08, 0, 0]} />

        {/* マント: 紋章の背景色の一枚布。肩に固定され、裾ほど自由に靡く
            (波は updateCape が毎フレーム頂点へ書く) */}
        <mesh geometry={capeGeo} material={CAPE_MAT} position={[0, 0.93, -0.04]} />

        {/* 頭(首振りのピボット): 頭サイズの尖ったフード=紋章の冠羽。
            開口部の闇に両目が灯る */}
        <group ref={head} position={[0, 0.98, 0]}>
          <mesh geometry={HOOD_GEO} material={CORAL_MAT} position={[0, 0.12, 0]} rotation={[-0.05, 0, 0]} />
          <mesh geometry={FACE_GEO} material={FACE_MAT} position={[0, 0.045, 0.062]} scale={[1, 1.1, 0.55]} />
          {[1, -1].map((s) => (
            <mesh
              key={s}
              geometry={EYE_GEO}
              material={EYE_MAT}
              position={[s * 0.028, 0.052, 0.099]}
            />
          ))}
        </group>

        {/* 左腕: 体側に添えて休める */}
        <group ref={armL} position={[-0.15, 0.87, 0.01]} rotation={[0, 0, -0.16]}>
          <mesh geometry={ARM_GEO} material={CORAL_MAT} position={[0, -0.14, 0]} />
          <mesh geometry={HAND_GEO} material={RUST_DEEP_MAT} position={[0, -0.31, 0]} />
        </group>

        {/* 右腕+ランタン: 「今日の灯」を提げる */}
        <group ref={armR} position={[0.15, 0.87, 0.01]} rotation={[0, 0, 0.16]}>
          <mesh geometry={ARM_GEO} material={CORAL_MAT} position={[0, -0.14, 0]} />
          <mesh geometry={HAND_GEO} material={RUST_DEEP_MAT} position={[0, -0.31, 0]} />
          <group ref={lantern} position={[0, -0.36, 0]}>
            <mesh geometry={LANTERN_HANDLE_GEO} material={RUST_MAT} position={[0, -0.03, 0]} />
            <mesh geometry={LANTERN_CAP_GEO} material={RUST_MAT} position={[0, -0.075, 0]} />
            <mesh geometry={LANTERN_GLOW_GEO} material={LANTERN_GLOW_MAT} position={[0, -0.14, 0]} />
            <mesh geometry={LANTERN_BASE_GEO} material={RUST_MAT} position={[0, -0.19, 0]} />
          </group>
        </group>
      </group>
    </group>
  );
}
