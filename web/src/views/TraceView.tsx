import { useEffect, useMemo, useState } from "react";
import { dayId, startOfDay, type StudyDay } from "../types";
import type { UserData } from "../data";
import { deleteSession, setDayNote } from "../data";
import { SessionRow } from "./TodayView";
import { askConfirm } from "../overlays";
import { durationLabel, lang, noteCountLabel, t } from "../i18n";

// 軌跡: 月カレンダー。学んだ日(sunYellow)と休んだ日(seaGreen)を同格に描く。
// やめた回数はいつも0。

export function TraceView({ uid, data }: { uid: string; data: UserData }) {
  const [view, setView] = useState<"calendar" | "index">("calendar");

  return (
    <div>
      <div className="chip-row" style={{ marginBottom: 20 }}>
        <button
          className={`chip${view === "calendar" ? " selected" : ""}`}
          onClick={() => setView("calendar")}
        >
          {t("calendarTab")}
        </button>
        <button
          className={`chip${view === "index" ? " selected" : ""}`}
          onClick={() => setView("index")}
        >
          {t("indexTab")}
        </button>
      </div>
      {view === "calendar" ? (
        <CalendarView uid={uid} data={data} />
      ) : (
        <NotesIndex data={data} />
      )}
    </div>
  );
}

/// 学びの索引。ひとこと(記録+日)を検索・項目で絞って一覧する。
/// 記録が消費ではなく、あとから引ける資産になる。
function NotesIndex({ data }: { data: UserData }) {
  const [query, setQuery] = useState("");
  const [itemFilter, setItemFilter] = useState<string | null>(null);

  const entries = useMemo(() => {
    const itemById = new Map(data.items.map((i) => [i.id, i]));
    const list: {
      date: Date;
      note: string;
      itemName?: string;
      itemStyle?: string;
      itemId?: string;
    }[] = [];
    for (const s of data.sessions) {
      if (!s.note) continue;
      const item = s.itemUUID ? itemById.get(s.itemUUID) : undefined;
      list.push({
        date: s.date,
        note: s.note,
        itemName: item?.name,
        itemStyle: item?.styleToken,
        itemId: item?.id,
      });
    }
    for (const d of data.days) {
      if (d.note) list.push({ date: d.date, note: d.note });
    }
    return list.sort((a, b) => b.date.getTime() - a.date.getTime());
  }, [data.items, data.sessions, data.days]);

  const q = query.trim().toLowerCase();
  const visible = entries.filter(
    (e) =>
      (!q || e.note.toLowerCase().includes(q)) &&
      (!itemFilter || e.itemId === itemFilter),
  );

  const fmt = new Intl.DateTimeFormat(lang, { month: "short", day: "numeric" });

  return (
    <div>
      <input
        className="field"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder={t("searchNotes")}
      />
      {data.items.length > 0 && (
        <div className="chip-row" style={{ marginTop: 12 }}>
          {data.items.map((item) => (
            <button
              key={item.id}
              className={`chip${itemFilter === item.id ? " selected" : ""}`}
              onClick={() => setItemFilter(itemFilter === item.id ? null : item.id)}
            >
              {item.name}
            </button>
          ))}
        </div>
      )}
      {visible.length === 0 ? (
        <p className="empty-note" style={{ marginTop: 24 }}>
          {t("noNotes")}
        </p>
      ) : (
        <>
          <p className="section-label">{noteCountLabel(visible.length)}</p>
          <div className="rows">
            {visible.map((e, i) => (
              <div
                key={`${e.date.getTime()}-${e.itemId ?? "day"}-${i}`}
                className="row"
              >
                <div className="row-main">
                  <div className="row-sub" style={{ marginBottom: 2 }}>
                    {fmt.format(e.date)}
                    {e.itemName ? ` · ${e.itemName}` : ""}
                  </div>
                  <div className="row-title" style={{ fontWeight: 400, fontSize: 15 }}>
                    {e.note}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
}

function CalendarView({ uid, data }: { uid: string; data: UserData }) {
  const today = startOfDay(new Date());
  const todayMs = today.getTime();
  const [monthStart, setMonthStart] = useState(
    new Date(today.getFullYear(), today.getMonth(), 1),
  );
  const [selected, setSelected] = useState<Date>(today);

  const dayById = useMemo(() => {
    const map = new Map<string, StudyDay>();
    for (const d of data.days) map.set(d.id, d);
    return map;
  }, [data.days]);

  const weeks = useMemo(() => buildWeeks(monthStart), [monthStart]);

  // 表示月の統計(当月なら今日まで)。合計時間もその月の今日までの記録に揃える
  // (未来日付の記録=時計ずれ等が合計にだけ紛れ込まないように、日数と同じ境界)。
  const stats = useMemo(() => {
    let studied = 0;
    let rested = 0;
    const cursor = new Date(monthStart);
    while (cursor.getMonth() === monthStart.getMonth() && cursor.getTime() <= todayMs) {
      if (dayById.has(dayId(cursor))) studied++;
      else rested++;
      cursor.setDate(cursor.getDate() + 1);
    }
    const minutes = data.sessions.reduce(
      (sum, s) =>
        s.date.getFullYear() === monthStart.getFullYear() &&
        s.date.getMonth() === monthStart.getMonth() &&
        startOfDay(s.date).getTime() <= todayMs
          ? sum + s.minutes
          : sum,
      0,
    );
    return { studied, rested, minutes };
  }, [monthStart, dayById, todayMs, data.sessions]);

  const selectedSessions = data.sessions
    .filter((s) => dayId(s.date) === dayId(selected))
    .sort((a, b) => a.date.getTime() - b.date.getTime());
  const selectedTotal = selectedSessions.reduce((sum, s) => sum + s.minutes, 0);
  const selectedDay = dayById.get(dayId(selected));

  const monthTitle = new Intl.DateTimeFormat(lang, {
    year: "numeric",
    month: "long",
  }).format(monthStart);
  const selectedTitle = new Intl.DateTimeFormat(lang, {
    month: "long",
    day: "numeric",
    weekday: "short",
  }).format(selected);

  const weekdayNames = useMemo(() => {
    const fmt = new Intl.DateTimeFormat(lang, { weekday: "narrow" });
    // 2023-01-01 は日曜。
    return Array.from({ length: 7 }, (_, i) => fmt.format(new Date(2023, 0, 1 + i)));
  }, []);

  const isCurrentMonth =
    monthStart.getFullYear() === today.getFullYear() &&
    monthStart.getMonth() === today.getMonth();

  return (
    <div>
      <div className="month-nav">
        <button
          className="month-arrow"
          onClick={() => setMonthStart(shiftMonth(monthStart, -1))}
          aria-label={t("prevMonth")}
        >
          ‹
        </button>
        <span className="month-title">{monthTitle}</span>
        <button
          className="month-arrow"
          onClick={() => setMonthStart(shiftMonth(monthStart, 1))}
          disabled={isCurrentMonth}
          aria-label={t("nextMonth")}
        >
          ›
        </button>
      </div>
      {/* 別の月を見ているときだけ、今日へ戻る近道を1行で。中央の月表示には重ねない。 */}
      {!isCurrentMonth && (
        <div className="month-today-row">
          <button
            className="chip"
            onClick={() => {
              setMonthStart(new Date(today.getFullYear(), today.getMonth(), 1));
              setSelected(today);
            }}
          >
            {t("todayJump")}
          </button>
        </div>
      )}

      <div className="calendar">
        {weekdayNames.map((n, i) => (
          <span key={i} className="weekday">
            {n}
          </span>
        ))}
        {weeks.flat().map((date, i) => {
          if (!date) return <span key={i} />;
          const id = dayId(date);
          const isFuture = date > today;
          const studied = dayById.has(id);
          const classes = ["day-cell"];
          if (isFuture) classes.push("future");
          else if (studied) classes.push("studied");
          else classes.push("rested");
          if (id === dayId(today)) classes.push("today");
          if (id === dayId(selected)) classes.push("selected");
          return (
            <button
              key={i}
              className={classes.join(" ")}
              onClick={() => !isFuture && setSelected(date)}
              disabled={isFuture}
            >
              {date.getDate()}
            </button>
          );
        })}
      </div>

      <div className="stat-strip">
        <div className="stat studied">
          <div className="stat-number">{stats.studied}</div>
          <div className="stat-label">{t("studiedDays")}</div>
        </div>
        <div className="stat rested">
          <div className="stat-number">{stats.rested}</div>
          <div className="stat-label">{t("restedDays")}</div>
        </div>
        <div className="stat">
          <div className="stat-number stat-number-small">
            {durationLabel(stats.minutes)}
          </div>
          <div className="stat-label">{t("monthTotal")}</div>
        </div>
      </div>

      <p className="section-label">
        {selectedTitle}
        {selectedTotal > 0 && (
          <span className="section-label-sub"> · {durationLabel(selectedTotal)}</span>
        )}
      </p>
      {selectedSessions.length === 0 ? (
        <p className="empty-note">{t("noDayRecords")}</p>
      ) : (
        <>
          {/* この日のひとこと(学んだ日にだけ書ける。iOS の setComment と同じ) */}
          {selectedDay && (
            <DayNoteField key={selectedDay.id} uid={uid} day={selectedDay} data={data} />
          )}
          <div className="rows">
            {selectedSessions.map((s) => (
              <SessionRow
                key={s.id}
                session={s}
                item={data.items.find((i) => i.id === s.itemUUID)}
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
    </div>
  );
}

function DayNoteField({
  uid,
  day,
  data,
}: {
  uid: string;
  day: StudyDay;
  data: UserData;
}) {
  const [note, setNote] = useState(day.note ?? "");

  // 他端末からの同期でひとことが変わったら追従する(編集中は上書きしない)。
  const [editing, setEditing] = useState(false);
  useEffect(() => {
    if (!editing) setNote(day.note ?? "");
  }, [day.note, editing]);

  const commit = async () => {
    setEditing(false);
    const value = note.trim();
    if (value === (day.note ?? "")) return;
    await setDayNote(uid, day, value || null, data);
  };

  return (
    <input
      className="field day-note-field"
      value={note}
      onChange={(e) => setNote(e.target.value)}
      onFocus={() => setEditing(true)}
      onBlur={() => void commit()}
      onKeyDown={(e) => {
        if (e.key === "Enter" && !e.nativeEvent.isComposing) {
          (e.target as HTMLInputElement).blur();
        }
      }}
      placeholder={t("dayNotePlaceholder")}
      maxLength={120}
    />
  );
}

function shiftMonth(monthStart: Date, delta: number): Date {
  return new Date(monthStart.getFullYear(), monthStart.getMonth() + delta, 1);
}

/// 月の週配列(日曜始まり)。月外は null。
function buildWeeks(monthStart: Date): (Date | null)[][] {
  const weeks: (Date | null)[][] = [];
  let week: (Date | null)[] = new Array(monthStart.getDay()).fill(null);
  const cursor = new Date(monthStart);
  while (cursor.getMonth() === monthStart.getMonth()) {
    week.push(new Date(cursor));
    if (week.length === 7) {
      weeks.push(week);
      week = [];
    }
    cursor.setDate(cursor.getDate() + 1);
  }
  if (week.length > 0) {
    while (week.length < 7) week.push(null);
    weeks.push(week);
  }
  return weeks;
}
