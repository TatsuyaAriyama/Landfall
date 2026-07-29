import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
  type CSSProperties,
  type ReactNode,
} from "react";
import * as THREE from "three";
import {
  Canvas,
  useFrame,
  useThree,
  type RootState,
} from "@react-three/fiber";
import { Html, OrbitControls, Stars, useGLTF } from "@react-three/drei";
import BoatModel from "./BoatModel";
import PhoenixModel, { type PhoenixPose } from "./PhoenixModel";
import { Moon, PassingSwells, Ripples, Sea, Sun } from "./SeaParts";
import { Horizon, Wake } from "./VoyageScene";
import { boatPartsFromIds, boatProps } from "../boat";
import { Gulls, type GullFlock } from "./Gulls";
import PassingShip from "./PassingShip";
import {
  ROOM_MAX_MEMBERS,
  clearHarborPresence,
  fetchMonth,
  listenHarborPresence,
  publishHarborPresence,
  type HarborMember,
  type HarborPresence,
  type HarborPresencePose,
  type HarborRoom,
  type HarborVoyage,
} from "../harbor";
import {
  activeEncounter,
  encounterPhase,
  type EncounterKind,
  type SeaRoute,
} from "../voyageMap";
import { downloadCanvas } from "../share";
import { demoLitMemberIds, isDemo } from "../demo";
import { playStrike } from "../audio";
import { t, voyageRemainingLabel, type I18nKey } from "../i18n";
import { SEA_LIGHT, useTimeOfDay, type TimeOfDay } from "../timeOfDay";
import {
  loadNavigatorInventory,
  saveNavigatorInventory,
  type NavigatorInventory,
} from "../inventory";
import { useBodyScrollLock } from "../scrollLock";
import {
  HARBOR_CONTROL_SETTINGS_EVENT,
  loadHarborControlSettings,
  type HarborControlSettings,
} from "../harborControls";

// 港の「みんなの海」。参加メンバー全員の船が同じ桟橋へ帰り、
// 灯台と広い砂地が迎える、まだ何もない拠点。
// VoyageScene/BoatStudioと同じ品質言語(低ポリ+flatShading、時間帯の海、波紋)。
//
// 反ストリークの約束: 船の位置は進捗・量・順位では決めない。
// uidのハッシュだけで決まる固定の舫い場所。誰も先頭ではない。

/// マウント後に届いた着岸/帰還を、船からの一撃として世界に流すイベント。
export interface StrikeEvent {
  uid: string;
  seq: number;
}

export interface HarborWorldProps {
  currentUid: string;
  room: HarborRoom;
  members: HarborMember[];
  /// 共同航海。undefined=読込中(何も出さない)、null=航海なし。
  voyage?: HarborVoyage | null;
  /// 選択中の航路(generateRoutes(voyage.seed)[voyage.routeIndex])。導出は呼び出し側。
  route?: SeaRoute | null;
  /// 航海の進捗(全員の合算・分)。導出は呼び出し側(RoomDetail)。
  progressMinutes?: number;
  strike?: StrikeEvent | null;
  /// この更新で新しく入港したメンバー。画面外から定位置まで航行させる。
  arrivingMemberIds?: ReadonlySet<string>;
  /// 世界へ入った間も使える、小さなチャットUI。
  immersiveChat?: ReactNode;
}

const CAM_POS: [number, number, number] = [0.2, 3.1, 9.4];
const CAM_TARGET: [number, number, number] = [0.45, 0.7, -1.25];
// 個人タイマーの航海と同じ距離・画角。港で乗船したときは港町のカメラを
// 使い回さず、この「船と水平線が同時に入る」構図へ切り替える。
const HARBOR_SAIL_CAM_POS: [number, number, number] = [-5.6, 2.4, 8.6];
const HARBOR_SAIL_CAM_TARGET: [number, number, number] = [0.8, 1.15, 0];
const HARBOR_SAIL_FOV = 38;
const HARBOR_SAIL_LIGHT_POS: Record<TimeOfDay, [number, number, number]> = {
  morning: [-5.2, 1.7, -5.5],
  day: [0.8, 5.1, -5.5],
  evening: [5.4, 1.25, -5.5],
  night: [5.1, 3.3, -5.5],
};
const HARBOR_SAIL_GULLS: GullFlock = [
  { r: 4.5, y: 2.6, omega: 0.08, scale: 0.14, flap: 2.0, phase: 0.2 },
  { r: 5.3, y: 3.2, omega: -0.055, scale: 0.12, flap: 1.6, phase: 2.1 },
  { r: 4.0, y: 2.2, omega: 0.105, scale: 0.15, flap: 2.4, phase: 4.0 },
  { r: 6.1, y: 2.8, omega: -0.045, scale: 0.11, flap: 1.8, phase: 5.5 },
];
const HARBOR_SAIL_LANES = [
  { x: 1.4, z: -2.45, scale: 0.48 },
  { x: -0.55, z: 2.5, scale: 0.44 },
  { x: 3.55, z: -4.45, scale: 0.4 },
] as const;
const HARBOR_SAIL_MAX_OFFSET = 0.75;
const HARBOR_SAIL_STEP = 0.12;

// 没入(砂の拠点に入る)ときの遠景→近景ドリー。遠景はコンパクトの構図そのまま。
type WorldPhase = "enter" | "idle" | "exit";
const HARBOR_FAR_POS = new THREE.Vector3(CAM_POS[0], CAM_POS[1], CAM_POS[2]);
const HARBOR_FAR_TARGET = new THREE.Vector3(CAM_TARGET[0], CAM_TARGET[1], CAM_TARGET[2]);
const HARBOR_DOLLY_SECONDS = 1.2;
const HARBOR_PIER_URL = "/models/harbor_pier.glb";
const HARBOR_TENT_URL = "/models/harbor_tent.glb";
const FISHING_ROD_URL = "/models/fishing_rod.glb";
type EquipmentAction = "pickup" | "equip" | "unequip" | null;
type HarborEmotePose = Extract<
  PhoenixPose,
  "hail" | "raise" | "point" | "lookout" | "read"
>;

const HARBOR_EMOTES: {
  pose: HarborEmotePose;
  label: I18nKey;
  mark: string;
}[] = [
  { pose: "hail", label: "emoteWave", mark: "≋" },
  { pose: "raise", label: "emoteLantern", mark: "✦" },
  { pose: "point", label: "emotePoint", mark: "→" },
  { pose: "lookout", label: "emoteLookout", mark: "⌁" },
  { pose: "read", label: "emoteRead", mark: "▤" },
];

function activeNavigatorPose(
  equipmentAction: EquipmentAction,
  emote: HarborEmotePose | null,
  fishingRod: boolean,
  walking: boolean,
  resting = false,
): HarborPresencePose {
  if (resting) return "rest";
  if (equipmentAction === "pickup") return "pickupRod";
  if (equipmentAction === "equip") return "equipRod";
  if (equipmentAction === "unequip") return "stowRod";
  if (emote) return emote;
  if (fishingRod) return walking ? "walkRod" : "holdRod";
  return walking ? "walk" : "idle";
}
function easeInOutCubic(v: number): number {
  return v < 0.5 ? 4 * v * v * v : 1 - Math.pow(-2 * v + 2, 3) / 2;
}
// 桟橋前の停泊位置。最大4隻を互い違いに舫い、進捗や順位では位置を変えない。
const MOORINGS = [
  { x: -2.55, z: 1.42, rot: -0.04 },
  { x: -0.86, z: 1.75, rot: 0.025 },
  { x: 0.9, z: 1.35, rot: -0.02 },
  { x: 2.58, z: 1.68, rot: 0.04 },
] as const;

/// 砂の拠点から海へ伸びる桟橋。Blender原本から書き出した共通GLBを、
/// 4隻の舫い場所を挟む3本の桟橋として配置する。モデルのローカル-Zが沖側なので
/// 半回転し、根元は砂へ少し沈める。灯はGLB内のemissive材質で見せる。
function HarborPier({ x }: { x: number }) {
  const { scene } = useGLTF(HARBOR_PIER_URL);
  const model = useMemo(() => scene.clone(true), [scene]);
  return (
    <group position={[x, -0.15, -1.05]} rotation={[0, Math.PI, 0]} scale={0.62}>
      <primitive object={model} />
    </group>
  );
}

useGLTF.preload(HARBOR_PIER_URL);
useGLTF.preload(HARBOR_TENT_URL);
useGLTF.preload(FISHING_ROD_URL);

// ジオメトリは色に依存しないので、モジュール読み込み時に一度だけ作る。
const LANTERN_GEO = new THREE.SphereGeometry(0.16, 10, 8);
const LANTERN_POLE_GEO = new THREE.CylinderGeometry(0.022, 0.022, 0.55, 6);

/// uid→32bit。船のレーンと揺れの位相を決める(進捗とは無関係)。
function hashUid(uid: string): number {
  let h = 5381;
  for (let i = 0; i < uid.length; i++) h = ((h << 5) + h + uid.charCodeAt(i)) >>> 0;
  return h >>> 0;
}

interface Berth {
  member: HarborMember;
  x: number;
  z: number;
  rot: number;
  phase: number;
}

/// メンバー(最大4人)を港の固定桟橋へ。ハッシュ順で決まり、量や順位には連動しない。
function makeBerths(members: HarborMember[]): Berth[] {
  const fleet = members
    .slice(0, ROOM_MAX_MEMBERS)
    .map((member) => ({ member, hash: hashUid(member.id) }))
    .sort((a, b) => a.hash - b.hash || (a.member.id < b.member.id ? -1 : 1));
  const start = Math.floor((MOORINGS.length - fleet.length) / 2);
  return fleet.map(({ member, hash }, i) => {
    const mooring = MOORINGS[Math.min(start + i, MOORINGS.length - 1)];
    return {
      member,
      x: mooring.x + ((((hash >> 3) % 100) / 100) * 0.16 - 0.08),
      z: mooring.z + ((((hash >> 11) % 100) / 100) * 0.1 - 0.05),
      rot: mooring.rot,
      phase: ((hash >> 5) % 628) / 100,
    };
  });
}

// ---- 帰る場所としての、まだ何もない砂の拠点 ----

const HARBOR_PIER_X = [-1.72, 0, 1.72] as const;
const HARBOR_SAND_CENTER_Z = -4.25;
const HARBOR_SAND_TOP = 0.31;
const HARBOR_LIGHTHOUSE_X = 4.1;
const HARBOR_LIGHTHOUSE_Z = -4.7;
const HARBOR_ANCHOR_X = -3.65;
const HARBOR_ANCHOR_Z = -2.35;
const HARBOR_ROPE_X = 2.55;
const HARBOR_ROPE_Z = -1.55;
const HARBOR_FISHING_ROD_X = 0;
const HARBOR_FISHING_ROD_Z = HARBOR_SAND_CENTER_Z;
const HARBOR_TENT_X = -2.25;
const HARBOR_TENT_Z = -5.25;
const HARBOR_TENT_REST_Z = -5.08;

/// 港で一息つくための、小さな航海士用テント。入口は桟橋側へ向き、
/// 夜は軒先の灯だけが暖かく残る。
function HarborTent({ lightsOn }: { lightsOn: boolean }) {
  const { scene } = useGLTF(HARBOR_TENT_URL);
  const model = useMemo(() => scene.clone(true), [scene]);
  return (
    <group position={[HARBOR_TENT_X, HARBOR_SAND_TOP, HARBOR_TENT_Z]} scale={0.88}>
      <primitive object={model} />
      {lightsOn && (
        <pointLight
          position={[-0.42, 0.68, 0.86]}
          color="#F3C065"
          intensity={0.52}
          distance={3.2}
          decay={2}
        />
      )}
    </group>
  );
}

/// 初めて港へ来た航海士のため、何もない砂地の中央へ一本だけ置かれた釣竿。
/// 道具そのものは浮かせず、足元の輪だけが静かに明滅して拾得物だと伝える。
function HarborFishingRod({ animate }: { animate: boolean }) {
  const { scene } = useGLTF(FISHING_ROD_URL);
  const model = useMemo(() => scene.clone(true), [scene]);
  const glow = useRef<THREE.MeshBasicMaterial>(null);

  useFrame(({ clock }) => {
    if (!animate || !glow.current) return;
    glow.current.opacity = 0.2 + Math.sin(clock.elapsedTime * 1.8) * 0.07;
  });

  return (
    <group position={[HARBOR_FISHING_ROD_X, HARBOR_SAND_TOP + 0.13, HARBOR_FISHING_ROD_Z]}>
      <group rotation={[0, -0.35, 1.22]} scale={0.82}>
        <primitive object={model} />
      </group>
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, -0.105, 0]}>
        <ringGeometry args={[0.34, 0.47, 28]} />
        <meshBasicMaterial
          ref={glow}
          color="#F3C065"
          transparent
          opacity={0.2}
          depthWrite={false}
          side={THREE.DoubleSide}
        />
      </mesh>
    </group>
  );
}

function HarborRopeAndAnchor() {
  const metal = "#3C4140";
  return (
    <>
      {/* 桟橋の脇に置いた舫い綱。ほかの荷物は置かず、港の用途だけを伝える。 */}
      <group position={[HARBOR_ROPE_X, HARBOR_SAND_TOP + 0.035, HARBOR_ROPE_Z]}>
        <mesh rotation={[-Math.PI / 2, 0, 0]} scale={[1.08, 0.78, 1]}>
          <torusGeometry args={[0.28, 0.038, 8, 24]} />
          <meshStandardMaterial color="#B7A277" flatShading roughness={1} />
        </mesh>
        <mesh position={[0.08, 0.012, 0.03]} rotation={[-Math.PI / 2, 0, 0]} scale={0.72}>
          <torusGeometry args={[0.28, 0.038, 8, 24]} />
          <meshStandardMaterial color="#A99368" flatShading roughness={1} />
        </mesh>
      </group>

      {/* 砂に立てた錨。空の拠点が船の帰る場所であることを示す唯一の標。 */}
      <group
        position={[HARBOR_ANCHOR_X, HARBOR_SAND_TOP, HARBOR_ANCHOR_Z]}
        rotation={[0, -0.18, -0.08]}
        scale={0.82}
      >
        <mesh position={[0, 0.72, 0]}>
          <cylinderGeometry args={[0.055, 0.075, 1.08, 8]} />
          <meshStandardMaterial color={metal} flatShading roughness={0.9} />
        </mesh>
        <mesh position={[0, 1.28, 0]}>
          <torusGeometry args={[0.16, 0.045, 8, 18]} />
          <meshStandardMaterial color={metal} flatShading roughness={0.9} />
        </mesh>
        <mesh position={[0, 1.02, 0]} rotation={[0, 0, Math.PI / 2]}>
          <cylinderGeometry args={[0.038, 0.048, 0.78, 8]} />
          <meshStandardMaterial color={metal} flatShading roughness={0.9} />
        </mesh>
        {[-1, 1].map((side) => (
          <group key={side}>
            <mesh position={[side * 0.25, 0.22, 0]} rotation={[0, 0, side * -0.93]}>
              <cylinderGeometry args={[0.045, 0.065, 0.55, 8]} />
              <meshStandardMaterial color={metal} flatShading roughness={0.9} />
            </mesh>
            <mesh
              position={[side * 0.5, 0.37, 0]}
              rotation={[0, 0, side * -0.46]}
            >
              <coneGeometry args={[0.13, 0.28, 6]} />
              <meshStandardMaterial color={metal} flatShading roughness={0.9} />
            </mesh>
          </group>
        ))}
      </group>
    </>
  );
}

function HarborLighthouse({ lightsOn }: { lightsOn: boolean }) {
  return (
    /* 灯台。砂の拠点で唯一の建造物として、海から帰る方向だけを示す。 */
    <group position={[HARBOR_LIGHTHOUSE_X, HARBOR_SAND_TOP, HARBOR_LIGHTHOUSE_Z]}>
      <mesh position={[0, 0.72, 0]}>
        <cylinderGeometry args={[0.3, 0.46, 1.42, 10]} />
        <meshStandardMaterial color="#E4D8B9" flatShading roughness={0.82} />
      </mesh>
      <mesh position={[0, 1.45, 0]}>
        <cylinderGeometry args={[0.42, 0.42, 0.15, 10]} />
        <meshStandardMaterial color="#88452F" flatShading roughness={0.82} />
      </mesh>
      <mesh position={[0, 1.7, 0]}>
        <cylinderGeometry args={[0.27, 0.27, 0.4, 10]} />
        <meshStandardMaterial
          color={lightsOn ? "#FFD27B" : "#B9D5C9"}
          emissive={lightsOn ? "#FF9F43" : "#B9D5C9"}
          emissiveIntensity={lightsOn ? 2.4 : 0.08}
          transparent
          opacity={0.92}
          fog={!lightsOn}
        />
      </mesh>
      <mesh position={[0, 2.02, 0]} rotation={[0, Math.PI / 4, 0]}>
        <coneGeometry args={[0.5, 0.4, 4]} />
        <meshStandardMaterial color="#A95035" flatShading roughness={0.85} />
      </mesh>
      {lightsOn && (
        <pointLight
          position={[0, 1.7, 0]}
          color="#FFD27B"
          intensity={0.7}
          distance={4.8}
          decay={2}
        />
      )}
    </group>
  );
}

function HarborTown({
  timeOfDay,
}: {
  timeOfDay: TimeOfDay;
}) {
  const lightsOn = timeOfDay === "evening" || timeOfDay === "night";
  return (
    <group>
      {/* 桟橋からそのまま上がれる、広く平らな砂の土台。建物用の余白を残す。 */}
      <mesh position={[0, 0.05, HARBOR_SAND_CENTER_Z]} scale={[1.45, 1, 1]}>
        <cylinderGeometry args={[3.8, 4.05, 0.52, 20]} />
        <meshStandardMaterial color="#B9A474" flatShading roughness={1} />
      </mesh>

      {/* 船4隻の舫い場所を挟む、Blender制作の三本の木桟橋。 */}
      {HARBOR_PIER_X.map((x) => <HarborPier key={x} x={x} />)}

      <HarborRopeAndAnchor />
      <HarborLighthouse lightsOn={lightsOn} />
      <HarborTent lightsOn={lightsOn} />
    </group>
  );
}

// ---- 航路の海域(嵐/海獣) ----
// 進捗が海域の区間に入ると船団と島の間に現れる。海域内の潮目3段階で縮み・薄れ、
// 抜けると海へ帰る/晴れる。品質言語は世界と同じ(低ポリ+flatShading・フラット)。

// 砂の拠点は安全な前景に置き、航海中の海域は島の外・左奥に遠く見せる。
const ENCOUNTER_POS: [number, number, number] = [-7.0, 0, -2.8];
const BEAST_BODY_COLOR = "#342A5C"; // midnight系(夜の海に沈まない程度に持ち上げ)
const BEAST_DARK_COLOR = "#241A44"; // midnight寄りの陰
const EYE_ORANGE = "#F5822A"; // returnOrange

// 潮目3段階の見た目(0=満力、2=あと少し)。しきい値通過はdampで滑らかに。
const BEAST_PHASE_SCALE = [1.15, 0.92, 0.7];
const BEAST_PHASE_Y = [0, -0.26, -0.55];
// ハリケーンは「巨大」が身上。満力ではっきり大きく、弱まるほど痩せて低くなる。
const HUR_PHASE_SCALE = [1.24, 1.0, 0.78];

const BEAST_BODY_GEO = new THREE.SphereGeometry(0.6, 9, 7);
const BEAST_HEAD_GEO = new THREE.ConeGeometry(0.3, 0.5, 7);
const BEAST_EYE_GEO = new THREE.SphereGeometry(0.06, 8, 6);
const TENT_SEG1_GEO = new THREE.CylinderGeometry(0.08, 0.14, 0.75, 6);
const TENT_SEG2_GEO = new THREE.CylinderGeometry(0.035, 0.08, 0.6, 6);
const TENT_TIP_GEO = new THREE.ConeGeometry(0.035, 0.3, 6);
const CLOUD_GEO = new THREE.SphereGeometry(0.5, 8, 6);
const BOLT_GEO = new THREE.PlaneGeometry(1.0, 0.045);
// ハリケーンの漏斗(海面へ降りる細い首)・目(淡い円盤)・海面のしぶきの環。
const HUR_FUNNEL_GEO = new THREE.CylinderGeometry(0.58, 0.24, 0.9, 9, 1, true);
const HUR_EYE_GEO = new THREE.CircleGeometry(0.3, 10);
const HUR_SKIRT_GEO = new THREE.TorusGeometry(1.05, 0.13, 8, 28);

// 材質は色に依存しないので、ジオメトリと同じくモジュールで一度だけ作る
// (海域は同時に1体なので、目や雲のアニメも共有インスタンスで問題ない)。
const KRAKEN_BODY_MAT = new THREE.MeshStandardMaterial({
  color: BEAST_BODY_COLOR,
  flatShading: true,
  roughness: 0.85,
});
const KRAKEN_DARK_MAT = new THREE.MeshStandardMaterial({
  color: BEAST_DARK_COLOR,
  flatShading: true,
  roughness: 0.85,
});
const KRAKEN_EYE_MAT = new THREE.MeshStandardMaterial({
  color: EYE_ORANGE,
  emissive: new THREE.Color(EYE_ORANGE),
  emissiveIntensity: 1.5,
  fog: false,
});
// ハリケーン: 夜の海に沈まない程度に持ち上げた嵐雲の青3段。稲光は薄紫のemissive。
const HUR_TIER_MATS = ["#3A4C6B", "#2B3A55", "#1E2A3E"].map(
  (color) =>
    new THREE.MeshStandardMaterial({
      color,
      flatShading: true,
      roughness: 0.95,
      transparent: true,
      emissive: new THREE.Color("#CECBF6"),
      emissiveIntensity: 0,
    }),
);
const HUR_FUNNEL_MAT = new THREE.MeshStandardMaterial({
  color: "#131B29",
  flatShading: true,
  roughness: 0.9,
  transparent: true,
  side: THREE.DoubleSide,
});
const HUR_EYE_MAT = new THREE.MeshBasicMaterial({
  color: "#EADEBD",
  transparent: true,
  opacity: 0.75,
  fog: false,
});
const HUR_SKIRT_MAT = new THREE.MeshBasicMaterial({
  color: "#7FA8B8",
  transparent: true,
  opacity: 0.22,
  depthWrite: false,
});

/// ハリケーンの積層。横からのカメラでも「回る嵐」と読めるよう、渦は上空の
/// 円盤ではなく、下ほどすぼまる3段の雲リングの塔として組む(上段が明るく大きい)。
/// 各段はゴツゴツした雲塊のリングで、段ごとに違う速さで回って渦を見せる。
const HUR_TIERS: {
  y: number;
  r: number;
  n: number;
  size: number;
  /// その段の回転速度の倍率(内側=下段ほど速い)。
  speed: number;
}[] = [
  { y: 1.78, r: 1.18, n: 8, size: 1.0, speed: 0.55 },
  { y: 1.28, r: 0.84, n: 7, size: 0.78, speed: 0.8 },
  { y: 0.86, r: 0.55, n: 6, size: 0.58, speed: 1.15 },
];

/// 段内の雲塊の配置(決定的な揺らぎつき)。モジュールで一度だけ計算する。
const HUR_TIER_PUFFS: { p: [number, number, number]; s: [number, number, number] }[][] =
  HUR_TIERS.map((tier, ti) =>
    Array.from({ length: tier.n }, (_, i) => {
      const ang = (i / tier.n) * Math.PI * 2 + ti * 0.7;
      const wob = ((ti * 11 + i * 17) % 10) / 10; // 0..0.9 の決定的な揺らぎ
      const r = tier.r * (0.92 + wob * 0.16);
      const size = tier.size * (0.85 + ((i * 7 + ti * 3) % 10) / 33);
      return {
        p: [Math.cos(ang) * r, tier.y + (wob - 0.45) * 0.14, Math.sin(ang) * r] as [
          number,
          number,
          number,
        ],
        s: [size * 1.05, size * 0.55, size * 0.85] as [number, number, number],
      };
    }),
  );

// 触腕4本の配置角(XZ平面)。yawグループで局所+Xを放射方向へ向ける。
const TENTACLES = [0, 1, 2, 3].map((i) => (i / 4) * Math.PI * 2 + 0.6);

/// いま海に描くべき海域(嵐/海獣)。phase は潮目(0=満力→2=あと少し)、
/// defeating は「抜けた瞬間の沈む/晴れる」演出中。
interface EncounterView {
  kind: EncounterKind;
  phase: number;
  defeating: boolean;
}

/// 海獣。海面から出る胴体+頭+触腕4本。ゆっくり上下に蠢き、
/// 潮目で縮んで沈み、討伐で深みへ帰る。命中でscaleパルスの身じろぎ。
function Kraken({
  phase,
  defeating,
  animate,
  hitClock,
}: {
  phase: number;
  defeating: boolean;
  animate: boolean;
  hitClock: { current: number };
}) {
  const root = useRef<THREE.Group>(null);
  const tents = useRef<(THREE.Group | null)[]>([]);
  const baseY = useRef(BEAST_PHASE_Y[phase]);
  const baseScale = useRef(BEAST_PHASE_SCALE[phase]);
  const invalidate = useThree((s) => s.invalidate);

  // reduced-motion(demandフレーム)時: 潮目の段階へ直接置いて一度だけ描く。
  useLayoutEffect(() => {
    if (animate) return;
    baseY.current = BEAST_PHASE_Y[phase];
    baseScale.current = BEAST_PHASE_SCALE[phase];
    const g = root.current;
    if (g) {
      g.position.y = baseY.current;
      g.scale.setScalar(baseScale.current);
    }
    invalidate();
  }, [phase, animate, invalidate]);

  useFrame(({ clock }, delta) => {
    if (!animate) return;
    const time = clock.elapsedTime;
    const g = root.current;
    if (!g) return;
    const lambda = defeating ? 2.0 : 1.3;
    baseY.current = THREE.MathUtils.damp(
      baseY.current,
      defeating ? -2.6 : BEAST_PHASE_Y[phase],
      lambda,
      delta,
    );
    baseScale.current = THREE.MathUtils.damp(
      baseScale.current,
      defeating ? 0.5 : BEAST_PHASE_SCALE[phase],
      lambda,
      delta,
    );
    // 一撃の命中で身じろぎ(scaleパルス)。
    const since = time - hitClock.current;
    const pulse = since >= 0 && since < 0.5 ? Math.sin((since / 0.5) * Math.PI) * 0.09 : 0;
    g.position.y = baseY.current + (defeating ? 0 : Math.sin(time * 0.5) * 0.06);
    g.scale.setScalar(baseScale.current * (1 + pulse));
    KRAKEN_EYE_MAT.emissiveIntensity = 1.5 + Math.sin(time * 2.4) * 0.3;
    for (let i = 0; i < tents.current.length; i++) {
      const tg = tents.current[i];
      if (tg) tg.rotation.z = -0.45 + Math.sin(time * 0.55 + i * 1.7) * 0.1;
    }
  });

  return (
    <group position={ENCOUNTER_POS}>
      <group ref={root}>
        {/* 胴体(押し潰した球)+頭(円錐) */}
        <mesh
          geometry={BEAST_BODY_GEO}
          material={KRAKEN_BODY_MAT}
          position={[0, 0.28, 0]}
          scale={[1, 0.92, 0.86]}
        />
        <mesh
          geometry={BEAST_HEAD_GEO}
          material={KRAKEN_DARK_MAT}
          position={[0, 0.95, 0]}
          rotation={[0.1, 0, -0.08]}
        />
        {/* 目: returnOrangeの小球(カメラ側) */}
        {[-0.2, 0.2].map((x) => (
          <mesh
            key={x}
            geometry={BEAST_EYE_GEO}
            material={KRAKEN_EYE_MAT}
            position={[x, 0.42, 0.48]}
          />
        ))}
        {/* 触腕: 曲げたコーンの3節。外へ倒し、節ごとに曲げて反りを作る */}
        {TENTACLES.map((a, i) => (
          <group key={a} rotation={[0, -a, 0]}>
            <group
              ref={(g) => {
                tents.current[i] = g;
              }}
              position={[0.58, -0.05, 0]}
              rotation={[0, 0, -0.45]}
            >
              <mesh geometry={TENT_SEG1_GEO} material={KRAKEN_BODY_MAT} position={[0, 0.34, 0]} />
              <group position={[0, 0.66, 0]} rotation={[0, 0, -0.5]}>
                <mesh
                  geometry={TENT_SEG2_GEO}
                  material={KRAKEN_DARK_MAT}
                  position={[0, 0.26, 0]}
                />
                <group position={[0, 0.52, 0]} rotation={[0, 0, -0.55]}>
                  <mesh
                    geometry={TENT_TIP_GEO}
                    material={KRAKEN_DARK_MAT}
                    position={[0, 0.12, 0]}
                  />
                </group>
              </group>
            </group>
          </group>
        ))}
      </group>
    </group>
  );
}

/// 嵐の航海 — 巨大なハリケーン。下ほどすぼまる3段の雲リングが段ごとに違う
/// 速さで回り、細い漏斗が海面へ降りて、しぶきの環を巻き上げる。右手前の
/// 水平線から滑り込んで来て(接近)、潮目で痩せ、抜けると空へほどけながら
/// 過ぎ去っていく。命中で稲光。
function Hurricane({
  phase,
  defeating,
  animate,
  hitClock,
}: {
  phase: number;
  defeating: boolean;
  animate: boolean;
  hitClock: { current: number };
}) {
  const root = useRef<THREE.Group>(null);
  const tiers = useRef<(THREE.Group | null)[]>([]);
  const skirt = useRef<THREE.Mesh>(null);
  const appear = useRef(0); // 0=水平線の彼方 → 1=定位置(接近の滑り込み)
  const baseScale = useRef(HUR_PHASE_SCALE[phase]);
  const fade = useRef(1);
  const drift = useRef(0); // 過ぎ去り(defeat)の横滑り
  const invalidate = useThree((s) => s.invalidate);

  const applyFade = (v: number) => {
    for (const m of HUR_TIER_MATS) m.opacity = v;
    HUR_FUNNEL_MAT.opacity = v;
    HUR_EYE_MAT.opacity = 0.75 * v;
    HUR_SKIRT_MAT.opacity = 0.22 * v;
  };

  // reduced-motion(demandフレーム)時: 接近は省略して定位置に置き、一度だけ描く。
  useLayoutEffect(() => {
    if (animate) return;
    appear.current = 1;
    baseScale.current = HUR_PHASE_SCALE[phase];
    fade.current = defeating ? 0 : 1;
    const g = root.current;
    if (g) {
      g.position.set(ENCOUNTER_POS[0], 0, ENCOUNTER_POS[2]);
      g.scale.setScalar(baseScale.current);
    }
    applyFade(fade.current);
    for (const m of HUR_TIER_MATS) m.emissiveIntensity = 0;
    invalidate();
  }, [phase, animate, defeating, invalidate]);

  useFrame(({ clock }, delta) => {
    if (!animate) return;
    const time = clock.elapsedTime;
    const g = root.current;
    if (!g) return;
    appear.current = THREE.MathUtils.damp(appear.current, 1, 1.1, delta);
    baseScale.current = THREE.MathUtils.damp(
      baseScale.current,
      defeating ? 0.35 : HUR_PHASE_SCALE[phase],
      defeating ? 1.6 : 1.2,
      delta,
    );
    fade.current = THREE.MathUtils.damp(fade.current, defeating ? 0 : 1, 1.8, delta);
    drift.current = THREE.MathUtils.damp(drift.current, defeating ? 2.4 : 0, 1.1, delta);
    // 接近: 右手前の水平線から定位置へ(島の背後は通らない)。
    // 過ぎ去り: ほどけながら空へ昇り、右へ流れていく。
    const t = appear.current;
    g.position.set(
      ENCOUNTER_POS[0] + (1 - t) * 3.0 + drift.current,
      (1 - t) * 0.3 + (1 - fade.current) * 1.5,
      ENCOUNTER_POS[2] + (1 - t) * 0.6,
    );
    // 命中で身震い(scaleパルス)。塔全体がわずかに傾いで揺れる。
    const since = time - hitClock.current;
    const pulse = since >= 0 && since < 0.5 ? Math.sin((since / 0.5) * Math.PI) * 0.07 : 0;
    g.scale.setScalar(baseScale.current * (0.55 + 0.45 * t) * (1 + pulse));
    g.rotation.z = 0.05 + Math.sin(time * 0.4) * 0.02;
    // 段ごとに違う速さで回る(下段=内側ほど速い)。弱まるほど回転もゆるむ。
    const spin = (0.6 - phase * 0.1) * (0.4 + 0.6 * fade.current);
    for (let i = 0; i < HUR_TIERS.length; i++) {
      const tg = tiers.current[i];
      if (tg) tg.rotation.y = -time * spin * HUR_TIERS[i].speed;
    }
    if (skirt.current) skirt.current.rotation.z = time * spin * 0.6;
    // 稲光: 決定的な疑似ランダムのまたたき+命中の強い閃き。
    const flick = Math.sin(time * 1.7) * Math.sin(time * 2.9 + 1.3) * Math.sin(time * 0.83 + 4.1);
    const strikeFlash = since >= 0 && since < 0.4 ? 1 - since / 0.4 : 0;
    const glow = (flick > 0.82 ? (flick - 0.82) * 3.2 : 0) + strikeFlash * 0.9;
    HUR_TIER_MATS.forEach((m, i) => {
      m.emissiveIntensity = glow * (1 - i * 0.25);
    });
    applyFade(fade.current);
  });

  return (
    <group ref={root} position={ENCOUNTER_POS}>
      {/* 3段の雲リング。段ごとに別グループで回す */}
      {HUR_TIER_PUFFS.map((puffs, ti) => (
        <group
          key={ti}
          ref={(el) => {
            tiers.current[ti] = el;
          }}
        >
          {puffs.map((puff, i) => (
            <mesh
              key={i}
              geometry={CLOUD_GEO}
              material={HUR_TIER_MATS[ti]}
              position={puff.p}
              scale={puff.s}
            />
          ))}
        </group>
      ))}
      {/* 漏斗: 塔の芯が海面へ降りる細い首 */}
      <mesh geometry={HUR_FUNNEL_GEO} material={HUR_FUNNEL_MAT} position={[0, 0.5, 0]} />
      {/* 目: 塔の頂の淡い円盤。カメラへ少し傾け、静けさを覗かせる */}
      <mesh
        geometry={HUR_EYE_GEO}
        material={HUR_EYE_MAT}
        position={[0, 2.0, 0.05]}
        rotation={[-Math.PI / 2 + 0.32, 0, 0]}
      />
      {/* 海面のしぶきの環。漏斗の足元で巻き上がる */}
      <mesh
        ref={skirt}
        geometry={HUR_SKIRT_GEO}
        material={HUR_SKIRT_MAT}
        position={[0, 0.08, 0]}
        rotation={[-Math.PI / 2, 0, 0]}
      />
    </group>
  );
}

interface Bolt {
  id: number;
  from: [number, number, number];
}

/// 一撃の光。船から海獣/嵐へ、emissiveな薄いプレーンが一閃して飛ぶ。
/// 到達時に hitClock を更新し(身じろぎ/明滅の起点)、自身を消す。
function StrikeBolt({
  from,
  hitClock,
  onDone,
}: {
  from: [number, number, number];
  hitClock: { current: number };
  onDone: () => void;
}) {
  const mesh = useRef<THREE.Mesh>(null);
  const mat = useRef<THREE.MeshBasicMaterial>(null);
  const start = useRef<number | null>(null);
  const finished = useRef(false);
  const path = useMemo(() => {
    const origin = new THREE.Vector3(from[0], 0.55, from[2]);
    const target = new THREE.Vector3(ENCOUNTER_POS[0], 0.75, ENCOUNTER_POS[2]);
    const dir = target.clone().sub(origin).normalize();
    const quat = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(1, 0, 0), dir);
    return { origin, target, quat };
  }, [from]);

  useFrame(({ clock }) => {
    if (finished.current) return;
    const time = clock.elapsedTime;
    if (start.current === null) start.current = time;
    const s = (time - start.current) / 0.4;
    if (s >= 1) {
      finished.current = true;
      hitClock.current = time; // 命中 → 海獣の身じろぎ/嵐の明滅
      onDone();
      return;
    }
    const m = mesh.current;
    if (m) {
      m.position.lerpVectors(path.origin, path.target, s);
      m.position.y += Math.sin(Math.PI * s) * 0.35;
      m.quaternion.copy(path.quat);
    }
    if (mat.current) mat.current.opacity = Math.sin(Math.PI * Math.min(s * 1.25, 1)) * 0.95;
  });

  return (
    <mesh ref={mesh} geometry={BOLT_GEO} position={[from[0], 0.55, from[2]]}>
      <meshBasicMaterial
        ref={mat}
        color="#F3C065"
        transparent
        opacity={0}
        blending={THREE.AdditiveBlending}
        depthWrite={false}
        side={THREE.DoubleSide}
        fog={false}
      />
    </mesh>
  );
}

/// 没入の入退場カメラ。enter=遠景(コンパクトの構図)から近景へドリーイン、
/// idle=OrbitControlsに委ねる、exit=いまの視点から遠景へ戻る。VoyageWorldと同作法。
function HarborCameraRig({
  phase,
  animate,
  near,
  onEntered,
  onExited,
}: {
  phase: WorldPhase;
  animate: boolean;
  near: { pos: THREE.Vector3; target: THREE.Vector3 };
  onEntered: () => void;
  onExited: () => void;
}) {
  const camera = useThree((s) => s.camera);
  const invalidate = useThree((s) => s.invalidate);
  const startAt = useRef<number | null>(null);
  const fromPos = useRef(new THREE.Vector3());
  const fromTarget = useRef(new THREE.Vector3());
  const look = useRef(new THREE.Vector3());
  const done = useRef(false);

  // reduced-motion は近景へジャンプカット。
  const initialised = useRef(false);
  useLayoutEffect(() => {
    if (initialised.current || animate) return;
    initialised.current = true;
    camera.position.copy(near.pos);
    camera.lookAt(near.target);
    invalidate();
  }, [animate, camera, near, invalidate]);

  useEffect(() => {
    startAt.current = null;
    done.current = false;
  }, [phase]);

  useFrame(({ clock }) => {
    if (!animate || phase === "idle" || done.current) return;
    const now = clock.elapsedTime;
    if (startAt.current === null) {
      startAt.current = now;
      // enter は「いまの視点(=遠景)」から、exit は「いま眺めている視点」から始める。
      fromPos.current.copy(camera.position);
      fromTarget.current.copy(phase === "enter" ? HARBOR_FAR_TARGET : near.target);
    }
    const raw = Math.min((now - startAt.current) / HARBOR_DOLLY_SECONDS, 1);
    const k = easeInOutCubic(raw);
    const toPos = phase === "enter" ? near.pos : HARBOR_FAR_POS;
    const toT = phase === "enter" ? near.target : HARBOR_FAR_TARGET;
    camera.position.lerpVectors(fromPos.current, toPos, k);
    look.current.lerpVectors(fromTarget.current, toT, k);
    camera.lookAt(look.current);
    if (raw >= 1) {
      done.current = true;
      if (phase === "enter") onEntered();
      else onExited();
    }
  });
  return null;
}

/// 近景の構図を画面比で決め、船着き場へ入退場するカメラを動かす。
function ImmersiveCamera({
  phase,
  animate,
  onEntered,
  onExited,
}: {
  phase: WorldPhase;
  animate: boolean;
  onEntered: () => void;
  onExited: () => void;
}) {
  const size = useThree((s) => s.size);
  const near = useMemo(() => {
    const aspect = size.width / Math.max(size.height, 1);
    const wide = aspect >= 1.05;
    // 横長は砂地と船団を広く、縦長は中央の桟橋を主役にして見渡せる距離へ。
    return wide
      ? {
          pos: new THREE.Vector3(0.2, 2.55, 8.6),
          target: new THREE.Vector3(0.4, 0.72, -1.5),
        }
      : {
          pos: new THREE.Vector3(0.25, 2.95, 9.9),
          target: new THREE.Vector3(0.35, 0.72, -1.72),
        };
  }, [size.width, size.height]);

  return (
    <HarborCameraRig
      phase={phase}
      animate={animate}
      near={near}
      onEntered={onEntered}
      onExited={onExited}
    />
  );
}

/// 一隻の船。位相の違う揺れ+航海士+名前ラベル+今日の灯。
function MemberBoat({
  berth,
  lit,
  animate,
  arriving,
  showSailor,
  fishingRod,
  sailorPose,
  sailorKey,
  onBoard,
}: {
  berth: Berth;
  lit: boolean;
  animate: boolean;
  arriving: boolean;
  showSailor: boolean;
  fishingRod: boolean;
  sailorPose: PhoenixPose;
  sailorKey: number;
  onBoard?: () => void;
}) {
  const { member, phase } = berth;
  const parts = useMemo(
    () =>
      boatPartsFromIds({
        boatSail: member.boatSail,
        boatJib: member.boatJib,
        boatHull: member.boatHull,
        boatStripe: member.boatStripe,
        boatFlag: member.boatFlag,
      }),
    [member],
  );
  const root = useRef<THREE.Group>(null);
  const bob = useRef<THREE.Group>(null);
  const lanternMat = useRef<THREE.MeshStandardMaterial>(null);
  const initialized = useRef(false);
  const invalidate = useThree((state) => state.invalidate);

  // 新しく届いた船だけ、左の画面外から始める。既にいた船は最初から定位置。
  // refを直接動かすため、親の再描画で開始位置へ巻き戻らない。
  useLayoutEffect(() => {
    const group = root.current;
    if (!group || initialized.current) return;
    initialized.current = true;
    group.position.set(arriving && animate ? berth.x - 11 : berth.x, 0, berth.z);
    group.rotation.set(0, arriving && animate ? -0.16 : berth.rot, 0);
    invalidate();
  }, [arriving, animate, berth.x, berth.z, berth.rot, invalidate]);

  // 動きを減らす設定では入港を省略し、定位置の更新も即時反映する。
  useLayoutEffect(() => {
    if (animate || !root.current) return;
    root.current.position.set(berth.x, 0, berth.z);
    root.current.rotation.set(0, berth.rot, 0);
    invalidate();
  }, [animate, berth.x, berth.z, berth.rot, invalidate]);

  // BoatModel自体の揺れは全船同位相なので、外側でuidごとの位相を重ねる。
  useFrame(({ clock }, delta) => {
    if (!animate) return;
    const time = clock.elapsedTime;
    const outer = root.current;
    if (outer) {
      // 新しい船の入港と、人数変化で既存船のレーンが変わる動きを同じ滑走で結ぶ。
      outer.position.x = THREE.MathUtils.damp(outer.position.x, berth.x, 1.65, delta);
      outer.position.z = THREE.MathUtils.damp(outer.position.z, berth.z, 1.65, delta);
      outer.rotation.y = THREE.MathUtils.damp(outer.rotation.y, berth.rot, 1.8, delta);
    }
    const g = bob.current;
    if (g) {
      g.position.y = Math.sin(time * 0.7 + phase) * 0.05;
      g.rotation.z = Math.sin(time * 0.55 + phase * 1.7) * 0.02;
    }
    if (lanternMat.current) {
      // ランタンのゆらぎ(emissiveのみ。lightは増やさない)。
      lanternMat.current.emissiveIntensity = 1.8 + Math.sin(time * 2.1 + phase) * 0.35;
    }
  });

  return (
    <group
      ref={root}
      scale={0.45}
      onClick={
        onBoard
          ? (event) => {
              event.stopPropagation();
              onBoard();
            }
          : undefined
      }
    >
      <Ripples animate={animate} />
      <group ref={bob}>
        <BoatModel parts={parts} animate={animate} />
        {/* 他の船には航海士を常に表示する。自分は陸上の操作キャラと二重にせず、
            乗船中だけここへ戻す。 */}
        {showSailor && (
          <group position={[0.45, 0.5, 0]} scale={1.15}>
            <PhoenixModel
              key={sailorKey}
              animate={animate}
              fishingRod={fishingRod}
              pose={sailorPose}
            />
          </group>
        )}
        {/* 今日の灯: 船尾の短い掲灯柱+暖色のランタン(emissiveな小球のみ) */}
        {lit && (
          <group position={[-0.88, 0.42, 0]}>
            <mesh geometry={LANTERN_POLE_GEO} position={[0, 0.27, 0]}>
              <meshStandardMaterial color="#5A2A15" flatShading roughness={0.8} />
            </mesh>
            <mesh geometry={LANTERN_GEO} position={[0, 0.62, 0]}>
              <meshStandardMaterial
                ref={lanternMat}
                color="#F3C065"
                emissive="#F3C065"
                emissiveIntensity={1.8}
                fog={false}
              />
            </mesh>
          </group>
        )}
      </group>
      <Html
        position={[0.1, 2.7, 0]}
        center
        distanceFactor={7}
        zIndexRange={[1, 0]}
        style={{ pointerEvents: "none" }}
      >
        <div className="harbor-world-name">{member.displayName}</div>
      </Html>
    </group>
  );
}

interface HarborWalkInput {
  x: number;
  z: number;
}

interface HarborWalkInputRef {
  current: HarborWalkInput;
}

interface HarborLookState {
  /// 0 = 世界の-Z方向を見る。正値で視線を右へ回す。
  yaw: number;
  /// 水平線から見下ろす仰角。
  pitch: number;
}

interface HarborLookRef {
  current: HarborLookState;
}

const WALK_START = new THREE.Vector3(0, 0.31, 0.18);
const WALK_SPEED = 1.45;
// PhoenixModel は内部で正面(+Z)を船首方向(+X)へ90度回している。
// 移動ベクトルから求めた一般的なY回転へ、このモデル固有の補正を必ず加える。
const WALKER_FRONT_YAW = -Math.PI / 2;

function canStandInHarbor(x: number, z: number): boolean {
  // 見た目の砂島よりひと回り内側。円形ではなく横長の楕円なので、
  // 桟橋の付け根から左右・奥へ広く歩ける。
  const onSand =
    Math.pow(x / 5.2, 2) +
      Math.pow((z - HARBOR_SAND_CENTER_Z) / 3.5, 2) <=
    1;
  const onPier =
    z >= -1.18 &&
    z <= 1.14 &&
    HARBOR_PIER_X.some((pierX) => Math.abs(x - pierX) <= 0.27);
  if (!onSand && !onPier) return false;

  // 更地の中で実体を持つのは、残した錨・綱・灯台だけ。
  if (Math.hypot(x - HARBOR_LIGHTHOUSE_X, z - HARBOR_LIGHTHOUSE_Z) < 0.58) return false;
  if (Math.hypot(x - HARBOR_ANCHOR_X, z - HARBOR_ANCHOR_Z) < 0.4) return false;
  if (Math.hypot(x - HARBOR_ROPE_X, z - HARBOR_ROPE_Z) < 0.34) return false;

  // テントの布と支柱は通り抜けられない。桟橋側の開口部から中央だけを歩け、
  // 寝具の手前で止まるため、見た目どおり「中へ入る」経路になる。
  const tentLocalX = x - HARBOR_TENT_X;
  const tentLocalZ = z - HARBOR_TENT_Z;
  const inTentFootprint =
    Math.abs(tentLocalX) <= 1.2 &&
    tentLocalZ >= -0.76 &&
    tentLocalZ <= 0.92;
  if (inTentFootprint) {
    const throughEntrance =
      Math.abs(tentLocalX) <= 0.42 && tentLocalZ >= -0.45;
    if (!throughEntrance) return false;
  }
  return true;
}

interface HarborWalkerTransform {
  x: number;
  z: number;
  yaw: number;
  walking: boolean;
}
type HarborPresencePayload = Omit<HarborPresence, "uid" | "updatedAt">;
type HarborPresencePriority = "movement" | "immediate" | "heartbeat";

// 位置は受信側で補間するため、毎フレーム送る必要はない。微小な揺れも捨てて
// Firestore の書き込みと、同室全員に発生する読み取りの両方を抑える。
const HARBOR_PRESENCE_MOVE_INTERVAL_MS = 1_000;
const HARBOR_PRESENCE_HEARTBEAT_MS = 15_000;
const HARBOR_PRESENCE_STALE_MS = 40_000;
const HARBOR_PRESENCE_POSITION_EPSILON = 0.06;
const HARBOR_PRESENCE_YAW_EPSILON = 0.08;
const HARBOR_PRESENCE_SAIL_EPSILON = 0.04;

function presenceStatusChanged(
  previous: HarborPresencePayload,
  next: HarborPresencePayload,
): boolean {
  return (
    previous.pose !== next.pose ||
    previous.aboard !== next.aboard ||
    previous.fishingRod !== next.fishingRod ||
    previous.emoteSeq !== next.emoteSeq
  );
}

function presenceMovementChanged(
  previous: HarborPresencePayload,
  next: HarborPresencePayload,
): boolean {
  const yawDelta = Math.abs(
    Math.atan2(
      Math.sin(next.yaw - previous.yaw),
      Math.cos(next.yaw - previous.yaw),
    ),
  );
  return (
    presenceStatusChanged(previous, next) ||
    Math.hypot(next.x - previous.x, next.z - previous.z) >=
      HARBOR_PRESENCE_POSITION_EPSILON ||
    yawDelta >= HARBOR_PRESENCE_YAW_EPSILON ||
    Math.abs(next.sailX - previous.sailX) >= HARBOR_PRESENCE_SAIL_EPSILON
  );
}

/// 没入時の航海士。WASD/矢印とスマホのスティックを同じ入力へまとめ、
/// 砂地と三本の桟橋だけを歩く。入力は常にカメラ基準へ変換し、
/// 障害物に沿って滑った時も「実際に進んだ方向」へ体を向ける。
function HarborWalker({
  active,
  animate,
  input,
  look,
  aboard,
  ownBerth,
  fishingRod,
  fishingRodAvailable,
  equipmentAction,
  emotePose,
  emoteSeq,
  restingAtTent,
  onNearOwnBoatChange,
  onNearFishingRodChange,
  onNearTentChange,
  onTransformChange,
  onMovementStart,
}: {
  active: boolean;
  animate: boolean;
  input: HarborWalkInputRef;
  look: HarborLookRef;
  aboard: boolean;
  ownBerth?: Berth;
  fishingRod: boolean;
  fishingRodAvailable: boolean;
  equipmentAction: EquipmentAction;
  emotePose: HarborEmotePose | null;
  emoteSeq: number;
  restingAtTent: boolean;
  onNearOwnBoatChange: (near: boolean) => void;
  onNearFishingRodChange: (near: boolean) => void;
  onNearTentChange: (near: boolean) => void;
  onTransformChange: (transform: HarborWalkerTransform) => void;
  onMovementStart: () => void;
}) {
  const root = useRef<THREE.Group>(null);
  const position = useRef(WALK_START.clone());
  // 初期視点の「前」は世界の-Z方向。
  const facing = useRef(Math.PI + WALKER_FRONT_YAW);
  const pressed = useRef(new Set<string>());
  const walkingRef = useRef(false);
  const nearBoatRef = useRef(false);
  const nearFishingRodRef = useRef(false);
  const nearTentRef = useRef(false);
  const lastReport = useRef<HarborWalkerTransform & { at: number }>({
    x: Number.NaN,
    z: Number.NaN,
    yaw: Number.NaN,
    walking: false,
    at: -10,
  });
  const [walking, setWalking] = useState(false);
  const camera = useThree((state) => state.camera);
  const size = useThree((state) => state.size);
  const cameraTarget = useRef(new THREE.Vector3());
  const desiredCamera = useRef(new THREE.Vector3());

  // 船体を直接タップして遠くから乗った場合も、降りる場所は必ず自分の船に
  // 最も近い桟橋端へ揃える。乗船中は非表示なので移動は見えず、降船時だけ自然に現れる。
  useEffect(() => {
    if (!aboard || !ownBerth) return;
    const pierX = HARBOR_PIER_X.reduce((nearest, candidate) =>
      Math.abs(candidate - ownBerth.x) < Math.abs(nearest - ownBerth.x)
        ? candidate
        : nearest,
    );
    position.current.set(pierX, WALK_START.y, 0.98);
    facing.current =
      Math.atan2(ownBerth.x - pierX, ownBerth.z - position.current.z) +
      WALKER_FRONT_YAW;
    root.current?.position.copy(position.current);
  }, [aboard, ownBerth]);

  useEffect(() => {
    if (!active || aboard) {
      pressed.current.clear();
      walkingRef.current = false;
      setWalking(false);
      if (nearBoatRef.current) {
        nearBoatRef.current = false;
        onNearOwnBoatChange(false);
      }
      if (nearFishingRodRef.current) {
        nearFishingRodRef.current = false;
        onNearFishingRodChange(false);
      }
      if (nearTentRef.current) {
        nearTentRef.current = false;
        onNearTentChange(false);
      }
      return;
    }
    const movementKeys = new Set([
      "KeyW",
      "KeyA",
      "KeyS",
      "KeyD",
      "ArrowUp",
      "ArrowLeft",
      "ArrowDown",
      "ArrowRight",
    ]);
    const onKeyDown = (event: KeyboardEvent) => {
      if (!movementKeys.has(event.code)) return;
      event.preventDefault();
      pressed.current.add(event.code);
    };
    const onKeyUp = (event: KeyboardEvent) => {
      if (!movementKeys.has(event.code)) return;
      event.preventDefault();
      pressed.current.delete(event.code);
    };
    const release = () => {
      pressed.current.clear();
    };
    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("keyup", onKeyUp);
    window.addEventListener("blur", release);
    return () => {
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("keyup", onKeyUp);
      window.removeEventListener("blur", release);
      release();
    };
  }, [
    active,
    aboard,
    onNearFishingRodChange,
    onNearOwnBoatChange,
    onNearTentChange,
  ]);

  useFrame(({ clock }, delta) => {
    if (!active || !root.current) return;
    const keys = pressed.current;
    const touch = input.current;
    let dx =
      touch.x +
      (keys.has("KeyD") || keys.has("ArrowRight") ? 1 : 0) -
      (keys.has("KeyA") || keys.has("ArrowLeft") ? 1 : 0);
    let dz =
      touch.z +
      (keys.has("KeyS") || keys.has("ArrowDown") ? 1 : 0) -
      (keys.has("KeyW") || keys.has("ArrowUp") ? 1 : 0);
    let movedX = 0;
    let movedZ = 0;
    if (!aboard && (dx !== 0 || dz !== 0)) {
      const length = Math.hypot(dx, dz);
      const strength = Math.min(length, 1);
      dx /= length;
      dz /= length;

      // 画面の右/奥を基準にした入力を、港のワールド座標へ変換する。
      const yaw = look.current.yaw;
      const worldX = Math.cos(yaw) * dx - Math.sin(yaw) * dz;
      const worldZ = Math.sin(yaw) * dx + Math.cos(yaw) * dz;
      const beforeX = position.current.x;
      const beforeZ = position.current.z;
      const nextX = beforeX + worldX * WALK_SPEED * strength * delta;
      const nextZ = beforeZ + worldZ * WALK_SPEED * strength * delta;
      if (canStandInHarbor(nextX, position.current.z)) position.current.x = nextX;
      if (canStandInHarbor(position.current.x, nextZ)) position.current.z = nextZ;
      movedX = position.current.x - beforeX;
      movedZ = position.current.z - beforeZ;

      // 入力ではなく実移動へ即座に正対させる。これで方向転換時の横滑りと、
      // 衝突時に片軸だけ進んだ際の体のずれを残さない。
      if (Math.hypot(movedX, movedZ) > 0.00001) {
        facing.current = Math.atan2(movedX, movedZ) + WALKER_FRONT_YAW;
      }
    }
    const moving = Math.hypot(movedX, movedZ) > 0.00001;
    if (moving !== walkingRef.current) {
      if (moving) onMovementStart();
      walkingRef.current = moving;
      setWalking(moving);
    }
    const nearOwnBoat =
      !aboard &&
      Boolean(
        ownBerth &&
          Math.hypot(
            position.current.x - ownBerth.x,
            position.current.z - ownBerth.z,
          ) <= 1.2,
      );
    if (nearOwnBoat !== nearBoatRef.current) {
      nearBoatRef.current = nearOwnBoat;
      onNearOwnBoatChange(nearOwnBoat);
    }
    const nearFishingRod =
      !aboard &&
      fishingRodAvailable &&
      Math.hypot(
        position.current.x - HARBOR_FISHING_ROD_X,
        position.current.z - HARBOR_FISHING_ROD_Z,
      ) <= 0.9;
    if (nearFishingRod !== nearFishingRodRef.current) {
      nearFishingRodRef.current = nearFishingRod;
      onNearFishingRodChange(nearFishingRod);
    }
    const nearTent =
      !aboard &&
      Math.hypot(
        position.current.x - HARBOR_TENT_X,
        position.current.z - HARBOR_TENT_REST_Z,
      ) <= 0.72;
    if (nearTent !== nearTentRef.current) {
      nearTentRef.current = nearTent;
      onNearTentChange(nearTent);
    }

    root.current.position.copy(position.current);
    root.current.rotation.y = facing.current;
    const focusX = aboard && ownBerth ? ownBerth.x : position.current.x;
    const focusZ = aboard && ownBerth ? ownBerth.z : position.current.z;
    const tall = size.width / Math.max(size.height, 1) < 0.72;
    const distance = tall ? 6.4 : 4.35;
    const horizontalDistance = Math.cos(look.current.pitch) * distance;
    const height = 0.74 + Math.sin(look.current.pitch) * distance;
    desiredCamera.current.set(
      focusX - Math.sin(look.current.yaw) * horizontalDistance,
      position.current.y + height,
      focusZ + Math.cos(look.current.yaw) * horizontalDistance,
    );
    camera.position.lerp(desiredCamera.current, 1 - Math.exp(-delta * 8));
    cameraTarget.current.set(
      focusX + Math.sin(look.current.yaw) * 0.68,
      0.68,
      focusZ - Math.cos(look.current.yaw) * 0.68,
    );
    camera.lookAt(cameraTarget.current);

    // Firestore側の送信間引きに入れる前に、変化の無いフレームを落とす。
    // 位置は補間されるので約12fpsの報告で十分滑らかに見える。
    const previous = lastReport.current;
    const now = clock.elapsedTime;
    const changed =
      Math.hypot(position.current.x - previous.x, position.current.z - previous.z) > 0.018 ||
      Math.abs(Math.atan2(
        Math.sin(facing.current - previous.yaw),
        Math.cos(facing.current - previous.yaw),
      )) > 0.025 ||
      moving !== previous.walking;
    if (changed || now - previous.at >= 1.5) {
      const next = {
        x: position.current.x,
        z: position.current.z,
        yaw: Math.atan2(Math.sin(facing.current), Math.cos(facing.current)),
        walking: moving,
        at: now,
      };
      lastReport.current = next;
      onTransformChange(next);
    }
  });

  const sailorPose = activeNavigatorPose(
    equipmentAction,
    emotePose,
    fishingRod,
    walking,
    restingAtTent,
  );

  return (
    <group ref={root} position={WALK_START} scale={0.42} visible={!aboard}>
      <PhoenixModel
        key={emoteSeq}
        animate={animate}
        pose={sailorPose}
        fishingRod={fishingRod}
      />
    </group>
  );
}

/// 別端末から届いた航海士。低頻度の座標更新をそのまま跳ばさず、
/// 描画フレーム側で位置と最短角を補間して歩いて見せる。
function RemoteHarborSailor({
  presence,
  member,
  animate,
}: {
  presence: HarborPresence;
  member: HarborMember;
  animate: boolean;
}) {
  const root = useRef<THREE.Group>(null);
  const initialized = useRef(false);
  const target = useRef(new THREE.Vector3(presence.x, HARBOR_SAND_TOP, presence.z));
  const targetYaw = useRef(presence.yaw);
  const invalidate = useThree((state) => state.invalidate);

  useEffect(() => {
    target.current.set(presence.x, HARBOR_SAND_TOP, presence.z);
    targetYaw.current = presence.yaw;
  }, [presence.x, presence.yaw, presence.z]);

  useLayoutEffect(() => {
    const group = root.current;
    if (!group) return;
    if (!initialized.current || !animate) {
      initialized.current = true;
      group.position.set(presence.x, HARBOR_SAND_TOP, presence.z);
      group.rotation.y = presence.yaw;
      invalidate();
    }
  }, [animate, invalidate, presence.x, presence.yaw, presence.z]);

  useFrame((_, delta) => {
    const group = root.current;
    if (!group || !animate) return;
    group.position.x = THREE.MathUtils.damp(
      group.position.x,
      target.current.x,
      10,
      delta,
    );
    group.position.z = THREE.MathUtils.damp(
      group.position.z,
      target.current.z,
      10,
      delta,
    );
    const angle = Math.atan2(
      Math.sin(targetYaw.current - group.rotation.y),
      Math.cos(targetYaw.current - group.rotation.y),
    );
    group.rotation.y += angle * (1 - Math.exp(-delta * 12));
  });

  return (
    <group ref={root} scale={0.42}>
      <PhoenixModel
        key={presence.emoteSeq}
        animate={animate}
        pose={presence.pose as PhoenixPose}
        fishingRod={presence.fishingRod}
      />
      <Html
        position={[0, 1.55, 0]}
        center
        distanceFactor={7}
        zIndexRange={[2, 0]}
        style={{ pointerEvents: "none" }}
      >
        <div className="harbor-live-sailor-name">
          <span aria-hidden="true" />
          {member.displayName}
        </div>
      </Html>
    </group>
  );
}

function HarborWalkControls({
  onInput,
  settings,
}: {
  onInput: (input: HarborWalkInput) => void;
  settings: HarborControlSettings;
}) {
  const activePointer = useRef<number | null>(null);
  const [knob, setKnob] = useState({ x: 0, y: 0 });
  const updateInput = (
    event: ReactPointerEvent<HTMLDivElement>,
  ) => {
    const rect = event.currentTarget.getBoundingClientRect();
    const dx = event.clientX - (rect.left + rect.width / 2);
    const dy = event.clientY - (rect.top + rect.height / 2);
    const distance = Math.hypot(dx, dy);
    const maxRadius = rect.width * 0.31;
    const deadZone = rect.width * 0.07;
    const visualScale = distance > maxRadius ? maxRadius / distance : 1;
    setKnob({ x: dx * visualScale, y: dy * visualScale });
    if (distance <= deadZone) {
      onInput({ x: 0, z: 0 });
      return;
    }
    const strength = Math.min((distance - deadZone) / (maxRadius - deadZone), 1);
    onInput({
      x: (dx / distance) * strength,
      z: (dy / distance) * strength,
    });
  };
  const release = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (activePointer.current !== event.pointerId) return;
    activePointer.current = null;
    setKnob({ x: 0, y: 0 });
    onInput({ x: 0, z: 0 });
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
  };
  return (
    <div
      className="harbor-walk-controls"
      style={
        {
          "--harbor-control-x": `${settings.x}%`,
          "--harbor-control-y": `${settings.y}%`,
          "--harbor-control-size": `${settings.size}px`,
        } as CSSProperties
      }
      role="group"
      aria-label={t("harborWalkControls")}
      onPointerDown={(event) => {
        event.preventDefault();
        event.stopPropagation();
        if (activePointer.current !== null) return;
        activePointer.current = event.pointerId;
        event.currentTarget.setPointerCapture(event.pointerId);
        updateInput(event);
      }}
      onPointerMove={(event) => {
        if (activePointer.current !== event.pointerId) return;
        event.preventDefault();
        event.stopPropagation();
        updateInput(event);
      }}
      onPointerUp={release}
      onPointerCancel={release}
      onLostPointerCapture={(event) => {
        if (activePointer.current !== event.pointerId) return;
        activePointer.current = null;
        setKnob({ x: 0, y: 0 });
        onInput({ x: 0, z: 0 });
      }}
    >
      <span className="direction up" aria-hidden="true">↑</span>
      <span className="direction left" aria-hidden="true">←</span>
      <span className="direction right" aria-hidden="true">→</span>
      <span className="direction down" aria-hidden="true">↓</span>
      <span
        className="joystick-knob"
        aria-hidden="true"
        style={{ transform: `translate3d(${knob.x}px, ${knob.y}px, 0)` }}
      >
        <span />
      </span>
    </div>
  );
}

function HarborSailingControls({
  onSteer,
  position,
}: {
  onSteer: (direction: -1 | 1) => void;
  position: number;
}) {
  const repeatTimer = useRef<number | undefined>(undefined);
  const stop = useCallback(() => {
    window.clearInterval(repeatTimer.current);
    repeatTimer.current = undefined;
  }, []);
  useEffect(() => stop, [stop]);

  const start = (
    event: ReactPointerEvent<HTMLButtonElement>,
    direction: -1 | 1,
  ) => {
    event.preventDefault();
    event.stopPropagation();
    stop();
    // iOSの一部バージョンではbuttonのpointer captureが例外になることがある。
    // 操船を先に確定し、captureは長押し継続の補助としてだけ試す。
    onSteer(direction);
    try {
      event.currentTarget.setPointerCapture(event.pointerId);
    } catch {
      // 一度のタップ移動はすでに反映済み。clickへ重ねて送らない。
    }
    repeatTimer.current = window.setInterval(() => onSteer(direction), 80);
  };
  const release = (event: ReactPointerEvent<HTMLButtonElement>) => {
    event.stopPropagation();
    stop();
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
  };

  return (
    <div
      className="harbor-sailing-controls"
      role="group"
      aria-label={t("harborSailingControls")}
      onPointerDown={(event) => event.stopPropagation()}
    >
      <button
        type="button"
        aria-label={t("harborSteerLeft")}
        onPointerDown={(event) => start(event, -1)}
        onPointerUp={release}
        onPointerCancel={release}
        onLostPointerCapture={stop}
        onClick={(event) => {
          if (event.detail === 0) onSteer(-1);
        }}
      >
        ←
      </button>
      <span className="harbor-sailing-position" aria-hidden="true">
        <i
          style={{
            left: `${((position + HARBOR_SAIL_MAX_OFFSET) /
              (HARBOR_SAIL_MAX_OFFSET * 2)) * 100}%`,
          }}
        />
      </span>
      <button
        type="button"
        aria-label={t("harborSteerRight")}
        onPointerDown={(event) => start(event, 1)}
        onPointerUp={release}
        onPointerCancel={release}
        onLostPointerCapture={stop}
        onClick={(event) => {
          if (event.detail === 0) onSteer(1);
        }}
      >
        →
      </button>
    </div>
  );
}

/// 共同航海の一隻。停泊用の MemberBoat と違い、航跡を引きながら同じ向きへ進む。
/// 船の前後差は在室時間や作業量ではなく、単なる並走レーンとして固定する。
function HarborSailingBoat({
  member,
  x,
  z,
  scale,
  animate,
  live,
  fishingRod,
  sailorPose,
  sailorKey,
  self,
}: {
  member?: HarborMember;
  x: number;
  z: number;
  scale: number;
  animate: boolean;
  live: boolean;
  fishingRod: boolean;
  sailorPose: PhoenixPose;
  sailorKey: number;
  self: boolean;
}) {
  const parts = useMemo(
    () =>
      member
        ? boatPartsFromIds({
            boatSail: member.boatSail,
            boatJib: member.boatJib,
            boatHull: member.boatHull,
            boatStripe: member.boatStripe,
            boatFlag: member.boatFlag,
          })
        : boatProps(),
    [member],
  );
  const root = useRef<THREE.Group>(null);
  const initialPosition = useRef<[number, number, number]>([x, 0, z]);
  const phase = useMemo(() => {
    const id = member?.id ?? "self";
    let hash = 0;
    for (const char of id) hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
    return (hash % 628) / 100;
  }, [member?.id]);

  useFrame(({ clock }, delta) => {
    if (!root.current) return;
    if (!animate) {
      root.current.position.set(x, 0, z);
      root.current.rotation.z = 0;
      return;
    }
    const time = clock.elapsedTime;
    root.current.position.x = THREE.MathUtils.damp(
      root.current.position.x,
      x + Math.sin(time * 0.28 + phase) * 0.16,
      // 自分の操作は軽快に、低頻度で届く相手の座標は次の更新まで滑らかに補間。
      self ? 8 : 3.5,
      delta,
    );
    root.current.position.y = Math.sin(time * 0.72 + phase) * 0.045;
    root.current.rotation.z = Math.sin(time * 0.55 + phase * 1.4) * 0.018;
  });

  return (
    <group
      ref={root}
      position={initialPosition.current}
      rotation={[0, 0.1, 0]}
      scale={scale}
    >
      <Wake animate={animate} />
      <BoatModel parts={parts} animate={animate} />
      <group position={[0.88, 0.57, 0.22]} scale={0.62}>
        <PhoenixModel
          key={sailorKey}
          animate={animate}
          pose={sailorPose}
          fishingRod={fishingRod}
        />
      </group>
      <Html
        position={[0.1, 1.48, 0]}
        center
        distanceFactor={8}
        zIndexRange={[2, 0]}
        style={{ pointerEvents: "none" }}
      >
        <div className={`harbor-sailing-name${live ? " live" : ""}`}>
          {live && <span aria-hidden="true" />}
          {self ? t("you") : member?.displayName ?? t("sailor")}
        </div>
      </Html>
    </group>
  );
}

/// 港から船へ乗ったあとの沖合。個人タイマーと同じ海・光・画角の中で、
/// 港の最大4隻が順位を作らず横並びに航行する。
function HarborSailingSea({
  currentUid,
  members,
  livePresence,
  timeOfDay,
  animate,
  fishingRod,
  ownPose,
  ownPoseKey,
  ownSailX,
}: {
  currentUid: string;
  members: HarborMember[];
  livePresence: ReadonlyMap<string, HarborPresence>;
  timeOfDay: TimeOfDay;
  animate: boolean;
  fishingRod: boolean;
  ownPose: PhoenixPose;
  ownPoseKey: number;
  ownSailX: number;
}) {
  const camera = useThree((state) => state.camera);
  const invalidate = useThree((state) => state.invalidate);
  const light = SEA_LIGHT[timeOfDay];
  const lightPosition = HARBOR_SAIL_LIGHT_POS[timeOfDay];
  const ownMember = members.find((member) => member.id === currentUid);
  const companions = members
    .filter((member) => member.id !== currentUid)
    .slice(0, HARBOR_SAIL_LANES.length);

  useLayoutEffect(() => {
    camera.position.set(...HARBOR_SAIL_CAM_POS);
    if (camera instanceof THREE.PerspectiveCamera) {
      camera.fov = HARBOR_SAIL_FOV;
      camera.updateProjectionMatrix();
    }
    camera.lookAt(...HARBOR_SAIL_CAM_TARGET);
    invalidate();
  }, [camera, invalidate]);

  return (
    <>
      <color attach="background" args={[light.sky]} />
      <fog attach="fog" args={[light.fog, 12, 34]} />
      <ambientLight color={light.ambient} intensity={timeOfDay === "day" ? 0.85 : 0.48} />
      <directionalLight
        color={light.keyLight}
        intensity={timeOfDay === "day" ? 1.45 : 1.08}
        position={[-6, 8, -5]}
      />
      <directionalLight color={light.fillLight} intensity={0.24} position={[5, 3, 6]} />
      {light.stars > 0 && (
        <Stars
          radius={42}
          depth={18}
          count={light.stars}
          factor={2}
          saturation={0}
          fade
          speed={animate ? 0.5 : 0}
        />
      )}
      <group position={lightPosition} scale={light.celestial === "moon" ? 0.4 : 0.72}>
        {light.celestial === "moon" ? (
          <Moon position={[0, 0, 0]} />
        ) : (
          <Sun position={[0, 0, 0]} color={light.reflection} />
        )}
      </group>
      <Sea
        moonX={lightPosition[0]}
        animate={animate}
        seaColor={light.sea}
        deepColor={light.seaDeep}
        lightColor={light.reflection}
        reflection={timeOfDay === "day" ? 0.34 : 0.5}
      />
      <Horizon />
      <PassingSwells animate={animate} flow={1} />
      {timeOfDay !== "night" && <Gulls flock={HARBOR_SAIL_GULLS} animate={animate} />}
      <group rotation={[0, 0.64, 0]}>
        <PassingShip animate={animate} />
      </group>

      <HarborSailingBoat
        member={ownMember}
        x={ownSailX}
        z={0}
        scale={0.55}
        animate={animate}
        live
        fishingRod={fishingRod}
        sailorPose={ownPose}
        sailorKey={ownPoseKey}
        self
      />
      {companions.map((member, index) => {
        const lane = HARBOR_SAIL_LANES[index];
        const presence = livePresence.get(member.id);
        return (
          <HarborSailingBoat
            key={member.id}
            member={member}
            x={lane.x + (presence?.sailX ?? 0)}
            z={lane.z}
            scale={lane.scale}
            animate={animate}
            live={Boolean(presence)}
            fishingRod={Boolean(presence?.fishingRod)}
            sailorPose={
              presence?.aboard ? (presence.pose as PhoenixPose) : "idle"
            }
            sailorKey={presence?.emoteSeq ?? 0}
            self={false}
          />
        );
      })}
      <OrbitControls
        target={HARBOR_SAIL_CAM_TARGET}
        enablePan={false}
        enableDamping={animate}
        minDistance={4}
        maxDistance={16}
        minPolarAngle={Math.PI * 0.12}
        maxPolarAngle={Math.PI * 0.49}
      />
    </>
  );
}

/// シーン本体。時間帯の海+砂の拠点+停泊する船団+沖の航路の海域(海獣/嵐)。
function HarborSea({
  roomName,
  timeOfDay,
  berths,
  litIds,
  arrivingMemberIds,
  animate,
  encounter,
  advanceOn,
  arriveFx,
  hitClock,
  bolts,
  onBoltDone,
  immersive,
  phase,
  onEnterWorld,
  onWorldEntered,
  onWorldExited,
  walkInput,
  look,
  currentUid,
  ownBerth,
  aboard,
  controlsLocked,
  fishingRodOwned,
  fishingRodVisible,
  equipmentAction,
  emotePose,
  emoteSeq,
  restingAtTent,
  livePresence,
  onNearOwnBoatChange,
  onNearFishingRodChange,
  onNearTentChange,
  onWalkerTransform,
  onMovementStart,
  onBoardOwnBoat,
}: {
  roomName: string;
  timeOfDay: TimeOfDay;
  berths: Berth[];
  litIds: ReadonlySet<string>;
  arrivingMemberIds: ReadonlySet<string>;
  animate: boolean;
  encounter: EncounterView | null;
  /// 到着済み(船団を島へ寄せる)。マウント時に真なら最初から寄せた位置で描く。
  advanceOn: boolean;
  /// 到着の演出中(光がふわっと明るくなる)。
  arriveFx: boolean;
  hitClock: { current: number };
  bolts: Bolt[];
  onBoltDone: (id: number) => void;
  /// 没入(みんなの海に入る)モードと入退場フェーズ。
  immersive: boolean;
  phase: WorldPhase;
  /// コンパクト時、海(空・水面)をタップすると世界へ入る。
  onEnterWorld: () => void;
  onWorldEntered: () => void;
  onWorldExited: () => void;
  walkInput: HarborWalkInputRef;
  look: HarborLookRef;
  currentUid: string;
  ownBerth?: Berth;
  aboard: boolean;
  controlsLocked: boolean;
  fishingRodOwned: boolean;
  fishingRodVisible: boolean;
  equipmentAction: EquipmentAction;
  emotePose: HarborEmotePose | null;
  emoteSeq: number;
  restingAtTent: boolean;
  livePresence: ReadonlyMap<string, HarborPresence>;
  onNearOwnBoatChange: (near: boolean) => void;
  onNearFishingRodChange: (near: boolean) => void;
  onNearTentChange: (near: boolean) => void;
  onWalkerTransform: (transform: HarborWalkerTransform) => void;
  onMovementStart: () => void;
  onBoardOwnBoat: () => void;
}) {
  const camera = useThree((s) => s.camera);
  const invalidate = useThree((s) => s.invalidate);
  const fleet = useRef<THREE.Group>(null);
  const keyLight = useRef<THREE.DirectionalLight>(null);
  const fillLight = useRef<THREE.DirectionalLight>(null);
  const ambient = useRef<THREE.AmbientLight>(null);
  const advance = useRef(advanceOn ? 1 : 0);
  const dim = useRef(1);
  const arriveClock = useRef<number | null>(null);
  const light = SEA_LIGHT[timeOfDay];
  const memberById = useMemo(
    () => new Map(berths.map((berth) => [berth.member.id, berth.member])),
    [berths],
  );

  // 海域の中では海がわずかに暗く、潮目が進むごとに明るさが戻る。
  const dimTarget =
    encounter && !encounter.defeating ? 0.62 + encounter.phase * 0.13 : 1;
  const advanceTarget = advanceOn ? 1 : 0;

  const applyVoyageLook = () => {
    if (keyLight.current) {
      keyLight.current.intensity = (timeOfDay === "day" ? 1.45 : 1.08) * dim.current;
    }
    if (fillLight.current) fillLight.current.intensity = 0.25 * dim.current;
    if (ambient.current) {
      ambient.current.intensity =
        (timeOfDay === "day" ? 0.85 : 0.48) * (0.6 + 0.4 * dim.current);
    }
    // 到着後は船団が桟橋へほんの少し寄り、港へ戻った余韻だけを残す。
    fleet.current?.position.set(0, 0, advance.current * -0.22);
  };

  // 固定の斜め視点(VoyageSceneと同じ作法)。スクロール中の帯なので
  // OrbitControlsは使わない — タッチ回転が縦スクロールを塞ぐため。
  useLayoutEffect(() => {
    camera.position.set(...CAM_POS);
    if (camera instanceof THREE.PerspectiveCamera) {
      camera.fov = 36;
      camera.updateProjectionMatrix();
    }
    camera.lookAt(CAM_TARGET[0], CAM_TARGET[1], CAM_TARGET[2]);
    invalidate();
  }, [camera, invalidate]);

  // reduced-motion時はジャンプカット: 目標値へ直接置いて一度だけ描く。
  useLayoutEffect(() => {
    if (animate) return;
    dim.current = dimTarget;
    advance.current = advanceTarget;
    applyVoyageLook();
    invalidate();
  });

  useFrame(({ clock }, delta) => {
    if (!animate) return;
    const time = clock.elapsedTime;
    // 到着の瞬間を覚えて、光をふわっと明るくする。
    if (arriveFx && arriveClock.current === null) arriveClock.current = time;
    if (!arriveFx) arriveClock.current = null;
    let target = dimTarget;
    if (arriveClock.current !== null) {
      const dt = time - arriveClock.current;
      if (dt > 1.2 && dt < 3.4) target = 1.22;
    }
    dim.current = THREE.MathUtils.damp(dim.current, target, 1.6, delta);
    advance.current = THREE.MathUtils.damp(advance.current, advanceTarget, 0.9, delta);
    applyVoyageLook();
  });

  return (
    <>
      <color attach="background" args={[light.sky]} />
      <fog attach="fog" args={[light.fog, 12, 31]} />
      {/* 航海中の海と同じ時刻・同じ光。港だけ別の夜にはしない。 */}
      <ambientLight
        ref={ambient}
        color={light.ambient}
        intensity={timeOfDay === "day" ? 0.85 : 0.48}
      />
      <directionalLight
        ref={keyLight}
        color={light.keyLight}
        intensity={timeOfDay === "day" ? 1.45 : 1.08}
        position={timeOfDay === "morning" ? [-7, 5, -8] : [-6, 8, -5]}
      />
      <directionalLight
        ref={fillLight}
        color={light.fillLight}
        intensity={0.25}
        position={[5, 3, 6]}
      />
      <Stars
        radius={42}
        depth={18}
        count={light.stars}
        factor={2.0}
        saturation={0}
        fade
        speed={animate ? 0.5 : 0}
      />
      {light.celestial === "moon" ? (
        <Moon position={[-8, 2.8, -16]} />
      ) : (
        <Sun
          position={timeOfDay === "evening" ? [-7, 2.4, -16] : [-7, 5.2, -16]}
          color={light.reflection}
        />
      )}
      <Sea
        moonX={-7}
        animate={animate}
        seaColor={light.sea}
        deepColor={light.seaDeep}
        lightColor={light.reflection}
        reflection={timeOfDay === "day" ? 0.34 : 0.5}
      />
      <Horizon />
      <HarborTown timeOfDay={timeOfDay} />
      {!fishingRodOwned && <HarborFishingRod animate={animate} />}
      {immersive && (
        <HarborWalker
          active={phase === "idle" && !controlsLocked}
          animate={animate}
          input={walkInput}
          look={look}
          aboard={aboard}
          ownBerth={ownBerth}
          fishingRod={fishingRodVisible}
          fishingRodAvailable={!fishingRodOwned}
          equipmentAction={equipmentAction}
          emotePose={emotePose}
          emoteSeq={emoteSeq}
          restingAtTent={restingAtTent}
          onNearOwnBoatChange={onNearOwnBoatChange}
          onNearFishingRodChange={onNearFishingRodChange}
          onNearTentChange={onNearTentChange}
          onTransformChange={onWalkerTransform}
          onMovementStart={onMovementStart}
        />
      )}
      {Array.from(livePresence.values()).map((presence) => {
        const member = memberById.get(presence.uid);
        return member && !presence.aboard ? (
          <RemoteHarborSailor
            key={presence.uid}
            presence={presence}
            member={member}
            animate={animate}
          />
        ) : null;
      })}
      <Html
        position={[0.75, 2.35, -3.25]}
        center
        distanceFactor={9}
        zIndexRange={[1, 0]}
        style={{ pointerEvents: "none" }}
      >
        <div className="harbor-world-island">{roomName}</div>
      </Html>
      {/* 海域: 砂島の外に見えるハリケーン/海獣。拠点へは入れない。 */}
      {encounter &&
        (encounter.kind === "storm" ? (
          <Hurricane
            phase={encounter.phase}
            defeating={encounter.defeating}
            animate={animate}
            hitClock={hitClock}
          />
        ) : (
          <Kraken
            phase={encounter.phase}
            defeating={encounter.defeating}
            animate={animate}
            hitClock={hitClock}
          />
        ))}
      {bolts.map((bolt) => (
        <StrikeBolt
          key={bolt.id}
          from={bolt.from}
          hitClock={hitClock}
          onDone={() => onBoltDone(bolt.id)}
        />
      ))}
      {/* 船団。砂地の前へ固定し、帰港時だけ桟橋へわずかに寄せる。 */}
      <group ref={fleet}>
        {berths.map((berth) => {
          const isSelf = berth.member.id === currentUid;
          const remote = isSelf ? undefined : livePresence.get(berth.member.id);
          const rod = isSelf ? fishingRodVisible : Boolean(remote?.fishingRod);
          const pose = isSelf
            ? activeNavigatorPose(equipmentAction, emotePose, rod, false)
            : remote?.aboard
              ? (remote.pose as PhoenixPose)
              : litIds.has(berth.member.id)
                ? "raise"
                : "idle";
          return (
            <MemberBoat
              key={berth.member.id}
              berth={berth}
              lit={litIds.has(berth.member.id)}
              animate={animate}
              arriving={arrivingMemberIds.has(berth.member.id)}
              showSailor={
                isSelf ? !immersive || aboard : !remote || remote.aboard
              }
              fishingRod={rod}
              sailorPose={pose}
              sailorKey={isSelf ? emoteSeq : remote?.emoteSeq ?? 0}
              onBoard={
                immersive && !aboard && isSelf ? onBoardOwnBoat : undefined
              }
            />
          );
        })}
      </group>
      {/* コンパクト時、船以外(空・水面)をどこでもタップで世界へ入るための、
          見えない受け皿。中を向いた大球で、船・月より奥に置く(船のタップが
          stopPropagationで勝つので、船=軌跡/それ以外=入場、と自然に分かれる)。 */}
      {!immersive && (
        <mesh onClick={onEnterWorld}>
          <sphereGeometry args={[46, 16, 12]} />
          <meshBasicMaterial
            side={THREE.BackSide}
            transparent
            opacity={0}
            depthWrite={false}
          />
        </mesh>
      )}
      {immersive && (
        <ImmersiveCamera
          phase={phase}
          animate={animate}
          onEntered={onWorldEntered}
          onExited={onWorldExited}
        />
      )}
    </>
  );
}

/// 帰港する3Dの拠点。桟橋・砂地・写真・チャット・共同航海を一つにする。
export default function HarborWorld({
  currentUid,
  room,
  members,
  voyage,
  route,
  progressMinutes = 0,
  strike,
  arrivingMemberIds = new Set<string>(),
  immersiveChat,
}: HarborWorldProps) {
  const timeOfDay = useTimeOfDay();
  const harborLight = SEA_LIGHT[timeOfDay];
  const [animate] = useState(
    () => !window.matchMedia("(prefers-reduced-motion: reduce)").matches,
  );
  const rootRef = useRef<HTMLDivElement>(null);
  const glRef = useRef<RootState | null>(null);
  const [flash, setFlash] = useState(false);
  const flashTimer = useRef<number | undefined>(undefined);
  const [inventory, setInventory] = useState<NavigatorInventory>(() =>
    loadNavigatorInventory(currentUid),
  );
  const inventoryUid = useRef(currentUid);
  const [bagOpen, setBagOpen] = useState(false);
  const [nearFishingRod, setNearFishingRod] = useState(false);
  const [nearTent, setNearTent] = useState(false);
  const [restingAtTent, setRestingAtTent] = useState(false);
  const [equipmentAction, setEquipmentAction] = useState<EquipmentAction>(null);
  const equipmentTimers = useRef<number[]>([]);
  const [emoteOpen, setEmoteOpen] = useState(false);
  const [emotePose, setEmotePose] = useState<HarborEmotePose | null>(null);
  const [emoteSeq, setEmoteSeq] = useState(0);
  const emoteTimer = useRef<number | undefined>(undefined);
  const [inventoryNotice, setInventoryNotice] = useState("");
  const noticeTimer = useRef<number | undefined>(undefined);

  useEffect(() => {
    if (inventoryUid.current === currentUid) return;
    inventoryUid.current = currentUid;
    setInventory(loadNavigatorInventory(currentUid));
    setBagOpen(false);
    setNearFishingRod(false);
    setNearTent(false);
    setRestingAtTent(false);
    setEquipmentAction(null);
    setEmoteOpen(false);
    setEmotePose(null);
  }, [currentUid]);

  useEffect(() => {
    if (inventoryUid.current === currentUid) {
      saveNavigatorInventory(currentUid, inventory);
    }
  }, [currentUid, inventory]);

  useEffect(
    () => () => {
      equipmentTimers.current.forEach((id) => window.clearTimeout(id));
      window.clearTimeout(emoteTimer.current);
      window.clearTimeout(noticeTimer.current);
    },
    [],
  );

  const showInventoryNotice = useCallback((message: string) => {
    setInventoryNotice(message);
    window.clearTimeout(noticeTimer.current);
    noticeTimer.current = window.setTimeout(() => setInventoryNotice(""), 2600);
  }, []);

  const stopEmote = useCallback(() => {
    window.clearTimeout(emoteTimer.current);
    setEmotePose(null);
  }, []);

  // ---- 没入(みんなの海に入る) ----
  // プライベート港は「参加者とすでに航海している」景色から始める。
  // 港町は消さず、船を降りたときに従来の島・桟橋へ戻れる二層構造にする。
  const [immersive, setImmersive] = useState(true);
  const [phase, setPhase] = useState<WorldPhase>("idle");
  const [aboard, setAboard] = useState(true);
  const [sailX, setSailX] = useState(0);
  const [nearOwnBoat, setNearOwnBoat] = useState(false);
  const [walkControlSettings, setWalkControlSettings] = useState(
    loadHarborControlSettings,
  );
  const walkInput = useRef<HarborWalkInput>({ x: 0, z: 0 });
  const setWalkInput = useCallback((next: HarborWalkInput) => {
    walkInput.current = next;
  }, []);
  const steerBoat = useCallback((direction: -1 | 1) => {
    setSailX((current) =>
      THREE.MathUtils.clamp(
        current + direction * HARBOR_SAIL_STEP,
        -HARBOR_SAIL_MAX_OFFSET,
        HARBOR_SAIL_MAX_OFFSET,
      ),
    );
  }, []);
  useEffect(() => {
    const syncSettings = (event: Event) => {
      const detail = (event as CustomEvent<HarborControlSettings>).detail;
      setWalkControlSettings(detail ?? loadHarborControlSettings());
    };
    window.addEventListener(HARBOR_CONTROL_SETTINGS_EVENT, syncSettings);
    return () =>
      window.removeEventListener(HARBOR_CONTROL_SETTINGS_EVENT, syncSettings);
  }, []);
  const fishingRodOwned = inventory.items.includes("fishingRod");
  // 解除中は、手からバッグへ届くまでモデルを残す。
  const fishingRodVisible =
    inventory.equipped === "fishingRod" || equipmentAction === "unequip";

  const pickUpFishingRod = useCallback(() => {
    if (equipmentAction || fishingRodOwned || !nearFishingRod) return;
    stopEmote();
    setWalkInput({ x: 0, z: 0 });
    setEquipmentAction("pickup");
    equipmentTimers.current.forEach((id) => window.clearTimeout(id));
    equipmentTimers.current.length = 0;
    equipmentTimers.current.push(
      window.setTimeout(() => {
        setInventory((current) =>
          current.items.includes("fishingRod")
            ? current
            : { ...current, items: [...current.items, "fishingRod"] },
        );
        setNearFishingRod(false);
        showInventoryNotice(t("fishingRodFound"));
      }, animate ? 680 : 0),
      window.setTimeout(() => setEquipmentAction(null), animate ? 1120 : 0),
    );
  }, [
    animate,
    equipmentAction,
    fishingRodOwned,
    nearFishingRod,
    setWalkInput,
    showInventoryNotice,
    stopEmote,
  ]);

  const toggleFishingRod = useCallback(() => {
    if (equipmentAction || !fishingRodOwned) return;
    stopEmote();
    setWalkInput({ x: 0, z: 0 });
    equipmentTimers.current.forEach((id) => window.clearTimeout(id));
    equipmentTimers.current.length = 0;
    if (inventory.equipped === "fishingRod") {
      setEquipmentAction("unequip");
      equipmentTimers.current.push(
        window.setTimeout(() => {
          setInventory((current) => ({ ...current, equipped: null }));
          showInventoryNotice(t("fishingRodUnequipped"));
        }, animate ? 620 : 0),
        window.setTimeout(() => setEquipmentAction(null), animate ? 1180 : 0),
      );
      return;
    }
    setEquipmentAction("equip");
    equipmentTimers.current.push(
      window.setTimeout(() => {
        setInventory((current) => ({ ...current, equipped: "fishingRod" }));
        showInventoryNotice(t("fishingRodEquipped"));
      }, animate ? 360 : 0),
      window.setTimeout(() => setEquipmentAction(null), animate ? 1180 : 0),
    );
  }, [
    animate,
    equipmentAction,
    fishingRodOwned,
    inventory.equipped,
    setWalkInput,
    showInventoryNotice,
    stopEmote,
  ]);

  const playEmote = useCallback(
    (pose: HarborEmotePose) => {
      if (equipmentAction) return;
      setWalkInput({ x: 0, z: 0 });
      window.clearTimeout(emoteTimer.current);
      setEmotePose(pose);
      setEmoteSeq((sequence) => (sequence + 1) % 2147483647);
      setEmoteOpen(false);
      emoteTimer.current = window.setTimeout(
        () => setEmotePose(null),
        animate ? (pose === "read" ? 8_000 : 4_200) : 1_800,
      );
    },
    [animate, equipmentAction, setWalkInput],
  );

  // ---- 同じ港にいる航海士のリアルタイム同期 ----
  const [presenceRows, setPresenceRows] = useState<HarborPresence[]>([]);
  const [presenceClock, setPresenceClock] = useState(0);
  const [pageVisible, setPageVisible] = useState(
    () => typeof document === "undefined" || document.visibilityState !== "hidden",
  );
  useEffect(() => {
    const updateVisibility = () =>
      setPageVisible(document.visibilityState !== "hidden");
    document.addEventListener("visibilitychange", updateVisibility);
    return () =>
      document.removeEventListener("visibilitychange", updateVisibility);
  }, []);
  useEffect(() => {
    if (isDemo || !immersive || !pageVisible) {
      setPresenceRows([]);
      return;
    }
    return listenHarborPresence(room.id, currentUid, setPresenceRows);
  }, [currentUid, immersive, pageVisible, room.id]);
  useEffect(() => {
    const timer = window.setInterval(
      () => setPresenceClock((clock) => clock + 1),
      5_000,
    );
    return () => window.clearInterval(timer);
  }, []);
  const livePresence = (() => {
    void presenceClock;
    const now = Date.now();
    const memberIds = new Set(members.map((member) => member.id));
    const result = new Map<string, HarborPresence>();
    for (const presence of presenceRows) {
      if (presence.uid === currentUid || !memberIds.has(presence.uid)) continue;
      if (now - presence.updatedAt.getTime() > HARBOR_PRESENCE_STALE_MS) continue;
      result.set(presence.uid, presence);
    }
    return result;
  })();

  const walkerTransform = useRef<HarborWalkerTransform>({
    x: WALK_START.x,
    z: WALK_START.z,
    yaw: Math.PI + WALKER_FRONT_YAW,
    walking: false,
  });
  const pendingPresence = useRef<HarborPresencePayload | null>(null);
  const presenceSendTimer = useRef<number | undefined>(undefined);
  const lastPresenceWrite = useRef(0);
  const lastPublishedPresence = useRef<HarborPresencePayload | null>(null);
  const flushPresence = useCallback(() => {
    presenceSendTimer.current = undefined;
    const next = pendingPresence.current;
    pendingPresence.current = null;
    if (
      !next ||
      isDemo ||
      !pageVisible ||
      document.visibilityState === "hidden"
    ) {
      return;
    }
    lastPresenceWrite.current = Date.now();
    lastPublishedPresence.current = next;
    void publishHarborPresence(room.id, next).catch(() => {
      if (lastPublishedPresence.current === next) {
        lastPublishedPresence.current = null;
      }
    });
  }, [pageVisible, room.id]);
  const queuePresence = useCallback(
    (
      next: HarborPresencePayload,
      priority: HarborPresencePriority = "movement",
    ) => {
      if (isDemo || !pageVisible) return;

      const previous = lastPublishedPresence.current;
      if (priority === "immediate") {
        if (previous && !presenceStatusChanged(previous, next)) return;
        pendingPresence.current = next;
        window.clearTimeout(presenceSendTimer.current);
        flushPresence();
        return;
      }
      if (priority === "heartbeat") {
        pendingPresence.current = next;
        window.clearTimeout(presenceSendTimer.current);
        flushPresence();
        return;
      }

      // 送信待ちがある間は最新座標へ差し替える。待ちがなければ、前回送信値
      // から見た目に出ない程度の差しかない更新を破棄する。
      if (pendingPresence.current) {
        pendingPresence.current = next;
        return;
      }
      if (previous && !presenceMovementChanged(previous, next)) return;
      pendingPresence.current = next;
      const wait = Math.max(
        0,
        HARBOR_PRESENCE_MOVE_INTERVAL_MS -
          (Date.now() - lastPresenceWrite.current),
      );
      if (wait === 0) {
        window.clearTimeout(presenceSendTimer.current);
        flushPresence();
      } else if (presenceSendTimer.current === undefined) {
        presenceSendTimer.current = window.setTimeout(flushPresence, wait);
      }
    },
    [flushPresence, pageVisible],
  );
  const currentPresence = useCallback(
    (transform = walkerTransform.current): HarborPresencePayload => ({
      x: transform.x,
      z: transform.z,
      yaw: transform.yaw,
      pose: activeNavigatorPose(
        equipmentAction,
        emotePose,
        fishingRodVisible,
        transform.walking && !aboard,
        restingAtTent,
      ),
      aboard,
      sailX,
      fishingRod: fishingRodVisible,
      emoteSeq,
    }),
    [
      aboard,
      emotePose,
      emoteSeq,
      equipmentAction,
      fishingRodVisible,
      restingAtTent,
      sailX,
    ],
  );
  const currentPresenceRef = useRef(currentPresence);
  currentPresenceRef.current = currentPresence;
  const handleWalkerTransform = useCallback(
    (transform: HarborWalkerTransform) => {
      walkerTransform.current = transform;
      if (immersive && pageVisible && phase === "idle") {
        queuePresence(currentPresence(transform));
      }
    },
    [currentPresence, immersive, pageVisible, phase, queuePresence],
  );

  // 仕草・装備・乗降の変化は、座標が止まっていてもすぐ共有する。
  useEffect(() => {
    if (!immersive || !pageVisible || phase !== "idle") return;
    queuePresence(currentPresenceRef.current(), "immediate");
  }, [
    aboard,
    emotePose,
    emoteSeq,
    equipmentAction,
    fishingRodVisible,
    immersive,
    pageVisible,
    phase,
    queuePresence,
    restingAtTent,
  ]);

  // 船の横移動は連打中も一秒ごとの最新位置だけを共有する。
  useEffect(() => {
    if (!immersive || !pageVisible || phase !== "idle") return;
    queuePresence(currentPresenceRef.current());
  }, [immersive, pageVisible, phase, queuePresence, sailX]);

  // 停止中は15秒に一度だけ在席を更新する。タブが隠れたら購読も送信も止め、
  // 在席ドキュメントを削除して他ユーザー側の不要な読み取りも発生させない。
  useEffect(() => {
    if (!immersive || !pageVisible || isDemo) return;
    const heartbeat = window.setInterval(
      () => queuePresence(currentPresenceRef.current(), "heartbeat"),
      HARBOR_PRESENCE_HEARTBEAT_MS,
    );
    return () => {
      window.clearInterval(heartbeat);
      window.clearTimeout(presenceSendTimer.current);
      presenceSendTimer.current = undefined;
      pendingPresence.current = null;
      lastPresenceWrite.current = 0;
      lastPublishedPresence.current = null;
      void clearHarborPresence(room.id).catch(() => {});
    };
  }, [immersive, pageVisible, queuePresence, room.id]);

  const look = useRef<HarborLookState>({ yaw: 0, pitch: 0.38 });
  const lookDrag = useRef<{ pointerId: number; x: number; y: number } | null>(null);
  const enterWorld = useCallback(() => {
    setImmersive((on) => {
      if (on) return on;
      look.current = { yaw: 0, pitch: 0.38 };
      setAboard(false);
      setNearOwnBoat(false);
      setNearTent(false);
      setRestingAtTent(false);
      setPhase(
        window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "idle" : "enter",
      );
      return true;
    });
  }, []);
  const requestClose = useCallback(() => {
    setWalkInput({ x: 0, z: 0 });
    setNearOwnBoat(false);
    setNearTent(false);
    setRestingAtTent(false);
    setEmoteOpen(false);
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setImmersive(false);
      setPhase("idle");
      return;
    }
    setPhase((p) => (p === "exit" ? p : "exit"));
  }, [setWalkInput]);
  const handleWorldEntered = useCallback(() => {
    setPhase((p) => (p === "enter" ? "idle" : p));
  }, []);
  const handleWorldExited = useCallback(() => {
    setImmersive(false);
    setPhase("idle");
    setAboard(false);
    setNearOwnBoat(false);
    setNearTent(false);
    setRestingAtTent(false);
    setEmoteOpen(false);
    stopEmote();
  }, [stopEmote]);
  const boardOwnBoat = useCallback(() => {
    setWalkInput({ x: 0, z: 0 });
    setNearOwnBoat(false);
    setSailX(0);
    setAboard(true);
  }, [setWalkInput]);
  const leaveSailing = useCallback(() => {
    setWalkInput({ x: 0, z: 0 });
    setBagOpen(false);
    setEmoteOpen(false);
    setSailX(0);
    setAboard(false);
    setNearOwnBoat(false);
  }, [setWalkInput]);
  const beginLook = useCallback(
    (event: ReactPointerEvent<HTMLDivElement>) => {
      // 航海中の見渡し操作は OrbitControls に任せる。港町だけ、航海士を
      // 中心にする独自カメラ操作を使う。
      if (aboard || !immersive || !(event.target instanceof HTMLCanvasElement)) return;
      event.preventDefault();
      lookDrag.current = {
        pointerId: event.pointerId,
        x: event.clientX,
        y: event.clientY,
      };
      event.currentTarget.setPointerCapture(event.pointerId);
    },
    [aboard, immersive],
  );
  const moveLook = useCallback((event: ReactPointerEvent<HTMLDivElement>) => {
    const drag = lookDrag.current;
    if (!drag || drag.pointerId !== event.pointerId) return;
    event.preventDefault();
    const dx = event.clientX - drag.x;
    const dy = event.clientY - drag.y;
    drag.x = event.clientX;
    drag.y = event.clientY;
    const nextYaw = look.current.yaw - dx * 0.007;
    look.current.yaw = Math.atan2(Math.sin(nextYaw), Math.cos(nextYaw));
    look.current.pitch = THREE.MathUtils.clamp(
      look.current.pitch + dy * 0.005,
      0.18,
      1.02,
    );
  }, []);
  const endLook = useCallback((event: ReactPointerEvent<HTMLDivElement>) => {
    if (lookDrag.current?.pointerId !== event.pointerId) return;
    lookDrag.current = null;
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
  }, []);

  // 没入中は背景スクロールを固定する。Escの状態更新とは寿命を分け、
  // iOS Safariでoverflowを再描画のたびに切り替えない。
  useBodyScrollLock(immersive);

  // 没入中は Esc で出る(背景固定は上の専用Hookが受け持つ)。
  useEffect(() => {
    if (!immersive) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      if (bagOpen) setBagOpen(false);
      else if (emoteOpen) setEmoteOpen(false);
      else if (restingAtTent) setRestingAtTent(false);
      else if (aboard) leaveSailing();
      else requestClose();
    };
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("keydown", onKey);
    };
  }, [
    aboard,
    bagOpen,
    emoteOpen,
    immersive,
    leaveSailing,
    requestClose,
    restingAtTent,
  ]);

  // 共同航海中はA/Dと左右キーでも、固定レーンの中だけ少し操船できる。
  useEffect(() => {
    if (!immersive || !aboard || bagOpen || emoteOpen) return;
    const onSteerKey = (event: KeyboardEvent) => {
      if (event.code === "KeyA" || event.code === "ArrowLeft") {
        event.preventDefault();
        steerBoat(-1);
      } else if (event.code === "KeyD" || event.code === "ArrowRight") {
        event.preventDefault();
        steerBoat(1);
      }
    };
    window.addEventListener("keydown", onSteerKey);
    return () => window.removeEventListener("keydown", onSteerKey);
  }, [aboard, bagOpen, emoteOpen, immersive, steerBoat]);

  // ---- 共同航海: 進捗・海域・到着・一撃 ----
  const target = voyage?.targetMinutes ?? 0;
  const frac = voyage && target > 0 ? Math.min(progressMinutes / target, 1) : 0;
  const arrived = Boolean(voyage?.arrivedAt);
  const voyageActive = Boolean(voyage) && !arrived;
  const identity = voyage ? voyage.createdAt.getTime() : null;
  const activeRoute = voyage && route ? route : null;
  const passedCount = activeRoute
    ? activeRoute.encounters.filter((e) => frac >= e.end).length
    : 0;

  // 海域を抜けた瞬間の演出(沈む/晴れる→帯)と、到着の演出。
  const [clearFx, setClearFx] = useState<{
    kind: EncounterKind;
    stage: "running" | "banner";
  } | null>(null);
  const [arriveStage, setArriveStage] = useState<"none" | "fx" | "quiet">("none");
  const identityRef = useRef<number | null | undefined>(undefined);
  const prevPassed = useRef<number | null>(null);
  const prevArrived = useRef<boolean | null>(null);
  const clearFxTimers = useRef<number[]>([]);
  const arriveTimers = useRef<number[]>([]);

  // 航海が入れ替わったら(次の航海など)演出を全部リセットする。
  // 旧航海のタイマーが残ると、新しい航海の最中に帯や滑走が誤発火する。
  // ※ このeffectは他の演出effectより先に宣言する(実行順が宣言順のため)。
  useEffect(() => {
    if (identityRef.current === identity) return;
    identityRef.current = identity;
    clearFxTimers.current.forEach((id) => window.clearTimeout(id));
    clearFxTimers.current.length = 0;
    arriveTimers.current.forEach((id) => window.clearTimeout(id));
    arriveTimers.current.length = 0;
    setClearFx(null);
    setArriveStage("none");
    prevPassed.current = null;
    prevArrived.current = null;
  }, [identity]);

  // 海域の通過。マウント中に区間の終端を越えた瞬間だけ流す
  // (開いた時に既に過ぎていた海域は静かに素通り)。
  useEffect(() => {
    if (!activeRoute) return;
    if (prevPassed.current === null) {
      prevPassed.current = passedCount;
      return;
    }
    if (passedCount <= prevPassed.current) {
      prevPassed.current = passedCount;
      return;
    }
    const cleared = activeRoute.encounters[passedCount - 1];
    prevPassed.current = passedCount;
    clearFxTimers.current.forEach((id) => window.clearTimeout(id));
    clearFxTimers.current.length = 0;
    if (arrived) return; // 到着と同時なら到着の演出に譲る
    if (!animate) {
      // reduced-motion: 沈む/晴れるはジャンプカットし、帯だけ見せる。
      setClearFx({ kind: cleared.kind, stage: "banner" });
      clearFxTimers.current.push(window.setTimeout(() => setClearFx(null), 4200));
      return;
    }
    setClearFx({ kind: cleared.kind, stage: "running" }); // 沈む/晴れる(約2.2秒)
    clearFxTimers.current.push(
      window.setTimeout(() => setClearFx({ kind: cleared.kind, stage: "banner" }), 2200),
      window.setTimeout(() => setClearFx(null), 6600),
    );
  }, [passedCount, activeRoute, arrived, animate]);

  // 到着。マウント中に arrivedAt が付いた瞬間だけ演出を流す
  // (最初から到着済みの港では静かに"quiet")。
  useEffect(() => {
    if (voyage === undefined || voyage === null) return;
    if (prevArrived.current === null) {
      prevArrived.current = arrived;
      if (arrived) setArriveStage("quiet");
      return;
    }
    if (arrived === prevArrived.current) return;
    prevArrived.current = arrived;
    if (!arrived) {
      setArriveStage("none");
      return;
    }
    // 海域の帯は打ち切り、到着を優先する。
    clearFxTimers.current.forEach((id) => window.clearTimeout(id));
    clearFxTimers.current.length = 0;
    setClearFx(null);
    setArriveStage("fx");
    arriveTimers.current.push(window.setTimeout(() => setArriveStage("quiet"), 8000));
  }, [voyage, arrived]);

  useEffect(() => {
    const a = clearFxTimers.current;
    const b = arriveTimers.current;
    return () => {
      a.forEach((id) => window.clearTimeout(id));
      b.forEach((id) => window.clearTimeout(id));
    };
  }, []);

  // いま描く海域。進捗が区間を越えた直後は、state(clearFx)が立つ前の
  // 1フレームでも海域を消さない(消えて→また現れるちらつきを防ぐ)。
  const enc = activeRoute && voyageActive ? activeEncounter(activeRoute, frac) : null;
  const pendingClear =
    identityRef.current === identity &&
    prevPassed.current !== null &&
    passedCount > prevPassed.current &&
    !arrived;
  const clearingKind: EncounterKind | null =
    clearFx?.stage === "running"
      ? clearFx.kind
      : pendingClear && activeRoute
        ? activeRoute.encounters[passedCount - 1].kind
        : null;
  const encounterView: EncounterView | null = enc
    ? { kind: enc.kind, phase: encounterPhase(enc, frac), defeating: false }
    : clearingKind
      ? { kind: clearingKind, phase: 2, defeating: true }
      : null;

  // 一撃: 新しい着岸/帰還(strike)ごとに、その船から一閃を飛ばす。
  const [bolts, setBolts] = useState<Bolt[]>([]);
  const hitClock = useRef(-10);
  const lastStrikeSeq = useRef(0);

  // スクロールで画面外に出たらrAFループを止める(VoyageSceneと同じ作法)。
  const [visible, setVisible] = useState(true);
  useEffect(() => {
    const el = rootRef.current;
    if (!el || typeof IntersectionObserver === "undefined") return;
    const observer = new IntersectionObserver(([entry]) => {
      setVisible(entry.isIntersecting);
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);
  useEffect(() => () => window.clearTimeout(flashTimer.current), []);

  const berths = useMemo(() => makeBerths(members), [members]);
  const ownBerth = useMemo(
    () => berths.find((berth) => berth.member.id === currentUid),
    [berths, currentUid],
  );

  // 嵐の航海 — ハリケーンの海域に入った瞬間、イベントの題字を一度だけ掲げる
  // (同じ航海では再表示しない)。表示のトリガーと消灯タイマーは別のeffectに
  // 分ける — 一緒にすると、StrictMode等でeffectが再実行された際に「表示済み」の
  // 早期returnがタイマーだけを取り消し、題字が出っぱなしになる。
  const [stormIntro, setStormIntro] = useState(false);
  const stormIntroShown = useRef<number | null>(null);
  const stormActive = encounterView?.kind === "storm" && !encounterView.defeating;
  useEffect(() => {
    if (!stormActive || identity === null) return;
    if (stormIntroShown.current === identity) return;
    stormIntroShown.current = identity;
    setStormIntro(true);
  }, [stormActive, identity]);
  useEffect(() => {
    if (!stormIntro) return;
    const id = window.setTimeout(() => setStormIntro(false), 4600);
    return () => window.clearTimeout(id);
  }, [stormIntro]);

  // 一撃の発火。航海中だけ音を添え、海域が出ている間だけ一閃を飛ばす
  // (何もない海に光が飛ぶと行き先が謎になる)。
  useEffect(() => {
    if (!strike || strike.seq === lastStrikeSeq.current) return;
    lastStrikeSeq.current = strike.seq;
    if (!voyageActive) return;
    playStrike();
    if (!animate) return; // reduced-motion: 一閃は省略(ジャンプカット)
    if (!encounterView || encounterView.defeating) return;
    const berth = berths.find((b) => b.member.id === strike.uid);
    if (!berth) return;
    setBolts((list) => [...list.slice(-3), { id: strike.seq, from: [berth.x, 0, berth.z] }]);
  }, [strike, voyageActive, animate, berths, encounterView]);

  // 今日の灯: 各メンバーの当月ペイロードを読み、今日が含まれる船に灯をともす。
  const [litIds, setLitIds] = useState<ReadonlySet<string>>(new Set());
  useEffect(() => {
    if (isDemo) {
      setLitIds(demoLitMemberIds);
      return;
    }
    let alive = true;
    const now = new Date();
    const ym = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
    const today = now.getDate();
    void Promise.all(
      members.slice(0, ROOM_MAX_MEMBERS).map(async (m) => {
        const month = await fetchMonth("rooms", room.id, m.id, ym);
        return month?.days.includes(today) ? m.id : null;
      }),
    ).then((ids) => {
      if (alive) setLitIds(new Set(ids.filter((id): id is string => id !== null)));
    });
    return () => {
      alive = false;
    };
  }, [room.id, members]);

  // 写真撮影。UIを含まないWebGLの絵を、見えている世界と同じ縦横比の
  // PNGへ同期レンダリングし、共有シートを挟まずそのまま端末へ保存する。
  const takePhoto = () => {
    const state = glRef.current;
    if (!state) return;
    const src = state.gl.domElement;
    setFlash(false);
    // 次フレームで付け直すと連写でもアニメが再生される。
    requestAnimationFrame(() => setFlash(true));
    window.clearTimeout(flashTimer.current);
    flashTimer.current = window.setTimeout(() => setFlash(false), 340);

    const w = src.width;
    const h = src.height;
    const out = document.createElement("canvas");
    out.width = w;
    out.height = h;
    const ctx = out.getContext("2d");
    if (!ctx) return;
    ctx.fillStyle = harborLight.sky;
    ctx.fillRect(0, 0, out.width, out.height);
    // preserveDrawingBufferなしで確実に写すため、直前に同期レンダリングする。
    state.gl.render(state.scene, state.camera);
    ctx.drawImage(src, 0, 0);
    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    void downloadCanvas(out, `aftide-harbor-${stamp}.png`);
  };

  return (
    <>
      <div
        ref={rootRef}
        className={`harbor-world time-${timeOfDay}${immersive ? " immersive" : ""}${
          aboard ? " sailing" : ""
        }`}
        data-time-of-day={timeOfDay}
        onPointerDown={beginLook}
        onPointerMove={moveLook}
        onPointerUp={endLook}
        onPointerCancel={endLook}
      >
        <Canvas
          dpr={[1, 2]}
          frameloop={immersive || (animate && visible) ? "always" : "demand"}
          camera={{ position: CAM_POS, fov: 36 }}
          onCreated={(state) => {
            glRef.current = state;
          }}
        >
          {aboard ? (
            <HarborSailingSea
              currentUid={currentUid}
              members={members}
              livePresence={livePresence}
              timeOfDay={timeOfDay}
              animate={animate}
              fishingRod={fishingRodVisible}
              ownPose={activeNavigatorPose(
                equipmentAction,
                emotePose,
                fishingRodVisible,
                false,
              )}
              ownPoseKey={emoteSeq}
              ownSailX={sailX}
            />
          ) : (
            <HarborSea
              roomName={room.name}
              timeOfDay={timeOfDay}
              berths={berths}
              litIds={litIds}
              arrivingMemberIds={arrivingMemberIds}
              animate={animate}
              encounter={encounterView}
              advanceOn={arrived}
              arriveFx={arriveStage === "fx"}
              hitClock={hitClock}
              bolts={bolts}
              onBoltDone={(id) => setBolts((list) => list.filter((b) => b.id !== id))}
              immersive={immersive}
              phase={phase}
              onEnterWorld={enterWorld}
              onWorldEntered={handleWorldEntered}
              onWorldExited={handleWorldExited}
              walkInput={walkInput}
              look={look}
              currentUid={currentUid}
              ownBerth={ownBerth}
              aboard={false}
              controlsLocked={
                bagOpen || emoteOpen || equipmentAction !== null || restingAtTent
              }
              fishingRodOwned={fishingRodOwned}
              fishingRodVisible={fishingRodVisible}
              equipmentAction={equipmentAction}
              emotePose={emotePose}
              emoteSeq={emoteSeq}
              restingAtTent={restingAtTent}
              livePresence={livePresence}
              onNearOwnBoatChange={setNearOwnBoat}
              onNearFishingRodChange={setNearFishingRod}
              onNearTentChange={setNearTent}
              onWalkerTransform={handleWalkerTransform}
              onMovementStart={stopEmote}
              onBoardOwnBoat={boardOwnBoat}
            />
          )}
        </Canvas>
        {/* コンパクト時の誘い。海(空・水面)をタップで世界へ入る。 */}
        {!immersive && (
          <div className="harbor-world-enter-hint">{t("enterWorldHint")}</div>
        )}
        {/* 没入時に世界から出るボタン。 */}
        {immersive && (
          <>
            <button
              className="harbor-world-close"
              onClick={aboard ? leaveSailing : requestClose}
            >
              {t(aboard ? "harborReturnToIsland" : "close")}
            </button>
            {aboard ? (
              <>
                <div className="harbor-sailing-status">
                  <strong>{room.name}</strong>
                  <span>{t("harborSailingTogether")}</span>
                </div>
                {!bagOpen && !emoteOpen && (
                  <HarborSailingControls onSteer={steerBoat} position={sailX} />
                )}
              </>
            ) : (
              <div className="harbor-walk-hint">{t("harborWalkHint")}</div>
            )}
            {!aboard &&
              !bagOpen &&
              !emoteOpen &&
              equipmentAction === null &&
              !restingAtTent && (
              <HarborWalkControls
                onInput={setWalkInput}
                settings={walkControlSettings}
              />
            )}
            {!bagOpen &&
              !nearFishingRod &&
              phase === "idle" &&
              ownBerth &&
              !aboard &&
              nearOwnBoat && (
                <button
                  type="button"
                  className="harbor-board-action"
                  onPointerDown={(event) => event.stopPropagation()}
                  onClick={() => {
                    setWalkInput({ x: 0, z: 0 });
                    setNearOwnBoat(false);
                    setAboard(true);
                  }}
                >
                  {t("harborBoardBoat")}
                </button>
              )}
            {!bagOpen &&
              !aboard &&
              !fishingRodOwned &&
              nearFishingRod &&
              phase === "idle" && (
                <button
                  type="button"
                  className="harbor-pickup-action"
                  disabled={equipmentAction !== null}
                  onPointerDown={(event) => event.stopPropagation()}
                  onClick={pickUpFishingRod}
                >
                  {t("pickUpFishingRod")}
                </button>
              )}
            {!bagOpen &&
              !aboard &&
              !nearFishingRod &&
              phase === "idle" &&
              (restingAtTent || nearTent) && (
                <button
                  type="button"
                  className="harbor-tent-action"
                  onPointerDown={(event) => event.stopPropagation()}
                  onClick={() => {
                    setWalkInput({ x: 0, z: 0 });
                    setEmoteOpen(false);
                    setRestingAtTent((resting) => !resting);
                  }}
                >
                  {t(restingAtTent ? "leaveTent" : "restInTent")}
                </button>
              )}
            {!bagOpen && !restingAtTent && (
              <div
                className="harbor-emote-dock"
                onPointerDown={(event) => event.stopPropagation()}
              >
                {emoteOpen && (
                  <div className="harbor-emote-panel" role="group" aria-label={t("emotes")}>
                    <div className="harbor-emote-live">
                      <span aria-hidden="true" />
                      {t("harborLive")}
                    </div>
                    <div className="harbor-emote-options">
                      {HARBOR_EMOTES.map((emote) => (
                        <button
                          key={emote.pose}
                          type="button"
                          className={emotePose === emote.pose ? "selected" : ""}
                          onClick={() => playEmote(emote.pose)}
                          aria-pressed={emotePose === emote.pose}
                        >
                          <span aria-hidden="true">{emote.mark}</span>
                          {t(emote.label)}
                        </button>
                      ))}
                    </div>
                  </div>
                )}
                <button
                  type="button"
                  className={`harbor-emote-toggle${emoteOpen ? " open" : ""}`}
                  onClick={() => {
                    setWalkInput({ x: 0, z: 0 });
                    setEmoteOpen((open) => !open);
                  }}
                  aria-expanded={emoteOpen}
                >
                  <span className="harbor-emote-toggle-mark" aria-hidden="true">
                    ≋
                  </span>
                  {t("emotes")}
                  {livePresence.size > 0 && (
                    <span className="harbor-live-count" aria-label={t("harborLive")}>
                      {livePresence.size + 1}
                    </span>
                  )}
                </button>
              </div>
            )}
            {immersiveChat}
          </>
        )}
        <button
          type="button"
          className={`harbor-bag-button${bagOpen ? " open" : ""}`}
          onPointerDown={(event) => event.stopPropagation()}
          onClick={() => {
            setWalkInput({ x: 0, z: 0 });
            setEmoteOpen(false);
            setBagOpen((open) => !open);
          }}
          aria-expanded={bagOpen}
          aria-controls="harbor-navigator-bag"
        >
          <span className="harbor-bag-mark" aria-hidden="true" />
          <span>{t("bag")}</span>
          <span className="harbor-bag-count">{inventory.items.length}</span>
        </button>
        {bagOpen && (
          <div
            id="harbor-navigator-bag"
            className="harbor-bag-panel"
            role="dialog"
            aria-label={t("bag")}
            onPointerDown={(event) => event.stopPropagation()}
          >
            <div className="harbor-bag-heading">
              <span>{t("bag")}</span>
              <button
                type="button"
                className="harbor-bag-dismiss"
                onClick={() => setBagOpen(false)}
                aria-label={t("close")}
              >
                ×
              </button>
            </div>
            {fishingRodOwned ? (
              <div className="harbor-bag-item">
                <img
                  className="harbor-bag-item-art"
                  src="/images/fishing-rod.png"
                  alt=""
                  aria-hidden="true"
                />
                <div className="harbor-bag-item-copy">
                  <div className="harbor-bag-item-title">
                    {t("fishingRod")}
                    {inventory.equipped === "fishingRod" && (
                      <span className="harbor-equipped-badge">{t("equipped")}</span>
                    )}
                  </div>
                  <div className="harbor-bag-item-desc">{t("fishingRodDesc")}</div>
                  <button
                    type="button"
                    className="harbor-equip-button"
                    onClick={toggleFishingRod}
                    disabled={equipmentAction !== null}
                  >
                    {inventory.equipped === "fishingRod" ||
                    equipmentAction === "unequip"
                      ? t("unequip")
                      : t("equip")}
                  </button>
                </div>
              </div>
            ) : (
              <p className="harbor-bag-empty">{t("bagEmpty")}</p>
            )}
          </div>
        )}
        {inventoryNotice && (
          <div className="harbor-inventory-notice" role="status">
            {inventoryNotice}
          </div>
        )}
        {/* 航海の進捗(連続バー+海域の印+残り)。個人の内訳や順位は出さない。 */}
        {voyageActive && voyage && activeRoute && (
          <div className="trial-bar">
            <div
              className="voyage-track"
              role="progressbar"
              aria-valuemin={0}
              aria-valuemax={voyage.targetMinutes}
              aria-valuenow={Math.min(progressMinutes, voyage.targetMinutes)}
            >
              <span
                className="voyage-fill"
                style={{ width: `${Math.round(frac * 100)}%` }}
              />
              {activeRoute.encounters.map((e, i) => (
                <span
                  key={i}
                  className={`voyage-mark ${e.kind}${frac >= e.end ? " passed" : ""}`}
                  style={{ left: `${Math.round(((e.start + e.end) / 2) * 100)}%` }}
                  title={t(e.kind === "storm" ? "encounterStorm" : "encounterKraken")}
                />
              ))}
            </div>
            <span className="trial-remaining">
              {voyageRemainingLabel(voyage.targetMinutes - progressMinutes)}
            </span>
          </div>
        )}
        {/* 嵐の航海の題字。ハリケーンの海域に入った瞬間、一度だけ掲げる。 */}
        {stormIntro && !clearFx && arriveStage !== "fx" && (
          <div className="trial-defeat" role="status">
            <div className="trial-defeat-title">{t("stormEventTitle")}</div>
            <div className="trial-defeat-sub">{t("stormEventSub")}</div>
          </div>
        )}
        {/* 海域を抜けた帯。世界の上にふわっと現れる一枚。 */}
        {clearFx?.stage === "banner" && (
          <div className="trial-defeat" role="status">
            <div className="trial-defeat-title">
              {t(clearFx.kind === "storm" ? "stormCleared" : "krakenCleared")}
            </div>
          </div>
        )}
        {/* 到着の帯+戦利品の告知(その航路に戦利品があるときだけ)。 */}
        {arriveStage === "fx" && (
          <div className="trial-defeat" role="status">
            <div className="trial-defeat-title">{t("voyageArrivedTitle")}</div>
            {activeRoute?.lootKey && (
              <div className="trial-defeat-sub">
                {t(
                  activeRoute.lootKey === "loot.moonlightSail"
                    ? "lootMoonlightNotice"
                    : "lootKrakenNotice",
                )}
              </div>
            )}
          </div>
        )}
        <button
          className="harbor-world-camera"
          onClick={takePhoto}
          aria-label={t("takePhoto")}
          title={t("takePhoto")}
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" aria-hidden="true">
            <path
              d="M4 8.5C4 7.7 4.7 7 5.5 7H8l1.4-2h5.2L16 7h2.5c.8 0 1.5.7 1.5 1.5v9c0 .8-.7 1.5-1.5 1.5h-13C4.7 19 4 18.3 4 17.5v-9Z"
              fill="currentColor"
            />
            <circle cx="12" cy="13" r="3.2" fill="#123830" />
          </svg>
        </button>
        {flash && <div className="harbor-world-flash" />}
      </div>
      <p className="harbor-world-hint">{t("lanternHint")}</p>
    </>
  );
}
