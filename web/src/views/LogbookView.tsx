import { useMemo, useState } from "react";
import type { UserData } from "../data";
import {
  completedWrappedMonths,
  wrappedMonth,
  type Archetype,
  type WrappedMonth,
} from "../wrapped";
import { ArchetypeSymbolSvg } from "../symbols";
import { lang, t, type I18nKey } from "../i18n";

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

      <ReachedIslands data={data} />
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
