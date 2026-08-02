import { useEffect, useMemo, useRef, useState } from "react";
import * as THREE from "three";
import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { Stars } from "@react-three/drei";
import BoatModel from "./BoatModel";
import PhoenixModel, { type PhoenixPose } from "./PhoenixModel";
import { Moon, NIGHT_BG, PassingSwells, Sea } from "./SeaParts";
import { Horizon, Island, Wake } from "./VoyageScene";
import { Gulls, type GullFlock } from "./Gulls";
import { boatProps } from "../boat";
import { durationLabel, t, tf } from "../i18n";
import { useBackToClose } from "../backClose";
import { useBodyScrollLock } from "../scrollLock";

// 着岸の世界。目的地に到達した瞬間に開く一幕。
//
// 以前は2DのSVGの船が画面を横切るだけだったが、それでは「辿り着いた」ことが
// 記号でしか伝わらない。ここでは作業中の世界(VoyagingWorld)と同じ言語 —
// 夜の海・星・月・流れる水の筋・旋回するカモメ・低ポリの島 — のまま、
// 航海の続きとして島へ寄せ、舫って、船を降り、浜をゆっくり上がる。
//
// 素材と配色は VoyagingWorld / VoyageScene と共有する。違うのは
// 「船が動かない世界で水が流れる」のではなく、船が本当に島へ近づくこと。

const BOAT_SCALE = 0.55;
const ISLAND_SCALE = 1.4;
/// 甲板の航海士の立ち位置(船のローカル)。VoyagingWorld と同値。
const DECK_LOCAL = new THREE.Vector3(0.88, 0.57, 0.22);
/// 航海士の大きさ。船に乗っているときと降りたあとで変えない
/// (変えると降りた瞬間に別人が現れたように見える)。
const SAILOR_SCALE = BOAT_SCALE * 0.62;

// ---- 一幕の時間割(秒) ----
/// 島の手前まで寄せる。
const SAIL_END = 4.2;
/// 舫う。船足が落ちて止まり、水の筋も静まる。
const MOOR_END = 6.2;
/// 舷を越えて浜へ降りる。
const STEP_END = 7.9;
/// 浜をゆっくり上がりきる。
const WALK_END = 10.6;
/// 振り向いて正面を向き、灯を掲げる。ここが一幕の終わり。
const LAND_END = 12.2;
/// 言葉が現れる時刻。振り向き始めてから出す(先に出ると上陸を見ない)。
const WORDS_AT = 10.8;

// ---- 島の据え方 ----
// Island() は自前で (3.5, 0, -0.9) にずれている。打ち消す group は必ず
// 「拡大の内側」に置く。外に置くと打ち消しぶんだけが拡大されず、島が
// ISLAND_SCALE 倍のずれ(x=+1.4)を持ったまま据わって、浜の位置を見誤る
// (航海士が海に降りる原因だった)。
const ISLAND_UNSHIFT: [number, number, number] = [-3.5, 0, 0.9];

// ---- 船の航路 ----
// 縦長の画面は横の視野がとても狭い(fov38・縦長だと見える幅は高さの半分以下)。
// 遠くから走らせると島が画面に入らないので、最後の一区間だけを見せる。
const BOAT_FROM = new THREE.Vector3(-5.0, 0, 0.9);
/// 舫う位置。船体は水の上(浜の半径2.66の外)、甲板の先だけが砂の上へ差し出る
/// ところまで寄せる。ここが遠いと、降りる一歩が宙を飛ぶ。
const BOAT_MOORED = new THREE.Vector3(-2.95, 0, -0.35);

/// PhoenixModel はルートを rotation=[0, π/2, 0] で据えてある(甲板では船首の +x を
/// 向いているのが正しいため)。つまりモデルの正面は +Z ではなく +X。
/// 進む向き d を向かせたいときは、atan2(d.x, d.z) からこのぶん引く。
/// これを忘れると、常に90度横を向いたまま歩く。
const FRONT_YAW = -Math.PI / 2;

// ---- 浜の上の足跡 ----
// 島の中身は Island() のローカル座標を ISLAND_SCALE 倍したところにある。
// 大事なのは、浜も丘も「円」ではなく低ポリの多角形だということ:
//   浜 = 9角形。上面の外接半径2.66に対し、内接半径は2.66*cos(π/9)=2.50。
//        砂の面は y=0.091、中心は (0, 0.14)。
//   丘 = 7角形の円錐。外接半径1.75(内接1.58)、中心 (0, 0)。
//   小丘 = 中心 (-1.19, 0.35)・半径0.84 の球。
// 立てる場所は「浜の内接半径の内側で、丘の外接半径の外」= 半径1.8〜2.4の帯。
// 外接半径で数えると角のあいだで浜から外れ、航海士が海に立つ。
const SAND_TOP = 0.065 * ISLAND_SCALE;
/// 航海士の原点は腰にあり、足はそこから約0.42下にある。浜に立たせるときは
/// このぶん持ち上げないと、脛まで砂に埋まる。
const FOOT_LIFT = SAILOR_SCALE * 0.42;
const STAND_Y = SAND_TOP + FOOT_LIFT;
const STEP_ONTO = new THREE.Vector3(-2.15, STAND_Y, -0.55);
/// 上がりきる先。島の奥(-z)へ向かうので、歩いているあいだは背中を見せる。
const LAND_TO = new THREE.Vector3(-1.75, STAND_Y, -1.35);

const MOON_POS: [number, number, number] = [4.4, 3.4, -6.2];

/// 着岸の空を旋回するカモメ。航海中(VoyagingWorld)より少し高く遠く回して、
/// 主役の上陸から目を逸らさせない。
const LANDFALL_GULLS: GullFlock = [
  { r: 4.6, y: 2.6, omega: 0.075, scale: 0.14, flap: 1.9, phase: 0.0 },
  { r: 5.4, y: 3.1, omega: -0.055, scale: 0.13, flap: 1.6, phase: 1.1 },
  { r: 4.1, y: 2.3, omega: 0.1, scale: 0.15, flap: 2.3, phase: 2.2 },
  { r: 6.0, y: 3.5, omega: -0.045, scale: 0.12, flap: 1.5, phase: 3.4 },
  { r: 5.0, y: 2.8, omega: 0.065, scale: 0.13, flap: 1.8, phase: 4.6 },
];

// ---- カメラの割り(時刻・位置・見る先) ----
// 遠くから寄せる → 島の手前で船を捉える → 降りる足元 → 上陸した先。
// 手で動かせるようにはしない。ここは一幕なので、見せたい順に見せる。
interface CamKey {
  at: number;
  pos: [number, number, number];
  look: [number, number, number];
}
// カメラは島の +z 側に置いて、ほぼ -z を向く。こうすると世界の x 軸が
// 画面の横に重なり、「左から島へ寄っていく」動きがそのまま横移動に見える。
// 後半のカメラは -x 側へ回す。浜の -x 側には小丘(中心(-1.19,0.35)・半径0.84)が
// あり、真正面から寄ると視線がその中を通って、砂の塊で航海士が隠れる。
const CAM_KEYS: CamKey[] = [
  { at: 0, pos: [-2.8, 4.6, 16.8], look: [-2.4, 0.8, 0.0] },
  { at: SAIL_END, pos: [-2.9, 3.4, 11.4], look: [-2.5, 0.6, -0.2] },
  { at: MOOR_END, pos: [-3.2, 1.9, 6.8], look: [-2.6, 0.5, -0.3] },
  { at: STEP_END, pos: [-3.2, 1.25, 3.9], look: [-2.25, 0.45, -0.6] },
  { at: WALK_END, pos: [-2.8, 0.95, 2.6], look: [-1.95, 0.45, -1.25] },
  // 最後は海側から寄って、上陸した航海士を正面から捉える。
  // ほぼ目線の高さに置く: 見下ろすと砂の面が画面の大半を埋めて、島ではなく
  // 「砂の板」になる。水平線を残して、海から来たことを画に留める。
  { at: LAND_END, pos: [-2.5, 0.75, 1.2], look: [-1.78, 0.44, -1.35] },
];

/// 最後に向く方角。カメラは真正面(+z)ではなく斜めにいるので、
/// 「正面を見せる」= 最後のカメラの方を向くこと。0 に固定すると横顔になる。
const FACE_VIEWER = (() => {
  const last = CAM_KEYS[CAM_KEYS.length - 1].pos;
  return Math.atan2(last[0] - LAND_TO.x, last[2] - LAND_TO.z) + FRONT_YAW;
})();

/// 0..1 の行き来を滑らかにする。等速で動かすと機械に見える。
function smooth(x: number): number {
  const k = THREE.MathUtils.clamp(x, 0, 1);
  return k * k * (3 - 2 * k);
}

// 毎フレーム呼ぶ計算で Vector3 を作らない(一幕のあいだ休みなく回る)。
const SCRATCH_A = new THREE.Vector3();
const SCRATCH_B = new THREE.Vector3();
const SCRATCH_DECK = new THREE.Vector3();

/// この時刻のカメラを CAM_KEYS から作る。
function camAt(time: number, pos: THREE.Vector3, look: THREE.Vector3): void {
  let i = 0;
  while (i < CAM_KEYS.length - 2 && time > CAM_KEYS[i + 1].at) i += 1;
  const a = CAM_KEYS[i];
  const b = CAM_KEYS[i + 1];
  const k = smooth((time - a.at) / Math.max(0.001, b.at - a.at));
  pos.fromArray(a.pos).lerp(SCRATCH_A.fromArray(b.pos), k);
  look.fromArray(a.look).lerp(SCRATCH_B.fromArray(b.look), k);
}

/// この時刻の船の位置。舫うまで減速しながら寄せる。
function boatAt(time: number, out: THREE.Vector3): void {
  const k = smooth(THREE.MathUtils.clamp(time / MOOR_END, 0, 1));
  out.copy(BOAT_FROM).lerp(BOAT_MOORED, k);
}

/// この時刻の航海士の位置と向き。
/// 舫うまでは甲板の上、そこから浜へ降り、浜を歩いて上がる。
function sailorAt(
  time: number,
  boat: THREE.Vector3,
  out: THREE.Vector3,
): { yaw: number; pose: PhoenixPose } {
  const deck = SCRATCH_DECK.copy(boat).addScaledVector(DECK_LOCAL, BOAT_SCALE);
  if (time < MOOR_END) {
    out.copy(deck);
    // 島が見えているあいだは、空いた手でその先を指している。
    return { yaw: 0, pose: time < SAIL_END ? "point" : "idle" };
  }
  if (time < STEP_END) {
    // 舷を越えて浜へ降りる一歩。
    // 高さだけ遅らせて落とすのが要。前後と同じ速さで下ろすと斜めに滑り、
    // 宙を歩いて見える(弧を描かせるのはもっと悪く、跳ねて浮く)。
    // 舳先まで水平に進んでから、最後に足を砂へ下ろす。
    const k = smooth((time - MOOR_END) / (STEP_END - MOOR_END));
    const d = SCRATCH_A.subVectors(STEP_ONTO, deck);
    const deckY = deck.y;
    out.copy(deck).lerp(STEP_ONTO, k);
    out.y = THREE.MathUtils.lerp(deckY, STEP_ONTO.y, smooth((k - 0.4) / 0.6));
    return { yaw: Math.atan2(d.x, d.z) + FRONT_YAW, pose: "walk" };
  }
  const inland = SCRATCH_A.subVectors(LAND_TO, STEP_ONTO);
  const walkYaw = Math.atan2(inland.x, inland.z) + FRONT_YAW;
  if (time < WALK_END) {
    // 浜をゆっくり上がる。島の奥へ向かうので背中が見えている。
    const k = smooth((time - STEP_END) / (WALK_END - STEP_END));
    out.copy(STEP_ONTO).lerp(LAND_TO, k);
    return { yaw: walkYaw, pose: "walk" };
  }
  // 上がりきったら、こちらへ振り向いて灯を掲げる。
  const k = smooth((time - WALK_END) / (LAND_END - WALK_END));
  out.copy(LAND_TO);
  return {
    yaw: THREE.MathUtils.lerp(walkYaw, FACE_VIEWER, k),
    pose: k > 0.55 ? "raise" : "idle",
  };
}

function LandfallSea({
  animate,
  onWords,
}: {
  animate: boolean;
  onWords: () => void;
}) {
  const parts = useMemo(() => boatProps(), []);
  const boatGroup = useRef<THREE.Group>(null);
  const sailorGroup = useRef<THREE.Group>(null);
  const wakeGroup = useRef<THREE.Group>(null);
  const { camera } = useThree();

  // 一幕の経過。clock.elapsedTime ではなく自分で積むので、
  // 静止設定(reduced-motion)では最後の姿へ跳ばせる。
  const time = useRef(animate ? 0 : LAND_END);
  const [pose, setPose] = useState<PhoenixPose>(animate ? "point" : "raise");
  const [flow, setFlow] = useState(animate ? 1 : 0);
  const said = useRef(false);

  const boat = useRef(new THREE.Vector3());
  const sailor = useRef(new THREE.Vector3());
  const camPos = useRef(new THREE.Vector3());
  const camLook = useRef(new THREE.Vector3());

  const place = () => {
    const time0 = time.current;
    boatAt(time0, boat.current);
    const { yaw, pose: next } = sailorAt(time0, boat.current, sailor.current);
    if (boatGroup.current) boatGroup.current.position.copy(boat.current);
    if (sailorGroup.current) {
      sailorGroup.current.position.copy(sailor.current);
      // 甲板にいるあいだは船と同じ向き。降りたら進む先を向く。
      sailorGroup.current.rotation.y = time0 < MOOR_END ? 0.1 : yaw;
    }
    if (wakeGroup.current) {
      // 航跡は船足に従って消える。位置は船に付いて回る。
      const k = 1 - smooth(THREE.MathUtils.clamp(time0 / MOOR_END, 0, 1));
      wakeGroup.current.position.copy(boat.current);
      wakeGroup.current.scale.set(BOAT_SCALE * k, BOAT_SCALE, BOAT_SCALE * k);
      wakeGroup.current.visible = k > 0.03;
    }
    camAt(time0, camPos.current, camLook.current);
    camera.position.copy(camPos.current);
    camera.lookAt(camLook.current);
    return next;
  };

  useFrame((_, delta) => {
    if (animate) time.current = Math.min(time.current + delta, LAND_END + 2);
    const next = place();
    if (next !== pose) setPose(next);
    const wantFlow = time.current < MOOR_END ? 1 : 0;
    if (wantFlow !== flow) setFlow(wantFlow);
    if (!said.current && time.current >= (animate ? WORDS_AT : 0)) {
      said.current = true;
      onWords();
    }
  });

  return (
    <>
      <color attach="background" args={[NIGHT_BG]} />
      <fog attach="fog" args={[NIGHT_BG, 14, 38]} />
      <ambientLight color="#ffe9c8" intensity={0.45} />
      <directionalLight color="#EADEBD" intensity={1.15} position={[-6, 8, -5]} />
      <directionalLight color="#5DCAA5" intensity={0.2} position={[5, 3, 6]} />
      <Stars
        radius={42}
        depth={18}
        count={380}
        factor={2.0}
        saturation={0}
        fade
        speed={animate ? 0.5 : 0}
      />
      <group position={MOON_POS} scale={0.4}>
        <Moon position={[0, 0, 0]} />
      </group>
      <Sea moonX={MOON_POS[0]} animate={animate} />
      <Horizon />
      <PassingSwells animate={animate} flow={flow} />
      <Gulls flock={LANDFALL_GULLS} animate={animate} opacity={0.42} />

      {/* 目的地の島。浜の中心を原点へ置く。打ち消しは拡大の内側で行う */}
      <group scale={ISLAND_SCALE}>
        <group position={ISLAND_UNSHIFT}>
          <Island />
        </group>
      </group>

      {/* 航跡。船に付いて回り、船足が落ちるにつれて消える */}
      <group ref={wakeGroup}>
        <Wake animate={animate} />
      </group>

      {/* 自分の船。甲板の航海士は乗せない(降りるので世界に直接置く) */}
      <group ref={boatGroup} rotation={[0, 0.1, 0]} scale={BOAT_SCALE}>
        <BoatModel parts={parts} animate={animate} />
      </group>

      {/* 航海士。甲板の上 → 舷を越える一歩 → 浜を上がる */}
      <group ref={sailorGroup} scale={SAILOR_SCALE}>
        <PhoenixModel animate={animate} pose={pose} />
      </group>
    </>
  );
}

export interface LandfallWorldProps {
  /// 到達した島の名前。
  name: string;
  /// ここまで積み重ねた航海の時間(分)。0なら添えない。
  minutes: number;
  onClose: () => void;
}

export default function LandfallWorld({ name, minutes, onClose }: LandfallWorldProps) {
  const [animate] = useState(
    () => !window.matchMedia("(prefers-reduced-motion: reduce)").matches,
  );
  const [words, setWords] = useState(!animate);

  // 端末の「戻る」だけは受ける。ここを塞ぐと Android で戻るを押した人が
  // アプリの外へ出てしまう(閉じ込めるより、逃げ道は残す)。
  useBackToClose(true, onClose);
  useBodyScrollLock();

  useEffect(() => {
    // Esc も上陸を見終えるまでは効かせない。タップと同じく「飛ばす操作」。
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape" && words) onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("keydown", onKey);
    };
  }, [onClose, words]);

  return (
    // タップでは閉じない。上陸は自分で「上陸する」を押して始めた一幕なので、
    // 途中で消す必要がない。以前は画面のどこを触っても閉じたため、
    // 見ようとした指がそのまま演出を飛ばしていた。
    // 閉じるのは、言葉と一緒に現れる「閉じる」だけ。
    <div className="landfall-world" role="dialog" aria-modal="true">
      <Canvas dpr={[1, 2]} camera={{ position: CAM_KEYS[0].pos, fov: 38 }}>
        <LandfallSea animate={animate} onWords={() => setWords(true)} />
      </Canvas>

      {words && (
        <div className="landfall-caption">
          {minutes > 0 && (
            <p className="landfall-time">
              {tf(t("landfallTime"), { time: durationLabel(minutes) })}
            </p>
          )}
          <p className="landfall-line">{tf(t("reachedIsland"), { name })}</p>
          <p className="landfall-sub">{t("voyageStays")}</p>
          <button className="landfall-close" onClick={onClose}>
            {t("close")}
          </button>
        </div>
      )}
    </div>
  );
}
