import type { StudySession } from "./types";
import type { BoatParts } from "./symbols";

// 船のカスタマイズ。累計時間(全期間)で選べる部位が増えていく。
// ストリークではなく累計なので、休んでも失われない。選択はローカル保存。

export type BoatPart = "sail" | "jib" | "hull" | "stripe" | "flag";

export interface BoatOption {
  id: string;
  color?: string; // 色を持つ部位のみ("none"系は持たない)
  unlockMinutes: number;
}

export const BOAT_OPTIONS: Record<BoatPart, BoatOption[]> = {
  sail: [
    { id: "sand", color: "#EADEBD", unlockMinutes: 0 },
    { id: "coral", color: "#F0997B", unlockMinutes: 10 * 60 },
    { id: "sunYellow", color: "#FFD84D", unlockMinutes: 25 * 60 },
    { id: "seaGreen", color: "#5DCAA5", unlockMinutes: 50 * 60 },
    { id: "lavender", color: "#CECBF6", unlockMinutes: 100 * 60 },
  ],
  jib: [
    { id: "sand", color: "#EADEBD", unlockMinutes: 0 },
    { id: "seaGreen", color: "#5DCAA5", unlockMinutes: 5 * 60 },
    { id: "coral", color: "#F0997B", unlockMinutes: 20 * 60 },
    { id: "sunYellow", color: "#FFD84D", unlockMinutes: 40 * 60 },
    { id: "lavender", color: "#CECBF6", unlockMinutes: 80 * 60 },
  ],
  hull: [
    { id: "sand", color: "#EADEBD", unlockMinutes: 0 },
    { id: "coral", color: "#F0997B", unlockMinutes: 30 * 60 },
    { id: "deepRust", color: "#7A3B22", unlockMinutes: 60 * 60 },
  ],
  stripe: [
    { id: "none", unlockMinutes: 0 },
    { id: "returnOrange", color: "#F5822A", unlockMinutes: 20 * 60 },
    { id: "deepRust", color: "#4A1B0C", unlockMinutes: 45 * 60 },
  ],
  flag: [
    { id: "none", unlockMinutes: 0 },
    { id: "pennant", unlockMinutes: 15 * 60 },
    { id: "swallow", unlockMinutes: 40 * 60 },
  ],
};

const KEY = (part: BoatPart) => `boat.${part}`;

export function totalMinutes(sessions: StudySession[]): number {
  return sessions.reduce((sum, s) => sum + s.minutes, 0);
}

export function boatPartId(part: BoatPart): string {
  const saved = localStorage.getItem(KEY(part));
  return BOAT_OPTIONS[part].some((o) => o.id === saved) && saved
    ? saved
    : BOAT_OPTIONS[part][0].id;
}

export function setBoatPart(part: BoatPart, id: string) {
  localStorage.setItem(KEY(part), id);
}

/// BoatSvg / BoatGroup にそのまま渡せる、いまの船の見た目一式。
export function boatProps(): BoatParts {
  const color = (part: BoatPart) =>
    BOAT_OPTIONS[part].find((o) => o.id === boatPartId(part))?.color;
  return {
    sail: color("sail"),
    jib: color("jib"),
    hull: color("hull"),
    stripe: color("stripe") ?? "none",
    flag: boatPartId("flag"),
  };
}
