export const PCCS_TONES = [
  { id: "v", nameJa: "鮮やか", nameEn: "Vivid", saturation: 0.88, value: 0.88 },
  { id: "b", nameJa: "明るい", nameEn: "Bright", saturation: 0.72, value: 0.96 },
  { id: "s", nameJa: "強い", nameEn: "Strong", saturation: 0.72, value: 0.78 },
  { id: "dp", nameJa: "深い", nameEn: "Deep", saturation: 0.78, value: 0.62 },
  { id: "lt", nameJa: "軽い", nameEn: "Light", saturation: 0.42, value: 0.96 },
  { id: "sf", nameJa: "柔らかい", nameEn: "Soft", saturation: 0.42, value: 0.78 },
  { id: "d", nameJa: "鈍い", nameEn: "Dull", saturation: 0.45, value: 0.62 },
  { id: "dk", nameJa: "暗い", nameEn: "Dark", saturation: 0.55, value: 0.42 },
  { id: "p", nameJa: "淡い", nameEn: "Pale", saturation: 0.22, value: 0.97 },
  { id: "ltg", nameJa: "明るい灰み", nameEn: "Light grayish", saturation: 0.22, value: 0.78 },
  { id: "g", nameJa: "灰み", nameEn: "Grayish", saturation: 0.25, value: 0.60 },
  { id: "dkg", nameJa: "暗い灰み", nameEn: "Dark grayish", saturation: 0.28, value: 0.40 },
] as const;

export type PccsToneId = (typeof PCCS_TONES)[number]["id"];

// PCCSの24色相を、画面上で隣り合う色が自然につながるようsRGB上へ写像する。
// 色票そのものの再現ではなく、作業項目の識別に使うデジタル表示用の近似値。
const PCCS_HUE_DEGREES = [
  350, 5, 20, 35, 50, 60, 72, 88, 105, 125, 145, 165,
  180, 195, 210, 225, 240, 255, 270, 285, 300, 315, 330, 340,
] as const;

export const PCCS_HUES = PCCS_HUE_DEGREES.map((degrees, index) => ({
  number: index + 1,
  degrees,
}));

export interface PccsSelection {
  tone: PccsToneId;
  hue: number;
}

export interface FreeColorSelection {
  hue: number;
  saturation: number;
  value: number;
}

export function pccsToken(tone: PccsToneId, hue: number): string {
  return `pccs-${tone}-${String(Math.min(24, Math.max(1, hue))).padStart(2, "0")}`;
}

export function parsePccsToken(token: string): PccsSelection | null {
  const match = /^pccs-([a-z]+)-(\d{2})$/.exec(token);
  if (!match) return null;
  const tone = PCCS_TONES.find((candidate) => candidate.id === match[1])?.id;
  const hue = Number(match[2]);
  return tone && hue >= 1 && hue <= 24 ? { tone, hue } : null;
}

export function hsvToRgb(hue: number, saturation: number, value: number) {
  const chroma = value * saturation;
  const section = (((hue % 360) + 360) % 360) / 60;
  const x = chroma * (1 - Math.abs((section % 2) - 1));
  const [r1, g1, b1] =
    section < 1 ? [chroma, x, 0] :
    section < 2 ? [x, chroma, 0] :
    section < 3 ? [0, chroma, x] :
    section < 4 ? [0, x, chroma] :
    section < 5 ? [x, 0, chroma] :
    [chroma, 0, x];
  const offset = value - chroma;
  return [r1 + offset, g1 + offset, b1 + offset] as const;
}

export function rgbToHex(rgb: readonly number[]): string {
  return `#${rgb
    .map((channel) => Math.round(channel * 255).toString(16).padStart(2, "0"))
    .join("")
    .toUpperCase()}`;
}

export function pccsColor(selection: PccsSelection): string {
  const tone = PCCS_TONES.find((candidate) => candidate.id === selection.tone) ?? PCCS_TONES[0];
  const hue = PCCS_HUES[selection.hue - 1] ?? PCCS_HUES[1];
  return rgbToHex(hsvToRgb(hue.degrees, tone.saturation, tone.value));
}

export function readableForeground(background: string): string {
  const channels = background
    .slice(1)
    .match(/.{2}/g)
    ?.map((pair) => Number.parseInt(pair, 16) / 255);
  if (!channels || channels.length !== 3) return "#F4F1EC";
  const linear = channels.map((channel) =>
    channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4,
  );
  const luminance = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
  return luminance > 0.38 ? "#141414" : "#F4F1EC";
}

export function pccsStyle(selection: PccsSelection) {
  const bg = pccsColor(selection);
  return { bg, fg: readableForeground(bg) };
}

export function pccsToFreeColor(selection: PccsSelection): FreeColorSelection {
  const tone = PCCS_TONES.find((candidate) => candidate.id === selection.tone) ?? PCCS_TONES[0];
  const hue = PCCS_HUES[selection.hue - 1] ?? PCCS_HUES[1];
  return { hue: hue.degrees, saturation: tone.saturation, value: tone.value };
}

export function freeColorToken(selection: FreeColorSelection): string {
  const hue = Math.round(((selection.hue % 360) + 360) % 360);
  const saturation = Math.round(Math.min(1, Math.max(0, selection.saturation)) * 100);
  const value = Math.round(Math.min(1, Math.max(0.18, selection.value)) * 100);
  return `sea-${String(hue).padStart(3, "0")}-${String(saturation).padStart(3, "0")}-${String(value).padStart(3, "0")}`;
}

export function parseFreeColorToken(token: string): FreeColorSelection | null {
  const match = /^sea-(\d{3})-(\d{3})-(\d{3})$/.exec(token);
  if (!match) return null;
  const hue = Number(match[1]);
  const saturation = Number(match[2]);
  const value = Number(match[3]);
  if (hue > 359 || saturation > 100 || value < 18 || value > 100) return null;
  return { hue, saturation: saturation / 100, value: value / 100 };
}

export function freeColor(selection: FreeColorSelection): string {
  return rgbToHex(hsvToRgb(selection.hue, selection.saturation, selection.value));
}

export function freeColorStyle(selection: FreeColorSelection) {
  const bg = freeColor(selection);
  return { bg, fg: readableForeground(bg) };
}

export function nearestPccs(selection: FreeColorSelection): PccsSelection {
  let best = { tone: PCCS_TONES[0].id, hue: 1 } as PccsSelection;
  let bestDistance = Number.POSITIVE_INFINITY;
  for (const tone of PCCS_TONES) {
    for (const hue of PCCS_HUES) {
      const hueDistance = Math.min(
        Math.abs(hue.degrees - selection.hue),
        360 - Math.abs(hue.degrees - selection.hue),
      ) / 180;
      const distance =
        hueDistance ** 2 +
        (tone.saturation - selection.saturation) ** 2 * 0.7 +
        (tone.value - selection.value) ** 2 * 0.7;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = { tone: tone.id, hue: hue.number };
      }
    }
  }
  return best;
}
