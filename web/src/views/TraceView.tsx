import { useEffect, useMemo, useState } from "react";
import { dayId, startOfDay, type StudyDay } from "../types";
import type { UserData } from "../data";
import { deleteSession, setDayNote } from "../data";
import { SessionRow } from "./TodayView";
import { askConfirm } from "../overlays";
import { lang, t } from "../i18n";

// 軌跡: 月カレンダー。学んだ日(sunYellow)と休んだ日(seaGreen)を同格に描く。
// やめた回数はいつも0。

export function TraceView({ uid, data }: { uid: string; data: UserData }) {
  const today = startOfDay(new Date());
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

  // 表示月の統計(当月なら今日まで)。
  const stats = useMemo(() => {
    let studied = 0;
    let rested = 0;
    const cursor = new Date(monthStart);
    while (cursor.getMonth() === monthStart.getMonth() && cursor <= today) {
      if (dayById.has(dayId(cursor))) studied++;
      else rested++;
      cursor.setDate(cursor.getDate() + 1);
    }
    return { studied, rested };
  }, [monthStart, dayById, today]);

  const selectedSessions = data.sessions.filter(
    (s) => dayId(s.date) === dayId(selected),
  );
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
          aria-label="previous month"
        >
          ‹
        </button>
        <span className="month-title">{monthTitle}</span>
        <button
          className="month-arrow"
          onClick={() => setMonthStart(shiftMonth(monthStart, 1))}
          disabled={isCurrentMonth}
          aria-label="next month"
        >
          ›
        </button>
      </div>

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
          <div className="stat-number">0</div>
          <div className="stat-label">{t("quitCount")}</div>
        </div>
      </div>

      <p className="section-label">{selectedTitle}</p>
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
