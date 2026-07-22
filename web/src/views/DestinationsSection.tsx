import {
  Component,
  lazy,
  Suspense,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import {
  destinationProgress,
  markDestinationDone,
  saveDestination,
  type Destination,
  type DestinationProgress,
} from "../destinations";
import type { UserData } from "../data";
import { boatProps } from "../boat";
import { BoatSvg, CoastSvg } from "../symbols";
import { askConfirm } from "../overlays";
import {
  remainingDaysLabel,
  remainingHoursLabel,
  t,
  tf,
} from "../i18n";

// 目的地(島)。海図カードの上を、記録するたび船が島へ近づいていく。
// 設定・変更はすべて「世界へズームインして中で行う」(VoyageWorld)に統一。
// 未設定でも同じ夜の海が見え、押すと世界に入ってそのまま設定できる。
// 到達したら「着岸。」の一枚(夜の入港と同じ世界)で祝う。

// three.js を含む航海シーンは重いので、表示するときだけ読み込む。
const VoyageScene = lazy(() => import("../three/VoyageScene"));

let voyageWorldPromise: Promise<typeof import("../three/VoyageWorld")> | null = null;
function loadVoyageWorld() {
  voyageWorldPromise ??= import("../three/VoyageWorld");
  return voyageWorldPromise;
}
const VoyageWorld = lazy(loadVoyageWorld);

/// WebGLが使えるか(一度だけ判定)。使えない環境では2Dカードのまま。
let webglCache: boolean | null = null;
function canUseWebGL(): boolean {
  if (webglCache !== null) return webglCache;
  try {
    const c = document.createElement("canvas");
    webglCache = Boolean(
      window.WebGLRenderingContext && (c.getContext("webgl2") || c.getContext("webgl")),
    );
  } catch {
    webglCache = false;
  }
  return webglCache;
}

/// 3Dの描画に失敗したら、白画面にせずフォールバックへ静かに戻る。
class VoyageErrorBoundary extends Component<
  { fallback: ReactNode; children?: ReactNode },
  { failed: boolean }
> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  render() {
    return this.state.failed ? this.props.fallback : this.props.children;
  }
}

/// 残り表示(「あと3時間20分」「あと12日」)。2D/3Dカードで共通。
function remainingLabel(progress: DestinationProgress): string {
  return progress.remainingMinutes !== undefined
    ? remainingHoursLabel(progress.remainingMinutes)
    : progress.remainingDays !== undefined
      ? remainingDaysLabel(progress.remainingDays)
      : "";
}

export function DestinationsSection({ uid, data }: { uid: string; data: UserData }) {
  // world: 開いている世界。dest=null は「新規作成」を世界の中で行う。
  const [world, setWorld] = useState<{ dest: Destination | null } | null>(null);
  const [celebrating, setCelebrating] = useState<Destination | null>(null);
  const celebratedRef = useRef<Set<string>>(new Set());

  const active = data.destinations.filter((d) => !d.achievedAt);

  // 到達の検知。達成した瞬間に achievedAt を刻み、着岸の一枚を出す。
  useEffect(() => {
    for (const dest of active) {
      const progress = destinationProgress(dest, data.sessions);
      if (progress.reached && !celebratedRef.current.has(dest.id)) {
        celebratedRef.current.add(dest.id);
        void saveDestination(uid, { ...dest, achievedAt: new Date() });
        setCelebrating(dest);
        break;
      }
    }
  }, [active, data.sessions, uid]);

  // 完了ゴールのその場チェック。世界を開かず、カード上で直接完了にする
  // (記録と同じくらい軽い操作にするため — 到達の検知は上のeffectがそのまま拾う)。
  const markDone = async (dest: Destination) => {
    const ok = await askConfirm({
      title: t("markDone"),
      message: t("markDoneConfirm"),
      confirmLabel: t("markDone"),
    });
    if (!ok) return;
    await markDestinationDone(uid, dest);
  };

  return (
    <>
      <p className="section-label">{t("destinations")}</p>
      <div className="dest-stack">
        {active.length === 0 ? (
          // 初めての人・未設定の人にも、まず同じ夜の海が見えている。
          // 押すと世界にズームインして、その中で目的地を設定する。
          <EmptySeaCard onClick={() => setWorld({ dest: null })} />
        ) : (
          active.map((dest, index) =>
            index === 0 && canUseWebGL() ? (
              <VoyageCard
                key={dest.id}
                dest={dest}
                data={data}
                onClick={() => setWorld({ dest })}
                onMarkDone={dest.manual ? () => void markDone(dest) : undefined}
              />
            ) : (
              <DestinationCard
                key={dest.id}
                dest={dest}
                data={data}
                onClick={() => setWorld({ dest })}
                onMarkDone={dest.manual ? () => void markDone(dest) : undefined}
              />
            ),
          )
        )}
      </div>

      {/* 没入エディタ(作成・変更とも同じ世界)。読込中は夜の海色の静かな幕。
          描画失敗時は幕をタップで閉じられる(旧ダイアログは廃止)。 */}
      {world && (
        <VoyageErrorBoundary
          fallback={
            <div className="voyage-world-loading" onClick={() => setWorld(null)} />
          }
        >
          <Suspense fallback={<div className="voyage-world-loading" />}>
            <VoyageWorld
              dest={world.dest}
              data={data}
              uid={uid}
              onClose={() => setWorld(null)}
            />
          </Suspense>
        </VoyageErrorBoundary>
      )}
      {celebrating && (
        <LandfallCelebration
          dest={celebrating}
          onClose={() => setCelebrating(null)}
        />
      )}
    </>
  );
}

/// 目的地が未設定でも、同じ夜の海が見えている。小さな一文でそっと促す。
function EmptySeaCard({ onClick }: { onClick: () => void }) {
  // 世界にすぐ入れるよう、海が見えた時点でチャンクを先読みしておく。
  useEffect(() => {
    void loadVoyageWorld();
  }, []);
  const fallback = (
    <button className="voyage-scene" onClick={onClick}>
      <div className="voyage-head">
        <span className="voyage-name">{t("setDestinationPrompt")}</span>
      </div>
    </button>
  );
  if (!canUseWebGL()) return fallback;
  return (
    <VoyageErrorBoundary fallback={fallback}>
      <Suspense fallback={fallback}>
        <VoyageScene
          name={t("setDestinationPrompt")}
          ratio={0.32}
          label=""
          onClick={onClick}
        />
      </Suspense>
    </VoyageErrorBoundary>
  );
}

/// 完了ゴールのその場チェック。カードの見出しに重ねる、丸い小さなボタン。
function CompleteCheckButton({ onMarkDone }: { onMarkDone: () => void }) {
  return (
    <button
      className="dest-complete"
      onClick={(e) => {
        e.stopPropagation();
        onMarkDone();
      }}
      aria-label={t("markDone")}
      title={t("markDone")}
    >
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" aria-hidden="true">
        <path
          d="M5 13l4 4L19 7"
          stroke="currentColor"
          strokeWidth="2.6"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    </button>
  );
}

/// 1件目の目的地の3D航海シーン。読込中と描画失敗時は2Dカードのまま。
function VoyageCard({
  dest,
  data,
  onClick,
  onMarkDone,
}: {
  dest: Destination;
  data: UserData;
  onClick: () => void;
  onMarkDone?: () => void;
}) {
  const progress = destinationProgress(dest, data.sessions);
  const item = dest.itemUUID ? data.items.find((i) => i.id === dest.itemUUID) : undefined;
  const name = item ? `${dest.name} · ${item.name}` : dest.name;
  const label = remainingLabel(progress);
  // カードが見えている=世界に入る可能性があるので、チャンクを先読みしておく。
  useEffect(() => {
    void loadVoyageWorld();
  }, []);
  return (
    // 描画失敗時のみ2Dカードへ。読込中は3Dシーンと同じ器(夜の海色+見出し)を
    // 出しておき、2Dカードが一瞬挟まるチラつきをなくす。
    <VoyageErrorBoundary
      fallback={
        <DestinationCard dest={dest} data={data} onClick={onClick} onMarkDone={onMarkDone} />
      }
    >
      <Suspense
        fallback={
          <button className="voyage-scene" onClick={onClick}>
            <div className="voyage-head">
              <span className="voyage-name">{name}</span>
              <span className="voyage-remaining">{label}</span>
            </div>
          </button>
        }
      >
        <VoyageScene name={name} ratio={progress.ratio} label={label} onClick={onClick}>
          {onMarkDone && <CompleteCheckButton onMarkDone={onMarkDone} />}
        </VoyageScene>
      </Suspense>
    </VoyageErrorBoundary>
  );
}

/// 海図カード。夜の海に水平線、右端に島、進捗の位置に船。
function DestinationCard({
  dest,
  data,
  onClick,
  onMarkDone,
}: {
  dest: Destination;
  data: UserData;
  onClick: () => void;
  onMarkDone?: () => void;
}) {
  const progress = destinationProgress(dest, data.sessions);
  const label = remainingLabel(progress);
  const item = dest.itemUUID ? data.items.find((i) => i.id === dest.itemUUID) : undefined;

  return (
    // 完了チェックの実ボタンをネストするため、カード自体はdiv+role="button"にする
    // (<button>の中に<button>は置けない)。キーボード操作は変わらず効く。
    <div
      className="dest-card"
      role="button"
      tabIndex={0}
      onClick={onClick}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onClick();
        }
      }}
    >
      <span className="dest-star" style={{ top: "18%", left: "12%" }} />
      <span className="dest-star" style={{ top: "30%", left: "38%" }} />
      <span className="dest-star" style={{ top: "14%", left: "60%" }} />
      <div className="dest-head">
        <span className="dest-name">
          {dest.name}
          {item && <span className="dest-item"> · {item.name}</span>}
        </span>
        <span className="dest-remaining">{label}</span>
        {onMarkDone && <CompleteCheckButton onMarkDone={onMarkDone} />}
      </div>
      <div className="dest-horizon" />
      <div className="dest-coast">
        <CoastSvg />
      </div>
      <div
        className="dest-boat"
        style={{ left: `calc(5% + ${Math.round(progress.ratio * 100) * 0.72}%)` }}
      >
        <div className="boat-anim">
          <BoatSvg {...boatProps()} />
        </div>
      </div>
    </div>
  );
}

/// 着岸の一枚。夜の海を船が島まで走り、「着岸。」の言葉が浮かぶ。
function LandfallCelebration({
  dest,
  onClose,
}: {
  dest: Destination;
  onClose: () => void;
}) {
  return (
    <div className="landfall-overlay" onClick={onClose}>
      <span className="harbor-star" style={{ top: "14%", left: "16%", width: 4, height: 4 }} />
      <span className="harbor-star" style={{ top: "8%", left: "42%", width: 3, height: 3 }} />
      <span className="harbor-star" style={{ top: "18%", left: "70%", width: 4, height: 4 }} />
      <span className="harbor-star" style={{ top: "28%", left: "88%", width: 3, height: 3 }} />
      <span className="harbor-moon" style={{ top: "10%", right: "14%" }} />

      <div className="landfall-sea">
        <div className="landfall-horizon" />
        <div className="landfall-coast">
          <CoastSvg />
        </div>
        <div className="landfall-boat">
          <BoatSvg {...boatProps()} />
        </div>
      </div>

      <div className="landfall-words">
        <div className="landfall-title">{t("landfallExcl")}</div>
        <p className="landfall-line">{tf(t("reachedIsland"), { name: dest.name })}</p>
        <p className="landfall-sub">{t("voyageStays")}</p>
        <button className="landfall-close" onClick={onClose}>
          {t("close")}
        </button>
      </div>
    </div>
  );
}
