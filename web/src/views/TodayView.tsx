import {
  Component,
  Suspense,
  lazy,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import {
  playChime,
  setSoundPref,
  soundPref,
  startSound,
  stopSound,
  type SoundMode,
} from "../audio";
import {
  STYLE_COLORS,
  dayId,
  normalizeStyle,
  normalizeSymbol,
  type StudyItem,
  type StudySession,
} from "../types";
import { deleteSession, recordSession, saveItem, type UserData } from "../data";
import { TileSymbolSvg } from "../symbols";
import { ItemEditor } from "./ItemEditor";
import { DestinationsSection } from "./DestinationsSection";
import { Modal, askConfirm, showToast } from "../overlays";
import { durationLabel, lang, t } from "../i18n";
import {
  clockLabel,
  creditedMinutes,
  elapsedSec,
  endBreak,
  eraseTimer,
  isOnBreak,
  pomoPhase,
  readTimer,
  startBreak,
  writeTimer,
  type RunningTimer,
  type TimerMode,
} from "../timer";
import { canUseWebGL } from "../webgl";
import { useDragReorder } from "../dragReorder";
import { useFloatingDrag } from "../floatingDrag";
import { whenIdle } from "../idle";

// 航海の世界は three.js を含んで重いので、初期描画と競合させない。
// 空き時間か、タイルへ指を置いた瞬間から読み込み、押した後の待ちを短くする。
let voyagingWorldPromise: Promise<typeof import("../three/VoyagingWorld")> | null = null;
function loadVoyagingWorld() {
  voyagingWorldPromise ??= import("../three/VoyagingWorld");
  return voyagingWorldPromise;
}
function preloadVoyagingWorld() {
  if (canUseWebGL()) void loadVoyagingWorld();
}
const VoyagingWorld = lazy(loadVoyagingWorld);

/// 3Dの描画に失敗しても計測は続けたい。世界だけ畳んでチップに戻す。
class VoyagingErrorBoundary extends Component<
  { onFail: () => void; children?: ReactNode },
  { failed: boolean }
> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  componentDidCatch() {
    this.props.onFail();
  }
  render() {
    return this.state.failed ? null : this.props.children;
  }
}

const MINUTE_PRESETS = [15, 30, 45, 60, 90];

// 前回記録した分数。次の記録ダイアログの初期値にする(いつも同じ長さの人の一手間を省く)。
const LAST_MINUTES_KEY = "record.lastMinutes";

function lastUsedMinutes(): number | null {
  const n = Number(localStorage.getItem(LAST_MINUTES_KEY) ?? 0);
  return Number.isFinite(n) && n >= 1 && n <= 6000 ? n : null;
}

// 計測の状態は timer.ts に集約(航海中の世界と共有する)。

export function TodayView({ uid, data }: { uid: string; data: UserData }) {
  const [recording, setRecording] = useState<StudyItem | null>(null);
  const [editing, setEditing] = useState<StudyItem | null>(null);
  const [creating, setCreating] = useState(false);
  const [timer, setTimer] = useState<RunningTimer | null>(() => readTimer());
  // 航海の世界を開いているか。閉じても計測は続く(チップから戻れる)。
  const [voyaging, setVoyaging] = useState(false);
  const [saving, setSaving] = useState(false);
  // 「時間を手で入れる」で開くときの初期値(測った分)。
  const [prefillMinutes, setPrefillMinutes] = useState<number | null>(null);

  // 読み込み済みの項目一覧から大元が消えたら、別端末からの削除を含めて
  // その項目を指す端末ローカルのタイマーも同時に畳む。
  useEffect(() => {
    if (!timer || data.items.some((item) => item.id === timer.itemId)) return;
    eraseTimer();
    setTimer(null);
    setVoyaging(false);
  }, [data.items, timer]);

  // 初期描画が終わって端末が空いたときだけ先読みする。Safariは idle API が
  // ないため idle.ts の短いタイマーへ落ちる。画面を離れたら予約も解除する。
  useEffect(() => {
    if (!canUseWebGL()) return;
    return whenIdle(preloadVoyagingWorld, { delay: 3000, timeout: 3500 });
  }, []);

  // 項目をタップしたら、その場で計測をはじめて航海の世界へ入る。
  // 分数を手で入れる画面は出さない(記録=航海そのもの)。
  const startTimer = (item: StudyItem, mode: TimerMode = "free") => {
    const next: RunningTimer = {
      itemId: item.id,
      startedAt: Date.now(),
      mode,
      breakMs: 0,
      breakStartedAt: null,
    };
    writeTimer(next);
    setTimer(next);
    setRecording(null);
    setVoyaging(true);
  };

  /// タイルを押したとき。同じ項目なら航海へ戻り、別の項目なら確認してから乗り換える
  /// (黙って始めると、走っていた航海の時間が消えてしまう)。
  const openOrStart = async (item: StudyItem) => {
    if (timer?.itemId === item.id) {
      setVoyaging(true);
      return;
    }
    if (timer) {
      const ok = await askConfirm({ title: t("switchVoyageConfirm"), danger: true });
      if (!ok) return;
    }
    startTimer(item);
  };

  const clearTimer = () => {
    eraseTimer();
    setTimer(null);
    setVoyaging(false);
  };

  /// 計測の途中で自由計測とポモドーロを切り替える。はじめた時刻は動かさない
  /// (ポモドーロにすると、この航海ぶん全体が集中/休憩の周期で数え直される)。
  const toggleMode = () => {
    if (!timer) return;
    const next: RunningTimer = { ...timer, mode: timer.mode === "pomo" ? "free" : "pomo" };
    writeTimer(next);
    setTimer(next);
  };

  /// 休憩に入る/おえる。時計はそのあいだ止まり、記録にも入らない。
  /// 休憩ぶんは切り替えた瞬間に引かれるので、いまの時刻も同時に取り直す
  /// (1秒ごとの now のままだと、再開の瞬間だけ時計が1秒巻き戻って見える)。
  const toggleBreak = () => {
    if (!timer) return;
    const at = Date.now();
    const next = isOnBreak(timer) ? endBreak(timer, at) : startBreak(timer, at);
    writeTimer(next);
    setTimer(next);
  };

  /// 航海を終えてそのまま記録する。ダイアログは挟まない。
  /// 書き込みが済んでから計測を捨てる(先に捨てると失敗時に時間が消える)。
  const finishTimer = async (note: string) => {
    if (!timer || saving) return;
    const item = data.items.find((i) => i.id === timer.itemId);
    if (!item) {
      clearTimer(); // 途中で項目が消えたときは静かに畳む
      return;
    }
    setSaving(true);
    try {
      const minutes = creditedMinutes(timer);
      await recordSession(uid, { item, minutes, note: note.trim() || undefined }, data);
      clearTimer();
      showToast(t("recordedToast"));
    } catch {
      // 失敗しても航海は続いている扱いにする。もう一度押せば記録できる。
      showToast(t("errGeneric"));
    } finally {
      setSaving(false);
    }
  };

  /// 計測を始め忘れたとき用。測った分を初期値にして、手で直せる画面へ。
  const switchToManual = () => {
    if (!timer) return;
    const item = data.items.find((i) => i.id === timer.itemId);
    const minutes = creditedMinutes(timer);
    clearTimer();
    if (item) {
      setPrefillMinutes(minutes);
      setRecording(item);
    }
  };

  const todayId = dayId(new Date());
  // 時刻順(新→古)に揃える。記録した直後のものが一番上に来るように
  // (同期の届き順には依存させない)。
  const todaySessions = useMemo(
    () =>
      data.sessions
        .filter((s) => dayId(s.date) === todayId)
        .sort((a, b) => b.date.getTime() - a.date.getTime()),
    [data.sessions, todayId],
  );
  const itemById = useMemo(
    () => new Map(data.items.map((i) => [i.id, i])),
    [data.items],
  );

  // タイルのドラッグ並び替え(マウスでも指でも動く。web/src/dragReorder.ts)。
  // 確定した並びを、そのまま sortOrder に振り直して保存する。
  const itemIds = useMemo(() => data.items.map((i) => i.id), [data.items]);
  const commitOrder = useCallback(
    async (ordered: string[]) =>
      void (await Promise.all(
        ordered.map((id, idx) => {
          const item = itemById.get(id);
          if (!item || item.sortOrder === idx) return Promise.resolve();
          return saveItem(uid, { ...item, id, sortOrder: idx });
        }),
      )),
    [itemById, uid],
  );
  const reorder = useDragReorder(itemIds, commitOrder);
  // 描画はドラッグ中の並びに従う(指を離すまで、手元で入れ替わって見える)。
  const orderedItems = useMemo(
    () => reorder.order.map((id) => itemById.get(id)).filter((i): i is StudyItem => !!i),
    [reorder.order, itemById],
  );
  // 今日の合計と項目ごとの分。見出しとタイルの小さなバッジに使う。
  const todayTotal = useMemo(
    () => todaySessions.reduce((sum, s) => sum + s.minutes, 0),
    [todaySessions],
  );
  // タイルには「今日」ではなく、その項目のこれまでの総作業時間を出す。
  const totalByItem = useMemo(() => {
    const map = new Map<string, number>();
    for (const s of data.sessions) {
      if (s.itemUUID) map.set(s.itemUUID, (map.get(s.itemUUID) ?? 0) + s.minutes);
    }
    return map;
  }, [data.sessions]);

  // 航海日誌のような日付。曜日は小さな見出し(帰帆の色)、日付はその下に。
  const today = new Date();
  const weekday = new Intl.DateTimeFormat(lang, { weekday: "long" }).format(today);
  const monthDay = new Intl.DateTimeFormat(lang, {
    month: "long",
    day: "numeric",
  }).format(today);

  return (
    <div>
      <header className="today-dateline">
        <span className="today-weekday">{weekday}</span>
        <h1 className="today-date">{monthDay}</h1>
      </header>

      <DestinationsSection uid={uid} data={data} />

      <p className="section-label">{t("items")}</p>
      {data.items.length === 0 && <p className="empty-note">{t("emptyToday")}</p>}
      <div className="tile-grid">
        {orderedItems.map((item) => {
          const style = STYLE_COLORS[normalizeStyle(item.styleToken)];
          const lifted = item.id === reorder.liftedId ? " lifted" : "";
          const timing = timer?.itemId === item.id;
          const totalMin = totalByItem.get(item.id) ?? 0;
          return (
            <button
              key={item.id}
              className={`tile${lifted}${timing ? " timing" : ""}`}
              onPointerEnter={preloadVoyagingWorld}
              onFocus={preloadVoyagingWorld}
              onTouchStart={preloadVoyagingWorld}
              onClick={() => void openOrStart(item)}
              {...reorder.tileProps(item.id)}
            >
              <div className="tile-art" style={{ background: style.bg }}>
                <TileSymbolSvg
                  symbol={normalizeSymbol(item.symbolToken)}
                  fg={style.fg}
                  bg={style.bg}
                />
              </div>
              <span className="tile-name">
                <span className="tile-name-text">{item.name}</span>
                {totalMin > 0 && (
                  <span className="tile-today">{durationLabel(totalMin)}</span>
                )}
              </span>
              <span
                className="tile-edit"
                style={{ background: style.bg, color: style.fg }}
                role="button"
                aria-label={t("editItem")}
                onClick={(e) => {
                  e.stopPropagation();
                  setEditing(item);
                }}
              >
                …
              </span>
            </button>
          );
        })}
        <button
          className="tile-add"
          onClick={() => setCreating(true)}
          aria-label={t("addItem")}
        >
          +
        </button>
      </div>

      {todaySessions.length > 0 && (
        <>
          <p className="section-label">
            {t("todaysLog")}
            {todayTotal > 0 && (
              <span className="section-label-sub"> · {durationLabel(todayTotal)}</span>
            )}
          </p>
          <div className="rows">
            {todaySessions.map((s) => (
              <SessionRow
                key={s.id}
                session={s}
                item={s.itemUUID ? itemById.get(s.itemUUID) : undefined}
                onDelete={async () => {
                  if (
                    await askConfirm({
                      title: t("deleteSessionConfirm"),
                      confirmLabel: t("delete"),
                      danger: true,
                    })
                  ) {
                    await deleteSession(uid, s, data);
                  }
                }}
              />
            ))}
          </div>
        </>
      )}

      {/* 航海中の世界。項目をタップした直後はこれが開く。 */}
      {timer && voyaging && canUseWebGL() && (
        <VoyagingErrorBoundary onFail={() => setVoyaging(false)}>
          <Suspense
            fallback={
              <div className="voyaging-world voyage-loading" role="status" aria-label={t("loading")}>
                <span />
              </div>
            }
          >
            <VoyagingWorld
              itemName={data.items.find((i) => i.id === timer.itemId)?.name ?? ""}
              timer={timer}
              hasDestination={data.destinations.some((d) => !d.achievedAt)}
              saving={saving}
              onFinish={(note) => void finishTimer(note)}
              onMinimize={() => setVoyaging(false)}
              onToggleMode={toggleMode}
              onManual={switchToManual}
              onToggleBreak={toggleBreak}
              onDiscard={async () => {
                if (await askConfirm({ title: t("timerDiscardConfirm"), danger: true })) {
                  clearTimer();
                }
              }}
            />
          </Suspense>
        </VoyagingErrorBoundary>
      )}

      {/* 世界を閉じているあいだのフローティングチップ。押すと航海に戻る。 */}
      {timer && !voyaging && (
        <TimerChip
          item={data.items.find((i) => i.id === timer.itemId)}
          timer={timer}
          onOpen={() => setVoyaging(true)}
          onToggleBreak={toggleBreak}
          onFinish={() => void finishTimer("")}
          onDiscard={async () => {
            if (
              await askConfirm({ title: t("timerDiscardConfirm"), danger: true })
            ) {
              clearTimer();
            }
          }}
        />
      )}

      {recording && (
        <RecordDialog
          uid={uid}
          item={recording}
          data={data}
          initialMinutes={prefillMinutes}
          onClose={() => {
            setRecording(null);
            setPrefillMinutes(null);
          }}
        />
      )}
      {(creating || editing) && (
        <ItemEditor
          uid={uid}
          item={editing}
          nextSortOrder={
            data.items.length === 0
              ? 0
              : Math.max(...data.items.map((i) => i.sortOrder)) + 1
          }
          data={data}
          onClose={() => {
            setCreating(false);
            setEditing(null);
          }}
        />
      )}
    </div>
  );
}

export function SessionRow({
  session,
  item,
  onDelete,
}: {
  session: StudySession;
  item?: StudyItem;
  onDelete?: () => void;
}) {
  const style = STYLE_COLORS[normalizeStyle(item?.styleToken ?? "midnight")];
  const time = `${String(session.date.getHours()).padStart(2, "0")}:${String(
    session.date.getMinutes(),
  ).padStart(2, "0")}`;
  return (
    <div className="row">
      {/* 項目のタイルと同じ絵柄(配色×シンボル)を小さく。色の点だけでは項目が判別できない。 */}
      <span className="row-tile" style={{ background: style.bg }}>
        <TileSymbolSvg
          symbol={normalizeSymbol(item?.symbolToken ?? "compass")}
          fg={style.fg}
          bg={style.bg}
        />
      </span>
      <div className="row-main">
        <div className="row-title">{item?.name ?? "—"}</div>
        <div className="row-sub">
          <span className="row-time">{time}</span>
          {session.note ? ` · ${session.note}` : ""}
        </div>
      </div>
      <span className="row-minutes">{durationLabel(session.minutes)}</span>
      {onDelete && (
        <button className="minus-button" onClick={onDelete} aria-label={t("delete")}>
          −
        </button>
      )}
    </div>
  );
}

/// 計測中の浮きチップ。項目名と時間、BGM切替、終了(記録へ)と取りやめ。
/// ポモドーロは「集中 24:59」のように残り時間を出し、区切りでやわらかい合図が鳴る。
function TimerChip({
  item,
  timer,
  onOpen,
  onToggleBreak,
  onFinish,
  onDiscard,
}: {
  item?: StudyItem;
  timer: RunningTimer;
  onOpen: () => void;
  onToggleBreak: () => void;
  onFinish: () => void;
  onDiscard: () => void;
}) {
  const floating = useFloatingDrag("landfall.timer-chip-position.v1");
  const [sound, setSound] = useState<SoundMode>(() => soundPref());
  // 1秒更新をチップの中だけに閉じ込める。親のTodayViewで持つと、時計の数字を
  // 変えるたびに目的地・全タイル・今日の記録まで再描画されてしまう。
  const [now, setNow] = useState(Date.now);
  // 休憩中は時計が止まる(elapsedSecが休憩ぶんを引く)。止まった数字だけでは
  // 事故に見えるので、局面の代わりに「錨を下ろしている」と出す。
  const resting = isOnBreak(timer);
  const elapsed = elapsedSec(timer, now);

  const phase = timer.mode === "pomo" && !resting ? pomoPhase(elapsed) : null;
  const phaseLabel = resting
    ? t("restingShort")
    : phase
      ? phase.inFocus
        ? t("focusLabel")
        : t("breakLabel")
      : "";
  const phaseKey = phase?.key ?? "";
  const display = clockLabel(phase ? phase.left : elapsed);

  useEffect(() => {
    setNow(Date.now());
    if (resting) return;
    const id = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, [resting]);

  // 区切り(集中⇄休憩)の合図。開始直後には鳴らさない。
  const prevPhase = useRef(phaseKey);
  useEffect(() => {
    if (timer.mode === "pomo" && prevPhase.current !== phaseKey) {
      prevPhase.current = phaseKey;
      playChime();
    }
  }, [timer.mode, phaseKey]);

  // 計測中はタブのタイトルにも時間を出す(別タブで作業していても進みが見える)。
  useEffect(() => {
    document.title = `${phaseLabel ? `${phaseLabel} ` : ""}${display} · Landfall`;
    return () => {
      document.title = "Landfall — Study Log";
    };
  }, [display, phaseLabel]);

  // BGM。チップが出ている間だけ流れる。
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

  return (
    <div
      ref={floating.elementRef}
      className={`timer-chip${floating.dragging ? " dragging" : ""}`}
      style={floating.style}
      {...floating.pointerProps}
    >
      {/* 名前と時間を押すと、航海の世界へ戻る。 */}
      <button
        className="timer-back"
        onClick={() => {
          if (!floating.consumeDraggedClick()) onOpen();
        }}
        aria-label={t("backToVoyage")}
      >
        <span className="timer-name">
          {phaseLabel && <span className="timer-phase">{phaseLabel} </span>}
          {item?.name ?? "—"}
        </span>
        <span className="timer-elapsed">{display}</span>
      </button>
      <button className="timer-sound" data-no-floating-drag onClick={cycleSound}>
        {soundLabel}
      </button>
      {/* 休憩。世界を閉じて実際に作業しているときこそ要る操作なので、
          世界の中だけでなくここにも置く。 */}
      <button
        className={`timer-break${resting ? " on" : ""}`}
        data-no-floating-drag
        onClick={onToggleBreak}
      >
        {resting ? t("endBreakShort") : t("takeBreakShort")}
      </button>
      <button className="timer-finish" data-no-floating-drag onClick={onFinish}>
        {t("timerFinish")}
      </button>
      <button
        className="timer-discard"
        data-no-floating-drag
        onClick={onDiscard}
        aria-label="discard"
      >
        ✕
      </button>
    </div>
  );
}

function RecordDialog({
  uid,
  item,
  data,
  initialMinutes,
  onClose,
}: {
  uid: string;
  item: StudyItem;
  data: UserData;
  initialMinutes?: number | null;
  onClose: () => void;
}) {
  const [minutes, setMinutes] = useState(() => initialMinutes ?? lastUsedMinutes() ?? 30);
  const [note, setNote] = useState("");
  const [working, setWorking] = useState(false);
  const style = STYLE_COLORS[normalizeStyle(item.styleToken)];

  const save = async () => {
    if (working || minutes <= 0) return;
    setWorking(true);
    const clamped = Math.min(minutes, 6000);
    localStorage.setItem(LAST_MINUTES_KEY, String(clamped));
    await recordSession(uid, { item, minutes: clamped, note }, data);
    showToast(t("recordedToast"));
    onClose();
  };

  return (
    <Modal onClose={onClose}>
      <>
        <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
          <div
            className="tile-art"
            style={{ background: style.bg, width: 52, aspectRatio: "1" }}
          >
            <TileSymbolSvg
              symbol={normalizeSymbol(item.symbolToken)}
              fg={style.fg}
              bg={style.bg}
            />
          </div>
          <h2 className="dialog-title">{item.name}</h2>
        </div>

        <p className="section-label">{t("minutesLabel")}</p>
        {/* 大きな数字を − / + で刻む(5分刻み)。数字は直接入力もできる。 */}
        <div className="stepper-row">
          <button
            className="minus-button stepper-button"
            onClick={() => setMinutes((m) => Math.max(5, Math.floor((m - 1) / 5) * 5))}
            aria-label="-5"
          >
            −
          </button>
          <span className="stepper-value">
            <input
              className="stepper-input"
              type="text"
              inputMode="numeric"
              value={minutes}
              // タップした瞬間に全選択して、そのまま新しい数を打ち込めるように。
              onFocus={(e) => e.target.select()}
              onChange={(e) => {
                const n = Number(e.target.value.replace(/[^0-9]/g, ""));
                setMinutes(Number.isFinite(n) ? Math.min(n, 6000) : 0);
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.nativeEvent.isComposing) void save();
              }}
              aria-label={t("minutesLabel")}
            />
            <span className="stepper-unit">{t("minutesUnit")}</span>
          </span>
          <button
            className="minus-button stepper-button"
            onClick={() => setMinutes((m) => Math.min(6000, Math.floor(m / 5) * 5 + 5))}
            aria-label="+5"
          >
            +
          </button>
        </div>
        {/* 分だけだと1時間を超えたときに読み取れない(90と出ても1時間30分だと
            すぐ分からない)。打ち込みは分のままが速いので、読み方だけ添える。 */}
        {minutes >= 60 && <p className="stepper-reading">{durationLabel(minutes)}</p>}
        <div className="chip-row" style={{ justifyContent: "center", marginTop: 14 }}>
          {MINUTE_PRESETS.map((m) => (
            <button
              key={m}
              className={`chip${minutes === m ? " selected" : ""}`}
              onClick={() => setMinutes(m)}
            >
              {durationLabel(m)}
            </button>
          ))}
        </div>

        <p className="section-label">{t("noteOptional")}</p>
        <input
          className="field"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          maxLength={120}
          placeholder={t("noteOptional")}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.nativeEvent.isComposing) void save();
          }}
        />

        <div style={{ height: 28 }} />
        <button className="primary-button" onClick={save} disabled={working || minutes <= 0}>
          {t("record")}
        </button>
      </>
    </Modal>
  );
}
