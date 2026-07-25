import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import * as THREE from "three";
import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { Stars } from "@react-three/drei";
import BoatModel from "./BoatModel";
import PhoenixModel from "./PhoenixModel";
import { Moon, NIGHT_BG, Sea } from "./SeaParts";
import { Horizon, Island, Wake } from "./VoyageScene";
import { boatProps, navigatorPose } from "../boat";
import {
  playChime,
  setSoundPref,
  soundPref,
  startSound,
  stopSound,
  type SoundMode,
} from "../audio";
import { clockLabel, elapsedSec, pomoPhase, type TimerMode } from "../timer";
import { t } from "../i18n";

// 作業中の世界。自分の船が夜の海を走り、その上に経過時間が出る。
// 「分数を入力する」のではなく、この航海そのものが記録になる。
//
// 構図・素材は目的地の航海シーン(VoyageScene)と同じ言語に揃える
// (低ポリ+flatShading、夜の海、星、月、波紋、甲板の航海士)。違いは
// 島へ近づくのではなく、いま進んでいる最中を見せること。

// 船は原点に置いたまま、海と波を後ろへ流して前進を感じさせる。
// 船首は +x を向いているので、水は -x へ流れる。
// 船だけを大写しにすると航海に見えないので、空と水平線が入る距離まで引く。
// 少し上を見て、月と星のための空を画面に残す。
const CAM_POS: [number, number, number] = [-5.6, 2.4, 8.6];
const CAM_TARGET = new THREE.Vector3(0.8, 1.15, 0);
const CAM_FOV = 38;

// 月と目的地の島の位置。縦長画面での見え方を実機で合わせた値。
const MOON_POS: [number, number, number] = [5.1, 3.3, -5.5];
const ISLAND_POS: [number, number, number] = [6.5, 0, -5.5];

const SAND = "#EADEBD";
const SWELL_GEO = new THREE.PlaneGeometry(1.6, 0.05);
// うねりが流れる範囲。端まで行ったら反対側へ回して継ぎ目なく続ける。
const SWELL_SPAN = 34;
const SWELL_MIN_X = -17;

/// 後ろへ流れていく水の筋。船を世界の原点に置いたまま「進んでいる」ことを伝える
/// 主役なので、はっきり見える濃さで流す(薄すぎると船が止まって見える)。
/// 手前(カメラ寄り=zが大きい)を速く、奥を遅くして視差をつける。
/// 速さは「ゆっくり進む帆船」に合わせる。船体は約1.3単位なので、手前の筋が
/// 毎秒1.2単位 ≒ 船一隻ぶん/秒。これ以上速いとモーターボートに見える。
const SWELL_LAYERS = [
  { count: 14, zMin: -8, zSpread: 6, speed: 0.45, opacity: 0.1, len: 1.15 },
  { count: 12, zMin: 0.8, zSpread: 4.6, speed: 1.2, opacity: 0.22, len: 0.8 },
];

function PassingSwells({ animate }: { animate: boolean }) {
  const layers = useRef<(THREE.Group | null)[]>([]);
  // 毎フレーム乱数を引かない。決まった散らし方で並べる。
  const swells = useMemo(
    () =>
      SWELL_LAYERS.map((layer, li) =>
        Array.from({ length: layer.count }, (_, i) => ({
          x: SWELL_MIN_X + ((i * 2.4 + li * 1.3) % SWELL_SPAN),
          z: layer.zMin + ((i * 5) % 7) * (layer.zSpread / 7),
          scale: layer.len * (0.6 + ((i * 3) % 6) / 6),
          opacity: layer.opacity * (0.7 + ((i * 7) % 4) / 6),
        })),
      ),
    [],
  );

  useFrame((_, delta) => {
    if (!animate) return;
    SWELL_LAYERS.forEach((layer, li) => {
      const group = layers.current[li];
      if (!group) return;
      for (const child of group.children) {
        child.position.x -= delta * layer.speed;
        if (child.position.x < SWELL_MIN_X) child.position.x += SWELL_SPAN;
      }
    });
  });

  return (
    <>
      {swells.map((list, li) => (
        <group
          key={li}
          ref={(g) => {
            layers.current[li] = g;
          }}
        >
          {list.map((s, i) => (
            <mesh
              key={i}
              geometry={SWELL_GEO}
              position={[s.x, 0.035 + li * 0.004, s.z]}
              rotation={[-Math.PI / 2, 0, 0]}
              scale={[s.scale, 1, 1]}
            >
              <meshBasicMaterial
                color={SAND}
                transparent
                opacity={s.opacity}
                depthWrite={false}
              />
            </mesh>
          ))}
        </group>
      ))}
    </>
  );
}

/// 目的地の島。航海が続くほど、ゆっくり近づいてくる(進んでいる証)。
/// 距離は漸近的に縮めるので、追い越して背後へ抜けてしまうことはない。
const ISLAND_APPROACH = 1.2; // 開始時は最終距離の2.2倍だけ遠い
const ISLAND_TAU = 1500; // 25分でおよそ半分まで詰まる
function ApproachingIsland({ startedAt, animate }: { startedAt: number; animate: boolean }) {
  const group = useRef<THREE.Group>(null);

  const place = (g: THREE.Group) => {
    const elapsed = Math.max(0, (Date.now() - startedAt) / 1000);
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

/// 世界の中身。カメラは固定の斜め視点で、ごくわずかに揺れる。
function VoyagingSea({
  animate,
  showIsland,
  startedAt,
}: {
  animate: boolean;
  showIsland: boolean;
  startedAt: number;
}) {
  const parts = useMemo(() => boatProps(), []);
  const camera = useThree((s) => s.camera);

  useFrame((state) => {
    if (!animate) return;
    const time = state.clock.elapsedTime;
    // 酔わない振幅で、船に乗っている感じだけを添える。
    camera.position.x = CAM_POS[0] + Math.sin(time * 0.22) * 0.08;
    camera.position.y = CAM_POS[1] + Math.sin(time * 0.35 + 1.0) * 0.05;
    camera.lookAt(CAM_TARGET);
  });

  return (
    <>
      <color attach="background" args={[NIGHT_BG]} />
      <fog attach="fog" args={[NIGHT_BG, 12, 34]} />
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
      {/* 月。縦長の画面は左右の視野が狭いので、置く場所と大きさを分けて決める:
          位置はgroupで、見かけの大きさはscaleで(近くに置くと巨大になり時計に被る)。 */}
      <group position={MOON_POS} scale={0.4}>
        <Moon position={[0, 0, 0]} />
      </group>
      {/* 水面の月光の筋は月の真下に立てる。 */}
      <Sea moonX={MOON_POS[0]} animate={animate} />
      <Horizon />
      <PassingSwells animate={animate} />
      {/* 目的地があるなら、その島を遠くの前方に置く。何へ向かっているかが見える。 */}
      {showIsland && <ApproachingIsland startedAt={startedAt} animate={animate} />}
      {/* 自分の船。配置は VoyageScene と同値(甲板の航海士も同じ位置・姿)。
          同心円の波紋(Ripples)は「その場で揺れている」に見えるので、走っている
          この画面では使わない。後ろへ引く航跡と、流れる水の筋で進みを見せる。 */}
      <group position={[0, 0, 0]} rotation={[0, 0.1, 0]} scale={0.55}>
        <Wake animate={animate} />
        <BoatModel parts={parts} animate={animate} />
        <group position={[0.88, 0.57, 0.22]} scale={0.62}>
          <PhoenixModel animate={animate} pose={navigatorPose()} />
        </group>
      </group>
    </>
  );
}

export interface VoyagingWorldProps {
  itemName: string;
  startedAt: number;
  mode: TimerMode;
  /// 目的地が設定されているか。遠くに島を出すかどうかだけに使う。
  hasDestination: boolean;
  /// 記録の書き込み中。二重に押させない。
  saving?: boolean;
  onFinish: (note: string) => void;
  onDiscard: () => void;
  /// 世界を閉じるだけ(計測は続く)。
  onMinimize: () => void;
  onToggleMode: () => void;
  /// 手で分数を入れる従来の記録へ逃げる(計測を始め忘れたとき用)。
  onManual: () => void;
}

export default function VoyagingWorld({
  itemName,
  startedAt,
  mode,
  hasDestination,
  saving = false,
  onFinish,
  onDiscard,
  onMinimize,
  onToggleMode,
  onManual,
}: VoyagingWorldProps) {
  const [animate] = useState(
    () => !window.matchMedia("(prefers-reduced-motion: reduce)").matches,
  );
  const [note, setNote] = useState("");
  const [sound, setSound] = useState<SoundMode>(() => soundPref());
  const [now, setNow] = useState(() => Date.now());
  // 海をタップすると、UIを消して世界だけにする(もう一度タップで戻る)。
  const [uiHidden, setUiHidden] = useState(false);

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);

  const sec = elapsedSec({ itemId: "", startedAt, mode }, now);
  const phase = mode === "pomo" ? pomoPhase(sec) : null;
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
    document.title = `${display} · ${itemName} · Landfall`;
    return () => {
      document.title = "Landfall — Study Log";
    };
  }, [display, itemName]);

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

  // Escは「閉じるだけ」(計測は続ける)。取り消しと混同させない。
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onMinimize();
    };
    window.addEventListener("keydown", onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = prev;
    };
  }, [onMinimize]);

  return (
    <div className="voyaging-world" role="dialog" aria-modal="true">
      <Canvas
        dpr={[1, 2]}
        camera={{ position: CAM_POS, fov: CAM_FOV }}
        onPointerMissed={() => setUiHidden((v) => !v)}
      >
        <VoyagingSea
          animate={animate}
          showIsland={hasDestination}
          startedAt={startedAt}
        />
      </Canvas>

      <div className={`voyaging-ui${uiHidden ? " hidden" : ""}`}>
        <div className="voyaging-top">
          <div className="voyaging-heading">
            <p className="voyaging-item">{itemName}</p>
            <p className="voyaging-clock">{display}</p>
            <p className="voyaging-phase">
              {phase
                ? phase.inFocus
                  ? t("focusLabel")
                  : t("breakLabel")
                : t("voyagingNow")}
            </p>
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
    </div>
  );
}
