import { STYLE_COLORS, normalizeStyle, normalizeSymbol, type TileSymbolToken } from "./types";

// iOS の TileSymbolView(200x200 設計座標)を SVG に移植。フラット塗りのみ。
// fg/bg を注入してどの配色でも成立させる。

/// 羅針盤のロゼッタ。基本方位を長く、副方位を短く、8方向に。iOS CompassRoseShape と同じ式。
function compassRosePath(): string {
  const c = 100;
  const pt = (ang: number, r: number) =>
    `${c + Math.cos(ang) * r},${c - Math.sin(ang) * r}`;
  let d = "";
  for (let i = 0; i < 8; i++) {
    const tipAng = (i * Math.PI) / 4;
    const tipR = i % 2 === 0 ? 70 : 40;
    const valAng = tipAng + Math.PI / 8;
    d += (i === 0 ? "M " : "L ") + pt(tipAng, tipR) + " ";
    d += "L " + pt(valAng, 15) + " ";
  }
  return d + "Z";
}

const ROSE = compassRosePath();

export function TileSymbolSvg({
  symbol,
  fg,
  bg,
}: {
  symbol: TileSymbolToken;
  fg: string;
  bg: string;
}) {
  switch (symbol) {
    case "anchor":
      return (
        <svg viewBox="0 0 200 200" aria-hidden="true">
          <circle cx="100" cy="26" r="17" fill="none" stroke={fg} strokeWidth="11" />
          <rect x="92.5" y="36" width="15" height="120" rx="7.5" fill={fg} />
          <rect x="61" y="57.5" width="78" height="13" rx="6.5" fill={fg} />
          <path
            d="M 100 180 Q 40 178 30 110 L 50 126 Q 74 150 100 152 Q 126 150 150 126 L 170 110 Q 160 178 100 180 Z"
            fill={fg}
          />
        </svg>
      );
    case "compass":
      return (
        <svg viewBox="0 0 200 200" aria-hidden="true">
          <circle cx="100" cy="100" r="86" fill="none" stroke={fg} strokeWidth="7" />
          <path d={ROSE} fill={fg} />
          <circle cx="100" cy="100" r="10" fill={bg} />
        </svg>
      );
    case "wheel":
      return (
        <svg viewBox="0 0 200 200" aria-hidden="true">
          {[0, 45, 90, 135].map((a) => (
            <rect
              key={a}
              x="93.5"
              y="10"
              width="13"
              height="180"
              rx="6.5"
              fill={fg}
              transform={`rotate(${a} 100 100)`}
            />
          ))}
          <circle cx="100" cy="100" r="60" fill="none" stroke={fg} strokeWidth="13" />
          <circle cx="100" cy="100" r="20" fill={fg} />
          <circle cx="100" cy="100" r="7" fill={bg} />
        </svg>
      );
    case "lighthouse":
      return (
        <svg viewBox="0 0 200 200" aria-hidden="true">
          <path
            d="M 74 174 L 87 72 L 113 72 L 126 174 Z
               M 82 72 L 118 72 L 114 58 L 86 58 Z
               M 89 40 L 113 40 L 113 58 L 89 58 Z
               M 100 22 L 84 42 L 116 42 Z"
            fill={fg}
          />
          <rect x="65" y="171" width="70" height="14" rx="7" fill={fg} />
          <polygon points="49,41 49,57 75,49" fill={fg} />
          <polygon points="151,41 151,57 125,49" fill={fg} />
        </svg>
      );
    case "island":
      return (
        <svg viewBox="0 0 200 200" aria-hidden="true">
          <path
            d="M 24 150 Q 40 86 84 52 Q 112 66 120 110 Q 132 88 150 84 Q 168 120 176 150 L 24 150 Z"
            fill={fg}
          />
          <rect x="40" y="165" width="120" height="10" rx="5" fill={fg} />
        </svg>
      );
    case "phoenix":
      return (
        <svg viewBox="0 0 200 200" aria-hidden="true">
          <path
            d="M 100 12 Q 112 28 124 54 Q 172 58 193 98 Q 150 100 127 116
               Q 135 150 143 192 Q 112 162 100 148 Q 88 162 57 192 Q 65 150 73 116
               Q 50 100 7 98 Q 28 58 76 54 Q 88 28 100 12 Z"
            fill={fg}
          />
          <circle cx="100" cy="50" r="8" fill={bg} />
        </svg>
      );
    case "book":
      return (
        <svg viewBox="0 0 200 200" aria-hidden="true">
          <path
            d="M 100 52 Q 56 24 16 38 L 16 148 Q 56 136 100 164 Q 144 136 184 148 L 184 38 Q 144 24 100 52 Z"
            fill={fg}
          />
          <rect x="96" y="54" width="8" height="106" fill={fg} />
        </svg>
      );
    case "pen":
      return (
        <svg viewBox="0 0 200 200" aria-hidden="true">
          <g transform="rotate(38 100 100)">
            <rect x="83" y="18" width="34" height="132" rx="17" fill={fg} />
            <polygon points="83,142 117,142 100,182" fill={fg} />
          </g>
        </svg>
      );
  }
}

// iOS の既定アイコン「Harbor」= LandfallShape(帰る帆＋船体＋望む陸地の二つの丘)。
// 1024 設計座標をそのまま移植。harborTeal 地に harborSand 塗り。角丸は iOS の
// スーパー楕円マスクに寄せて 22.37%(≒229/1024)。favicon と同一図案。
const LANDFALL_PATH =
  // 陸地(大きな丸い丘＋小さな丘＋水平の底辺)
  "M430 748 Q452 512 556 386 Q590 350 624 386 Q676 486 705 612 " +
  "Q742 548 788 524 Q832 642 852 748 L430 748 Z " +
  // 帆(細く高い山型)
  "M318 386 Q376 524 404 668 L302 668 Q300 522 318 386 Z " +
  // 船体(帆の下の三日月)
  "M215 650 Q320 646 404 700 Q300 778 215 650 Z";

export function LandfallMark() {
  return (
    <svg viewBox="0 0 1024 1024" aria-hidden="true">
      <rect width="1024" height="1024" rx="229" fill="#184A40" />
      <path d={LANDFALL_PATH} fill="#EADEBD" fillRule="evenodd" />
    </svg>
  );
}

// サインイン画面「夜の入港」の部品。帆船と海岸はアイコン(LandfallShape)の
// 1024座標から切り出したシェイプ。harborTeal 地に harborSand 塗り、フラットのみ。

export const SAIL = "M318 386 Q376 524 404 668 L302 668 Q300 522 318 386 Z";
export const HULL = "M215 650 Q320 646 404 700 Q300 778 215 650 Z";
export const COAST =
  "M430 748 Q452 512 556 386 Q590 350 624 386 Q676 486 705 612 " +
  "Q742 548 788 524 Q832 642 852 748 L430 748 Z";

/// 入港する帆船(帆+船体)。帆の色と旗は船のカスタマイズ(累計時間で解放)に対応。
export function BoatSvg({
  sail = "#EADEBD",
  flag = "none",
}: {
  sail?: string;
  flag?: string;
} = {}) {
  return (
    <svg viewBox="215 335 190 402" aria-hidden="true">
      {flag === "pennant" && <polygon points="318,344 366,357 318,370" fill="#F5822A" />}
      {flag === "swallow" && (
        <polygon points="318,344 370,344 352,357 370,370 318,370" fill="#F0997B" />
      )}
      <path d={SAIL} fill={sail} />
      <path d={HULL} fill="#EADEBD" />
    </svg>
  );
}

/// 迎える海岸(二つの丘)。iOS と同じく横に引き伸ばして低い稜線にする。
export function CoastSvg() {
  return (
    <svg viewBox="430 340 422 408" preserveAspectRatio="none" aria-hidden="true">
      <path d={COAST} fill="#EADEBD" />
    </svg>
  );
}

// タイプ診断のシンボル(iOS ArchetypeSymbols の移植)。フラット塗りのみ。

export const PHOENIX_PATH =
  "M 100 12 Q 112 28 124 54 Q 172 58 193 98 Q 150 100 127 116 " +
  "Q 135 150 143 192 Q 112 162 100 148 Q 88 162 57 192 Q 65 150 73 116 " +
  "Q 50 100 7 98 Q 28 58 76 54 Q 88 28 100 12 Z";

export const STONE_BRIDGE_PATH =
  "M 6 72 Q 100 44 194 72 Q 192 116 198 160 L 160 160 L 160 114 " +
  "Q 158 94 136 92 Q 114 94 112 114 L 112 160 L 88 160 L 88 114 " +
  "Q 86 94 64 92 Q 42 94 40 114 L 40 160 L 2 160 Q 8 116 6 72 Z";

export const WAVE_RIDER_PATH =
  "M 12 172 Q 46 150 70 44 Q 120 18 150 60 Q 164 94 132 118 " +
  "Q 132 80 92 72 Q 104 162 190 172 Z";

export const COMET_TAIL_PATH = "M 40 112 Q 92 34 186 16 Q 142 92 88 160 Z";
export const MORNING_SUN_PATH = "M 48 114 A 52 52 0 0 1 152 114 Z";

export function ArchetypeSymbolSvg({ archetype }: { archetype: string }) {
  switch (archetype) {
    case "phoenix":
      return (
        <svg viewBox="0 0 200 200" aria-hidden="true">
          <path d={PHOENIX_PATH} fill="#F0997B" />
          <circle cx="100" cy="50" r="8" fill="#1A1130" />
        </svg>
      );
    case "stoneBridge":
      return (
        <svg viewBox="0 0 200 200" aria-hidden="true">
          <path d={STONE_BRIDGE_PATH} fill="#5DCAA5" />
        </svg>
      );
    case "waveRider":
      return (
        <svg viewBox="0 0 200 200" aria-hidden="true">
          <path d={WAVE_RIDER_PATH} fill="#CECBF6" />
        </svg>
      );
    case "comet":
      return (
        <svg viewBox="0 0 200 200" aria-hidden="true">
          <path d={COMET_TAIL_PATH} fill="#F5822A" />
          <circle cx="64" cy="136" r="34" fill="#FFD84D" />
        </svg>
      );
    default:
      // 朝凪: 昇る半円の太陽と、静かな水面の線。
      return (
        <svg viewBox="0 0 200 200" aria-hidden="true">
          <path d="M 48 114 A 52 52 0 0 1 152 114 Z" fill="#FFD84D" />
          <rect x="8" y="112" width="184" height="12" rx="6" fill="#CECBF6" />
          <rect x="54" y="140" width="92" height="9" rx="4.5" fill="#CECBF6" />
          <rect x="80" y="164" width="40" height="7" rx="3.5" fill="#CECBF6" />
        </svg>
      );
  }
}

/// 丸いプレイヤーアイコン。項目タイル(角丸四角)と区別するため円にする(iOS と同じ)。
export function PlayerAvatar({
  styleToken,
  symbolToken,
  size,
}: {
  styleToken: string;
  symbolToken: string;
  size: number;
}) {
  const style = STYLE_COLORS[normalizeStyle(styleToken)];
  return (
    <span
      aria-hidden="true"
      style={{
        width: size,
        height: size,
        borderRadius: "50%",
        background: style.bg,
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        flex: "none",
      }}
    >
      <span style={{ width: size * 0.56, height: size * 0.56, display: "inline-flex" }}>
        <TileSymbolSvg symbol={normalizeSymbol(symbolToken)} fg={style.fg} bg={style.bg} />
      </span>
    </span>
  );
}

/// アプリのブランドマーク。iOS の既定アイコンと同一図案。
export function BrandMark({ size }: { size: number }) {
  return (
    <span
      style={{ display: "inline-flex", width: size, height: size }}
      aria-hidden="true"
    >
      <LandfallMark />
    </span>
  );
}
