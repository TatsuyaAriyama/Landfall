import {
  Component,
  lazy,
  Suspense,
  useEffect,
  useMemo,
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
import { askConfirm, showToast } from "../overlays";
import { canUseWebGL } from "../webgl";
import {
  deadlineRemainingLabel,
  durationLabel,
  remainingDaysLabel,
  remainingHoursLabel,
  shortDateLabel,
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

/// 着岸の一幕。到達した瞬間だけ開くので、ここも表示するときに読み込む。
const LandfallWorld = lazy(() => import("../three/LandfallWorld"));

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
  if (progress.remainingMinutes !== undefined) {
    return remainingHoursLabel(progress.remainingMinutes);
  }
  // 期日目標。締切当日は日ではなく時間・分で残りを言う。
  if (progress.remainingMs !== undefined) return deadlineRemainingLabel(progress.remainingMs);
  if (progress.remainingDays !== undefined) return remainingDaysLabel(progress.remainingDays);
  return "";
}

/// カードの右上に出す一言。ステップ目標なら「次: 〈次のステップ〉」を、
/// なければ従来の残り表示を返す(近い目標を提示して手を動かしやすくする)。
function destSubLabel(dest: Destination, progress: DestinationProgress): string {
  // 着いたら残り(「あと0分」)ではなく、着いたことを言う。
  if (progress.reached) return t("landReady");
  if (progress.stepsTotal !== undefined) {
    const next = dest.steps?.find((s) => !s.doneAt);
    return next
      ? tf(t("nextStepLabel"), { name: next.name })
      : tf(t("stepsCount"), { done: progress.stepsDone ?? 0, total: progress.stepsTotal });
  }
  return remainingLabel(progress);
}

/// 直近に辿り着いた小島(達成日が最も新しいステップ)。「いつその小さな目標を
/// 達成したか」をカードに小さく添えるために使う。iOS の latestDoneStep と同じ。
function latestDoneStep(dest: Destination): { name: string; doneAt: Date } | null {
  let latest: { name: string; doneAt: Date } | null = null;
  for (const s of dest.steps ?? []) {
    if (!s.doneAt) continue;
    if (!latest || s.doneAt > latest.doneAt) latest = { name: s.name, doneAt: s.doneAt };
  }
  return latest;
}

export function DestinationsSection({ uid, data }: { uid: string; data: UserData }) {
  // world: 開いている世界。dest=null は「新規作成」を世界の中で行う。
  const [world, setWorld] = useState<{ dest: Destination | null } | null>(null);
  const [celebrating, setCelebrating] = useState<Destination | null>(null);
  // 二重に押させない。保存の往復のあいだにもう一度押されると、着岸が二回走る。
  const landingRef = useRef<Set<string>>(new Set());

  // 毎描画で新しい配列を作ると、下の到達検知 effect が毎描画で走り、
  // 正しさが celebratedRef だけに依存してしまう。中身が変わったときだけ作り直す。
  const active = useMemo(
    () => data.destinations.filter((d) => !d.achievedAt),
    [data.destinations],
  );

  // 上陸は本人が決める。条件を満たしても自動では祝わない。
  //
  // 以前は達成を検知した瞬間に achievedAt を刻み、そのまま着岸の一幕を流していた。
  // だが期日目標の達成条件は「締切時刻を過ぎたこと」なので、何もしなくても
  // 時間が経てば着岸し、達成ではなく期限切れを祝うことになっていた。
  // 「辿り着いた」と決めるのは本人の仕事にする。
  const land = async (dest: Destination, early: boolean): Promise<boolean> => {
    if (early) {
      const ok = await askConfirm({
        title: t("landHere"),
        message: t("landHereConfirm"),
        confirmLabel: t("landHere"),
      });
      if (!ok) return false;
    }
    if (landingRef.current.has(dest.id)) return false;
    landingRef.current.add(dest.id);
    const achieved = { ...dest, achievedAt: new Date() };
    try {
      // 祝うのは書き込めたあと。先に一幕を流すと、保存に失敗したときに
      // 「着岸したのに記録が残っていない」状態を祝ってしまう。
      await saveDestination(uid, achieved);
    } catch {
      showToast(t("errGeneric"));
      return false;
    } finally {
      landingRef.current.delete(dest.id);
    }
    // 島の名前と航海した時間は保存の往復を待たずに手元の値で足りる。
    setCelebrating(achieved);
    return true;
  };

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
                paused={world !== null || celebrating !== null}
                dest={dest}
                data={data}
                onClick={() => setWorld({ dest })}
                onMarkDone={dest.manual ? () => void markDone(dest) : undefined}
                onLand={() => void land(dest, false)}
              />
            ) : (
              <DestinationCard
                key={dest.id}
                dest={dest}
                data={data}
                onClick={() => setWorld({ dest })}
                onMarkDone={dest.manual ? () => void markDone(dest) : undefined}
                onLand={() => void land(dest, false)}
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
              // まだ届いていなくても、本人の意思でこの航海を締められる。
              // 届いているときは出さない — カードに「上陸する」が既に出ているし、
              // 確認の文(まだ届いていない)がその場合は嘘になる。
              // 取り消したときは世界を閉じない(確認で戻ってきた人を放り出さない)。
              onLand={
                world.dest && !destinationProgress(world.dest, data.sessions).reached
                  ? async () => {
                      const target = world.dest!;
                      if (await land(target, true)) setWorld(null);
                    }
                  : undefined
              }
            />
          </Suspense>
        </VoyageErrorBoundary>
      )}
      {celebrating && (
        // 3Dが使えない端末では言葉だけを出す。演出は諦めても、
        // 到達したことは必ず伝える。
        <VoyageErrorBoundary
          fallback={
            <LandfallWords
              name={celebrating.name}
              minutes={destinationProgress(celebrating, data.sessions).minutes}
              onClose={() => setCelebrating(null)}
            />
          }
        >
          <Suspense fallback={null}>
            <LandfallWorld
              name={celebrating.name}
              minutes={destinationProgress(celebrating, data.sessions).minutes}
              onClose={() => setCelebrating(null)}
            />
          </Suspense>
        </VoyageErrorBoundary>
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

/// 上陸のボタン。島に着いた(条件を満たした)ときだけ、カードの下端に出す。
/// 丸い小さなチェックにはしない。ここは航海の締めなので、はっきり読める言葉で置く。
function LandButton({ onLand }: { onLand: () => void }) {
  return (
    <button
      className="dest-land"
      onClick={(e) => {
        e.stopPropagation();
        onLand();
      }}
    >
      {t("landNow")}
    </button>
  );
}

/// 1件目の目的地の3D航海シーン。読込中と描画失敗時は2Dカードのまま。
function VoyageCard({
  paused,
  dest,
  data,
  onClick,
  onMarkDone,
  onLand,
}: {
  paused: boolean;
  dest: Destination;
  data: UserData;
  onClick: () => void;
  onMarkDone?: () => void;
  onLand: () => void;
}) {
  const progress = destinationProgress(dest, data.sessions);
  const item = dest.itemUUID ? data.items.find((i) => i.id === dest.itemUUID) : undefined;
  const name = item ? `${dest.name} · ${item.name}` : dest.name;
  const label = destSubLabel(dest, progress);
  const stepFlags = dest.steps?.map((s) => ({ done: Boolean(s.doneAt), doneAt: s.doneAt }));
  // 直近に辿り着いた小島と、その日付(カードの下に小さなオレンジ文字で)。
  const latest = latestDoneStep(dest);
  // カードが見えている=世界に入る可能性があるので、チャンクを先読みしておく。
  useEffect(() => {
    void loadVoyageWorld();
  }, []);
  // WebGLのコンテキストが失われたら2Dカードへ落とす(真っ白のまま残さない)。
  const [glLost, setGlLost] = useState(false);
  if (glLost) {
    return (
      <DestinationCard
        dest={dest}
        data={data}
        onClick={onClick}
        onMarkDone={onMarkDone}
        onLand={onLand}
      />
    );
  }
  return (
    // 描画失敗時のみ2Dカードへ。読込中は3Dシーンと同じ器(夜の海色+見出し)を
    // 出しておき、2Dカードが一瞬挟まるチラつきをなくす。
    <VoyageErrorBoundary
      fallback={
        <DestinationCard
          dest={dest}
          data={data}
          onClick={onClick}
          onMarkDone={onMarkDone}
          onLand={onLand}
        />
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
        <VoyageScene
          name={name}
          ratio={progress.ratio}
          label={label}
          steps={stepFlags}
          onClick={onClick}
          footnote={
            latest ? `${latest.name} · ${shortDateLabel(latest.doneAt)}` : undefined
          }
          paused={paused}
          onContextLost={() => setGlLost(true)}
          action={progress.reached ? <LandButton onLand={onLand} /> : undefined}
        >
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
  onLand,
}: {
  dest: Destination;
  data: UserData;
  onClick: () => void;
  onMarkDone?: () => void;
  onLand: () => void;
}) {
  const progress = destinationProgress(dest, data.sessions);
  const label = destSubLabel(dest, progress);
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
      {progress.reached && <LandButton onLand={onLand} />}
      <div className="dest-horizon" />
      {/* ステップ目標: 航路の目印を小さな pips(●達成/○未達)で示す。 */}
      {dest.steps && dest.steps.length > 0 && (
        <div className="dest-steps" aria-hidden="true">
          {dest.steps.map((s) => (
            <span key={s.id} className={`dest-pip${s.doneAt ? " done" : ""}`} />
          ))}
        </div>
      )}
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

/// 3Dを描けないときの着岸。船も海も出さず、到達だけを伝える。
function LandfallWords({
  name,
  minutes,
  onClose,
}: {
  name: string;
  minutes: number;
  onClose: () => void;
}) {
  // 出た直後のタップでは閉じない(直前に押した指がそのまま当たる)。
  const readyAt = useRef(Date.now() + 700);
  return (
    <div
      className="landfall-overlay"
      onClick={() => {
        if (Date.now() < readyAt.current) return;
        onClose();
      }}
    >
      <div className="landfall-words">
        <div className="landfall-title">{t("landfallExcl")}</div>
        <p className="landfall-line">{tf(t("reachedIsland"), { name })}</p>
        {minutes > 0 && (
          <p className="landfall-time">
            {tf(t("landfallTime"), { time: durationLabel(minutes) })}
          </p>
        )}
        <p className="landfall-sub">{t("voyageStays")}</p>
        <button className="landfall-close" onClick={onClose}>
          {t("close")}
        </button>
      </div>
    </div>
  );
}
