// Renders Landfall's 4 Wrapped share cards to PNG for store listing / ad
// use, without needing Xcode. It re-implements the SwiftUI views in
// Landfall/Views/Wrapped/*.swift as HTML/CSS/SVG using the same design
// tokens (Landfall/Design/Theme.swift) and the same dummy month
// (WrappedMonth.dummy), then rasterizes each card at the app's 3x export
// scale with headless Chromium.
//
// This is a visual approximation, not a build of the real Swift views —
// useful for marketing assets, but for the actual App Store screenshots
// prefer exporting from the app itself (Share button on a Wrapped card)
// or Tools/RenderHarness/RenderCard.swift on macOS, which use the real
// SwiftUI renderer and system font.
//
// Usage:
//   npm install --no-save playwright
//   node render-wrapped-cards.js [outDir]

const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');

const SCALE = 3;
const pt = (v) => v * SCALE;

const COLOR = {
  ink: '#141414',
  paper: '#FFFFFF',
  sunYellow: '#FFD84D',
  seaGreen: '#5DCAA5',
  coral: '#F0997B',
  deepRust: '#4A1B0C',
  midnight: '#1A1130',
  lavender: '#CECBF6',
  violet: '#534AB7',
  returnOrange: '#F5822A',
};

// ---- WrappedMonth.dummy (Landfall/Models/WrappedMonth.swift) ----
const month = {
  year: 2026,
  month: 5,
  daysInMonth: 31,
  studiedDays: new Set([1, 2, 3, 10, 11, 14, 15, 16, 22, 23, 24, 25, 29, 30]),
  archetype: 'phoenix',
};
month.studiedCount = month.studiedDays.size;
month.restedCount = month.daysInMonth - month.studiedCount;
month.quitCount = 0;

function gaps(m) {
  const sorted = [...m.studiedDays].sort((a, b) => a - b);
  const result = [];
  for (let i = 0; i < sorted.length - 1; i++) {
    const a = sorted[i], b = sorted[i + 1];
    if (b - a > 1) result.push({ startDay: a + 1, length: b - a - 1, endDay: b - 1 });
  }
  return result;
}
month.significantGaps = gaps(month).filter((g) => g.length >= 2);
month.longestGap = month.significantGaps.reduce(
  (best, g) => (!best || g.length > best.length ? g : best), null
);
month.resumeDays = month.significantGaps.map((g) => g.endDay + 1);
month.resumeCount = month.resumeDays.length;
{
  const last = Math.max(...month.studiedDays);
  month.openTrailingGap = month.daysInMonth - last >= 2 ? true : null;
}
{
  const returned = month.significantGaps.length;
  const open = month.openTrailingGap ? 1 : 0;
  month.resumePower = returned + open > 0 ? Math.round((returned / (returned + open)) * 100) : null;
}
month.shortDate = (day) => `${month.month}/${day}`;

const ARCHETYPE = {
  phoenix: {
    displayName: 'Phoenix',
    tagline: 'Sink deep. Always return.',
    subline: 'The length of the gap is nothing to you.',
  },
};

// ---- MonthWaveform (Landfall/Views/Waveform/MonthWaveform.swift) ----
function buildWaveform({ width, height, lineColor, gapBarColor, resumeMarkerColor, gapLabelColor }) {
  const lineWidth = pt(3);
  const resumeBandHeight = pt(34);
  const gapBandHeight = pt(46);
  const markerDiameter = pt(9);
  const gapBarHeight = pt(7);
  const baseRise = 0.6;
  const stepRise = 0.09;
  const minResumeLabelSpacing = pt(34);
  const shortGapLabelThreshold = pt(45);

  const dayWidth = width / month.daysInMonth;
  const topY = resumeBandHeight;
  const baselineY = height - gapBandHeight;

  const sortedStudied = [...month.studiedDays].sort((a, b) => a - b);
  const blockIndex = {};
  for (const day of sortedStudied) {
    blockIndex[day] = month.studiedDays.has(day - 1) ? (blockIndex[day - 1] ?? 0) + 1 : 0;
  }
  const levelY = (day) => {
    if (!(day in blockIndex)) return baselineY;
    const fraction = Math.min(baseRise + stepRise * blockIndex[day], 1.0);
    return baselineY - fraction * (baselineY - topY);
  };

  let d = '';
  let currentY = baselineY;
  d += `M0,${currentY}`;
  for (let day = 1; day <= month.daysInMonth; day++) {
    const y = levelY(day);
    const x = (day - 1) * dayWidth;
    if (y !== currentY) {
      d += ` L${x},${currentY} L${x},${y}`;
      currentY = y;
    }
    d += ` L${day * dayWidth},${y}`;
  }

  const gapLabel = (gap, barWidth) =>
    barWidth < shortGapLabelThreshold ? `${gap.length}d` : `${gap.length}-day gap`;

  let gapMarkup = '';
  for (const gap of month.significantGaps) {
    const startX = (gap.startDay - 1) * dayWidth + pt(2);
    const endX = gap.endDay * dayWidth - pt(2);
    const midX = (startX + endX) / 2;
    const barW = Math.max(endX - startX, gapBarHeight);
    const barY = baselineY + pt(14);
    gapMarkup += `<rect x="${midX - barW / 2}" y="${barY}" width="${barW}" height="${gapBarHeight}" rx="${gapBarHeight / 2}" fill="${gapBarColor}"/>`;
    gapMarkup += `<text x="${midX}" y="${barY + gapBarHeight + pt(14) + pt(4)}" text-anchor="middle" font-size="${pt(11)}" font-weight="400" fill="${gapLabelColor}">${gapLabel(gap, endX - startX)}</text>`;
  }

  const labeledResumeDays = () => {
    const result = new Set();
    let lastX = -Infinity;
    for (const day of [...month.resumeDays].sort((a, b) => a - b)) {
      const x = (day - 1) * dayWidth;
      if (x - lastX >= minResumeLabelSpacing) {
        result.add(day);
        lastX = x;
      }
    }
    return result;
  };
  const labeled = labeledResumeDays();

  let resumeMarkup = '';
  for (const day of month.resumeDays) {
    const x = (day - 1) * dayWidth;
    const y = levelY(day);
    resumeMarkup += `<circle cx="${x}" cy="${y}" r="${markerDiameter / 2}" fill="${resumeMarkerColor}"/>`;
    if (labeled.has(day)) {
      const lx = Math.min(Math.max(x, pt(14)), width - pt(14));
      resumeMarkup += `<text x="${lx}" y="${y - pt(20)}" text-anchor="middle" font-size="${pt(12)}" font-weight="500" fill="${resumeMarkerColor}">Return</text>`;
    }
  }

  return `
    <svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
      <path d="${d}" fill="none" stroke="${lineColor}" stroke-width="${lineWidth}" stroke-linecap="round" stroke-linejoin="round"/>
      ${gapMarkup}
      ${resumeMarkup}
    </svg>`;
}

// ---- ArchetypeSymbols.swift: PhoenixSymbol ----
const PHOENIX_PATH =
  'M100,12 Q112,28 124,54 Q172,58 193,98 Q150,100 127,116 Q135,150 143,192 ' +
  'Q112,162 100,148 Q88,162 57,192 Q65,150 73,116 Q50,100 7,98 Q28,58 76,54 Q88,28 100,12 Z';

function phoenixSymbolSvg(size) {
  return `
    <svg width="${size}" height="${size}" viewBox="0 0 200 200">
      <path d="${PHOENIX_PATH}" fill="${COLOR.coral}"/>
      <circle cx="100" cy="50" r="8" fill="${COLOR.midnight}"/>
    </svg>`;
}

// ---- Shared card chrome ----
const CARD_W = pt(390);
const CARD_H = pt(693);
const CORNER = pt(20);
const PAD = pt(36);
const CONTENT_W = CARD_W - PAD * 2;

const FONT_STACK = "'Liberation Sans', 'DejaVu Sans', Arial, sans-serif";

function kicker(text, color) {
  return `<div style="font:400 ${pt(15)}px ${FONT_STACK};letter-spacing:${pt(2)}px;color:${color};">${text}</div>`;
}
function brandmark(color) {
  return `<div style="font:400 ${pt(13)}px ${FONT_STACK};color:${color};opacity:0.4;">Landfall</div>`;
}
function cardShell({ bg, align = 'flex-start', content }) {
  return `
  <div class="card" style="width:${CARD_W}px;height:${CARD_H}px;border-radius:${CORNER}px;background:${bg};padding:${PAD}px;box-sizing:border-box;display:flex;flex-direction:column;align-items:${align};font-family:${FONT_STACK};">
    ${content}
  </div>`;
}

// ---- Card 1: Fact ----
function factRow(count, verb, accent) {
  return `
    <div style="display:flex;align-items:baseline;gap:${pt(10)}px;">
      <span style="font:500 ${pt(64)}px ${FONT_STACK};font-variant-numeric:tabular-nums;color:${accent};">${count}</span>
      <span style="font:500 ${pt(22)}px ${FONT_STACK};color:${accent};">days</span>
      <span style="font:500 ${pt(22)}px ${FONT_STACK};color:#FFFFFF;">${verb}</span>
    </div>`;
}
function card1() {
  const content = `
    ${kicker(`You, May 2026`, '#FFFFFF')}
    <div style="flex:1;"></div>
    <div style="display:flex;flex-direction:column;gap:${pt(44)}px;">
      ${factRow(month.studiedCount, 'studied', COLOR.sunYellow)}
      ${factRow(month.restedCount, 'rested', COLOR.seaGreen)}
    </div>
    <div style="flex:1;"></div>
    <div style="font:500 ${pt(20)}px ${FONT_STACK};color:#FFFFFF;">And you never once quit.</div>
    <div style="height:${pt(44)}px;"></div>
    ${brandmark('#FFFFFF')}
  `;
  return cardShell({ bg: COLOR.ink, content });
}

// ---- Card 2: Silence ----
function card2() {
  const gap = month.longestGap;
  const content = `
    ${kicker('Your longest gap', COLOR.deepRust)}
    <div style="display:flex;align-items:baseline;gap:${pt(8)}px;margin-top:${pt(16)}px;color:${COLOR.deepRust};">
      <span style="font:500 ${pt(80)}px ${FONT_STACK};font-variant-numeric:tabular-nums;">${gap.length}</span>
      <span style="font:500 ${pt(24)}px ${FONT_STACK};">days</span>
    </div>
    <div style="flex:1;"></div>
    <div style="font:500 ${pt(19)}px ${FONT_STACK};color:${COLOR.deepRust};">${month.shortDate(gap.startDay)}–${month.shortDate(gap.endDay)}, you fell silent.</div>
    <div style="flex:1;"></div>
    <div style="width:100%;box-sizing:border-box;padding:${pt(22)}px;border-radius:${pt(20)}px;background:${COLOR.deepRust};display:flex;flex-direction:column;gap:${pt(10)}px;">
      <div style="font:500 ${pt(19)}px ${FONT_STACK};color:${COLOR.coral};">And yet on ${month.shortDate(gap.endDay + 1)}, you came back.</div>
      <div style="font:400 ${pt(15)}px ${FONT_STACK};color:${COLOR.coral};">${month.resumeCount} returns this month.</div>
    </div>
    <div style="height:${pt(44)}px;"></div>
    ${brandmark(COLOR.deepRust)}
  `;
  return cardShell({ bg: COLOR.coral, content });
}

// ---- Card 3: Archetype ----
function statPill(text) {
  return `<div style="font:400 ${pt(14)}px ${FONT_STACK};font-variant-numeric:tabular-nums;color:${COLOR.lavender};padding:${pt(9)}px ${pt(16)}px;border-radius:999px;border:${pt(1.5)}px solid ${COLOR.violet};">${text}</div>`;
}
function card3() {
  const a = ARCHETYPE[month.archetype];
  const content = `
    ${kicker('Your comeback type', COLOR.lavender)}
    <div style="flex:1;"></div>
    ${phoenixSymbolSvg(pt(150))}
    <div style="height:${pt(40)}px;"></div>
    <div style="font:500 ${pt(36)}px ${FONT_STACK};color:#FFFFFF;">${a.displayName}</div>
    <div style="display:flex;flex-direction:column;gap:${pt(9)}px;align-items:center;text-align:center;padding-top:${pt(18)}px;font:500 ${pt(17)}px ${FONT_STACK};color:${COLOR.lavender};">
      <div>${a.tagline}</div>
      <div>${a.subline}</div>
    </div>
    <div style="flex:1;"></div>
    <div style="display:flex;gap:${pt(12)}px;">
      ${month.resumePower !== null ? statPill(`Comeback ${month.resumePower}`) : ''}
      ${statPill(`${month.resumeCount} returns`)}
    </div>
    <div style="height:${pt(44)}px;"></div>
    ${brandmark('#FFFFFF')}
  `;
  return cardShell({ bg: COLOR.midnight, align: 'center', content });
}

// ---- Card 4: Trace ----
function statBlock(label, value, unit, alignItems) {
  return `
    <div style="flex:1;display:flex;flex-direction:column;gap:${pt(6)}px;align-items:${alignItems};">
      <div style="font:400 ${pt(13)}px ${FONT_STACK};color:${COLOR.ink};opacity:0.5;">${label}</div>
      <div style="display:flex;align-items:baseline;gap:${pt(2)}px;">
        <span style="font:500 ${pt(30)}px ${FONT_STACK};font-variant-numeric:tabular-nums;color:${COLOR.ink};">${value}</span>
        <span style="font:500 ${pt(14)}px ${FONT_STACK};color:${COLOR.ink};">${unit}</span>
      </div>
    </div>`;
}
function card4() {
  const waveformHeight = pt(216);
  const svg = buildWaveform({
    width: CONTENT_W,
    height: waveformHeight,
    lineColor: COLOR.ink,
    gapBarColor: COLOR.coral,
    resumeMarkerColor: COLOR.returnOrange,
    gapLabelColor: hexWithOpacity(COLOR.deepRust, 0.85),
  });
  const content = `
    ${kicker('Trace of May', hexWithOpacity(COLOR.ink, 0.55))}
    <div style="flex:1;"></div>
    <div style="width:${CONTENT_W}px;height:${waveformHeight}px;">${svg}</div>
    <div style="flex:1;"></div>
    <div style="display:flex;width:100%;">
      ${statBlock('Total', month.studiedCount, 'days', 'flex-start')}
      ${statBlock('Returns', month.resumeCount, 'times', 'center')}
      ${statBlock('Times quit', month.quitCount, 'times', 'flex-end')}
    </div>
    <div style="height:${pt(44)}px;"></div>
    ${brandmark(COLOR.ink)}
  `;
  return cardShell({ bg: COLOR.paper, content });
}

function hexWithOpacity(hex, opacity) {
  const n = parseInt(hex.slice(1), 16);
  const r = (n >> 16) & 0xff, g = (n >> 8) & 0xff, b = n & 0xff;
  return `rgba(${r},${g},${b},${opacity})`;
}

const cards = [
  { id: 'card1-fact', html: card1() },
  { id: 'card2-silence', html: card2() },
  { id: 'card3-archetype', html: card3() },
  { id: 'card4-trace', html: card4() },
];

const pageHtml = `<!doctype html>
<html><head><meta charset="utf-8"><style>
  html,body{margin:0;padding:0;background:transparent;}
  .card{overflow:hidden;}
  #stage{display:flex;gap:40px;padding:20px;}
</style></head>
<body><div id="stage">
${cards.map((c) => `<div id="${c.id}">${c.html}</div>`).join('\n')}
</div></body></html>`;

(async () => {
  const outDir = process.argv[2] || path.join(__dirname, 'out');
  fs.mkdirSync(outDir, { recursive: true });
  const htmlPath = path.join(outDir, '.stage.html');
  fs.writeFileSync(htmlPath, pageHtml);

  const browser = await chromium.launch({
    executablePath: process.env.PLAYWRIGHT_CHROMIUM_PATH || undefined,
  });
  const page = await browser.newPage({ viewport: { width: 5200, height: 2200 } });
  await page.goto('file://' + htmlPath);
  await page.waitForTimeout(100);

  for (const c of cards) {
    const el = await page.$('#' + c.id + ' .card');
    const outPath = path.join(outDir, `Landfall-${month.year}-${String(month.month).padStart(2, '0')}-${c.id}.png`);
    await el.screenshot({ path: outPath, omitBackground: true });
    console.log('WROTE', outPath);
  }

  await browser.close();
  fs.unlinkSync(htmlPath);
})();
