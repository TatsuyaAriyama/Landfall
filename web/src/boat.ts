import type { StudySession } from "./types";

// 船のカスタマイズ。累計時間(全期間)で帆の色と旗が増えていく。
// ストリークではなく累計なので、休んでも失われない。選択はローカル保存。

const SAIL_KEY = "boat.sail";
const FLAG_KEY = "boat.flag";

export interface BoatOption {
  id: string;
  color?: string; // 帆の色(旗は色を持たない)
  unlockMinutes: number; // 解放に必要な累計(分)
}

export const SAIL_OPTIONS: BoatOption[] = [
  { id: "sand", color: "#EADEBD", unlockMinutes: 0 },
  { id: "coral", color: "#F0997B", unlockMinutes: 10 * 60 },
  { id: "sunYellow", color: "#FFD84D", unlockMinutes: 25 * 60 },
  { id: "seaGreen", color: "#5DCAA5", unlockMinutes: 50 * 60 },
  { id: "lavender", color: "#CECBF6", unlockMinutes: 100 * 60 },
];

export const FLAG_OPTIONS: BoatOption[] = [
  { id: "none", unlockMinutes: 0 },
  { id: "pennant", unlockMinutes: 15 * 60 },
  { id: "swallow", unlockMinutes: 40 * 60 },
];

export function totalMinutes(sessions: StudySession[]): number {
  return sessions.reduce((sum, s) => sum + s.minutes, 0);
}

export function boatSail(): string {
  const id = localStorage.getItem(SAIL_KEY) ?? "sand";
  return SAIL_OPTIONS.find((o) => o.id === id)?.color ?? "#EADEBD";
}

export function boatFlag(): string {
  return localStorage.getItem(FLAG_KEY) ?? "none";
}

export function setBoat(sailId: string, flagId: string) {
  localStorage.setItem(SAIL_KEY, sailId);
  localStorage.setItem(FLAG_KEY, flagId);
}

export function boatSailId(): string {
  return localStorage.getItem(SAIL_KEY) ?? "sand";
}
