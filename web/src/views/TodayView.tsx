import { useMemo, useState } from "react";
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
import { lang, t } from "../i18n";

const MINUTE_PRESETS = [15, 30, 45, 60, 90];

export function TodayView({ uid, data }: { uid: string; data: UserData }) {
  const [recording, setRecording] = useState<StudyItem | null>(null);
  const [editing, setEditing] = useState<StudyItem | null>(null);
  const [creating, setCreating] = useState(false);

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
                  if (confirm(t("deleteSessionConfirm"))) {
                    await deleteSession(uid, s, data);
                  }
                }}
              />
            ))}
          </div>
        </>
      )}

      {recording && (
        <RecordDialog
          uid={uid}
          item={recording}
          data={data}
          onClose={() => setRecording(null)}
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
        <button className="quiet-button" onClick={onDelete}>
          {t("delete")}
        </button>
      )}
    </div>
  );
}

function RecordDialog({
  uid,
  item,
  data,
  onClose,
}: {
  uid: string;
  item: StudyItem;
  data: UserData;
  onClose: () => void;
}) {
  const [minutes, setMinutes] = useState(30);
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
    onClose();
  };

  return (
    <div className="overlay" onClick={onClose}>
      <div className="dialog" onClick={(e) => e.stopPropagation()}>
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
            min={1}
            max={6000}
            value={minutes}
            onChange={(e) => setMinutes(Number(e.target.value))}
          />
        </div>

        <p className="section-label">{t("noteOptional")}</p>
        <input
          className="field"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          maxLength={120}
          placeholder={t("noteOptional")}
        />

        <div style={{ height: 28 }} />
        <button className="primary-button" onClick={save} disabled={working || minutes <= 0}>
          {t("record")}
        </button>
      </div>
    </div>
  );
}
