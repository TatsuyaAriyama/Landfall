import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import * as THREE from "three";
import { Canvas, useFrame, useThree, type ThreeEvent } from "@react-three/fiber";
import { Html, OrbitControls, Stars } from "@react-three/drei";
import BoatModel from "./BoatModel";
import PhoenixModel from "./PhoenixModel";
import { NIGHT_BG, Ripples, Sea } from "./SeaParts";
import {
  Horizon,
  Island,
  StepBuoys,
  Wake,
  X_END,
  X_START,
  type VoyageStep,
} from "./VoyageScene";
import { Gulls, type GullFlock } from "./Gulls";
import { boatProps, navigatorPose } from "../boat";
import { playPlink } from "../audio";
import type { UserData } from "../data";
import {
  MAX_STEPS,
  deleteDestination,
  destinationProgress,
  saveDestination,
  type Destination,
  type DestinationStep,
} from "../destinations";
import { newUUID } from "../types";
import { askConfirm, showToast } from "../overlays";
import { t } from "../i18n";

// 目的地の没入エディタ。3D航海カードをタップすると、この「世界」へズームインして
// 入り、夜の海の中で島の名前・対象項目・目標を設定・変更できる。
// 保存/削除/検証はDestinationDialogと同等。世界観はVoyageScene/BoatStudioと同じ。

export interface VoyageWorldProps {
  dest: Destination | null; // null = 新規作成(世界の中でそのまま設定する)
  data: UserData;
  uid: string;
  onClose: () => void;
}

type Phase = "enter" | "idle" | "exit";

// カードと同じ遠景から、船と島を望む近景へドリーインする。
// カードと同じ establishing 構図(引き+俯瞰の斜め)から入場する(iOS cardCam と同値)。
const FAR_POS = new THREE.Vector3(2.2, 8.2, 14.0);
const FAR_TARGET = new THREE.Vector3(0.2, 0.5, 0.2);
const DOLLY_SECONDS = 1.2;
const ISLAND_POS: [number, number, number] = [3.5, 0, -0.9];

// ジオメトリは色に依存しないので、モジュール読み込み時に一度だけ作る。
const MOON_GEO = new THREE.SphereGeometry(1.1, 20, 14);
const BOAT_HIT_GEO = new THREE.BoxGeometry(3.0, 2.6, 1.6);
const TAP_RING_GEO = new THREE.RingGeometry(0.9, 1.0, 48);
const SHOOTING_GEO = new THREE.PlaneGeometry(1.8, 0.035);

// この世界の空を旋回するカモメ。ホームの目的地カード(VoyageScene)で飛んでいる
// カモメが、カードを押して入ったあとの世界にも居るようにする。
// 半径・高さ・大きさはこの構図(fov44・近景は注視点から6〜8の距離・見下ろし)に
// 投影して決めた値:
// ・全羽が水平線(縦長で sy≈209)より上の空の帯に入る。高さは、上端の名前欄に
//   隠れない sy≈30〜112 に落ちるよう低めに寄せた(y=3.0以上は入力欄の裏に来る)
// ・翼幅は縦長で21〜26px、横長で23〜30px(カードの9〜19pxより近いぶん大きい)
// ・1羽以上が見えている時間は縦長で91%、横長で100%(同時に縦長2.2羽・横長6.1羽)
// 縦長は左右の視野が±10°しかなく、1羽あたり画面に入るのは1割ほどしかない。
// だから羽数で埋める(カード5羽・航海中10羽に対して、ここは18羽)。
// 半径4.8より内側は詰めない。カメラの手前を横切るときに巨大に映る
// (どうしても詰めるなら、高さを上げて画面の外を通す)。同じ理由で、半径が
// 5.2以下の羽は高さを2.6以上に保つこと。
const WORLD_GULLS: GullFlock = [
  { r: 4.8, y: 2.6, omega: 0.045, scale: 0.13, flap: 1.5, phase: 0.0 },
  { r: 5.4, y: 2.9, omega: -0.082, scale: 0.14, flap: 2.2, phase: 0.46 },
  { r: 6.2, y: 2.5, omega: 0.059, scale: 0.16, flap: 1.8, phase: 0.92 },
  { r: 6.4, y: 2.8, omega: -0.096, scale: 0.16, flap: 2.5, phase: 1.05 },
  { r: 7.2, y: 2.4, omega: 0.073, scale: 0.17, flap: 2.1, phase: 1.51 },
  { r: 8.0, y: 2.7, omega: -0.05, scale: 0.19, flap: 1.7, phase: 1.97 },
  { r: 8.2, y: 2.9, omega: 0.087, scale: 0.19, flap: 2.4, phase: 2.09 },
  { r: 5.0, y: 2.7, omega: -0.064, scale: 0.13, flap: 2.0, phase: 2.55 },
  { r: 5.6, y: 2.4, omega: 0.101, scale: 0.15, flap: 1.6, phase: 3.01 },
  { r: 5.8, y: 2.6, omega: -0.078, scale: 0.15, flap: 2.3, phase: 3.14 },
  { r: 6.6, y: 2.9, omega: 0.055, scale: 0.16, flap: 1.9, phase: 3.6 },
  { r: 7.4, y: 2.6, omega: -0.092, scale: 0.18, flap: 1.5, phase: 4.06 },
  { r: 7.6, y: 2.4, omega: 0.069, scale: 0.18, flap: 2.2, phase: 4.19 },
  { r: 8.4, y: 2.8, omega: -0.046, scale: 0.19, flap: 1.8, phase: 4.65 },
  { r: 5.2, y: 2.8, omega: 0.083, scale: 0.14, flap: 2.5, phase: 5.11 },
  { r: 6.0, y: 2.5, omega: -0.06, scale: 0.15, flap: 2.1, phase: 5.24 },
  { r: 6.8, y: 2.4, omega: 0.097, scale: 0.17, flap: 1.7, phase: 5.7 },
  { r: 7.0, y: 2.7, omega: -0.074, scale: 0.17, flap: 2.4, phase: 6.15 },
];

function easeInOutCubic(v: number): number {
  return v < 0.5 ? 4 * v * v * v : 1 - Math.pow(-2 * v + 2, 3) / 2;
}

/// 入場・退場のカメラ演出。idle中はOrbitControlsに任せる(pan無効なので
/// 注視点はnear.targetのまま動かない=退場はそこから遠景へ戻せばよい)。
function CameraRig({
  phase,
  animate,
  near,
  onEntered,
  onExited,
}: {
  phase: Phase;
  animate: boolean;
  near: { pos: THREE.Vector3; target: THREE.Vector3 };
  onEntered: () => void;
  onExited: () => void;
}) {
  const camera = useThree((s) => s.camera);
  const invalidate = useThree((s) => s.invalidate);
  const startAt = useRef<number | null>(null);
  const fromPos = useRef(new THREE.Vector3());
  const look = useRef(new THREE.Vector3());
  const done = useRef(false);

  // 初期配置。reduced-motionなら最初から近景(ジャンプカット)。
  const initialised = useRef(false);
  useLayoutEffect(() => {
    if (initialised.current) return;
    initialised.current = true;
    if (animate) {
      camera.position.copy(FAR_POS);
      camera.lookAt(FAR_TARGET);
    } else {
      camera.position.copy(near.pos);
      camera.lookAt(near.target);
    }
    invalidate();
  }, [animate, camera, near, invalidate]);

  // フェーズが変わったらタイムラインを巻き直す。
  useEffect(() => {
    startAt.current = null;
    done.current = false;
  }, [phase]);

  useFrame(({ clock }) => {
    if (!animate || phase === "idle" || done.current) return;
    const now = clock.elapsedTime;
    if (startAt.current === null) {
      startAt.current = now;
      // 退場は「いまの視点」から遠景へ逆再生する(回して眺めた後でも滑らか)。
      fromPos.current.copy(phase === "enter" ? FAR_POS : camera.position);
    }
    const raw = Math.min((now - startAt.current) / DOLLY_SECONDS, 1);
    const k = easeInOutCubic(raw);
    const toPos = phase === "enter" ? near.pos : FAR_POS;
    const fromT = phase === "enter" ? FAR_TARGET : near.target;
    const toT = phase === "enter" ? near.target : FAR_TARGET;
    camera.position.lerpVectors(fromPos.current, toPos, k);
    look.current.lerpVectors(fromT, toT, k);
    camera.lookAt(look.current);
    if (raw >= 1) {
      done.current = true;
      if (phase === "enter") onEntered();
      else onExited();
    }
  });
  return null;
}

/// 月。タップするとふわっと一瞬明るくなる(emissiveをease)。
function TappableMoon({ animate }: { animate: boolean }) {
  const mat = useRef<THREE.MeshStandardMaterial>(null);
  const glowAt = useRef(-Infinity);
  const clock = useThree((s) => s.clock);

  useFrame(({ clock: c }) => {
    if (!animate || !mat.current) return;
    const p = (c.elapsedTime - glowAt.current) / 1.3;
    mat.current.emissiveIntensity =
      p >= 0 && p < 1 ? 0.95 + Math.sin(Math.PI * p) * 0.8 : 0.95;
  });

  return (
    <mesh
      geometry={MOON_GEO}
      position={[-8, 3.2, -16]}
      onClick={(e: ThreeEvent<MouseEvent>) => {
        e.stopPropagation();
        if (animate) glowAt.current = clock.elapsedTime;
      }}
    >
      <meshStandardMaterial
        ref={mat}
        color={NIGHT_BG}
        emissive="#EADEBD"
        emissiveIntensity={0.95}
        fog={false}
      />
    </mesh>
  );
}

/// 流れ星。8〜20秒間隔で、細長い淡いメッシュが約1.5秒かけて夜空を横切る。
function ShootingStar({ animate }: { animate: boolean }) {
  const mesh = useRef<THREE.Mesh>(null);
  const mat = useRef<THREE.MeshBasicMaterial>(null);
  const nextAt = useRef(5 + Math.random() * 9); // 初回は少し早めに
  const startAt = useRef<number | null>(null);
  const from = useRef(new THREE.Vector3());
  const vel = useRef(new THREE.Vector3());

  useFrame(({ clock }) => {
    if (!animate) return;
    const time = clock.elapsedTime;
    if (startAt.current === null) {
      if (time < nextAt.current) return;
      startAt.current = time;
      const sign = Math.random() < 0.5 ? 1 : -1;
      from.current.set(
        -sign * (3 + Math.random() * 6),
        6 + Math.random() * 3.5,
        -21 - Math.random() * 4,
      );
      vel.current.set(sign * (8 + Math.random() * 4), -(2 + Math.random() * 2), 0);
      return;
    }
    const p = (time - startAt.current) / 1.5;
    const m = mesh.current;
    const mm = mat.current;
    if (p >= 1) {
      startAt.current = null;
      nextAt.current = time + 8 + Math.random() * 12;
      if (m) m.visible = false;
      return;
    }
    if (m && mm) {
      m.visible = true;
      m.position.copy(from.current).addScaledVector(vel.current, p);
      m.rotation.z = Math.atan2(vel.current.y, vel.current.x);
      mm.opacity = Math.sin(Math.PI * p) * 0.5;
    }
  });

  return (
    <mesh ref={mesh} geometry={SHOOTING_GEO} visible={false}>
      <meshBasicMaterial
        ref={mat}
        color="#EADEBD"
        transparent
        opacity={0}
        fog={false}
        depthWrite={false}
        side={THREE.DoubleSide}
      />
    </mesh>
  );
}

/// 進捗位置の船。タップで小さくホップ+波紋が一周広がり、短い音が鳴る。
/// 連打はタイムラインを巻き直すだけなので壊れない。
function PlayfulBoat({ boatX, animate }: { boatX: number; animate: boolean }) {
  const parts = useMemo(() => boatProps(), []);
  const hop = useRef<THREE.Group>(null);
  const ringMesh = useRef<THREE.Mesh>(null);
  const ringMat = useRef<THREE.MeshBasicMaterial>(null);
  const tapAt = useRef(-Infinity);
  const lastSound = useRef(0);
  const clock = useThree((s) => s.clock);

  const onTap = (e: ThreeEvent<MouseEvent>) => {
    e.stopPropagation();
    const now = performance.now();
    if (now - lastSound.current > 180) {
      lastSound.current = now;
      playPlink();
    }
    if (animate) tapAt.current = clock.elapsedTime;
  };

  useFrame(({ clock: c }) => {
    if (!animate) return;
    const p = (c.elapsedTime - tapAt.current) / 1.1;
    const g = hop.current;
    const rm = ringMesh.current;
    const rmat = ringMat.current;
    if (p >= 0 && p < 1) {
      const hopP = Math.min(p / 0.32, 1); // 前半でホップ、波紋は最後まで広がる
      if (g) g.position.y = Math.sin(Math.PI * hopP) * 0.22;
      if (rm && rmat) {
        rm.visible = true;
        const s = 1 + p * 3.6;
        rm.scale.set(s, s, 1);
        rmat.opacity = (1 - p) * 0.42;
      }
    } else {
      if (g) g.position.y = 0;
      if (rm) rm.visible = false;
    }
  });

  return (
    <group position={[boatX, 0, 0]} rotation={[0, 0.1, 0]} scale={0.55}>
      <Ripples animate={animate} />
      <Wake animate={animate} />
      <mesh
        ref={ringMesh}
        geometry={TAP_RING_GEO}
        rotation={[-Math.PI / 2, 0, 0]}
        position={[0, 0.03, 0]}
        visible={false}
      >
        <meshBasicMaterial
          ref={ringMat}
          color="#7FB8A6"
          transparent
          opacity={0}
          depthWrite={false}
        />
      </mesh>
      <group ref={hop}>
        <BoatModel parts={parts} animate={animate} />
        {/* 甲板の自分の航海士(カードと同じ配置。姿は装いで選んだもの) */}
        <group position={[0.88, 0.57, 0.22]} scale={0.62}>
          <PhoenixModel animate={animate} pose={navigatorPose()} />
        </group>
      </group>
      {/* 透明な当たり判定(船体+帆を覆う) */}
      <mesh geometry={BOAT_HIT_GEO} position={[0.1, 1.0, 0]} onClick={onTap}>
        <meshBasicMaterial transparent opacity={0} depthWrite={false} />
      </mesh>
    </group>
  );
}

/// 世界そのもの。VoyageScene/BoatStudioと同じ夜の海+星・月・霧・島・船。
function WorldScene({
  phase,
  animate,
  boatX,
  islandLabel,
  steps,
  onToggleStep,
  onEntered,
  onExited,
}: {
  phase: Phase;
  animate: boolean;
  boatX: number;
  islandLabel: string;
  steps?: VoyageStep[];
  onToggleStep?: (index: number) => void;
  onEntered: () => void;
  onExited: () => void;
}) {
  // 近景の構図は画面の縦横比で決める。横長なら船と島の中間を見る。縦長は
  // 視野が狭いので船寄り+少し引き、下部パネルに隠れないよう視線をやや
  // 沈めて船を画面上寄りに置く(島は回して見つける楽しみに残す)。
  const size = useThree((s) => s.size);
  const near = useMemo(() => {
    const aspect = size.width / Math.max(size.height, 1);
    const wide = aspect >= 1.05;
    const tx = boatX + (ISLAND_POS[0] - boatX) * (wide ? 0.5 : 0.08);
    // カモメは注視点の真上を回らせる。見渡す操作(OrbitControls)の中心も同じ点
    // なので、どちらへ回しても空にカモメが残る。
    const gullCenter: [number, number, number] = [tx, 0, -0.5];
    return wide
      ? {
          pos: new THREE.Vector3(tx - 1.2, 1.9, 5.4),
          target: new THREE.Vector3(tx, 0.5, -0.5),
          maxPolar: Math.PI * 0.52,
          gullCenter,
        }
      : {
          pos: new THREE.Vector3(tx - 1.0, 1.9, 7.2),
          target: new THREE.Vector3(tx, -0.25, -0.5),
          maxPolar: Math.PI * 0.46,
          gullCenter,
        };
  }, [boatX, size.width, size.height]);

  return (
    <>
      <color attach="background" args={[NIGHT_BG]} />
      <fog attach="fog" args={[NIGHT_BG, 12, 30]} />
      {/* 月光: VoyageSceneと同じトーン。影は使わない。 */}
      <ambientLight color="#ffe9c8" intensity={0.45} />
      <directionalLight color="#EADEBD" intensity={1.15} position={[-6, 8, -5]} />
      <directionalLight color="#5DCAA5" intensity={0.2} position={[5, 3, 6]} />
      <Stars
        radius={42}
        depth={18}
        count={620}
        factor={2.1}
        saturation={0}
        fade
        speed={animate ? 0.5 : 0}
      />
      <TappableMoon animate={animate} />
      <ShootingStar animate={animate} />
      <Sea moonX={-8} animate={animate} />
      <Horizon />
      <Gulls flock={WORLD_GULLS} animate={animate} center={near.gullCenter} />
      <Island />
      {/* ステップ目標なら、航路にブイを浮かべる。タップでその場で達成/取消。 */}
      {steps && steps.length > 0 && <StepBuoys steps={steps} onToggle={onToggleStep} />}
      {/* 入力中の島の名前が、島の上にライブで浮かぶ */}
      {islandLabel && (
        <Html
          position={[ISLAND_POS[0], 1.9, ISLAND_POS[2]]}
          center
          distanceFactor={9}
          zIndexRange={[3, 0]}
          style={{ pointerEvents: "none" }}
        >
          <div className="voyage-world-label">{islandLabel}</div>
        </Html>
      )}
      <PlayfulBoat boatX={boatX} animate={animate} />
      <CameraRig
        phase={phase}
        animate={animate}
        near={near}
        onEntered={onEntered}
        onExited={onExited}
      />
      {phase === "idle" && (
        <OrbitControls
          target={[near.target.x, near.target.y, near.target.z]}
          enablePan={false}
          enableDamping
          minDistance={3.2}
          maxDistance={11}
          minPolarAngle={Math.PI * 0.16}
          maxPolarAngle={near.maxPolar}
        />
      )}
    </>
  );
}

// 日付/時刻の入力欄は端末のローカル時刻で扱う。toISOString はUTCに寄るので、
// JSTでは日付が一日ずれる(前日が入る)。
const pad2 = (n: number) => String(n).padStart(2, "0");
function dateInputValue(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}
function timeInputValue(d: Date): string {
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

/// 没入エディタ本体。全画面の夜の海+世界に馴染む半透明の編集UI。
export default function VoyageWorld({ dest, data, uid, onClose }: VoyageWorldProps) {
  const [animate] = useState(
    () => !window.matchMedia("(prefers-reduced-motion: reduce)").matches,
  );
  const [phase, setPhase] = useState<Phase>(animate ? "enter" : "idle");
  // 海など「外側」をタップすると、編集UIをフェードして世界に入り込む(もう一度タップで戻る)。
  const [uiHidden, setUiHidden] = useState(false);

  // ---- 編集状態 ----
  // 目標のかたちは2つだけ:「期日を決める」か「ステップで辿る」か。
  // (累計時間/完了は廃止。累計時間は着岸時にどの形でも表示される)
  const [name, setName] = useState(dest?.name ?? "");
  const [kind, setKind] = useState<"date" | "steps">(
    dest?.steps && dest.steps.length > 0 ? "steps" : "date",
  );
  // ステップ目標の編集リスト(順序付き)。チェックの反転は即保存する。
  const [steps, setSteps] = useState<DestinationStep[]>(() => dest?.steps ?? []);
  const [dateStr, setDateStr] = useState(
    dest?.targetDate ? dateInputValue(dest.targetDate) : "",
  );
  // 時刻も決めるか。既定は日付だけ(=その日いっぱいが締切)。
  const [withTime, setWithTime] = useState(Boolean(dest?.targetHasTime));
  const [timeStr, setTimeStr] = useState(
    dest?.targetDate && dest.targetHasTime ? timeInputValue(dest.targetDate) : "",
  );
  const [working, setWorking] = useState(false);
  const confirmingRef = useRef(false);
  // 期日を「触った」印。既存の値がすでに有効でも、開いた直後には
  // 自動保存しない(ただ見ただけで閉じてしまうのを防ぐ)ためのガード。
  const dateTouched = useRef(false);
  const autoSavedRef = useRef(false);

  const trimmed = name.replace(/^[\s　]+|[\s　]+$/g, "");
  // 名前のあるステップだけを有効とみなす(空行は保存時に落とす)。
  const namedSteps = steps.filter((s) => s.name.trim().length > 0);
  // 締切。時刻を決めていなければ「その日いっぱい」(destinationDeadline と同じ解釈)。
  const targetDateValue = (): Date | undefined => {
    if (kind !== "date" || dateStr.length !== 10) return undefined;
    if (withTime) {
      if (timeStr.length !== 5) return undefined;
      return new Date(`${dateStr}T${timeStr}:00`);
    }
    return new Date(`${dateStr}T00:00:00`);
  };
  // 時刻まで決めるときは、過ぎた時刻を締切にできないようにする
  // (保存した瞬間に着岸してしまうため)。
  const deadlinePassed = (() => {
    if (!withTime) return false;
    const target = targetDateValue();
    return target ? target.getTime() <= Date.now() : false;
  })();
  const dateValid =
    dateStr.length === 10 && (!withTime || timeStr.length === 5) && !deadlinePassed;
  const valid =
    trimmed.length > 0 && (kind === "date" ? dateValid : namedSteps.length >= 1);

  // ---- 世界の配置(カードと同じ航路・島) ----
  // ステップ目標は「達成数/全数」で船が進む(編集中の局所stateを即反映)。
  const stepDoneFlags: VoyageStep[] = steps.map((s) => ({
    done: Boolean(s.doneAt),
    doneAt: s.doneAt,
  }));
  const stepsRatio = steps.length
    ? stepDoneFlags.filter((s) => s.done).length / steps.length
    : 0;
  const ratio =
    kind === "steps"
      ? stepsRatio
      : dest
        ? destinationProgress(dest, data.sessions).ratio
        : 0;
  const boatX = X_START + Math.min(Math.max(ratio, 0), 1) * (X_END - X_START);

  // ---- 閉じる(退場演出→onClose。reduced-motionはジャンプカット) ----
  const phaseRef = useRef(phase);
  phaseRef.current = phase;
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;
  const requestClose = useCallback(() => {
    if (confirmingRef.current || phaseRef.current === "exit") return;
    if (!animate) {
      onCloseRef.current();
      return;
    }
    setPhase("exit");
  }, [animate]);
  const handleEntered = useCallback(() => {
    setPhase((p) => (p === "enter" ? "idle" : p));
  }, []);
  const handleExited = useCallback(() => {
    onCloseRef.current();
  }, []);

  // Escで閉じる+表示中は背景スクロールを固定(Modalと同じ作法)。
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") requestClose();
    };
    window.addEventListener("keydown", onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = prev;
    };
  }, [requestClose]);

  // ---- ステップの編集(追加・改名・削除・達成の反転) ----
  // チェックの反転(パネル/世界のブイ)は、既存の目的地ならその場で確定する。
  // 新規(未保存)の目的地は局所stateだけ動かし、確定は「保存」に委ねる
  // (id未確定のまま書くと毎回別の島が生まれてしまうため)。
  const persistSteps = (next: DestinationStep[]) => {
    setSteps(next);
    if (dest?.id && trimmed.length > 0 && next.some((s) => s.name.trim().length > 0)) {
      // fire-and-forget。オフラインや一時的な失敗は握りつぶす(局所stateは進む)。
      void saveDestination(uid, {
        id: dest.id,
        name: trimmed,
        steps: next,
        createdAt: dest.createdAt,
      }).catch(() => {});
    }
  };
  const toggleStep = (index: number) => {
    playPlink();
    persistSteps(
      steps.map((s, i) =>
        i === index ? { ...s, doneAt: s.doneAt ? undefined : new Date() } : s,
      ),
    );
  };
  const addStep = () => {
    if (steps.length >= MAX_STEPS) return;
    setSteps((list) => [...list, { id: newUUID(), name: "" }]);
  };
  const removeStep = (index: number) => {
    setSteps((list) => list.filter((_, i) => i !== index));
  };
  const renameStep = (index: number, value: string) => {
    setSteps((list) => list.map((s, i) => (i === index ? { ...s, name: value } : s)));
  };

  // ---- 保存/削除(DestinationDialogと同等) ----
  const save = async () => {
    if (!valid || working) return;
    setWorking(true);
    await saveDestination(uid, {
      id: dest?.id,
      name: trimmed,
      // 種類ごとに、その種類の値だけを書く(排他)。
      targetDate: targetDateValue(),
      targetHasTime: kind === "date" && withTime && timeStr.length === 5,
      steps: kind === "steps" ? namedSteps : undefined,
      createdAt: dest?.createdAt,
    });
    showToast(t("savedToast"));
    requestClose();
  };

  // 期日を選び終えたら、そのまま保存してズームアウト(ホームへ戻る)。
  // 「保存する」を別途押す一手間をなくす — 名前だけの変更は従来通り
  // 保存ボタンで確定する(値を触っていなければここでは動かない)。
  useEffect(() => {
    // 目標の種類を切り替えたら、前の種類での「触った/自動保存済み」の印は捨てる。
    dateTouched.current = false;
    autoSavedRef.current = false;
  }, [kind]);

  // 時刻も決めるときは日付を選んだ時点では閉じない(時刻を入れる間が要る)。
  // そちらは「保存する」で確定させる。
  useEffect(() => {
    if (kind !== "date" || withTime || !dateTouched.current || autoSavedRef.current) return;
    if (dateStr.length !== 10 || !trimmed || working) return;
    autoSavedRef.current = true;
    void save();
  }, [dateStr, kind, withTime, trimmed, working]);

  const remove = async () => {
    if (!dest || working) return;
    confirmingRef.current = true;
    const ok = await askConfirm({
      title: t("deleteDestination"),
      message: t("deleteDestinationConfirm"),
      confirmLabel: t("delete"),
      danger: true,
    });
    confirmingRef.current = false;
    if (!ok) return;
    setWorking(true);
    await deleteDestination(uid, dest.id);
    requestClose();
  };

  // iOS Safari はキーボードでレイアウトビューポートが縮まないため、
  // visualViewport の縮み量ぶんだけ下部パネルを持ち上げる(--vv-lift)。
  const rootRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const vv = window.visualViewport;
    if (!vv) return;
    const apply = () => {
      const lift = Math.max(0, window.innerHeight - vv.height - vv.offsetTop);
      rootRef.current?.style.setProperty("--vv-lift", `${lift}px`);
    };
    vv.addEventListener("resize", apply);
    vv.addEventListener("scroll", apply);
    apply();
    return () => {
      vv.removeEventListener("resize", apply);
      vv.removeEventListener("scroll", apply);
    };
  }, []);

  return (
    <div
      ref={rootRef}
      className="voyage-world"
      role="dialog"
      aria-modal="true"
      aria-label={t("destinationTitle")}
    >
      <Canvas
        dpr={[1, 2]}
        frameloop={animate ? "always" : "demand"}
        camera={{ position: [FAR_POS.x, FAR_POS.y, FAR_POS.z], fov: 44 }}
        // 海など「外側」(オブジェクト以外)をタップ = 編集UIをフェードして世界に入り込む/戻す。
        onPointerMissed={() => {
          if (phase === "idle") setUiHidden((h) => !h);
        }}
      >
        <WorldScene
          phase={phase}
          animate={animate}
          boatX={boatX}
          islandLabel={trimmed}
          steps={kind === "steps" ? stepDoneFlags : undefined}
          onToggleStep={toggleStep}
          onEntered={handleEntered}
          onExited={handleExited}
        />
      </Canvas>

      <div className={`voyage-world-ui${phase === "idle" && !uiHidden ? "" : " hidden"}`}>
        <div className="voyage-world-top">
          <input
            className="field voyage-world-name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder={t("islandNamePlaceholder")}
            maxLength={60}
            aria-label={t("islandName")}
          />
          <button className="voyage-world-close" onClick={requestClose}>
            {t("close")}
          </button>
        </div>

        <div className="voyage-world-panel">
          {/* 質問形式:この島へは、どう向かう?(答えは2つ) */}
          <p className="section-label">{t("goalQuestion")}</p>
          <div className="chip-row">
            <button
              className={`chip${kind === "date" ? " selected" : ""}`}
              onClick={() => setKind("date")}
            >
              {t("goalDateOption")}
            </button>
            <button
              className={`chip${kind === "steps" ? " selected" : ""}`}
              onClick={() => setKind("steps")}
            >
              {t("goalStepsOption")}
            </button>
          </div>

          <div style={{ marginTop: 14 }}>
            {kind === "date" ? (
              <>
                <p className="quest-intro">{t("goalDateDesc")}</p>
                <input
                  className="field"
                  type="date"
                  value={dateStr}
                  min={dateInputValue(new Date())}
                  onChange={(e) => {
                    dateTouched.current = true;
                    setDateStr(e.target.value);
                  }}
                />
                <label className="voyage-time-toggle">
                  <input
                    type="checkbox"
                    checked={withTime}
                    onChange={(e) => {
                      const on = e.target.checked;
                      // 時刻を決めるあいだは自動保存で閉じない。
                      if (on) autoSavedRef.current = true;
                      setWithTime(on);
                      if (!on) setTimeStr("");
                    }}
                  />
                  {t("goalTimeToggle")}
                </label>
                {withTime && (
                  <>
                    <input
                      className="field"
                      type="time"
                      value={timeStr}
                      onChange={(e) => setTimeStr(e.target.value)}
                      aria-label={t("goalTime")}
                    />
                    <p className="quest-intro">
                      {deadlinePassed ? t("goalTimePast") : t("goalTimeDesc")}
                    </p>
                  </>
                )}
              </>
            ) : (
              <>
                <p className="quest-intro">{t("goalStepsDesc")}</p>
                <div className="step-list">
                  {steps.map((step, i) => (
                    <div key={step.id} className="step-row">
                      <button
                        type="button"
                        className={`step-check${step.doneAt ? " done" : ""}`}
                        onClick={() => toggleStep(i)}
                        aria-pressed={Boolean(step.doneAt)}
                        aria-label={t("markDone")}
                      >
                        {step.doneAt ? (
                          <svg width="14" height="14" viewBox="0 0 24 24" aria-hidden="true">
                            <path
                              d="M5 13l4 4L19 7"
                              fill="none"
                              stroke="currentColor"
                              strokeWidth="3"
                              strokeLinecap="round"
                              strokeLinejoin="round"
                            />
                          </svg>
                        ) : null}
                      </button>
                      <input
                        className={`field step-input${step.doneAt ? " done" : ""}`}
                        value={step.name}
                        onChange={(e) => renameStep(i, e.target.value)}
                        placeholder={t("stepPlaceholder")}
                        maxLength={60}
                        aria-label={t("goalSteps")}
                      />
                      <button
                        type="button"
                        className="step-remove"
                        onClick={() => removeStep(i)}
                        aria-label={t("delete")}
                      >
                        ×
                      </button>
                    </div>
                  ))}
                </div>
                {steps.length < MAX_STEPS && (
                  <button type="button" className="step-add" onClick={addStep}>
                    + {t("addStep")}
                  </button>
                )}
              </>
            )}
          </div>

          <div style={{ height: 18 }} />
          <button
            className="primary-button"
            onClick={save}
            disabled={!valid || working}
          >
            {t("save")}
          </button>
          {dest && (
            <button className="danger-button" onClick={remove} disabled={working}>
              {t("deleteDestination")}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
