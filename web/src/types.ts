// Firestore スキーマ(docs/SCHEMA.md)に対応する型とデザイントークン。

/// 項目タイルで選べる配色。グリッドは一覧性が命なので、ここは意図的に増やさない。
export const TILE_STYLES = [
  "midnight",
  "coral",
  "ink",
  "seaGreen",
  "violet",
  "sunYellow",
] as const;
export type TileStyleToken = (typeof TILE_STYLES)[number];

/// プレイヤーカードで選べる配色。タイルの6色に加えて、既存のブランド色から
/// 組んだ6色を足す(新しい色は増やさない — パレットの外に出ない)。
/// 港のカードは一人一枚なので、タイルより多くても画面は散らからない。
export const PROFILE_STYLES = [
  ...TILE_STYLES,
  "harbor",
  "sand",
  "ember",
  "rust",
  "lavender",
  "sunrise",
] as const;
export type ProfileStyleToken = (typeof PROFILE_STYLES)[number];

export const TILE_SYMBOLS = [
  "anchor",
  "compass",
  "wheel",
  "lighthouse",
  "island",
  "phoenix",
  "book",
  "pen",
  "sailboat",
  "attire",
] as const;
export type TileSymbolToken = (typeof TILE_SYMBOLS)[number];

export function normalizeStyle(token: string): TileStyleToken {
  return (TILE_STYLES as readonly string[]).includes(token)
    ? (token as TileStyleToken)
    : "midnight";
}

/// プレイヤーカードの配色。タイルより語彙が広い。
/// 相手が新しいクライアントで選んだ色も、こちらが知らなければ midnight に落ちる。
export function normalizeProfileStyle(token: string): ProfileStyleToken {
  return (PROFILE_STYLES as readonly string[]).includes(token)
    ? (token as ProfileStyleToken)
    : "midnight";
}

/// 旧トークンの移行(波→錨・彗星→羅針盤・朝日→灯台)。iOS の TileSymbol.from と同じ。
export function normalizeSymbol(token: string): TileSymbolToken {
  switch (token) {
    case "wave":
      return "anchor";
    case "comet":
      return "compass";
    case "sun":
      return "lighthouse";
    default:
      return (TILE_SYMBOLS as readonly string[]).includes(token)
        ? (token as TileSymbolToken)
        : "compass";
  }
}

/// 配色(背景/前景)。iOS の TileStyle と同じ組み。ink の背景だけ明暗に追従。
/// 前半6色はタイルとカード共用、後半6色はプレイヤーカード専用。
export const STYLE_COLORS: Record<ProfileStyleToken, { bg: string; fg: string }> = {
  midnight: { bg: "#1A1130", fg: "#F0997B" },
  coral: { bg: "#F0997B", fg: "#4A1B0C" },
  ink: { bg: "var(--tile-ink)", fg: "#FFD84D" },
  seaGreen: { bg: "#5DCAA5", fg: "#1A1130" },
  violet: { bg: "#534AB7", fg: "#CECBF6" },
  sunYellow: { bg: "#FFD84D", fg: "#4A1B0C" },
  harbor: { bg: "#184A40", fg: "#EADEBD" },
  sand: { bg: "#EADEBD", fg: "#4A1B0C" },
  ember: { bg: "#F3C065", fg: "#4A1B0C" },
  rust: { bg: "#4A1B0C", fg: "#F3C065" },
  lavender: { bg: "#CECBF6", fg: "#534AB7" },
  sunrise: { bg: "#F5822A", fg: "#1A1130" },
};

export interface StudyItem {
  id: string; // UUID(大文字)
  name: string;
  styleToken: string;
  symbolToken: string;
  sortOrder: number;
  createdAt: Date;
  updatedAt: Date;
}

export interface StudySession {
  id: string; // UUID(大文字)
  date: Date;
  minutes: number;
  note?: string;
  itemUUID?: string;
  updatedAt: Date;
}

export interface StudyDay {
  id: string; // yyyy-MM-dd
  date: Date;
  note?: string;
  updatedAt: Date;
}

/// 日の docID(yyyy-MM-dd、端末ローカルのタイムゾーン)。iOS の dayDocID と同じ。
export function dayId(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

export function startOfDay(date: Date): Date {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  return d;
}

export function newUUID(): string {
  return crypto.randomUUID().toUpperCase();
}

/// 前後の空白を除く。JS の String.trim は全角スペース(U+3000)を残すため、
/// あらゆる空白文字(全角スペース・タブ・改行含む)を対象にする。
export function trimAll(value: string): string {
  return value.replace(/^[\s　]+|[\s　]+$/g, "");
}
