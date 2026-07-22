import type { WrappedMonth, Archetype } from "./wrapped";
import {
  COMET_TAIL_PATH,
  MORNING_SUN_PATH,
  PHOENIX_PATH,
  STONE_BRIDGE_PATH,
  WAVE_RIDER_PATH,
} from "./symbols";

// 航海誌カードのPNG生成。canvasに直接描く(外部ライブラリ不使用)。
// 390x560 の絵はがきを2倍(780x1120)で描き、保存/共有する。

const W = 780;
const H = 1120;
const PAD = 72;
const FONT = "-apple-system, 'Hiragino Sans', 'Noto Sans JP', sans-serif";

export type CardKind = "days" | "voyage" | "archetype";

function newCanvas(): [HTMLCanvasElement, CanvasRenderingContext2D] {
  const canvas = document.createElement("canvas");
  canvas.width = W;
  canvas.height = H;
  const ctx = canvas.getContext("2d")!;
  return [canvas, ctx];
}

function roundedBg(ctx: CanvasRenderingContext2D, color: string) {
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.roundRect(0, 0, W, H, 40);
  ctx.fill();
}

function brand(ctx: CanvasRenderingContext2D, color: string) {
  ctx.fillStyle = color;
  ctx.font = `400 26px ${FONT}`;
  ctx.textAlign = "left";
  ctx.fillText("Landfall-StudyLog", PAD, H - 56);
}

function stat(
  ctx: CanvasRenderingContext2D,
  y: number,
  value: string,
  label: string,
  color: string,
) {
  ctx.fillStyle = color;
  ctx.textAlign = "left";
  ctx.font = `500 112px ${FONT}`;
  ctx.fillText(value, PAD, y);
  ctx.font = `400 30px ${FONT}`;
  ctx.fillText(label, PAD, y + 44);
}

export function drawCard(
  kind: CardKind,
  month: WrappedMonth,
  title: string,
  texts: {
    studied: string;
    rested: string;
    quit: string;
    total: string;
    returns: string;
    longestGap: string;
    typeName: string;
    tagline: string;
    subline: string;
  },
): HTMLCanvasElement {
  const [canvas, ctx] = newCanvas();

  if (kind === "days") {
    roundedBg(ctx, "#FFD84D");
    ctx.fillStyle = "#4A1B0C";
    ctx.font = `400 30px ${FONT}`;
    ctx.fillText(title, PAD, PAD + 30);
    stat(ctx, 340, String(month.studiedDays.size), texts.studied, "#141414");
    stat(ctx, 580, String(month.daysInMonth - month.studiedDays.size), texts.rested, "#141414");
    stat(ctx, 820, "0", texts.quit, "#141414");
    if (texts.total) {
      ctx.fillStyle = "#4A1B0C";
      ctx.font = `400 28px ${FONT}`;
      ctx.fillText(texts.total, PAD, H - 110);
    }
    brand(ctx, "rgba(20,20,20,0.4)");
  } else if (kind === "voyage") {
    roundedBg(ctx, "#F0997B");
    ctx.fillStyle = "#4A1B0C";
    ctx.font = `400 30px ${FONT}`;
    ctx.fillText(title, PAD, PAD + 30);
    // 日々の帯(8列)
    const cols = 8;
    const gap = 16;
    const cell = (W - PAD * 2 - gap * (cols - 1)) / cols;
    for (let day = 1; day <= month.daysInMonth; day++) {
      const i = day - 1;
      const x = PAD + (i % cols) * (cell + gap);
      const y = 200 + Math.floor(i / cols) * (44 + gap);
      ctx.fillStyle = month.studiedDays.has(day) ? "#4A1B0C" : "rgba(74,27,12,0.18)";
      ctx.beginPath();
      ctx.roundRect(x, y, cell, 44, 12);
      ctx.fill();
    }
    stat(ctx, 700, String(month.resumeCount), texts.returns, "#4A1B0C");
    if (month.longestGap) {
      stat(ctx, 920, String(month.longestGap.length), texts.longestGap, "#4A1B0C");
    }
    brand(ctx, "rgba(74,27,12,0.4)");
  } else {
    roundedBg(ctx, "#1A1130");
    drawArchetype(ctx, month.archetype);
    ctx.fillStyle = "#CECBF6";
    ctx.textAlign = "center";
    ctx.font = `500 52px ${FONT}`;
    ctx.fillText(texts.typeName, W / 2, 720);
    ctx.font = `400 32px ${FONT}`;
    ctx.fillText(texts.tagline, W / 2, 790);
    ctx.fillStyle = "rgba(206,203,246,0.7)";
    ctx.font = `400 26px ${FONT}`;
    ctx.fillText(texts.subline, W / 2, 838);
    ctx.textAlign = "left";
    brand(ctx, "rgba(206,203,246,0.4)");
  }
  return canvas;
}

/// タイプのシンボル(200x200設計座標)をカード中央上部に描く。
function drawArchetype(ctx: CanvasRenderingContext2D, archetype: Archetype) {
  const size = 300;
  ctx.save();
  ctx.translate((W - size) / 2, 260);
  ctx.scale(size / 200, size / 200);
  switch (archetype) {
    case "phoenix": {
      ctx.fillStyle = "#F0997B";
      ctx.fill(new Path2D(PHOENIX_PATH));
      ctx.fillStyle = "#1A1130";
      ctx.beginPath();
      ctx.arc(100, 50, 8, 0, Math.PI * 2);
      ctx.fill();
      break;
    }
    case "stoneBridge":
      ctx.fillStyle = "#5DCAA5";
      ctx.fill(new Path2D(STONE_BRIDGE_PATH));
      break;
    case "waveRider":
      ctx.fillStyle = "#CECBF6";
      ctx.fill(new Path2D(WAVE_RIDER_PATH));
      break;
    case "comet": {
      ctx.fillStyle = "#F5822A";
      ctx.fill(new Path2D(COMET_TAIL_PATH));
      ctx.fillStyle = "#FFD84D";
      ctx.beginPath();
      ctx.arc(64, 136, 34, 0, Math.PI * 2);
      ctx.fill();
      break;
    }
    default: {
      ctx.fillStyle = "#FFD84D";
      ctx.fill(new Path2D(MORNING_SUN_PATH));
      ctx.fillStyle = "#CECBF6";
      for (const [x, y, w, h] of [
        [8, 112, 184, 12],
        [54, 140, 92, 9],
        [80, 164, 40, 7],
      ] as const) {
        ctx.beginPath();
        ctx.roundRect(x, y, w, h, h / 2);
        ctx.fill();
      }
    }
  }
  ctx.restore();
}

/// 保存/共有。モバイルは共有シート、それ以外はPNGダウンロード。
export async function saveCanvas(canvas: HTMLCanvasElement, filename: string) {
  const blob = await new Promise<Blob | null>((resolve) =>
    canvas.toBlob(resolve, "image/png"),
  );
  if (!blob) return;
  const file = new File([blob], filename, { type: "image/png" });
  if (navigator.canShare?.({ files: [file] })) {
    try {
      await navigator.share({ files: [file] });
      return;
    } catch (err) {
      // 共有をやめた場合(AbortError)はダウンロードにも進まない。
      // それ以外(ジェスチャ切れ等)は無言で終わらせずダウンロードへ。
      if (err instanceof DOMException && err.name === "AbortError") return;
    }
  }
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 4000);
}
