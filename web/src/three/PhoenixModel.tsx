import { useRef } from "react";
import * as THREE from "three";
import { useFrame } from "@react-three/fiber";

// 航海士フェニックス(人型)。アプリの不死鳥の紋章をそのまま立てた、
// 生きた紋章のようなキャラクター — 上の棘=頭、三日月の翼=腕、下の二叉=脚。
// 紙のように薄く鋭いシルエットを保ち、丸い目穴は頭を貫くmidnightの円として
// どの角度からも読めるようにする。品質言語は船と同じ(低ポリ+flatShading)。
//
// 原点=接地点(足先 y=0)、前方=+X(船の舳先と同じ向き)。全高≈1.3。
//
// ゲーム内のサイズ目安:
//  - HarborWorld の船(scale 0.45)の甲板に立たせるなら scale 0.20〜0.24
//    (全高 0.26〜0.31 ≒ マストの半分弱。舳先寄り +0.6, デッキ上 y≈0.32)
//  - BoatStudio のような単体ステージなら scale 0.9〜1.1
// 関節は肩・首・脚をグループのピボットで持ち、将来の歩行・手振りにも使える。
// 360度ビューアは URL ハッシュ #phoenix(PhoenixViewer.tsx)。

const CORAL = "#F0997B"; // 紋章の主色
const CORAL_DEEP = "#D97F63"; // 翼・脚の裏面(陰の面で立体を読ませる)
const MIDNIGHT = "#1A1130"; // 目穴
const EMBER = "#F5822A"; // returnOrange。胸の熾火

/// 胴: 肩幅→腰へ絞る盾形。薄い押し出しで「立てた紋章」の平面感を保つ。
function makeTorsoGeometry(): THREE.BufferGeometry {
  const s = new THREE.Shape();
  s.moveTo(-0.16, 0.4);
  s.lineTo(0.16, 0.4);
  s.quadraticCurveTo(0.2, 0.3, 0.1, 0.02);
  s.quadraticCurveTo(0.05, -0.04, 0, -0.05);
  s.quadraticCurveTo(-0.05, -0.04, -0.1, 0.02);
  s.quadraticCurveTo(-0.2, 0.3, -0.16, 0.4);
  const geo = new THREE.ExtrudeGeometry(s, {
    depth: 0.13,
    steps: 1,
    curveSegments: 5,
    bevelEnabled: false,
  });
  geo.translate(0, 0, -0.065);
  return geo;
}

/// 頭: 紋章の上向きの棘。付け根から鋭く尖る三角の薄板。
function makeHeadGeometry(): THREE.BufferGeometry {
  const s = new THREE.Shape();
  s.moveTo(-0.125, 0);
  s.lineTo(0.125, 0);
  s.quadraticCurveTo(0.05, 0.18, 0, 0.4);
  s.quadraticCurveTo(-0.05, 0.18, -0.125, 0);
  const geo = new THREE.ExtrudeGeometry(s, {
    depth: 0.11,
    steps: 1,
    curveSegments: 5,
    bevelEnabled: false,
  });
  geo.translate(0, 0, -0.055);
  return geo;
}

/// 腕=翼。紋章の三日月をそのまま腕にする(上縁は張り出し、下縁は抉れる)。
/// dir=+1が右腕。肩(原点)から外へ流れ、先端は鋭く。
function makeWingArmGeometry(dir: 1 | -1): THREE.BufferGeometry {
  const s = new THREE.Shape();
  s.moveTo(0, 0.07);
  s.quadraticCurveTo(dir * 0.3, 0.13, dir * 0.56, -0.06); // 上縁: 外へ張り出す
  s.quadraticCurveTo(dir * 0.28, -0.04, dir * 0.04, -0.12); // 下縁: 三日月の抉れ
  s.quadraticCurveTo(dir * -0.02, -0.03, 0, 0.07); // 肩の付け根
  const geo = new THREE.ExtrudeGeometry(s, {
    depth: 0.045,
    steps: 1,
    curveSegments: 6,
    bevelEnabled: false,
  });
  geo.translate(0, 0, -0.0225);
  return geo;
}

/// 脚: 紋章の下の二叉。腿から足先へ一直線に細る刃で、先端が接地する。
function makeLegGeometry(): THREE.BufferGeometry {
  const s = new THREE.Shape();
  s.moveTo(-0.055, 0);
  s.lineTo(0.055, 0);
  s.quadraticCurveTo(0.075, -0.32, 0.015, -0.66); // 外縁
  s.quadraticCurveTo(-0.035, -0.32, -0.055, 0); // 内縁
  const geo = new THREE.ExtrudeGeometry(s, {
    depth: 0.07,
    steps: 1,
    curveSegments: 5,
    bevelEnabled: false,
  });
  geo.translate(0, 0, -0.035);
  return geo;
}

// ジオメトリと材質は状態に依存しないので、モジュール読み込み時に一度だけ作る。
const TORSO_GEO = makeTorsoGeometry();
const HEAD_GEO = makeHeadGeometry();
const WING_R_GEO = makeWingArmGeometry(1);
const WING_L_GEO = makeWingArmGeometry(-1);
const LEG_GEO = makeLegGeometry();
const EYE_GEO = new THREE.CylinderGeometry(0.055, 0.055, 0.13, 12);
const EMBER_GEO = new THREE.OctahedronGeometry(0.032, 0);

const CORAL_MAT = new THREE.MeshStandardMaterial({
  color: CORAL,
  flatShading: true,
  roughness: 0.85,
});
const CORAL_DEEP_MAT = new THREE.MeshStandardMaterial({
  color: CORAL_DEEP,
  flatShading: true,
  roughness: 0.85,
});
const EYE_MAT = new THREE.MeshStandardMaterial({
  color: MIDNIGHT,
  flatShading: true,
  roughness: 0.75,
});
// 胸の熾火。ランタンと同じ、ごく小さなemissiveの一点(同時に1体なので共有で良い)。
const EMBER_MAT = new THREE.MeshStandardMaterial({
  color: EMBER,
  flatShading: true,
  roughness: 0.85,
  emissive: new THREE.Color(EMBER),
  emissiveIntensity: 0.8,
  fog: false,
});

/// 生きた紋章の航海士。薄く鋭い板の組み合わせで紋章のシルエットを立て、
/// 呼吸・翼腕の揺れ・頭の見渡しで「静かに構えるスタイリッシュな相棒」を作る。
/// 肩・首・脚はピボットgrupで持ち、将来のポーズ付けにもそのまま使える。
export default function PhoenixModel({ animate = true }: { animate?: boolean }) {
  const core = useRef<THREE.Group>(null); // 胴から上(呼吸)
  const head = useRef<THREE.Group>(null);
  const armR = useRef<THREE.Group>(null);
  const armL = useRef<THREE.Group>(null);

  useFrame(({ clock }) => {
    if (!animate) return;
    const time = clock.elapsedTime;
    // 呼吸: 胴から上がゆっくり上下し、わずかに重心を移す。脚は甲板に植わったまま。
    if (core.current) {
      core.current.position.y = Math.sin(time * 0.9) * 0.02;
      core.current.rotation.x = Math.sin(time * 0.9 + 0.8) * 0.012;
    }
    // 頭: 水平線をゆっくり見渡す。
    if (head.current) {
      head.current.rotation.y = Math.sin(time * 0.33) * 0.1;
      head.current.rotation.z = Math.sin(time * 0.9 + 2.0) * 0.02;
    }
    // 翼腕: マントの裾が風を受けるような、左右で位相の違う微動。
    if (armR.current) armR.current.rotation.z = -0.1 + Math.sin(time * 0.7) * 0.05;
    if (armL.current) armL.current.rotation.z = 0.1 + Math.sin(time * 0.7 + Math.PI) * 0.05;
    // 熾火の脈動。
    EMBER_MAT.emissiveIntensity = 0.8 + Math.sin(time * 1.6) * 0.2;
  });

  return (
    // 形は正面=+Zで組み、グループごと+X向きへ(船の舳先と同じ向き)。
    <group rotation={[0, Math.PI / 2, 0]}>
      {/* 脚: 紋章の二叉。左右へしっかり開いて接地し、動かない(呼吸は上半身で吸収)。
          回転はピボット基準で正=外向き(正面から見て逆ハの字のフォーク)。 */}
      {[1, -1].map((s) => (
        <group key={s} position={[s * 0.085, 0.66, 0]} rotation={[0, 0, s * 0.24]}>
          <mesh geometry={LEG_GEO} material={CORAL_DEEP_MAT} />
        </group>
      ))}

      {/* 胴から上(呼吸のまとまり) */}
      <group ref={core}>
        {/* 胴: 立てた盾形 */}
        <mesh geometry={TORSO_GEO} material={CORAL_MAT} position={[0, 0.6, 0]} />
        {/* 胸の熾火 */}
        <mesh geometry={EMBER_GEO} material={EMBER_MAT} position={[0, 0.83, 0.075]} />

        {/* 頭: 上向きの棘。目穴は頭を貫くmidnightの円柱で、両面から読める */}
        <group ref={head} position={[0, 0.99, 0]}>
          <mesh geometry={HEAD_GEO} material={CORAL_MAT} />
          <mesh
            geometry={EYE_GEO}
            material={EYE_MAT}
            position={[0, 0.13, 0]}
            rotation={[Math.PI / 2, 0, 0]}
          />
        </group>

        {/* 翼腕: 紋章の三日月。肩ピボットから外へ流し、先端は鋭く下がる */}
        <group ref={armR} position={[0.15, 0.94, 0]} rotation={[0, 0, -0.1]}>
          <mesh geometry={WING_R_GEO} material={CORAL_MAT} />
          <mesh
            geometry={WING_R_GEO}
            material={CORAL_DEEP_MAT}
            position={[0.015, -0.015, 0]}
            scale={[0.86, 0.86, 0.6]}
          />
        </group>
        <group ref={armL} position={[-0.15, 0.94, 0]} rotation={[0, 0, 0.1]}>
          <mesh geometry={WING_L_GEO} material={CORAL_MAT} />
          <mesh
            geometry={WING_L_GEO}
            material={CORAL_DEEP_MAT}
            position={[-0.015, -0.015, 0]}
            scale={[0.86, 0.86, 0.6]}
          />
        </group>
      </group>
    </group>
  );
}
