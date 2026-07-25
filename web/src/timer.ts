// 作業の計測(ストップウォッチ)。記録は「手で分数を入れる」のではなく、
// 作業をはじめた時刻を控えて経過を数える方式を主とする。
//
// 控えるのは「はじめた時刻」だけ。経過は常に現在時刻との差から求めるので、
// 再読込しても、タブを閉じていた間も、時間は失われない。

const TIMER_ITEM_KEY = "timer.itemId";
const TIMER_START_KEY = "timer.startedAt";
const TIMER_MODE_KEY = "timer.mode";

export type TimerMode = "free" | "pomo";

// ポモドーロ: 25分の集中+5分の休憩を繰り返す。数えるのは集中の分だけ。
export const POMO_WORK = 25 * 60;
export const POMO_CYCLE = 30 * 60;

export interface RunningTimer {
  itemId: string;
  startedAt: number; // epoch ms
  mode: TimerMode;
}

export function readTimer(): RunningTimer | null {
  const itemId = localStorage.getItem(TIMER_ITEM_KEY);
  const startedAt = Number(localStorage.getItem(TIMER_START_KEY) ?? 0);
  const mode: TimerMode = localStorage.getItem(TIMER_MODE_KEY) === "pomo" ? "pomo" : "free";
  return itemId && startedAt > 0 ? { itemId, startedAt, mode } : null;
}

export function writeTimer(t: RunningTimer): void {
  localStorage.setItem(TIMER_ITEM_KEY, t.itemId);
  localStorage.setItem(TIMER_START_KEY, String(t.startedAt));
  localStorage.setItem(TIMER_MODE_KEY, t.mode);
}

export function eraseTimer(): void {
  localStorage.removeItem(TIMER_ITEM_KEY);
  localStorage.removeItem(TIMER_START_KEY);
  localStorage.removeItem(TIMER_MODE_KEY);
}

/// ポモドーロで実際に集中していた秒数(休憩は数えない)。
export function pomoWorkedSec(elapsedSec: number): number {
  const cycles = Math.floor(elapsedSec / POMO_CYCLE);
  return cycles * POMO_WORK + Math.min(elapsedSec % POMO_CYCLE, POMO_WORK);
}

/// 記録する分数。自由計測はそのまま、ポモドーロは集中していた分だけ。
/// 1分未満でも「0分の記録」は作らず1分にする。上限は記録側と同じ6000分。
export function creditedMinutes(t: RunningTimer, at: number = Date.now()): number {
  const elapsedSec = Math.max(0, Math.floor((at - t.startedAt) / 1000));
  const workedSec = t.mode === "pomo" ? pomoWorkedSec(elapsedSec) : elapsedSec;
  return Math.min(Math.max(1, Math.round(workedSec / 60)), 6000);
}

/// 経過秒。表示はすべてここを通す。
export function elapsedSec(t: RunningTimer, at: number = Date.now()): number {
  return Math.max(0, Math.floor((at - t.startedAt) / 1000));
}

/// ポモドーロのいまの局面。集中か休憩か、その局面の残り秒。
export interface PomoPhase {
  inFocus: boolean;
  left: number;
  /// 局面が変わったことを検知するための鍵(周回数+集中/休憩)。
  key: string;
}

export function pomoPhase(sec: number): PomoPhase {
  const rem = sec % POMO_CYCLE;
  const inFocus = rem < POMO_WORK;
  return {
    inFocus,
    left: inFocus ? POMO_WORK - rem : POMO_CYCLE - rem,
    key: `${Math.floor(sec / POMO_CYCLE)}-${inFocus ? "f" : "b"}`,
  };
}

/// 時計表示。1時間を超えたら H:MM:SS、それまでは MM:SS。
export function clockLabel(sec: number): string {
  const s = Math.max(0, Math.floor(sec));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const r = s % 60;
  const mm = String(m).padStart(2, "0");
  const ss = String(r).padStart(2, "0");
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}
