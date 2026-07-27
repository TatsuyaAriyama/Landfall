// 作業の計測(ストップウォッチ)。記録は「手で分数を入れる」のではなく、
// 作業をはじめた時刻を控えて経過を数える方式を主とする。
//
// 控えるのは「はじめた時刻」だけ。経過は常に現在時刻との差から求めるので、
// 再読込しても、タブを閉じていた間も、時間は失われない。

import { storage } from "./storage";

const TIMER_ITEM_KEY = "timer.itemId";
const TIMER_START_KEY = "timer.startedAt";
const TIMER_MODE_KEY = "timer.mode";
const TIMER_BREAK_MS_KEY = "timer.breakMs";
const TIMER_BREAK_AT_KEY = "timer.breakStartedAt";

export type TimerMode = "free" | "pomo";

// ポモドーロ: 25分の集中+5分の休憩を繰り返す。数えるのは集中の分だけ。
export const POMO_WORK = 25 * 60;
export const POMO_CYCLE = 30 * 60;

export interface RunningTimer {
  itemId: string;
  startedAt: number; // epoch ms
  mode: TimerMode;
  /// 休憩で止めていた合計ミリ秒(すでに終わった休憩ぶん)。
  breakMs: number;
  /// いま休憩中なら、その休憩をはじめた時刻。休んでいなければ null。
  breakStartedAt: number | null;
}

export function readTimer(): RunningTimer | null {
  const itemId = storage.get(TIMER_ITEM_KEY);
  const startedAt = Number(storage.get(TIMER_START_KEY) ?? 0);
  const mode: TimerMode = storage.get(TIMER_MODE_KEY) === "pomo" ? "pomo" : "free";
  // 休憩の欄が無い航海(この機能より前から走っているもの)は、休んでいない扱い。
  const breakMs = Number(storage.get(TIMER_BREAK_MS_KEY) ?? 0);
  const breakAt = Number(storage.get(TIMER_BREAK_AT_KEY) ?? 0);
  return itemId && startedAt > 0
    ? {
        itemId,
        startedAt,
        mode,
        breakMs: Number.isFinite(breakMs) && breakMs > 0 ? breakMs : 0,
        breakStartedAt: Number.isFinite(breakAt) && breakAt > 0 ? breakAt : null,
      }
    : null;
}

export function writeTimer(t: RunningTimer): void {
  storage.set(TIMER_ITEM_KEY, t.itemId);
  storage.set(TIMER_START_KEY, String(t.startedAt));
  storage.set(TIMER_MODE_KEY, t.mode);
  storage.set(TIMER_BREAK_MS_KEY, String(Math.max(0, Math.round(t.breakMs))));
  if (t.breakStartedAt) {
    storage.set(TIMER_BREAK_AT_KEY, String(t.breakStartedAt));
  } else {
    storage.remove(TIMER_BREAK_AT_KEY);
  }
}

export function eraseTimer(): void {
  storage.remove(TIMER_ITEM_KEY);
  storage.remove(TIMER_START_KEY);
  storage.remove(TIMER_MODE_KEY);
  storage.remove(TIMER_BREAK_MS_KEY);
  storage.remove(TIMER_BREAK_AT_KEY);
}

/// いま休憩中か(錨を下ろしているか)。
export function isOnBreak(t: RunningTimer): boolean {
  return t.breakStartedAt !== null;
}

/// 休憩に入る。時計はここで止まる。
export function startBreak(t: RunningTimer, at: number = Date.now()): RunningTimer {
  return isOnBreak(t) ? t : { ...t, breakStartedAt: at };
}

/// 休憩をおえる。休んでいた長さを溜めておき、時計を動かし直す。
export function endBreak(t: RunningTimer, at: number = Date.now()): RunningTimer {
  if (t.breakStartedAt === null) return t;
  return {
    ...t,
    breakMs: t.breakMs + Math.max(0, at - t.breakStartedAt),
    breakStartedAt: null,
  };
}

/// ポモドーロで実際に集中していた秒数(休憩は数えない)。
export function pomoWorkedSec(elapsedSec: number): number {
  const cycles = Math.floor(elapsedSec / POMO_CYCLE);
  return cycles * POMO_WORK + Math.min(elapsedSec % POMO_CYCLE, POMO_WORK);
}

/// 記録する分数。自由計測はそのまま、ポモドーロは集中していた分だけ。
/// 1分未満でも「0分の記録」は作らず1分にする。上限は記録側と同じ6000分。
export function creditedMinutes(t: RunningTimer, at: number = Date.now()): number {
  const sec = elapsedSec(t, at);
  const workedSec = t.mode === "pomo" ? pomoWorkedSec(sec) : sec;
  return Math.min(Math.max(1, Math.round(workedSec / 60)), 6000);
}

/// 経過秒。表示も記録もすべてここを通す。
/// 休憩していた時間は差し引く — 休んでいた分を作業時間として記録するのは嘘になる。
/// 控えるのは時刻だけなので、休憩したまま再読込しても数え方は変わらない。
export function elapsedSec(t: RunningTimer, at: number = Date.now()): number {
  const resting = t.breakStartedAt === null ? 0 : Math.max(0, at - t.breakStartedAt);
  return Math.max(0, Math.floor((at - t.startedAt - t.breakMs - resting) / 1000));
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
