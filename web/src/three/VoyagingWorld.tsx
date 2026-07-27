import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import * as THREE from "three";
import { Canvas, useFrame } from "@react-three/fiber";
import { OrbitControls, Stars } from "@react-three/drei";
import BoatModel from "./BoatModel";
import PhoenixModel from "./PhoenixModel";
import { Moon, PassingSwells, Sea, Sun } from "./SeaParts";
import { Horizon, Island, Wake } from "./VoyageScene";
import { Gulls, type GullFlock } from "./Gulls";
import PassingShip from "./PassingShip";
import { boatProps } from "../boat";
import { useNavigatorPose } from "./navigatorPose";
import {
  playChime,
  setSoundPref,
  soundPref,
  startSound,
  stopSound,
  type SoundMode,
} from "../audio";
import { clockLabel, elapsedSec, isOnBreak, pomoPhase, type RunningTimer } from "../timer";
import { durationLabel, t } from "../i18n";
import { useBackToClose } from "../backClose";
import { SEA_LIGHT, useTimeOfDay, type TimeOfDay } from "../timeOfDay";
import { STYLE_COLORS, normalizeStyle, normalizeSymbol } from "../types";
import { TileSymbolSvg } from "../symbols";

// 作業中の世界。自分の船が現在の時間帯の海を走り、その上に経過時間が出る。
// 「分数を入力する」のではなく、この航海そのものが記録になる。
//
// 構図・素材は目的地の航海シーン(VoyageScene)と同じ言語に揃える
// (低ポリ+flatShading、時間に沿う空と海、天体、波紋、甲板の航海士)。違いは
// 島へ近づくのではなく、いま進んでいる最中を見せること。

// 船は原点に置いたまま、海と波を後ろへ流して前進を感じさせる。
// 船首は +x を向いているので、水は -x へ流れる。
// 船だけを大写しにすると航海に見えないので、空と水平線が入る距離まで引く。
// 少し上を見て、月と星のための空を画面に残す。
const CAM_POS: [number, number, number] = [-5.6, 2.4, 8.6];
const CAM_TARGET = new THREE.Vector3(0.8, 1.15, 0);
const CAM_FOV = 38;

/// 既定のカメラが向いている方位(Y軸まわり)。他人の船の灯は、この向きに対して
/// 横切らせる — 世界の座標軸に沿って走らせると、カメラは斜めを向いているので
/// 航路のほとんどが画面の外を通ってしまう。
const VIEW_YAW = Math.atan2(-(CAM_TARGET.x - CAM_POS[0]), -(CAM_TARGET.z - CAM_POS[2]));

// 月と目的地の島の位置。縦長画面での見え方を実機で合わせた値。
const MOON_POS: [number, number, number] = [5.1, 3.3, -5.5];
const ISLAND_POS: [number, number, number] = [6.5, 0, -5.5];
const VOYAGING_LIGHT_POS: Record<TimeOfDay, [number, number, number]> = {
  morning: [-5.2, 1.7, -5.5],
  day: [0.8, 5.1, -5.5],
  evening: [5.4, 1.25, -5.5],
  night: MOON_POS,
};

/// 休憩中の流れの速さ(通常=1)。錨を下ろしたら止まりきらずに漂う程度まで落ちる。
const RESTING_FLOW = 0.12;

// 航海中の空を旋回するカモメ。半径・高さ・大きさは、この構図(縦長・fov38)に
// 投影して決めた値: 空の空き帯(見出しの下〜水平線の上)に入る割合が高く、
// 翼幅が画面上で20〜30px程度に収まる組み合わせ。1羽以上見えている時間は約89%。
// 半径を6.6より外へ出すとカメラのすぐ横を通って巨大に映るので広げない。
const VOYAGING_GULLS: GullFlock = [
  { r: 4.2, y: 2.3, omega: 0.085, scale: 0.15, flap: 2.1, phase: 0.0 },
  { r: 5.0, y: 2.8, omega: -0.065, scale: 0.14, flap: 1.7, phase: 0.8 },
  { r: 4.6, y: 2.0, omega: 0.11, scale: 0.16, flap: 2.5, phase: 1.6 },
  { r: 5.6, y: 3.2, omega: 0.055, scale: 0.13, flap: 1.6, phase: 2.4 },
  { r: 3.9, y: 2.6, omega: -0.1, scale: 0.17, flap: 2.3, phase: 3.2 },
  { r: 6.0, y: 2.2, omega: 0.07, scale: 0.12, flap: 1.9, phase: 4.0 },
  { r: 5.2, y: 3.5, omega: -0.05, scale: 0.14, flap: 1.5, phase: 4.8 },
  { r: 4.4, y: 3.0, omega: 0.095, scale: 0.16, flap: 2.2, phase: 5.6 },
  { r: 6.6, y: 2.5, omega: -0.045, scale: 0.12, flap: 1.8, phase: 6.1 },
  { r: 3.6, y: 3.3, omega: 0.125, scale: 0.18, flap: 2.6, phase: 2.0 },
];

/// 目的地の島。航海が続くほど、ゆっくり近づいてくる(進んでいる証)。
/// 距離は漸近的に縮めるので、追い越して背後へ抜けてしまうことはない。
const ISLAND_APPROACH = 1.2; // 開始時は最終距離の2.2倍だけ遠い
const ISLAND_TAU = 1500; // 25分でおよそ半分まで詰まる
function ApproachingIsland({ timer, animate }: { timer: RunningTimer; animate: boolean }) {
  const group = useRef<THREE.Group>(null);

  const place = (g: THREE.Group) => {
    // 近づく距離は「働いた時間」で決まる。休憩しているあいだ、島は近づかない。
    const elapsed = elapsedSec(timer);
    const k = 1 + ISLAND_APPROACH * Math.exp(-elapsed / ISLAND_TAU);
    g.position.set(ISLAND_POS[0] * k, ISLAND_POS[1], ISLAND_POS[2] * k);
  };

  // 静止時(reduced-motion)でも、経過に見合った位置には置く。
  useLayoutEffect(() => {
    if (group.current) place(group.current);
  });

  useFrame(() => {
    if (!animate || !group.current) return;
    place(group.current);
  });

  return (
    <group ref={group} scale={0.7}>
      <Island />
    </group>
  );
}

/// 世界の中身。カメラはドラッグで見渡せる(OrbitControls)。
function VoyagingSea({
  animate,
  showIsland,
  timer,
  resting,
  timeOfDay,
}: {
  animate: boolean;
  showIsland: boolean;
  timer: RunningTimer;
  resting: boolean;
  timeOfDay: TimeOfDay;
}) {
  const parts = useMemo(() => boatProps(), []);
  const light = SEA_LIGHT[timeOfDay];
  const lightPosition = VOYAGING_LIGHT_POS[timeOfDay];
  // 甲板の航海士。待機を基本にときどき辺りを見渡し、休憩中は腰を下ろす
  // (立ち座りだけは PhoenixModel がゆっくり補間する)。
  const pose = useNavigatorPose(animate, resting ? "sit" : null);

  // カメラは OrbitControls に任せる(見渡せるようにするため)。
  // ここで camera.position / lookAt を書くと操作と取り合いになるので触らない。

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
          factor={2.0}
          saturation={0}
          fade
          speed={animate ? 0.5 : 0}
        />
      )}
      {/* 天体。縦長画面では位置と見かけの大きさを分けて調整する。 */}
      <group position={lightPosition} scale={light.celestial === "moon" ? 0.4 : 0.72}>
        {light.celestial === "moon" ? (
          <Moon position={[0, 0, 0]} />
        ) : (
          <Sun position={[0, 0, 0]} color={light.reflection} />
        )}
      </group>
      {/* 水面の反射は、その時間の太陽/月の真下に立てる。 */}
      <Sea
        moonX={lightPosition[0]}
        animate={animate}
        seaColor={light.sea}
        deepColor={light.seaDeep}
        lightColor={light.reflection}
        reflection={timeOfDay === "day" ? 0.34 : 0.5}
      />
      <Horizon />
      <PassingSwells animate={animate} flow={resting ? RESTING_FLOW : 1} />
      {timeOfDay !== "night" && <Gulls flock={VOYAGING_GULLS} animate={animate} />}
      {/* 数分に一度、水平線の手前を他人の船の灯が渡っていく。
          既定の視線を横切る向きに置く(VIEW_YAW)。 */}
      <group rotation={[0, VIEW_YAW, 0]}>
        <PassingShip animate={animate} />
      </group>
      {/* 目的地があるなら、その島を遠くの前方に置く。何へ向かっているかが見える。 */}
      {showIsland && <ApproachingIsland timer={timer} animate={animate} />}
      {/* 自分の船。配置は VoyageScene と同値(甲板の航海士も同じ位置・姿)。
          同心円の波紋(Ripples)は「その場で揺れている」に見えるので、走っている
          この画面では使わない。後ろへ引く航跡と、流れる水の筋で進みを見せる。 */}
      <group position={[0, 0, 0]} rotation={[0, 0.1, 0]} scale={0.55}>
        <Wake animate={animate} />
        <BoatModel parts={parts} animate={animate} />
        <group position={[0.88, 0.57, 0.22]} scale={0.62}>
          <PhoenixModel animate={animate} pose={pose} />
        </group>
      </group>
      {/* ドラッグで360度見渡せる。水平は制限なし、俯角は水面より下へ潜らせない
          (海は円盤なので下から見ると裏側が見えてしまう)。 */}
      <OrbitControls
        target={[CAM_TARGET.x, CAM_TARGET.y, CAM_TARGET.z]}
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

export interface VoyagingWorldProps {
  itemName: string;
  /// 走っている航海そのもの(休憩の状態を含む)。
  timer: RunningTimer;
  /// 目的地が設定されているか。遠くに島を出すかどうかだけに使う。
  hasDestination: boolean;
  /// 記録の書き込み中。二重に押させない。
  saving?: boolean;
  /// 保存成功後に、航海中の海を残したまま表示する完了内容。
  completion?: {
    minutes: number;
    note?: string;
    styleToken: string;
    symbolToken: string;
  };
  onFinish: (note: string) => void;
  onHome: () => void;
  onDiscard: () => void;
  /// 世界を閉じるだけ(計測は続く)。
  onMinimize: () => void;
  onToggleMode: () => void;
  /// 手で分数を入れる従来の記録へ逃げる(計測を始め忘れたとき用)。
  onManual: () => void;
  /// 休憩に入る/休憩をおえる。時計はこのあいだ止まる。
  onToggleBreak: () => void;
}

export default function VoyagingWorld({
  itemName,
  timer,
  hasDestination,
  saving = false,
  completion,
  onFinish,
  onHome,
  onDiscard,
  onMinimize,
  onToggleMode,
  onManual,
  onToggleBreak,
}: VoyagingWorldProps) {
  const mode = timer.mode;
  const resting = completion ? false : isOnBreak(timer);
  const [animate] = useState(
    () => !window.matchMedia("(prefers-reduced-motion: reduce)").matches,
  );
  const timeOfDay = useTimeOfDay();
  const [note, setNote] = useState("");
  const [sound, setSound] = useState<SoundMode>(() => soundPref());
  const [now, setNow] = useState(() => Date.now());
  // 海をタップすると、UIを消して世界だけにする(もう一度タップで戻る)。
  const [uiHidden, setUiHidden] = useState(false);
  // タップとドラッグ(見渡す操作)を見分けるための押した位置。
  const pointerDown = useRef<{ x: number; y: number; onWorld: boolean } | null>(null);

  useEffect(() => {
    if (completion) return;
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [completion]);

  const sec = elapsedSec(timer, now);
  const phase = mode === "pomo" && !resting ? pomoPhase(sec) : null;
  // 自由計測は経過を数え上げ、ポモドーロは今の局面の残りを数え下げる。
  const display = phase ? clockLabel(phase.left) : clockLabel(sec);

  // 局面が変わったら知らせる。初回マウントでは鳴らさない。
  const prevPhase = useRef(phase?.key);
  useEffect(() => {
    if (!phase) return;
    if (prevPhase.current !== undefined && prevPhase.current !== phase.key) playChime();
    prevPhase.current = phase.key;
  }, [phase?.key, phase]);

  // タイトルにも出す。タブが後ろにいても進み具合が分かる。
  useEffect(() => {
    document.title = completion
      ? `${durationLabel(completion.minutes)} · ${itemName} · Landfall`
      : `${display} · ${itemName} · Landfall`;
    return () => {
      document.title = "Landfall — Study Log";
    };
  }, [completion, display, itemName]);

  // 記録が海へ刻まれた瞬間を、短い音でも知らせる。
  useEffect(() => {
    if (completion) playChime();
  }, [completion]);

  // BGM。航海の世界を見ているあいだ流れる(畳んでいるあいだは浮きピル側が受け持つ)。
  useEffect(() => {
    startSound(sound);
    return () => stopSound();
  }, [sound]);

  const cycleSound = () => {
    const next: SoundMode = sound === "off" ? "waves" : sound === "waves" ? "piano" : "off";
    setSoundPref(next);
    setSound(next);
  };

  const soundLabel =
    sound === "off" ? t("soundOff") : sound === "waves" ? t("soundWaves") : t("soundPiano");

  // 計測中の「戻る」は世界を畳む。完了後は戻り先のない浮きチップを作らず、
  // 明示ボタンと同じくホームへ戻す。
  const closeAction = completion ? onHome : onMinimize;
  useBackToClose(true, closeAction);

  // Escは「閉じるだけ」(計測は続ける)。取り消しと混同させない。
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") closeAction();
    };
    window.addEventListener("keydown", onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = prev;
    };
  }, [closeAction]);

  return (
    <div
      className={`voyaging-world time-${timeOfDay}`}
      data-time-of-day={timeOfDay}
      role="dialog"
      aria-modal="true"
      // 世界を「タップ」したらUIを消して世界だけにする(もう一度で戻る)。
      // R3Fの onPointerMissed は当たり判定が無いときだけ呼ばれ、海はメッシュなので
      // ほとんど発火しない。だからここで受ける。見渡すドラッグでは消さないよう、
      // 押してから離すまでに動いた距離で見分ける。
      onPointerDown={(e) => {
        // 3D側の判定は「canvasかどうか」では見ない。R3Fが canvas を包む div が
        // 手前に来るので当たらない。UIの上でなければ世界とみなす。
        pointerDown.current = {
          x: e.clientX,
          y: e.clientY,
          onWorld:
            !completion &&
            !(e.target as HTMLElement).closest(
              ".voyaging-top, .voyaging-panel, .voyaging-complete",
            ),
        };
      }}
      onPointerUp={(e) => {
        const from = pointerDown.current;
        pointerDown.current = null;
        if (!from || !from.onWorld) return;
        if (Math.hypot(e.clientX - from.x, e.clientY - from.y) < 6) {
          setUiHidden((v) => !v);
        }
      }}
    >
      <Canvas dpr={[1, 2]} camera={{ position: CAM_POS, fov: CAM_FOV }}>
        <VoyagingSea
          animate={animate}
          showIsland={hasDestination}
          timer={timer}
          resting={resting}
          timeOfDay={timeOfDay}
        />
      </Canvas>

      {!completion && (
        <div className={`voyaging-ui${uiHidden ? " hidden" : ""}`}>
          <div className="voyaging-top">
            <div className="voyaging-heading">
              <p className="voyaging-item">{itemName}</p>
              <p className="voyaging-clock">{display}</p>
              <p className="voyaging-phase">
                {resting
                  ? t("restingNow")
                  : phase
                    ? phase.inFocus
                      ? t("focusLabel")
                      : t("breakLabel")
                    : t("voyagingNow")}
              </p>
              {/* 休憩。押すと時計が止まり、甲板の航海士が腰を下ろす。
                  設定(下のチップ)でも記録の締め(下のパネル)でもない、
                  この航海の途中の行動なので、時計のすぐ下に単独で置く。 */}
              <button
                className={`voyaging-break${resting ? " on" : ""}`}
                onClick={() => {
                  // 休憩ぶんはこの瞬間に引かれる。1秒ごとの now のままだと
                  // 再開した瞬間だけ時計が1秒巻き戻って見えるので、取り直す。
                  setNow(Date.now());
                  onToggleBreak();
                }}
              >
                {resting ? t("endBreak") : t("takeBreak")}
              </button>
              {/* 航海の「進み方」の設定。下の行動(記録する/やめる)とは別ものなので、
                  時計のそばに小さく置いて混ぜない。 */}
              <div className="voyaging-modes">
                <button
                  className={`voyaging-mode${mode === "pomo" ? " on" : ""}`}
                  onClick={onToggleMode}
                  aria-pressed={mode === "pomo"}
                >
                  {t("pomodoroChip")}
                </button>
                <button className="voyaging-mode" onClick={cycleSound}>
                  {soundLabel}
                </button>
              </div>
              {/* 見渡せること・世界だけにできることを知らせる。 */}
              <p className="voyaging-hint">{t("lookAroundHint")}</p>
            </div>
            <button className="voyage-world-close" onClick={onMinimize}>
              {t("close")}
            </button>
          </div>

          {/* 下のパネルは「この航海をどうするか」だけ。 */}
          <div className="voyaging-panel">
            <input
              className="field"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder={t("noteOptional")}
              maxLength={120}
              aria-label={t("noteOptional")}
            />
            <button
              className="primary-button voyaging-record"
              onClick={() => onFinish(note)}
              disabled={saving}
            >
              {t("finishVoyage")}
            </button>
            <div className="voyaging-alt">
              <button className="voyaging-link" onClick={onManual}>
                {t("enterByHand")}
              </button>
              <button className="voyaging-link danger" onClick={onDiscard}>
                {t("discardVoyage")}
              </button>
            </div>
          </div>
        </div>
      )}

      {completion && (
        <VoyageCompletion
          itemName={itemName}
          minutes={completion.minutes}
          note={completion.note}
          styleToken={completion.styleToken}
          symbolToken={completion.symbolToken}
          onHome={onHome}
        />
      )}
    </div>
  );
}

function VoyageCompletion({
  itemName,
  minutes,
  note,
  styleToken,
  symbolToken,
  onHome,
}: {
  itemName: string;
  minutes: number;
  note?: string;
  styleToken: string;
  symbolToken: string;
  onHome: () => void;
}) {
  const style = STYLE_COLORS[normalizeStyle(styleToken)];

  return (
    <section
      className="voyaging-complete"
      role="status"
      aria-live="polite"
      aria-label={t("voyageComplete")}
    >
      <div className="voyaging-complete-card">
        <span className="voyaging-complete-line" aria-hidden="true" />
        <p className="voyaging-complete-eyebrow">{t("voyageComplete")}</p>
        <div
          className="voyaging-complete-icon"
          style={{ background: style.bg }}
          aria-hidden="true"
        >
          <TileSymbolSvg
            symbol={normalizeSymbol(symbolToken)}
            fg={style.fg}
            bg={style.bg}
          />
        </div>
        <p className="voyaging-complete-label">{t("completedWork")}</p>
        <h2 className="voyaging-complete-name">{itemName}</h2>
        {note && <p className="voyaging-complete-note">{note}</p>}
        <p className="voyaging-complete-time">
          {t("completedTotal")} {durationLabel(minutes)}
        </p>
        <button className="primary-button voyaging-complete-home" onClick={onHome}>
          {t("returnHome")}
        </button>
      </div>
    </section>
  );
}
