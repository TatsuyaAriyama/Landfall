import type { LootKey } from "./boat";

// 共同航海の海図。seed から決定的に3本の航路を生成する
// (全メンバーが同じ seed を読むので、全員の海図・遭遇位置が一致する)。
// 航路は毎回ランダムだが、性格は3類型で固定:
//   凪   … 遭遇が少なく静か。戦利品はない。
//   嵐   … 嵐の海域を抜ける。到着で「月光の帆」。
//   深み … 海獣の棲む深みを渡る。到着で「海獣の旗」。

export type EncounterKind = "kraken" | "storm";

export interface RouteEncounter {
  kind: EncounterKind;
  /// 航路上の区間(進捗率 0..1)。frac がこの区間にある間、海に現れる。
  start: number;
  end: number;
}

export type RouteArchetype = "calm" | "squall" | "deep";

export interface SeaRoute {
  archetype: RouteArchetype;
  encounters: RouteEncounter[];
  /// 到着で解放される戦利品(凪は undefined)。
  lootKey?: LootKey;
  /// 海図に描く経路(0..1 の正規化座標。両端が港と島)。
  points: { x: number; y: number }[];
}

/// mulberry32。seed が同じなら列も同じ(全端末で海図を一致させる要)。
function prng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function newVoyageSeed(): number {
  return Math.floor(Math.random() * 0x7fffffff);
}

/// 区間ヘルパー。中心と幅から、到着間際(>0.94)に食い込まない区間を作る。
function segment(kind: EncounterKind, center: number, span: number): RouteEncounter {
  const half = span / 2;
  const end = Math.min(center + half, 0.94);
  return { kind, start: Math.max(end - span, 0.05), end };
}

/// 経路点。港(左)から島(右)へ、中間3点を揺らした波形。
/// baseY は航路の基準の高さ(0..1)、rand で有機的に散らす。
function makePoints(rand: () => number, baseY: number): { x: number; y: number }[] {
  const jitter = () => (rand() - 0.5) * 0.16;
  return [
    { x: 0.06, y: 0.5 },
    { x: 0.28, y: baseY + jitter() },
    { x: 0.5, y: baseY + jitter() },
    { x: 0.72, y: baseY + jitter() },
    { x: 0.94, y: 0.48 },
  ];
}

/// seed から3航路(凪・嵐・深み)。並び順もseedで入れ替わる。
export function generateRoutes(seed: number): SeaRoute[] {
  const rand = prng(seed);

  const calm: SeaRoute = {
    archetype: "calm",
    encounters:
      rand() < 0.55
        ? [segment("storm", 0.38 + rand() * 0.26, 0.13)]
        : [],
    points: [],
  };
  const squall: SeaRoute = {
    archetype: "squall",
    encounters: [
      segment("storm", 0.24 + rand() * 0.1, 0.17),
      segment("storm", 0.6 + rand() * 0.14, 0.21),
    ],
    lootKey: "loot.moonlightSail",
    points: [],
  };
  const deep: SeaRoute = {
    archetype: "deep",
    encounters: [
      segment("storm", 0.26 + rand() * 0.08, 0.13),
      segment("kraken", 0.62 + rand() * 0.1, 0.25),
    ],
    lootKey: "loot.krakenFlag",
    points: [],
  };

  // 並び順(上・中・下のどこを通るか)を入れ替える。
  const routes = [calm, squall, deep];
  for (let i = routes.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [routes[i], routes[j]] = [routes[j], routes[i]];
  }
  const baseYs = [0.22, 0.5, 0.78];
  routes.forEach((route, i) => {
    route.points = makePoints(rand, baseYs[i]);
  });
  return routes;
}

/// 進捗率 frac のいま、立ちはだかっている遭遇(なければ null)。
export function activeEncounter(route: SeaRoute, frac: number): RouteEncounter | null {
  return route.encounters.find((e) => frac >= e.start && frac < e.end) ?? null;
}

/// 遭遇の中の潮目(0=満力 → 2=あと少し)。3D の縮み/薄れの段階に使う。
export function encounterPhase(enc: RouteEncounter, frac: number): number {
  const sub = (frac - enc.start) / Math.max(enc.end - enc.start, 0.001);
  return sub >= 2 / 3 ? 2 : sub >= 1 / 3 ? 1 : 0;
}

/// Catmull-Rom 補間で経路上の位置(t: 0..1)。海図の遭遇アイコン配置に使う。
export function routePointAt(route: SeaRoute, t: number): { x: number; y: number } {
  const pts = route.points;
  const n = pts.length - 1;
  const clamped = Math.min(Math.max(t, 0), 0.9999);
  const seg = Math.min(Math.floor(clamped * n), n - 1);
  const local = clamped * n - seg;
  const p0 = pts[Math.max(seg - 1, 0)];
  const p1 = pts[seg];
  const p2 = pts[seg + 1];
  const p3 = pts[Math.min(seg + 2, n)];
  const cr = (a: number, b: number, c: number, d: number, u: number) =>
    0.5 *
    (2 * b + (c - a) * u + (2 * a - 5 * b + 4 * c - d) * u * u + (3 * b - a - 3 * c + d) * u * u * u);
  return {
    x: cr(p0.x, p1.x, p2.x, p3.x, local),
    y: cr(p0.y, p1.y, p2.y, p3.y, local),
  };
}

/// 経路を滑らかな SVG パスに(Catmull-Rom → 三次ベジェ)。座標は任意スケール後の点列。
export function smoothPath(pts: { x: number; y: number }[]): string {
  if (pts.length < 2) return "";
  let d = `M ${pts[0].x.toFixed(1)} ${pts[0].y.toFixed(1)}`;
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[Math.max(i - 1, 0)];
    const p1 = pts[i];
    const p2 = pts[i + 1];
    const p3 = pts[Math.min(i + 2, pts.length - 1)];
    const c1x = p1.x + (p2.x - p0.x) / 6;
    const c1y = p1.y + (p2.y - p0.y) / 6;
    const c2x = p2.x - (p3.x - p1.x) / 6;
    const c2y = p2.y - (p3.y - p1.y) / 6;
    d += ` C ${c1x.toFixed(1)} ${c1y.toFixed(1)}, ${c2x.toFixed(1)} ${c2y.toFixed(1)}, ${p2.x.toFixed(1)} ${p2.y.toFixed(1)}`;
  }
  return d;
}
