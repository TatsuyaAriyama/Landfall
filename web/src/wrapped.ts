import type { StudyDay, StudySession } from "./types";

// 航海誌(Wrapped)の月次統計とタイプ診断。iOS の MonthStats / WrappedMonth の移植。
// すべて純粋関数。判定順・しきい値は iOS と完全に一致させる。

export type Archetype = "phoenix" | "stoneBridge" | "waveRider" | "comet" | "morningCalm";

export interface GapSpan {
  startDay: number;
  length: number;
}

export interface WrappedMonth {
  year: number;
  month: number; // 1-based
  daysInMonth: number;
  studiedDays: Set<number>;
  archetype: Archetype;
  totalMinutes: number;
  gaps: GapSpan[];
  significantGaps: GapSpan[]; // 2日以上(定義上すべて帰還済み)
  openTrailingGap: GapSpan | null; // 月末まで続く未帰還の空白(2日以上)
  resumeCount: number; // 帰還した回数
  longestGap: GapSpan | null;
}

function daysInMonth(year: number, month: number): number {
  return new Date(year, month, 0).getDate();
}

export function studiedDaySet(year: number, month: number, entries: StudyDay[]): Set<number> {
  const days = new Set<number>();
  for (const e of entries) {
    if (e.date.getFullYear() === year && e.date.getMonth() + 1 === month) {
      days.add(e.date.getDate());
    }
  }
  return days;
}

function computeGaps(studied: Set<number>): GapSpan[] {
  const sorted = [...studied].sort((a, b) => a - b);
  const result: GapSpan[] = [];
  for (let i = 1; i < sorted.length; i++) {
    const a = sorted[i - 1];
    const b = sorted[i];
    if (b - a > 1) result.push({ startDay: a + 1, length: b - a - 1 });
  }
  return result;
}

function longestStreak(studied: Set<number>): number {
  const sorted = [...studied].sort((a, b) => a - b);
  if (sorted.length === 0) return 0;
  let best = 1;
  let current = 1;
  for (let i = 1; i < sorted.length; i++) {
    if (sorted[i] === sorted[i - 1] + 1) {
      current++;
      best = Math.max(best, current);
    } else {
      current = 1;
    }
  }
  return best;
}

/// 波乗り型: 学習した週が3週以上、月内に完全に含まれる週はすべて学習あり、
/// 学習週ごとの学習日数の最大-最小が1以下。週は日曜始まり。
function isWaveRider(
  year: number,
  month: number,
  studied: Set<number>,
  dayCount: number,
): boolean {
  if (studied.size === 0) return false;
  const weekDays = new Map<string, number[]>();
  for (let day = 1; day <= dayCount; day++) {
    const date = new Date(year, month - 1, day);
    const weekStart = new Date(date);
    weekStart.setDate(date.getDate() - date.getDay());
    const key = `${weekStart.getFullYear()}-${weekStart.getMonth()}-${weekStart.getDate()}`;
    const list = weekDays.get(key) ?? [];
    list.push(day);
    weekDays.set(key, list);
  }
  const studiedCounts: number[] = [];
  for (const days of weekDays.values()) {
    const count = days.filter((d) => studied.has(d)).length;
    if (count > 0) studiedCounts.push(count);
  }
  if (studiedCounts.length < 3) return false;
  for (const days of weekDays.values()) {
    if (days.length === 7 && !days.some((d) => studied.has(d))) return false;
  }
  return Math.max(...studiedCounts) - Math.min(...studiedCounts) <= 1;
}

/// タイプ診断。上から順に最初に該当したタイプを返す。全タイプ肯定的。
export function diagnose(year: number, month: number, studied: Set<number>): Archetype {
  const dayCount = daysInMonth(year, month);
  const gaps = computeGaps(studied);
  const significant = gaps.filter((g) => g.length >= 2);
  const last = studied.size > 0 ? Math.max(...studied) : 0;
  const trailing = studied.size > 0 && dayCount - last >= 2 ? dayCount - last : 0;

  if (significant.some((g) => g.length >= 5)) return "phoenix";
  if (studied.size > 0 && gaps.every((g) => g.length <= 2) && trailing <= 2) {
    return "stoneBridge";
  }
  if (isWaveRider(year, month, studied, dayCount)) return "waveRider";
  if (studied.size >= 3 && longestStreak(studied) / studied.size >= 0.7) return "comet";
  return "morningCalm";
}

export function wrappedMonth(
  year: number,
  month: number,
  entries: StudyDay[],
  sessions: StudySession[],
): WrappedMonth {
  const studied = studiedDaySet(year, month, entries);
  const dayCount = daysInMonth(year, month);
  const gaps = computeGaps(studied);
  const significantGaps = gaps.filter((g) => g.length >= 2);
  const last = studied.size > 0 ? Math.max(...studied) : 0;
  const openTrailingGap: GapSpan | null =
    studied.size > 0 && dayCount - last >= 2
      ? { startDay: last + 1, length: dayCount - last }
      : null;
  const totalMinutes = sessions.reduce((sum, s) => {
    return s.date.getFullYear() === year && s.date.getMonth() + 1 === month
      ? sum + s.minutes
      : sum;
  }, 0);
  return {
    year,
    month,
    daysInMonth: dayCount,
    studiedDays: studied,
    archetype: diagnose(year, month, studied),
    totalMinutes,
    gaps,
    significantGaps,
    openTrailingGap,
    resumeCount: significantGaps.length,
    longestGap:
      significantGaps.length > 0
        ? significantGaps.reduce((a, b) => (b.length > a.length ? b : a))
        : null,
  };
}

export interface YearMonth {
  year: number;
  month: number; // 1-based
}

/// 航海誌を閲覧できる月。記録が1日以上ある月Mについて、今日が「Mの最終日」以上なら
/// 閲覧可能(過去分は無期限に残る)。新しい順。iOS の completedWrappedMonths と同じ。
export function completedWrappedMonths(entries: StudyDay[], today: Date): YearMonth[] {
  const t = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const seen = new Map<string, YearMonth>();
  for (const e of entries) {
    const ym = { year: e.date.getFullYear(), month: e.date.getMonth() + 1 };
    seen.set(`${ym.year}-${ym.month}`, ym);
  }
  const result: YearMonth[] = [];
  for (const ym of seen.values()) {
    const lastDay = new Date(ym.year, ym.month, 0);
    if (t >= new Date(lastDay.getFullYear(), lastDay.getMonth(), lastDay.getDate())) {
      result.push(ym);
    }
  }
  return result.sort((a, b) => (a.year !== b.year ? b.year - a.year : b.month - a.month));
}
