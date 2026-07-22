import { useMemo, useState } from "react";
import { createVoyage } from "../harbor";
import {
  generateRoutes,
  newVoyageSeed,
  routePointAt,
  smoothPath,
  type RouteArchetype,
  type SeaRoute,
} from "../voyageMap";
import { askConfirm, showToast } from "../overlays";
import { hoursShortLabel, t, type I18nKey } from "../i18n";

// 共同航海の海図パネル。目的地までの時間を決めると seed から海図がひらき、
// 3本の航路(凪・嵐・深み)から1本を選んで出航する。seed と選択は
// voyage ドキュメントに書かれ、全メンバーが同じ海図・同じ海域を見る。

const ROUTE_NAME: Record<RouteArchetype, I18nKey> = {
  calm: "routeCalm",
  squall: "routeSquall",
  deep: "routeDeep",
};
const ROUTE_DESC: Record<RouteArchetype, I18nKey> = {
  calm: "routeCalmDesc",
  squall: "routeSquallDesc",
  deep: "routeDeepDesc",
};
// 航路の色。海図の線とカードの点で対応づける(凪=海緑、嵐=雨の青、深み=薄紫)。
const ROUTE_COLOR: Record<RouteArchetype, string> = {
  calm: "#5DCAA5",
  squall: "#7FA8B8",
  deep: "#CECBF6",
};

function lootLabel(route: SeaRoute): string {
  if (route.lootKey === "loot.moonlightSail") return t("routeLootMoonlight");
  if (route.lootKey === "loot.krakenFlag") return t("routeLootKraken");
  return t("routeLootNone");
}

/// 嵐の印(小さな雲+雨脚)。
function StormMark({ x, y, dim }: { x: number; y: number; dim: boolean }) {
  return (
    <g transform={`translate(${x.toFixed(1)} ${y.toFixed(1)})`} opacity={dim ? 0.45 : 1}>
      <circle cx="-3" cy="0" r="4" fill="#7FA8B8" />
      <circle cx="3" cy="-1.5" r="5" fill="#7FA8B8" />
      <rect x="-7" y="1.5" width="14" height="4" rx="2" fill="#7FA8B8" />
      <line x1="-3" y1="7" x2="-4.5" y2="11" stroke="#7FA8B8" strokeWidth="1.5" strokeLinecap="round" />
      <line x1="2" y1="7" x2="0.5" y2="11" stroke="#7FA8B8" strokeWidth="1.5" strokeLinecap="round" />
    </g>
  );
}

/// 海獣の印(頭+触腕3本)。
function KrakenMark({ x, y, dim }: { x: number; y: number; dim: boolean }) {
  return (
    <g transform={`translate(${x.toFixed(1)} ${y.toFixed(1)})`} opacity={dim ? 0.45 : 1}>
      <circle cx="0" cy="-2" r="4.5" fill="#CECBF6" />
      <path d="M -4 1 Q -6 5 -8.5 4.5" stroke="#CECBF6" strokeWidth="2" fill="none" strokeLinecap="round" />
      <path d="M 0 2 Q 0 6 -1.5 8" stroke="#CECBF6" strokeWidth="2" fill="none" strokeLinecap="round" />
      <path d="M 4 1 Q 6 5 8.5 4.5" stroke="#CECBF6" strokeWidth="2" fill="none" strokeLinecap="round" />
      <circle cx="-1.5" cy="-2.5" r="0.9" fill="#123830" />
      <circle cx="1.5" cy="-2.5" r="0.9" fill="#123830" />
    </g>
  );
}

/// 海図。左の港から右の島へ、3本の航路が波形に伸びる。線をタップでも選べる。
function ChartSvg({
  routes,
  selected,
  onSelect,
}: {
  routes: SeaRoute[];
  selected: number | null;
  onSelect: (i: number) => void;
}) {
  const W = 340;
  const H = 200;
  const scale = (p: { x: number; y: number }) => ({ x: p.x * W, y: p.y * H });
  return (
    <svg className="sea-chart" viewBox={`0 0 ${W} ${H}`} role="img" aria-label={t("voyageTitle")}>
      {/* 緯度の淡い破線(海図らしさ) */}
      {[0.25, 0.5, 0.75].map((f) => (
        <line
          key={f}
          x1={8}
          x2={W - 8}
          y1={H * f}
          y2={H * f}
          stroke="#EADEBD"
          strokeOpacity={0.07}
          strokeDasharray="2 7"
        />
      ))}
      {routes.map((route, i) => {
        const d = smoothPath(route.points.map(scale));
        const color = ROUTE_COLOR[route.archetype];
        const isSel = selected === i;
        return (
          <g key={i}>
            <path
              d={d}
              fill="none"
              stroke={color}
              strokeWidth={isSel ? 3 : 2}
              strokeOpacity={isSel ? 1 : 0.38}
              strokeDasharray={isSel ? undefined : "5 6"}
              strokeLinecap="round"
            />
            {route.encounters.map((e, j) => {
              const c = scale(routePointAt(route, (e.start + e.end) / 2));
              return e.kind === "storm" ? (
                <StormMark key={j} x={c.x} y={c.y} dim={!isSel} />
              ) : (
                <KrakenMark key={j} x={c.x} y={c.y} dim={!isSel} />
              );
            })}
            {/* 太い透明ストロークの当たり判定 */}
            <path
              d={d}
              fill="none"
              stroke="transparent"
              strokeWidth={24}
              style={{ cursor: "pointer" }}
              onClick={() => onSelect(i)}
            />
          </g>
        );
      })}
      {/* 港(左)と島(右)。航路の端を覆うよう最後に描く */}
      <g transform={`translate(${0.06 * W} ${0.5 * H})`}>
        <circle r="5.5" fill="#EADEBD" />
        <circle r="2" fill="#123830" />
      </g>
      <g transform={`translate(${0.94 * W} ${0.48 * H})`}>
        <path d="M -14 8 L -4 -10 L 3 8 Z" fill="#2E6B54" />
        <path d="M -2 8 L 6 -4 L 13 8 Z" fill="#245544" />
      </g>
    </svg>
  );
}

/// 海図パネル本体。目的地までの時間 → 海図をひらく → 航路を選んで出航。
export function VoyageChartPanel({ roomId }: { roomId: string }) {
  const [presetHours, setPresetHours] = useState(20);
  const [customHours, setCustomHours] = useState("");
  const [seed, setSeed] = useState<number | null>(null);
  const [routeIndex, setRouteIndex] = useState<number | null>(null);
  const [working, setWorking] = useState(false);

  const hours = customHours.trim() ? Number(customHours) : presetHours;
  const valid = Number.isFinite(hours) && hours >= 1 && hours <= 10000;
  const routes = useMemo(() => (seed !== null ? generateRoutes(seed) : null), [seed]);

  const depart = async () => {
    if (seed === null || routeIndex === null || !valid || working) return;
    const ok = await askConfirm({
      title: t("setSail"),
      message: t("setSailConfirm"),
      confirmLabel: t("setSail"),
    });
    if (!ok) return;
    setWorking(true);
    try {
      await createVoyage(roomId, seed, routeIndex, Math.round(hours * 60));
    } catch {
      showToast(t("errGeneric"));
    } finally {
      setWorking(false);
    }
  };

  return (
    <div className="quest-panel">
      <p className="section-label">{t("voyageTitle")}</p>
      <p className="quest-intro">{t("voyageIntro")}</p>
      <p className="row-sub" style={{ margin: "12px 0 6px" }}>
        {t("voyageTargetLabel")}
      </p>
      <div className="chip-row">
        {[20, 50, 100].map((h) => (
          <button
            key={h}
            className={`chip${!customHours.trim() && presetHours === h ? " selected" : ""}`}
            onClick={() => {
              setPresetHours(h);
              setCustomHours("");
            }}
          >
            {hoursShortLabel(h)}
          </button>
        ))}
        <input
          className="field quest-hours-field"
          inputMode="numeric"
          value={customHours}
          onChange={(e) => setCustomHours(e.target.value.replace(/[^0-9]/g, "").slice(0, 5))}
          placeholder={t("voyageCustomHours")}
          aria-label={t("voyageTargetLabel")}
        />
        <span className="row-sub">{t("hoursUnit")}</span>
      </div>
      {routes === null ? (
        <div style={{ marginTop: 14 }}>
          <button
            className="primary-button"
            onClick={() => setSeed(newVoyageSeed())}
            disabled={!valid}
          >
            {t("openChart")}
          </button>
        </div>
      ) : (
        <>
          <ChartSvg routes={routes} selected={routeIndex} onSelect={setRouteIndex} />
          <div className="route-cards">
            {routes.map((route, i) => (
              <button
                key={i}
                className={`route-card${routeIndex === i ? " selected" : ""}`}
                onClick={() => setRouteIndex(i)}
                aria-pressed={routeIndex === i}
              >
                <span
                  className="route-dot"
                  style={{ background: ROUTE_COLOR[route.archetype] }}
                />
                <span className="route-card-main">
                  <span className="route-card-name">{t(ROUTE_NAME[route.archetype])}</span>
                  <span className="route-card-desc">{t(ROUTE_DESC[route.archetype])}</span>
                  <span className={`route-loot${route.lootKey ? "" : " none"}`}>
                    {lootLabel(route)}
                  </span>
                </span>
              </button>
            ))}
          </div>
          <div className="chip-row" style={{ marginTop: 14 }}>
            <button
              className="primary-button"
              onClick={depart}
              disabled={routeIndex === null || working}
            >
              {t("setSail")}
            </button>
            <button
              className="chip"
              onClick={() => {
                setSeed(newVoyageSeed());
                setRouteIndex(null);
              }}
            >
              {t("redrawChart")}
            </button>
          </div>
        </>
      )}
    </div>
  );
}
