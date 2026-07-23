import { useEffect, useMemo, useRef, useState } from "react";
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

const MINUTE_PRESETS = [15, 30, 45, 60, 90];

// 前回記録した分数。次の記録ダイアログの初期値にする(いつも同じ長さの人の一手間を省く)。
const LAST_MINUTES_KEY = "record.lastMinutes";

function lastUsedMinutes(): number | null {
  const n = Number(localStorage.getItem(LAST_MINUTES_KEY) ?? 0);
  return Number.isFinite(n) && n >= 1 && n <= 6000 ? n : null;
}

// タイマー(iOS の FloatingTimerChip 相当)。再読込しても続くよう localStorage に控える。
const TIMER_ITEM_KEY = "timer.itemId";
const TIMER_START_KEY = "timer.startedAt";
const TIMER_MODE_KEY = "timer.mode";

type TimerMode = "free" | "pomo";

// ポモドーロ: 25分の集中+5分の休憩を繰り返す。数えるのは集中の分だけ。
const POMO_WORK = 25 * 60;
const POMO_CYCLE = 30 * 60;

interface RunningTimer {
  itemId: string;
  startedAt: number; // epoch ms
  mode: TimerMode;
}

function readTimer(): RunningTimer | null {
  const itemId = localStorage.getItem(TIMER_ITEM_KEY);
  const startedAt = Number(localStorage.getItem(TIMER_START_KEY) ?? 0);
  const mode: TimerMode = localStorage.getItem(TIMER_MODE_KEY) === "pomo" ? "pomo" : "free";
  return itemId && startedAt > 0 ? { itemId, startedAt, mode } : null;
}

/// ポモドーロで実際に集中していた秒数。
function pomoWorkedSec(elapsedSec: number): number {
  const cycles = Math.floor(elapsedSec / POMO_CYCLE);
  return cycles * POMO_WORK + Math.min(elapsedSec % POMO_CYCLE, POMO_WORK);
}

export function TodayView({ uid, data }: { uid: string; data: UserData }) {
  const [recording, setRecording] = useState<StudyItem | null>(null);
  const [prefillMinutes, setPrefillMinutes] = useState<number | null>(null);
  const [editing, setEditing] = useState<StudyItem | null>(null);
  const [creating, setCreating] = useState(false);
  const [timer, setTimer] = useState<RunningTimer | null>(() => readTimer());
  const [now, setNow] = useState(Date.now());
  // タイルのドラッグ並び替え。ドロップした瞬間に sortOrder を書き直して反映する。
  const [dragId, setDragId] = useState<string | null>(null);
  const [overId, setOverId] = useState<string | null>(null);

  const dropOn = async (targetId: string) => {
    const from = dragId;
    setDragId(null);
    setOverId(null);
    if (!from || from === targetId) return;
    const ids = data.items.map((i) => i.id);
    const fromIdx = ids.indexOf(from);
    const toIdx = ids.indexOf(targetId);
    if (fromIdx < 0 || toIdx < 0) return;
    ids.splice(toIdx, 0, ...ids.splice(fromIdx, 1));
    await Promise.all(
      ids.map((id, idx) => {
        const item = data.items.find((i) => i.id === id);
        if (!item || item.sortOrder === idx) return Promise.resolve();
        return saveItem(uid, { ...item, id, sortOrder: idx });
      }),
    );
  };

  useEffect(() => {
    if (!timer) return;
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [timer]);

  const startTimer = (item: StudyItem, mode: TimerMode) => {
    const t: RunningTimer = { itemId: item.id, startedAt: Date.now(), mode };
    localStorage.setItem(TIMER_ITEM_KEY, t.itemId);
    localStorage.setItem(TIMER_START_KEY, String(t.startedAt));
    localStorage.setItem(TIMER_MODE_KEY, mode);
    setTimer(t);
    setRecording(null);
  };

  const clearTimer = () => {
    localStorage.removeItem(TIMER_ITEM_KEY);
    localStorage.removeItem(TIMER_START_KEY);
    localStorage.removeItem(TIMER_MODE_KEY);
    setTimer(null);
  };

  const finishTimer = () => {
    if (!timer) return;
    const item = data.items.find((i) => i.id === timer.itemId);
    const elapsedSec = Math.floor((Date.now() - timer.startedAt) / 1000);
    const workedSec = timer.mode === "pomo" ? pomoWorkedSec(elapsedSec) : elapsedSec;
    const minutes = Math.max(1, Math.round(workedSec / 60));
    clearTimer();
    if (item) {
      setPrefillMinutes(Math.min(minutes, 6000));
      setRecording(item);
    }
  };

  const todayId = dayId(new Date());
  // 時刻順(古→新)に揃える。同期の届き順に依存させない。
  const todaySessions = useMemo(
    () =>
      data.sessions
        .filter((s) => dayId(s.date) === todayId)
        .sort((a, b) => a.date.getTime() - b.date.getTime()),
    [data.sessions, todayId],
  );
  const itemById = useMemo(
    () => new Map(data.items.map((i) => [i.id, i])),
    [data.items],
  );
  // 今日の合計と項目ごとの分。見出しとタイルの小さなバッジに使う。
  const todayTotal = useMemo(
    () => todaySessions.reduce((sum, s) => sum + s.minutes, 0),
    [todaySessions],
  );
  const todayByItem = useMemo(() => {
    const map = new Map<string, number>();
    for (const s of todaySessions) {
      if (s.itemUUID) map.set(s.itemUUID, (map.get(s.itemUUID) ?? 0) + s.minutes);
    }
    return map;
  }, [todaySessions]);

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
        {data.items.map((item) => {
          const style = STYLE_COLORS[normalizeStyle(item.styleToken)];
          const dragClass =
            item.id === dragId ? " dragging" : item.id === overId ? " drag-over" : "";
          const timing = timer?.itemId === item.id;
          const todayMin = todayByItem.get(item.id) ?? 0;
          return (
            <button
              key={item.id}
              className={`tile${dragClass}${timing ? " timing" : ""}`}
              onClick={() => setRecording(item)}
              draggable
              onDragStart={(e) => {
                e.dataTransfer.effectAllowed = "move";
                setDragId(item.id);
              }}
              onDragOver={(e) => {
                e.preventDefault();
                if (overId !== item.id) setOverId(item.id);
              }}
              onDrop={(e) => {
                e.preventDefault();
                void dropOn(item.id);
              }}
              onDragEnd={() => {
                setDragId(null);
                setOverId(null);
              }}
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
                {todayMin > 0 && (
                  <span className="tile-today">{durationLabel(todayMin)}</span>
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

      {/* 計測中のフローティングチップ */}
      {timer && (
        <TimerChip
          item={data.items.find((i) => i.id === timer.itemId)}
          startedAt={timer.startedAt}
          mode={timer.mode}
          now={now}
          onFinish={finishTimer}
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
          onStartTimer={
            prefillMinutes === null ? (mode) => startTimer(recording, mode) : undefined
          }
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
      <span className="row-minutes">
        {session.minutes}
        {t("minutesUnit")}
      </span>
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
  startedAt,
  mode,
  now,
  onFinish,
  onDiscard,
}: {
  item?: StudyItem;
  startedAt: number;
  mode: TimerMode;
  now: number;
  onFinish: () => void;
  onDiscard: () => void;
}) {
  const [sound, setSound] = useState<SoundMode>(() => soundPref());
  const elapsed = Math.max(0, Math.floor((now - startedAt) / 1000));

  let display: string;
  let phaseLabel = "";
  let phaseKey = "";
  if (mode === "pomo") {
    const rem = elapsed % POMO_CYCLE;
    const inFocus = rem < POMO_WORK;
    const left = inFocus ? POMO_WORK - rem : POMO_CYCLE - rem;
    phaseLabel = inFocus ? t("focusLabel") : t("breakLabel");
    phaseKey = `${Math.floor(elapsed / POMO_CYCLE)}-${inFocus ? "f" : "b"}`;
    display = `${String(Math.floor(left / 60)).padStart(2, "0")}:${String(left % 60).padStart(2, "0")}`;
  } else {
    display = `${String(Math.floor(elapsed / 60)).padStart(2, "0")}:${String(elapsed % 60).padStart(2, "0")}`;
  }

  // 区切り(集中⇄休憩)の合図。開始直後には鳴らさない。
  const prevPhase = useRef(phaseKey);
  useEffect(() => {
    if (mode === "pomo" && prevPhase.current !== phaseKey) {
      prevPhase.current = phaseKey;
      playChime();
    }
  }, [mode, phaseKey]);

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
    <div className="timer-chip">
      <span className="timer-name">
        {phaseLabel && <span className="timer-phase">{phaseLabel} </span>}
        {item?.name ?? "—"}
      </span>
      <span className="timer-elapsed">{display}</span>
      <button className="timer-sound" onClick={cycleSound}>
        {soundLabel}
      </button>
      <button className="timer-finish" onClick={onFinish}>
        {t("timerFinish")}
      </button>
      <button className="timer-discard" onClick={onDiscard} aria-label="discard">
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
  onStartTimer,
  onClose,
}: {
  uid: string;
  item: StudyItem;
  data: UserData;
  initialMinutes?: number | null;
  onStartTimer?: (mode: TimerMode) => void;
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
        <div className="chip-row" style={{ justifyContent: "center", marginTop: 14 }}>
          {MINUTE_PRESETS.map((m) => (
            <button
              key={m}
              className={`chip${minutes === m ? " selected" : ""}`}
              onClick={() => setMinutes(m)}
            >
              {m}
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
        {onStartTimer && (
          <>
            <button className="timer-start-outline" onClick={() => onStartTimer("free")}>
              {t("startTimer")}
            </button>
            <button className="timer-start-outline" onClick={() => onStartTimer("pomo")}>
              {t("startPomodoro")}
            </button>
          </>
        )}
      </>
    </Modal>
  );
}
