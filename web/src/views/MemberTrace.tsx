import { useEffect, useMemo, useState } from "react";
import {
  fetchMonth,
  type HarborMember,
  type SharedMonth,
} from "../harbor";
import { STYLE_COLORS, normalizeStyle } from "../types";
import { PlayerAvatar } from "../symbols";
import { lang, t } from "../i18n";

/// 港のメンバーの月間の軌跡。学んだ日と、日ごとの記録(項目・分・ひとこと)。
/// プライベート(rooms)とパブリック(publicHarbors)で同じ画面を使う。
export function MemberTrace({
  root,
  containerId,
  member,
  onBack,
}: {
  root: "rooms" | "publicHarbors";
  containerId: string;
  member: HarborMember;
  onBack: () => void;
}) {
  const now = new Date();
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth()); // 0-based
  const [data, setData] = useState<SharedMonth | null>(null);
  const [loaded, setLoaded] = useState(false);

  const ym = `${year}-${String(month + 1).padStart(2, "0")}`;

  useEffect(() => {
    let alive = true;
    setLoaded(false);
    fetchMonth(root, containerId, member.id, ym).then((m) => {
      if (alive) {
        setData(m);
        setLoaded(true);
      }
    });
    return () => {
      alive = false;
    };
  }, [root, containerId, member.id, ym]);

  const monthTitle = new Intl.DateTimeFormat(lang, {
    year: "numeric",
    month: "long",
  }).format(new Date(year, month, 1));

  const isCurrentMonth = year === now.getFullYear() && month === now.getMonth();
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const studied = useMemo(() => new Set(data?.days ?? []), [data]);

  const sessionsByDay = useMemo(() => {
    const map = new Map<number, NonNullable<SharedMonth["sessions"]>>();
    for (const s of data?.sessions ?? []) {
      const list = map.get(s.day) ?? [];
      list.push(s);
      map.set(s.day, list);
    }
    return [...map.entries()].sort((a, b) => b[0] - a[0]);
  }, [data]);

  const shift = (delta: number) => {
    const d = new Date(year, month + delta, 1);
    setYear(d.getFullYear());
    setMonth(d.getMonth());
  };

  return (
    <div>
      <button className="quiet-button" onClick={onBack}>
        ‹ {t("back")}
      </button>

      <div className="member-head">
        <PlayerAvatar styleToken={member.styleToken} symbolToken={member.symbolToken} size={44} />
        <div>
          <div className="row-title">{member.displayName}</div>
          {member.resolve && <div className="row-sub">{member.resolve}</div>}
        </div>
      </div>

      <div className="month-nav">
        <button className="month-arrow" onClick={() => shift(-1)} aria-label="previous month">
          ‹
        </button>
        <span className="month-title">{monthTitle}</span>
        <button
          className="month-arrow"
          onClick={() => shift(1)}
          disabled={isCurrentMonth}
          aria-label="next month"
        >
          ›
        </button>
      </div>

      {!loaded ? (
        <p className="empty-note">{t("loading")}</p>
      ) : (
        <>
          <div className="dot-grid">
            {Array.from({ length: daysInMonth }, (_, i) => i + 1).map((day) => (
              <span
                key={day}
                className={`dot-day${studied.has(day) ? " studied" : ""}`}
              >
                {day}
              </span>
            ))}
          </div>

          {sessionsByDay.length === 0 ? (
            <p className="empty-note" style={{ marginTop: 20 }}>
              {t("noDayRecords")}
            </p>
          ) : (
            sessionsByDay.map(([day, sessions]) => (
              <div key={day}>
                <p className="section-label">
                  {new Intl.DateTimeFormat(lang, { month: "long", day: "numeric" }).format(
                    new Date(year, month, day),
                  )}
                </p>
                <div className="rows">
                  {sessions.map((s, i) => {
                    const style = STYLE_COLORS[normalizeStyle(s.styleToken)];
                    return (
                      <div key={i} className="row">
                        <span className="row-dot" style={{ background: style.bg }} />
                        <div className="row-main">
                          <div className="row-title">{s.itemName ?? "—"}</div>
                          {s.note && <div className="row-sub">{s.note}</div>}
                        </div>
                        <span className="row-minutes">
                          {s.minutes}
                          {t("minutesUnit")}
                        </span>
                      </div>
                    );
                  })}
                </div>
              </div>
            ))
          )}
        </>
      )}
    </div>
  );
}
