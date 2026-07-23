import { useRef } from "react";
import * as THREE from "three";
import { useFrame } from "@react-three/fiber";

// 航海士フェニックス「佇む海鳥」。アプリのツバメ紋章(冠羽の棘・三日月の翼・
// 燕尾・丸い目)を、甲板から水平線を見守る小さな相棒として3D化する。
// 品質言語は船と同じ(低ポリ+flatShading・フラット配色)。
// 原点=接地点(足元 y=0)、前方=+X(船の舳先と同じ向き)。全高≈1.4。
//
// ゲーム内のサイズ目安:
//  - HarborWorld の船(scale 0.45)の甲板に乗せる相棒なら scale 0.18〜0.22
//    (全高 0.25〜0.31 ≒ マストの半分弱。舳先寄り +0.6, デッキ上 y≈0.32 が座りが良い)
//  - BoatStudio のような単体ステージなら scale 0.8〜1.0
// 360度ビューアは URL ハッシュ #phoenix(PhoenixViewer.tsx)。

const CORAL = "#F0997B"; // 主羽色
const RUST = "#7A3B22"; // 濃い羽(冠羽・風切・燕尾)
const RUST_DEEP = "#4A1B0C"; // 嘴・脚
const SAND = "#EADEBD"; // 胸元・目の縁
const MIDNIGHT = "#1A1130"; // 目(紋章の目穴)
const EMBER = "#F5822A"; // returnOrange。胸元の熾火

/// 冠羽の基本の後傾。呼吸アニメはこの角度を中心に揺らす。
const CREST_TILT = 0.5;

/// 畳んだ翼のクレセント(側面プロフィール)。肩から尾へ流れる三日月を
/// 薄く押し出し、マントのように体側へ沿わせる。sx/syで羽層ごとの形を変える。
function makeWingGeometry(sx: number, sy: number, depth: number): THREE.BufferGeometry {
  const s = new THREE.Shape();
  s.moveTo(0.16, 0.1);
  s.quadraticCurveTo(-0.2, 0.16, -0.58, -0.18); // 上縁: 後方へ流れるスウィープ
  s.quadraticCurveTo(-0.24, -0.14, 0.0, -0.26); // 下縁: 内へ抉れる三日月
  s.quadraticCurveTo(0.2, -0.1, 0.16, 0.1); // 前縁(肩)の丸み
  const geo = new THREE.ExtrudeGeometry(s, {
    depth,
    steps: 1,
    curveSegments: 6,
    bevelEnabled: true,
    bevelThickness: 0.015,
    bevelSize: 0.015,
    bevelSegments: 1,
  });
  geo.translate(0, 0, -depth / 2);
  geo.scale(sx, sy, 1);
  geo.computeVertexNormals();
  return geo;
}

/// 燕尾の一叉。細身の刃を薄く押し出し、左右をヨーで交差させて
/// 燕尾服の裾のように背後へ流す。紋章の深い二叉に合わせて長めに。
function makeTailGeometry(): THREE.BufferGeometry {
  const s = new THREE.Shape();
  s.moveTo(0.02, 0.05);
  s.quadraticCurveTo(-0.36, 0.08, -0.72, -0.14); // 上縁: 先端へ流れる
  s.quadraticCurveTo(-0.34, -0.07, 0.02, -0.05); // 下縁: 根元へ戻る
  const geo = new THREE.ExtrudeGeometry(s, {
    depth: 0.03,
    steps: 1,
    curveSegments: 5,
    bevelEnabled: false,
  });
  geo.translate(0, 0, -0.015);
  return geo;
}

/// 水かき足。5角錐を前へ倒して平たく潰し、接地面(y=0)に載せる。
function makeFootGeometry(): THREE.BufferGeometry {
  const geo = new THREE.ConeGeometry(0.08, 0.18, 5);
  geo.rotateZ(-Math.PI / 2); // 先端を+Xへ
  geo.scale(1, 0.3, 1);
  geo.translate(0.05, 0.027, 0);
  return geo;
}

// ジオメトリと材質は色・状態に依存しないので、モジュール読み込み時に一度だけ作る。
const TORSO_GEO = new THREE.SphereGeometry(0.3, 9, 7);
const CHEST_GEO = new THREE.SphereGeometry(0.2, 8, 6);
const NECK_LOW_GEO = new THREE.CylinderGeometry(0.115, 0.16, 0.26, 7);
const NECK_HIGH_GEO = new THREE.CylinderGeometry(0.085, 0.115, 0.24, 7);
const HEAD_GEO = new THREE.SphereGeometry(0.155, 9, 7);
const CREST_GEO = new THREE.ConeGeometry(0.055, 0.34, 6);
const BEAK_GEO = new THREE.ConeGeometry(0.042, 0.16, 6);
const EYE_GEO = new THREE.SphereGeometry(0.038, 8, 6);
const EYE_RING_GEO = new THREE.TorusGeometry(0.046, 0.009, 5, 10);
const EMBER_GEO = new THREE.OctahedronGeometry(0.045, 0);
const LEG_GEO = new THREE.CylinderGeometry(0.032, 0.04, 0.26, 6);
const TAIL_BASE_GEO = new THREE.ConeGeometry(0.11, 0.24, 6);
const FOOT_GEO = makeFootGeometry();
const WING_MAIN_GEO = makeWingGeometry(1, 1, 0.05); // 雨覆(主層)
const WING_PRIM_GEO = makeWingGeometry(1.22, 0.62, 0.035); // 風切(長く細い層)
const WING_COVERT_GEO = makeWingGeometry(0.5, 0.52, 0.03); // 肩の小羽
const TAIL_GEO = makeTailGeometry();

const CORAL_MAT = new THREE.MeshStandardMaterial({
  color: CORAL,
  flatShading: true,
  roughness: 0.85,
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
  roughness: 0.9,
});
const EYE_MAT = new THREE.MeshStandardMaterial({
  color: MIDNIGHT,
  flatShading: true,
  roughness: 0.8,
});
// 胸元の熾火。ランタンと同じ、ごく小さなemissiveの一点(同時に1体なので共有で良い)。
const EMBER_MAT = new THREE.MeshStandardMaterial({
  color: EMBER,
  flatShading: true,
  roughness: 0.85,
  emissive: new THREE.Color(EMBER),
  emissiveIntensity: 0.75,
  fog: false,
});

/// 佇む海鳥の航海士。S字の首で頭を高く保ち、翼はマントのように畳み、
/// 燕尾は裾のように背後で交差する。呼吸の上下+尾の揺れ+冠羽の微動で
/// 「静かに水平線を見張っている」佇まいを作る。
export default function PhoenixModel({ animate = true }: { animate?: boolean }) {
  const body = useRef<THREE.Group>(null);
  const head = useRef<THREE.Group>(null);
  const tail = useRef<THREE.Group>(null);
  const crest = useRef<THREE.Mesh>(null);
  const wings = useRef<(THREE.Group | null)[]>([]);

  useFrame(({ clock }) => {
    if (!animate) return;
    const time = clock.elapsedTime;
    // 呼吸: 胴だけがゆっくり上下し、脚は甲板に植わったまま(重なりで吸収)。
    if (body.current) {
      body.current.position.y = Math.sin(time * 0.9) * 0.025;
      body.current.rotation.z = Math.sin(time * 0.9 + 0.6) * 0.012;
    }
    // 頭: 水平線をゆっくり見渡す小さな首振り。
    if (head.current) {
      head.current.rotation.y = Math.sin(time * 0.35) * 0.06;
      head.current.rotation.z = Math.sin(time * 0.9 + 1.8) * 0.02;
    }
    // 尾: 裾がわずかに流れる横揺れ。
    if (tail.current) tail.current.rotation.y = Math.sin(time * 0.7 + 1.0) * 0.05;
    // 冠羽: 風を受けるようなごく小さな前後の揺れ。
    if (crest.current) crest.current.rotation.z = CREST_TILT + Math.sin(time * 1.1) * 0.04;
    // 翼: 畳んだまま羽を締めたり緩めたりする微動(左右で位相をずらす)。
    for (let i = 0; i < wings.current.length; i++) {
      const w = wings.current[i];
      if (w) w.rotation.z = Math.sin(time * 0.8 + i * Math.PI) * 0.025;
    }
    // 熾火の脈動。
    EMBER_MAT.emissiveIntensity = 0.75 + Math.sin(time * 1.6) * 0.2;
  });

  return (
    <group>
      {/* 脚+水かき足(接地したまま動かない) */}
      {[1, -1].map((s) => (
        <group key={s} position={[0.04, 0, s * 0.09]}>
          <mesh geometry={LEG_GEO} material={RUST_DEEP_MAT} position={[0, 0.13, 0]} />
          <mesh geometry={FOOT_GEO} material={RUST_DEEP_MAT} position={[0.01, 0, 0]} />
        </group>
      ))}

      {/* 胴から上(呼吸で上下するまとまり) */}
      <group ref={body}>
        {/* 胴: 紡錘形。わずかに前傾して身を乗り出す */}
        <mesh
          geometry={TORSO_GEO}
          material={CORAL_MAT}
          position={[0, 0.6, 0]}
          rotation={[0, 0, -0.14]}
          scale={[1.2, 0.95, 0.88]}
        />
        {/* 胸当て: sandの明るい前掛け */}
        <mesh
          geometry={CHEST_GEO}
          material={SAND_MAT}
          position={[0.18, 0.5, 0]}
          scale={[1, 1.1, 0.85]}
        />
        {/* 喉元の熾火(不死鳥の灯。ランタンと同じ小さな一点) */}
        <mesh geometry={EMBER_GEO} material={EMBER_MAT} position={[0.3, 0.94, 0]} />

        {/* 首: 後傾→前傾の2節でS字を作り、頭を高く掲げる */}
        <mesh
          geometry={NECK_LOW_GEO}
          material={CORAL_MAT}
          position={[0.17, 0.94, 0]}
          rotation={[0, 0, 0.26]}
        />
        <mesh
          geometry={NECK_HIGH_GEO}
          material={CORAL_MAT}
          position={[0.15, 1.1, 0]}
          rotation={[0, 0, -0.3]}
        />

        {/* 頭(首振りのピボット) */}
        <group ref={head} position={[0.19, 1.2, 0]}>
          <mesh geometry={HEAD_GEO} material={CORAL_MAT} scale={[1.05, 1, 0.95]} />
          {/* 冠羽: 紋章の上向きの棘。後傾させて速度感を出す */}
          <mesh
            ref={crest}
            geometry={CREST_GEO}
            material={RUST_MAT}
            position={[-0.06, 0.13, 0]}
            rotation={[0, 0, CREST_TILT]}
          />
          {/* 嘴: 前方へ */}
          <mesh
            geometry={BEAK_GEO}
            material={RUST_DEEP_MAT}
            position={[0.2, -0.02, 0]}
            rotation={[0, 0, -Math.PI / 2]}
          />
          {/* 目: 紋章の丸い目穴。midnightの円+sandの細い縁を両側に */}
          {[1, -1].map((s) => (
            <group key={s}>
              <mesh
                geometry={EYE_GEO}
                material={EYE_MAT}
                position={[0.06, 0.05, s * 0.132]}
                scale={[1, 1, 0.5]}
              />
              <mesh
                geometry={EYE_RING_GEO}
                material={SAND_MAT}
                position={[0.06, 0.05, s * 0.142]}
              />
            </group>
          ))}
        </group>

        {/* 翼: 体側に畳んだ三日月のマント。雨覆→風切→肩の小羽の3層 */}
        {[1, -1].map((s, i) => (
          <group
            key={s}
            ref={(g) => {
              wings.current[i] = g;
            }}
            position={[0.1, 0.8, s * 0.235]}
            rotation={[s * -0.16, s * -0.12, 0]}
          >
            <mesh geometry={WING_MAIN_GEO} material={CORAL_MAT} />
            <mesh
              geometry={WING_PRIM_GEO}
              material={RUST_MAT}
              position={[-0.1, -0.05, s * -0.012]}
            />
            <mesh
              geometry={WING_COVERT_GEO}
              material={SAND_MAT}
              position={[0.06, 0.05, s * 0.03]}
              rotation={[0, 0, 0.1]}
            />
          </group>
        ))}

        {/* 尾(横揺れのピボット): 尾筒+交差する二叉の裾 */}
        <group ref={tail} position={[-0.26, 0.58, 0]}>
          <mesh
            geometry={TAIL_BASE_GEO}
            material={CORAL_MAT}
            position={[-0.09, 0.02, 0]}
            rotation={[0, 0, Math.PI / 2]}
          />
          <mesh
            geometry={TAIL_GEO}
            material={RUST_MAT}
            position={[0, 0, 0.035]}
            rotation={[0, -0.16, 0.55]}
          />
          <mesh
            geometry={TAIL_GEO}
            material={RUST_MAT}
            position={[0, -0.02, -0.035]}
            rotation={[0, 0.16, 0.62]}
          />
        </group>
      </group>
    </group>
  );
}
