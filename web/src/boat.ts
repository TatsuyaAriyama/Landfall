import type { StudySession } from "./types";
import type { BoatParts } from "./symbols";

// 船のカスタマイズ。累計時間(全期間)で選べる部位が増えていく。
// ストリークではなく累計なので、休んでも失われない。選択はローカル保存。

export type BoatPart = "sail" | "jib" | "hull" | "stripe" | "flag";

export interface BoatOption {
  id: string;
  color?: string; // 色を持つ部位のみ("none"系は持たない)
  unlockMinutes: number;
  // 共同航海の戦利品。累計時間ではなく「その戦利品のある航路で島に
  // 着いた」ことで解放される(ローカルフラグに永続化)。
  lootKey?: LootKey;
}

export const BOAT_OPTIONS: Record<BoatPart, BoatOption[]> = {
  sail: [
    { id: "sand", color: "#EADEBD", unlockMinutes: 0 },
    { id: "coral", color: "#F0997B", unlockMinutes: 10 * 60 },
    { id: "sunYellow", color: "#FFD84D", unlockMinutes: 25 * 60 },
    { id: "seaGreen", color: "#5DCAA5", unlockMinutes: 50 * 60 },
    { id: "lavender", color: "#CECBF6", unlockMinutes: 100 * 60 },
    { id: "moonlight", color: "#F4F1EC", unlockMinutes: 0, lootKey: "loot.moonlightSail" },
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
    { id: "kraken", unlockMinutes: 0, lootKey: "loot.krakenFlag" },
  ],
};

const KEY = (part: BoatPart) => `boat.${part}`;

// ---- 共同航海の戦利品(ローカルフラグ) ----
// 到着を検知した時点(購読/起動時チェック)で立てる。港を出ても失われない。

export type LootKey = "loot.moonlightSail" | "loot.krakenFlag";

// 旧「港の試練」のフラグ。持っている人は両方の戦利品を解放済みとして扱う。
const LEGACY_LOOT_KEY = "loot.harborTrial";

export function hasLoot(key: LootKey): boolean {
  return (
    localStorage.getItem(key) === "1" || localStorage.getItem(LEGACY_LOOT_KEY) === "1"
  );
}

/// 戦利品を解放する。新規に解放されたときだけ true(トースト表示の判定に使う)。
export function grantLoot(key: LootKey): boolean {
  if (hasLoot(key)) return false;
  localStorage.setItem(key, "1");
  return true;
}

/// この部位オプションはいま選べるか(累計時間 or 航海の戦利品)。
export function isBoatOptionUnlocked(option: BoatOption, total: number): boolean {
  return option.lootKey ? hasLoot(option.lootKey) : total >= option.unlockMinutes;
}

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

// ---- 港への「見た目」の共有 ----
// 港のメンバードキュメントには色そのものではなく部位の id を書く
// (スキーマは docs/SCHEMA.md、検証は firestore.rules)。

/// 港のメンバードキュメントに載せる、いまの船の部位id一式。
export function boatShareData(): Record<string, string> {
  return {
    boatSail: boatPartId("sail"),
    boatJib: boatPartId("jib"),
    boatHull: boatPartId("hull"),
    boatStripe: boatPartId("stripe"),
    boatFlag: boatPartId("flag"),
  };
}

/// 共有された部位idを BoatParts(色)へ解決する。
/// 未知・欠損の id は各部位の既定(砂色/なし)に静かに落とす。
export function boatPartsFromIds(ids: {
  boatSail?: string;
  boatJib?: string;
  boatHull?: string;
  boatStripe?: string;
  boatFlag?: string;
}): BoatParts {
  const pick = (part: BoatPart, id: string | undefined): BoatOption =>
    BOAT_OPTIONS[part].find((o) => o.id === id) ?? BOAT_OPTIONS[part][0];
  return {
    sail: pick("sail", ids.boatSail).color,
    jib: pick("jib", ids.boatJib).color,
    hull: pick("hull", ids.boatHull).color,
    stripe: pick("stripe", ids.boatStripe).color ?? "none",
    flag: pick("flag", ids.boatFlag).id,
  };
}
