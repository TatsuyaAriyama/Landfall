import { useEffect, useMemo, useState } from "react";
import {
  STYLE_COLORS,
  dayId,
  normalizeStyle,
  normalizeSymbol,
  type StudyItem,
  type StudySession,
} from "../types";
import { deleteSession, recordSession, type UserData } from "../data";
import { TileSymbolSvg } from "../symbols";
import { ItemEditor } from "./ItemEditor";
import { Modal, askConfirm, showToast } from "../overlays";
import { lang, t } from "../i18n";

const MINUTE_PRESETS = [15, 30, 45, 60, 90];

// タイマー(iOS の FloatingTimerChip 相当)。再読込しても続くよう localStorage に控える。
const TIMER_ITEM_KEY = "timer.itemId";
const TIMER_START_KEY = "timer.startedAt";

interface RunningTimer {
  itemId: string;
  startedAt: number; // epoch ms
}

function readTimer(): RunningTimer | null {
  const itemId = localStorage.getItem(TIMER_ITEM_KEY);
  const startedAt = Number(localStorage.getItem(TIMER_START_KEY) ?? 0);
  return itemId && startedAt > 0 ? { itemId, startedAt } : null;
}

export function TodayView({ uid, data }: { uid: string; data: UserData }) {
  const [recording, setRecording] = useState<StudyItem | null>(null);
  const [prefillMinutes, setPrefillMinutes] = useState<number | null>(null);
  const [editing, setEditing] = useState<StudyItem | null>(null);
  const [creating, setCreating] = useState(false);
  const [timer, setTimer] = useState<RunningTimer | null>(() => readTimer());
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    if (!timer) return;
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [timer]);

  const startTimer = (item: StudyItem) => {
    const t: RunningTimer = { itemId: item.id, startedAt: Date.now() };
    localStorage.setItem(TIMER_ITEM_KEY, t.itemId);
    localStorage.setItem(TIMER_START_KEY, String(t.startedAt));
    setTimer(t);
    setRecording(null);
  };

  const clearTimer = () => {
    localStorage.removeItem(TIMER_ITEM_KEY);
    localStorage.removeItem(TIMER_START_KEY);
    setTimer(null);
  };

  const finishTimer = () => {
    if (!timer) return;
    const item = data.items.find((i) => i.id === timer.itemId);
    const minutes = Math.max(1, Math.round((Date.now() - timer.startedAt) / 60000));
    clearTimer();
    if (item) {
      setPrefillMinutes(Math.min(minutes, 6000));
      setRecording(item);
    }
  };

  const todayId = dayId(new Date());
  const todaySessions = useMemo(
    () => data.sessions.filter((s) => dayId(s.date) === todayId),
    [data.sessions, todayId],
  );
  const itemById = useMemo(
    () => new Map(data.items.map((i) => [i.id, i])),
    [data.items],
  );

  const heading = new Intl.DateTimeFormat(lang, {
    month: "long",
    day: "numeric",
    weekday: "long",
  }).format(new Date());

  return (
    <div>
      <h1 className="page-title">{heading}</h1>

      <p className="section-label">{t("items")}</p>
      {data.items.length === 0 && <p className="empty-note">{t("emptyToday")}</p>}
      <div className="tile-grid">
        {data.items.map((item) => {
          const style = STYLE_COLORS[normalizeStyle(item.styleToken)];
          return (
            <button key={item.id} className="tile" onClick={() => setRecording(item)}>
              <div className="tile-art" style={{ background: style.bg }}>
                <TileSymbolSvg
                  symbol={normalizeSymbol(item.symbolToken)}
                  fg={style.fg}
                  bg={style.bg}
                />
              </div>
              <span className="tile-name">{item.name}</span>
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
          <p className="section-label">{t("todaysLog")}</p>
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
          onStartTimer={prefillMinutes === null ? () => startTimer(recording) : undefined}
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
  return (
    <div className="row">
      <span className="row-dot" style={{ background: style.bg }} />
      <div className="row-main">
        <div className="row-title">{item?.name ?? "—"}</div>
        {session.note && <div className="row-sub">{session.note}</div>}
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

/// 計測中の浮きチップ。項目名と経過時間、終了(記録へ)と取りやめ。
function TimerChip({
  item,
  startedAt,
  now,
  onFinish,
  onDiscard,
}: {
  item?: StudyItem;
  startedAt: number;
  now: number;
  onFinish: () => void;
  onDiscard: () => void;
}) {
  const elapsed = Math.max(0, Math.floor((now - startedAt) / 1000));
  const mm = String(Math.floor(elapsed / 60)).padStart(2, "0");
  const ss = String(elapsed % 60).padStart(2, "0");
  return (
    <div className="timer-chip">
      <span className="timer-name">{item?.name ?? "—"}</span>
      <span className="timer-elapsed">
        {mm}:{ss}
      </span>
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
  onStartTimer?: () => void;
  onClose: () => void;
}) {
  const [minutes, setMinutes] = useState(initialMinutes ?? 30);
  const [note, setNote] = useState("");
  const [working, setWorking] = useState(false);
  const style = STYLE_COLORS[normalizeStyle(item.styleToken)];

  const save = async () => {
    if (working || minutes <= 0) return;
    setWorking(true);
    await recordSession(
      uid,
      { item, minutes: Math.min(minutes, 6000), note },
      data,
    );
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
        <div className="chip-row">
          {MINUTE_PRESETS.map((m) => (
            <button
              key={m}
              className={`chip${minutes === m ? " selected" : ""}`}
              onClick={() => setMinutes(m)}
            >
              {m}
            </button>
          ))}
          <input
            className="field"
            style={{ width: 100, padding: "8px 14px", minHeight: 40 }}
            type="number"
            inputMode="numeric"
            min={1}
            max={6000}
            value={minutes}
            onChange={(e) => setMinutes(Number(e.target.value))}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.nativeEvent.isComposing) void save();
            }}
          />
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
          <button className="quiet-button timer-start" onClick={onStartTimer}>
            {t("startTimer")}
          </button>
        )}
      </>
    </Modal>
  );
}
