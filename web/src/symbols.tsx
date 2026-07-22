import type { TileSymbolToken } from "./types";

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

/// アプリのブランドマーク(島+水面、harborTeal 地)。favicon と同じ図案。
export function BrandMark({ size }: { size: number }) {
  return (
    <svg viewBox="0 0 200 200" width={size} height={size} aria-hidden="true">
      <rect width="200" height="200" rx="44" fill="#184A40" />
      <path
        d="M 24 150 Q 40 86 84 52 Q 112 66 120 110 Q 132 88 150 84 Q 168 120 176 150 L 24 150 Z"
        fill="#EADEBD"
      />
      <rect x="40" y="165" width="120" height="10" rx="5" fill="#EADEBD" />
    </svg>
  );
}
