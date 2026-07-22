import { useMemo, useState } from "react";
import type { UserData } from "../data";
import {
  completedWrappedMonths,
  wrappedMonth,
  type Archetype,
  type WrappedMonth,
} from "../wrapped";
import { ArchetypeSymbolSvg, COAST, HULL, SAIL } from "../symbols";
import { boatFlag, boatSail } from "../boat";
import { drawCard, saveCanvas, type CardKind } from "../share";
import { lang, t, yearChartTitle, type I18nKey } from "../i18n";

// 航海誌。月末に生まれる、その月のまとめカード(iOS の Wrapped と同じ内容)。
// カードは絵はがき(iOS: 390x693、固定デザインのため常にライトの配色で描く)。

const ARCHETYPE_KEYS: Record<Archetype, { name: I18nKey; tag: I18nKey; sub: I18nKey }> = {
  phoenix: { name: "typePhoenix", tag: "tagPhoenix", sub: "subPhoenix" },
  stoneBridge: { name: "typeStoneBridge", tag: "tagStoneBridge", sub: "subStoneBridge" },
  waveRider: { name: "typeWaveRider", tag: "tagWaveRider", sub: "subWaveRider" },
  comet: { name: "typeComet", tag: "tagComet", sub: "subComet" },
  morningCalm: { name: "typeMorningCalm", tag: "tagMorningCalm", sub: "subMorningCalm" },
};

export function LogbookView({ data }: { data: UserData }) {
  const [view, setView] = useState<"cards" | "year">("cards");
  return (
    <div>
      <div className="chip-row" style={{ marginBottom: 24 }}>
        <button
          className={`chip${view === "cards" ? " selected" : ""}`}
          onClick={() => setView("cards")}
        >
          {t("monthCards")}
        </button>
        <button
          className={`chip${view === "year" ? " selected" : ""}`}
          onClick={() => setView("year")}
        >
          {t("yearChart")}
        </button>
      </div>
      {view === "cards" ? <MonthCards data={data} /> : <YearChart data={data} />}
      <ReachedIslands data={data} />
    </div>
  );
}

function MonthCards({ data }: { data: UserData }) {
  const months = useMemo(
    () => completedWrappedMonths(data.days, new Date()),
    [data.days],
  );
  const [selected, setSelected] = useState(0);

  if (months.length === 0) {
    return <p className="empty-note">{t("firstLogbook")}</p>;
  }

  const ym = months[Math.min(selected, months.length - 1)];
  const month = wrappedMonth(ym.year, ym.month, data.days, data.sessions);
  const monthTitle = (y: number, m: number) =>
    new Intl.DateTimeFormat(lang, { year: "numeric", month: "long" }).format(
      new Date(y, m - 1, 1),
    );

  return (
    <div>
      <div className="chip-row" style={{ marginBottom: 24 }}>
        {months.map((m, i) => (
          <button
            key={`${m.year}-${m.month}`}
            className={`chip${i === selected ? " selected" : ""}`}
            onClick={() => setSelected(i)}
          >
            {monthTitle(m.year, m.month)}
          </button>
        ))}
      </div>

      <div className="wrapped-stack">
        <DaysCard month={month} title={monthTitle(ym.year, ym.month)} />
        <VoyageCard month={month} />
        <ArchetypeCard month={month} />
      </div>

      {/* 画像で保存(スマホでは共有シート)。SNSやアルバムへ。 */}
      <div className="chip-row" style={{ marginTop: 20, justifyContent: "center" }}>
        {(["days", "voyage", "archetype"] as CardKind[]).map((kind, i) => (
          <button
            key={kind}
            className="chip"
            onClick={() => {
              const keys = ARCHETYPE_KEYS[month.archetype];
              const hours = Math.floor(month.totalMinutes / 60);
              const mins = month.totalMinutes % 60;
              const canvas = drawCard(kind, month, monthTitle(ym.year, ym.month), {
                studied: t("studiedDays"),
                rested: t("restedDays"),
                quit: t("quitCount"),
                total:
                  month.totalMinutes > 0
                    ? lang === "ja"
                      ? `${hours > 0 ? `${hours}時間` : ""}${mins}分`
                      : `${hours > 0 ? `${hours}h ` : ""}${mins}m`
                    : "",
                returns: t("returnsLabel"),
                longestGap: t("longestGapLabel"),
                typeName: t(keys.name),
                tagline: t(keys.tag),
                subline: t(keys.sub),
              });
              void saveCanvas(canvas, `landfall-${ym.year}-${ym.month}-${kind}.png`);
            }}
          >
            {t("saveImage")} {i + 1}
          </button>
        ))}
      </div>
    </div>
  );
}

/// 年間海図。1年の海に12ヶ月の航路を描き、到達した島が浮かぶ。
function YearChart({ data }: { data: UserData }) {
  const now = new Date();
  const [year, setYear] = useState(now.getFullYear());

  const years = useMemo(() => {
    const set = new Set<number>([now.getFullYear()]);
    for (const d of data.days) set.add(d.date.getFullYear());
    return [...set].sort((a, b) => b - a);
  }, [data.days, now]);

  // 月ごとの学んだ日数(航路の点の明るさになる)
  const counts = Array.from({ length: 12 }, (_, m) =>
    data.days.filter((d) => d.date.getFullYear() === year && d.date.getMonth() === m).length,
  );
  const islands = data.destinations.filter(
    (d) => d.achievedAt && d.achievedAt.getFullYear() === year,
  );

  const px = (m: number) => 70 + (m * (880 - 140)) / 11;
  const py = (m: number) => 250 + Math.sin(m * 0.9) * 70;
  let route = `M ${px(0)} ${py(0)}`;
  for (let m = 1; m < 12; m++) {
    const cx = (px(m - 1) + px(m)) / 2;
    route += ` Q ${cx} ${py(m - 1)} ${px(m)} ${py(m)}`;
  }
  const currentMonth = year === now.getFullYear() ? now.getMonth() : 11;

  return (
    <div>
      {years.length > 1 && (
        <div className="chip-row" style={{ marginBottom: 16 }}>
          {years.map((y) => (
            <button
              key={y}
              className={`chip${y === year ? " selected" : ""}`}
              onClick={() => setYear(y)}
            >
              {y}
            </button>
          ))}
        </div>
      )}
      <div className="year-chart">
        <svg viewBox="0 0 880 480" aria-hidden="true">
          <circle cx="120" cy="60" r="3" fill="#EADEBD" opacity="0.3" />
          <circle cx="420" cy="40" r="4" fill="#EADEBD" opacity="0.35" />
          <circle cx="700" cy="70" r="3" fill="#EADEBD" opacity="0.3" />
          <circle cx="800" cy="120" r="22" fill="#EADEBD" opacity="0.85" />
          <text x="40" y="52" fill="#EADEBD" fontSize="24" fontWeight="500">
            {yearChartTitle(year)}
          </text>

          <path
            d={route}
            fill="none"
            stroke="#EADEBD"
            strokeOpacity="0.3"
            strokeWidth="2.5"
            strokeDasharray="2 9"
            strokeLinecap="round"
          />

          {counts.map((count, m) => (
            <g key={m}>
              <circle
                cx={px(m)}
                cy={py(m)}
                r={count > 0 ? 9 : 5}
                fill="#EADEBD"
                opacity={count > 0 ? 0.35 + Math.min(0.65, count / 20) : 0.15}
              />
              <text
                x={px(m)}
                y={py(m) + 34}
                fill="#EADEBD"
                opacity="0.5"
                fontSize="15"
                textAnchor="middle"
              >
                {m + 1}
              </text>
            </g>
          ))}

          {/* 到達した島(その月の航路のそばに浮かぶ) */}
          {islands.map((d) => {
            const m = d.achievedAt!.getMonth();
            return (
              <g key={d.id} transform={`translate(${px(m) - 34}, ${py(m) - 92})`}>
                <g transform="scale(0.16) translate(-430, -340)">
                  <path d={COAST} fill="#EADEBD" />
                </g>
                <text x="34" y="-12" fill="#EADEBD" fontSize="15" textAnchor="middle">
                  {d.name}
                </text>
              </g>
            );
          })}

          {/* いまの位置の船 */}
          <g
            transform={`translate(${px(currentMonth) - 15}, ${py(currentMonth) - 62}) scale(0.16)`}
          >
            <g transform="translate(-215, -335)">
              {boatFlag() === "pennant" && (
                <polygon points="318,344 366,357 318,370" fill="#F5822A" />
              )}
              {boatFlag() === "swallow" && (
                <polygon points="318,344 370,344 352,357 370,370 318,370" fill="#F0997B" />
              )}
              <path d={SAIL} fill={boatSail()} />
              <path d={HULL} fill="#EADEBD" />
            </g>
          </g>
        </svg>
      </div>
    </div>
  );
}

/// 到達した島。目的地に着岸した記録が、ここに残り続ける。
function ReachedIslands({ data }: { data: UserData }) {
  const reached = data.destinations
    .filter((d) => d.achievedAt)
    .sort((a, b) => (b.achievedAt?.getTime() ?? 0) - (a.achievedAt?.getTime() ?? 0));
  if (reached.length === 0) return null;
  const fmt = new Intl.DateTimeFormat(lang, { year: "numeric", month: "long", day: "numeric" });
  return (
    <div>
      <p className="section-label">{t("reachedIslands")}</p>
      <div className="rows">
        {reached.map((d) => (
          <div key={d.id} className="row">
            <span className="island-mark" aria-hidden="true" />
            <div className="row-main">
              <div className="row-title">{d.name}</div>
              <div className="row-sub">{d.achievedAt ? fmt.format(d.achievedAt) : ""}</div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function Brandmark({ color }: { color: string }) {
  return (
    <div className="wrapped-brand" style={{ color }}>
      Landfall-StudyLog
    </div>
  );
}

/// 1枚目: 学んだ日・休んだ日・やめた回数(同格の三段)。
function DaysCard({ month, title }: { month: WrappedMonth; title: string }) {
  const hours = Math.floor(month.totalMinutes / 60);
  const mins = month.totalMinutes % 60;
  const total =
    lang === "ja"
      ? `${hours > 0 ? `${hours}時間` : ""}${mins}分`
      : `${hours > 0 ? `${hours}h ` : ""}${mins}m`;
  return (
    <div className="wrapped-card" style={{ background: "#FFD84D", color: "#141414" }}>
      <div className="wrapped-kicker" style={{ color: "#4A1B0C" }}>
        {title}
      </div>
      <div className="wrapped-stats">
        <div className="wrapped-stat">
          <span className="wrapped-number">{month.studiedDays.size}</span>
          <span className="wrapped-label">{t("studiedDays")}</span>
        </div>
        <div className="wrapped-stat">
          <span className="wrapped-number">{month.daysInMonth - month.studiedDays.size}</span>
          <span className="wrapped-label">{t("restedDays")}</span>
        </div>
        <div className="wrapped-stat">
          <span className="wrapped-number">0</span>
          <span className="wrapped-label">{t("quitCount")}</span>
        </div>
      </div>
      {month.totalMinutes > 0 && (
        <div className="wrapped-total" style={{ color: "#4A1B0C" }}>
          {total}
        </div>
      )}
      <Brandmark color="rgba(20,20,20,0.4)" />
    </div>
  );
}

/// 2枚目: 月の航海図(日々の帯)と、帰還・いちばん長い空白。
function VoyageCard({ month }: { month: WrappedMonth }) {
  return (
    <div className="wrapped-card" style={{ background: "#F0997B", color: "#4A1B0C" }}>
      <div className="wrapped-kicker">{t("trace")}</div>
      <div className="wrapped-days-strip">
        {Array.from({ length: month.daysInMonth }, (_, i) => i + 1).map((day) => (
          <span
            key={day}
            className="wrapped-day"
            style={{
              background: month.studiedDays.has(day) ? "#4A1B0C" : "rgba(74,27,12,0.18)",
            }}
          />
        ))}
      </div>
      <div className="wrapped-facts">
        <div className="wrapped-fact">
          <span className="wrapped-number">
            {month.resumeCount}
            {lang === "ja" && <span className="wrapped-unit">{t("timesUnit")}</span>}
          </span>
          <span className="wrapped-label">{t("returnsLabel")}</span>
        </div>
        {month.longestGap && (
          <div className="wrapped-fact">
            <span className="wrapped-number">
              {month.longestGap.length}
              <span className="wrapped-unit">
                {lang === "ja" ? t("daysUnit") : ` ${t("daysUnit")}`}
              </span>
            </span>
            <span className="wrapped-label">{t("longestGapLabel")}</span>
          </div>
        )}
      </div>
      <Brandmark color="rgba(74,27,12,0.4)" />
    </div>
  );
}

/// 3枚目: タイプ診断。シンボル+型名+決め台詞+添え書き。
function ArchetypeCard({ month }: { month: WrappedMonth }) {
  const keys = ARCHETYPE_KEYS[month.archetype];
  return (
    <div className="wrapped-card wrapped-card-center" style={{ background: "#1A1130", color: "#CECBF6" }}>
      <div className="wrapped-symbol">
        <ArchetypeSymbolSvg archetype={month.archetype} />
      </div>
      <div className="wrapped-type-name">{t(keys.name)}</div>
      <div className="wrapped-type-tag">{t(keys.tag)}</div>
      <div className="wrapped-type-sub">{t(keys.sub)}</div>
      <Brandmark color="rgba(206,203,246,0.4)" />
    </div>
  );
}
