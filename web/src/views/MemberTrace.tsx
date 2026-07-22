import { useEffect, useMemo, useState } from "react";
import {
  fetchMonth,
  type HarborMember,
  type SharedMonth,
} from "../harbor";
import { STYLE_COLORS, normalizeStyle, normalizeSymbol } from "../types";
import { PlayerAvatar, TileSymbolSvg } from "../symbols";
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
  // 全日展開はしない。選んだ日だけ詳細を見せる(プライバシーと見やすさの両立)。
  const [selectedDay, setSelectedDay] = useState<number | null>(null);

  const ym = `${year}-${String(month + 1).padStart(2, "0")}`;

  useEffect(() => {
    let alive = true;
    setLoaded(false);
    setSelectedDay(null);
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

  const daySessions = useMemo(
    () => (selectedDay ? (data?.sessions ?? []).filter((s) => s.day === selectedDay) : []),
    [data, selectedDay],
  );

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
          {/* 学んだ日はホバーで浮かび、押すとその日だけ詳細が開く(全展開しない)。 */}
          <div className="dot-grid">
            {Array.from({ length: daysInMonth }, (_, i) => i + 1).map((day) => {
              const has = studied.has(day);
              return (
                <button
                  key={day}
                  className={`dot-day${has ? " studied" : ""}${
                    selectedDay === day ? " selected" : ""
                  }`}
                  disabled={!has}
                  onClick={() => setSelectedDay(selectedDay === day ? null : day)}
                >
                  {day}
                </button>
              );
            })}
          </div>

          {studied.size === 0 ? (
            <p className="empty-note" style={{ marginTop: 20 }}>
              {t("noDayRecords")}
            </p>
          ) : selectedDay === null ? (
            <p className="empty-note" style={{ marginTop: 20 }}>
              {t("tapDayHint")}
            </p>
          ) : (
            <div>
              <p className="section-label">
                {new Intl.DateTimeFormat(lang, { month: "long", day: "numeric" }).format(
                  new Date(year, month, selectedDay),
                )}
              </p>
              <div className="rows">
                {daySessions.map((s, i) => {
                  const style = STYLE_COLORS[normalizeStyle(s.styleToken)];
                  const time = s.date
                    ? `${String(s.date.getHours()).padStart(2, "0")}:${String(
                        s.date.getMinutes(),
                      ).padStart(2, "0")}`
                    : "";
                  return (
                    <div key={i} className="row">
                      {/* 項目タイルと同じ絵柄。色の点だけでは項目が判別できない。 */}
                      <span className="row-tile" style={{ background: style.bg }}>
                        <TileSymbolSvg
                          symbol={normalizeSymbol(s.symbolToken)}
                          fg={style.fg}
                          bg={style.bg}
                        />
                      </span>
                      <div className="row-main">
                        <div className="row-title">{s.itemName ?? "—"}</div>
                        {(time || s.note) && (
                          <div className="row-sub">
                            {time && <span className="row-time">{time}</span>}
                            {time && s.note ? " · " : ""}
                            {s.note ?? ""}
                          </div>
                        )}
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
          )}
        </>
      )}
    </div>
  );
}
