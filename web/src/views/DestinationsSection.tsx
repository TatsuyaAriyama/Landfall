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
  deleteDestination,
  destinationProgress,
  saveDestination,
  type Destination,
  type DestinationProgress,
} from "../destinations";
import type { UserData } from "../data";
import { boatProps } from "../boat";
import { BoatSvg, CoastSvg } from "../symbols";
import { Modal, askConfirm, showToast } from "../overlays";
import {
  remainingDaysLabel,
  remainingHoursLabel,
  t,
  tf,
} from "../i18n";

// 目的地(島)。海図カードの上を、記録するたび船が島へ近づいていく。
// 1件目は3Dの航海シーン(自分の船が夜の海を島へ走る)、2件目以降は2Dカード。
// 3Dカードはタップするとその世界へズームインし、世界の中で編集できる
// (VoyageWorld)。2Dカードと新規作成は従来のダイアログのまま。
// 到達したら「着岸。」の一枚(夜の入港と同じ世界)で祝う。

// three.js を含む航海シーンは重いので、表示するときだけ読み込む。
const VoyageScene = lazy(() => import("../three/VoyageScene"));

// 世界(VoyageWorld)のチャンクは、読み込み完了を覚えておく。
// 読み込みが済むまでカードのタップは従来のダイアログへ流し、
// 「編集中にチャンクが届いて世界へ差し替わり、入力が消える」事故を防ぐ。
let voyageWorldReady = false;
let voyageWorldPromise: Promise<typeof import("../three/VoyageWorld")> | null = null;
function loadVoyageWorld() {
  voyageWorldPromise ??= import("../three/VoyageWorld").then((m) => {
    voyageWorldReady = true;
    return m;
  });
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

/// 3Dの描画に失敗したら、白画面にせず2Dカードへ静かに戻る。
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
  const [editing, setEditing] = useState<Destination | null>(null);
  const [world, setWorld] = useState<Destination | null>(null);
  const [creating, setCreating] = useState(false);
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

  return (
    <>
      <p className="section-label">{t("destinations")}</p>
      <div className="dest-stack">
        {active.length === 0 ? (
          // 初めての人・未設定の人にも、まず同じ夜の海が見えている。
          // 押すと目的地の設定へ(「追加」ボタンは置かない)。
          <EmptySeaCard onClick={() => setCreating(true)} />
        ) : (
          active.map((dest, index) =>
            index === 0 && canUseWebGL() ? (
              <VoyageCard
                key={dest.id}
                dest={dest}
                data={data}
                onClick={() => {
                  // 世界のチャンクが未着ならこの回は従来のダイアログで開く
                  // (Suspenseフォールバックからの差し替えで入力が消えるのを防ぐ)。
                  if (voyageWorldReady) setWorld(dest);
                  else setEditing(dest);
                }}
              />
            ) : (
              <DestinationCard
                key={dest.id}
                dest={dest}
                data={data}
                onClick={() => setEditing(dest)}
              />
            ),
          )
        )}
      </div>

      {(creating || editing) && (
        <DestinationDialog
          uid={uid}
          dest={editing}
          data={data}
          onClose={() => {
            setCreating(false);
            setEditing(null);
          }}
        />
      )}
      {/* 3Dカードから入る没入エディタ。
          読込中は夜の海色の静かな幕(旧ダイアログを一瞬でも見せない)。
          描画失敗時のみ従来のダイアログへ(編集手段を失わない)。 */}
      {world && (
        <VoyageErrorBoundary
          fallback={
            <DestinationDialog
              uid={uid}
              dest={world}
              data={data}
              onClose={() => setWorld(null)}
            />
          }
        >
          <Suspense fallback={<div className="voyage-world-loading" />}>
            <VoyageWorld dest={world} data={data} uid={uid} onClose={() => setWorld(null)} />
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

/// 1件目の目的地の3D航海シーン。読込中と描画失敗時は2Dカードのまま。
function VoyageCard({
  dest,
  data,
  onClick,
}: {
  dest: Destination;
  data: UserData;
  onClick: () => void;
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
      fallback={<DestinationCard dest={dest} data={data} onClick={onClick} />}
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
        <VoyageScene name={name} ratio={progress.ratio} label={label} onClick={onClick} />
      </Suspense>
    </VoyageErrorBoundary>
  );
}

/// 海図カード。夜の海に水平線、右端に島、進捗の位置に船。
function DestinationCard({
  dest,
  data,
  onClick,
}: {
  dest: Destination;
  data: UserData;
  onClick: () => void;
}) {
  const progress = destinationProgress(dest, data.sessions);
  const label = remainingLabel(progress);
  const item = dest.itemUUID ? data.items.find((i) => i.id === dest.itemUUID) : undefined;

  return (
    <button className="dest-card" onClick={onClick}>
      <span className="dest-star" style={{ top: "18%", left: "12%" }} />
      <span className="dest-star" style={{ top: "30%", left: "38%" }} />
      <span className="dest-star" style={{ top: "14%", left: "60%" }} />
      <div className="dest-head">
        <span className="dest-name">
          {dest.name}
          {item && <span className="dest-item"> · {item.name}</span>}
        </span>
        <span className="dest-remaining">{label}</span>
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
    </button>
  );
}

/// 目的地の作成・編集。名前、対象の項目、目標(累計時間 or 期日)。
function DestinationDialog({
  uid,
  dest,
  data,
  onClose,
}: {
  uid: string;
  dest: Destination | null;
  data: UserData;
  onClose: () => void;
}) {
  const [name, setName] = useState(dest?.name ?? "");
  const [itemUUID, setItemUUID] = useState<string | undefined>(dest?.itemUUID);
  const [kind, setKind] = useState<"hours" | "date">(
    dest?.targetDate && !dest?.targetMinutes ? "date" : "hours",
  );
  const [hours, setHours] = useState(
    dest?.targetMinutes ? String(Math.round(dest.targetMinutes / 60)) : "20",
  );
  const [dateStr, setDateStr] = useState(
    dest?.targetDate ? dest.targetDate.toISOString().slice(0, 10) : "",
  );
  const [working, setWorking] = useState(false);

  const trimmed = name.replace(/^[\s　]+|[\s　]+$/g, "");
  const hoursNum = Number(hours);
  const valid =
    trimmed.length > 0 &&
    (kind === "hours" ? hoursNum > 0 && hoursNum <= 10000 : dateStr.length === 10);

  const save = async () => {
    if (!valid || working) return;
    setWorking(true);
    await saveDestination(uid, {
      id: dest?.id,
      name: trimmed,
      itemUUID,
      targetMinutes: kind === "hours" ? Math.round(hoursNum * 60) : undefined,
      targetDate: kind === "date" ? new Date(`${dateStr}T00:00:00`) : undefined,
      createdAt: dest?.createdAt,
    });
    showToast(t("savedToast"));
    onClose();
  };

  const remove = async () => {
    if (!dest || working) return;
    const ok = await askConfirm({
      title: t("deleteDestination"),
      message: t("deleteDestinationConfirm"),
      confirmLabel: t("delete"),
      danger: true,
    });
    if (!ok) return;
    setWorking(true);
    await deleteDestination(uid, dest.id);
    onClose();
  };

  return (
    <Modal onClose={onClose}>
      <>
        <h2 className="dialog-title">{t("destinationTitle")}</h2>

        <p className="section-label">{t("islandName")}</p>
        <input
          className="field"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder={t("islandNamePlaceholder")}
          maxLength={60}
          autoFocus={!dest}
        />

        <p className="section-label">{t("countsToward")}</p>
        <div className="chip-row">
          <button
            className={`chip${itemUUID === undefined ? " selected" : ""}`}
            onClick={() => setItemUUID(undefined)}
          >
            {t("allItems")}
          </button>
          {data.items.map((item) => (
            <button
              key={item.id}
              className={`chip${itemUUID === item.id ? " selected" : ""}`}
              onClick={() => setItemUUID(item.id)}
            >
              {item.name}
            </button>
          ))}
        </div>

        <p className="section-label">{t("goalKind")}</p>
        <div className="chip-row">
          <button
            className={`chip${kind === "hours" ? " selected" : ""}`}
            onClick={() => setKind("hours")}
          >
            {t("goalHours")}
          </button>
          <button
            className={`chip${kind === "date" ? " selected" : ""}`}
            onClick={() => setKind("date")}
          >
            {t("goalDate")}
          </button>
        </div>

        <div style={{ marginTop: 16 }}>
          {kind === "hours" ? (
            <div className="stepper-row" style={{ justifyContent: "flex-start" }}>
              <span className="stepper-value">
                <input
                  className="stepper-input"
                  type="text"
                  inputMode="numeric"
                  value={hours}
                  onChange={(e) => setHours(e.target.value.replace(/[^0-9]/g, ""))}
                  aria-label={t("goalHours")}
                />
                <span className="stepper-unit">{t("hoursUnit")}</span>
              </span>
            </div>
          ) : (
            <input
              className="field"
              type="date"
              value={dateStr}
              min={new Date().toISOString().slice(0, 10)}
              onChange={(e) => setDateStr(e.target.value)}
            />
          )}
        </div>

        <div style={{ height: 28 }} />
        <button className="primary-button" onClick={save} disabled={!valid || working}>
          {t("save")}
        </button>
        {dest && (
          <button className="danger-button" onClick={remove} disabled={working}>
            {t("deleteDestination")}
          </button>
        )}
      </>
    </Modal>
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
