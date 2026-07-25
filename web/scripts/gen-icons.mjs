// public/ のアイコンPNGを favicon.svg(唯一のソース)から再生成する。
//
// 経緯: icon-180.png / icon-512.png が壊れたPNG(IDATのCRC不一致・IEND欠落)
// のままコミットされており、iPadOS が apple-touch-icon をデコードできず
// ホーム画面のアイコンが崩れていた。手作業で書き出すと同じ事故が起きるため、
// 生成をスクリプト化して書き出し後に必ず整合性を検証する。
//
//   npm run icons
//
// 出力はすべて不透明(アルファなし・color type 2)の全面塗りPNG。
// iOS/Androidはアイコンの角丸マスクを自分で適用するので、こちら側では
// 角を丸めない(丸めると透明部分が黒く出る)。

import { Resvg } from '@resvg/resvg-js'
import fs from 'node:fs'
import path from 'node:path'
import zlib from 'node:zlib'
import { fileURLToPath } from 'node:url'

const PUBLIC_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'public')
const SOURCE_SVG = path.join(PUBLIC_DIR, 'favicon.svg')
const BACKGROUND = '#184A40' // manifest の background_color / theme_color と同じ

// maskable は各プラットフォームが最大で外周20%を切り落とすため、
// 図案を80%に縮めて安全領域(中央の円)に収める。
const MASKABLE_SCALE = 0.8

const OUTPUTS = [
  // apple-touch-icon。iPad(152)/iPad Pro(167)/iPhone(180)。
  { file: 'icon-152.png', size: 152, variant: 'any' },
  { file: 'icon-167.png', size: 167, variant: 'any' },
  { file: 'icon-180.png', size: 180, variant: 'any' },
  // web app manifest。
  { file: 'icon-192.png', size: 192, variant: 'any' },
  { file: 'icon-512.png', size: 512, variant: 'any' },
  { file: 'icon-maskable-192.png', size: 192, variant: 'maskable' },
  { file: 'icon-maskable-512.png', size: 512, variant: 'maskable' },
]

/** favicon.svg から viewBox と図案(角丸の背景 rect を除いた中身)を取り出す。 */
function readSource() {
  const svg = fs.readFileSync(SOURCE_SVG, 'utf8')
  const viewBox = svg.match(/viewBox="0 0 (\d+(?:\.\d+)?) (\d+(?:\.\d+)?)"/)
  if (!viewBox) throw new Error(`favicon.svg に viewBox="0 0 W H" が見つからない: ${SOURCE_SVG}`)

  const inner = svg
    .replace(/^[\s\S]*?<svg\b[^>]*>/, '')
    .replace(/<\/svg>[\s\S]*$/, '')
    .replace(/<rect\b[^>]*\/>/g, '') // 背景の角丸 rect はアイコンでは使わない
    .trim()
  if (!inner) throw new Error('favicon.svg から図案を取り出せなかった')

  return { width: Number(viewBox[1]), height: Number(viewBox[2]), art: inner }
}

function renderRgba(svg, size) {
  const rendered = new Resvg(svg, { fitTo: { mode: 'width', value: size } }).render()
  const { width, height } = rendered
  if (width !== size || height !== size) {
    throw new Error(`描画サイズが一致しない: ${width}x${height} (期待: ${size}x${size})`)
  }
  return { pixels: rendered.pixels, width, height }
}

/** 図案だけを描いて、不透明ピクセルの外接矩形をユーザー単位で求める。 */
function artBounds({ width, height, art }) {
  const probe = 512
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}">${art}</svg>`
  const { pixels } = renderRgba(svg, probe)

  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
  for (let y = 0; y < probe; y++) {
    for (let x = 0; x < probe; x++) {
      if (pixels[(y * probe + x) * 4 + 3] > 8) {
        if (x < minX) minX = x
        if (x > maxX) maxX = x
        if (y < minY) minY = y
        if (y > maxY) maxY = y
      }
    }
  }
  if (maxX < 0) throw new Error('図案が空だった')

  const scale = width / probe
  return {
    x: minX * scale,
    y: minY * scale,
    width: (maxX - minX + 1) * scale,
    height: (maxY - minY + 1) * scale,
  }
}

function buildSvg(source, variant, bounds) {
  const { width, height, art } = source
  const canvas = `<rect width="${width}" height="${height}" fill="${BACKGROUND}"/>`
  if (variant !== 'maskable') {
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}">${canvas}${art}</svg>`
  }

  // 図案の外接矩形をキャンバス中央に寄せてから MASKABLE_SCALE 倍する。
  const cx = width / 2
  const cy = height / 2
  const dx = cx - (bounds.x + bounds.width / 2)
  const dy = cy - (bounds.y + bounds.height / 2)
  const transform =
    `translate(${cx} ${cy}) scale(${MASKABLE_SCALE}) translate(${-cx} ${-cy}) translate(${dx} ${dy})`
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}">` +
    `${canvas}<g transform="${transform}">${art}</g></svg>`
  )
}

// --- 最小限のPNGエンコーダ(color type 2 / 8bit、アルファなし) -----------------
// resvg が返す RGBA を、アルファを落として書き出す。iOS はアイコンの透明度を
// 扱えず黒く塗り潰すため、アルファチャンネル自体を持たせない。

const CRC_TABLE = (() => {
  const table = new Uint32Array(256)
  for (let n = 0; n < 256; n++) {
    let c = n
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    table[n] = c >>> 0
  }
  return table
})()

function crc32(buf) {
  let crc = 0xffffffff
  for (let i = 0; i < buf.length; i++) crc = CRC_TABLE[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8)
  return (crc ^ 0xffffffff) >>> 0
}

function chunk(type, data) {
  const out = Buffer.alloc(data.length + 12)
  out.writeUInt32BE(data.length, 0)
  out.write(type, 4, 'latin1')
  data.copy(out, 8)
  out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length)
  return out
}

/** PNGの各スキャンラインに、絶対値和が最小になるフィルタを選んで適用する。 */
function filterScanlines(rgb, width, height) {
  const bpp = 3
  const stride = width * bpp
  const out = Buffer.alloc(height * (stride + 1))
  const candidate = Buffer.alloc(stride)
  let prev = Buffer.alloc(stride)

  for (let y = 0; y < height; y++) {
    const line = rgb.subarray(y * stride, (y + 1) * stride)
    let bestType = 0
    let bestScore = Infinity
    let best = null

    for (let type = 0; type <= 4; type++) {
      let score = 0
      for (let x = 0; x < stride; x++) {
        const a = x >= bpp ? line[x - bpp] : 0
        const b = prev[x]
        const c = x >= bpp ? prev[x - bpp] : 0
        let v
        switch (type) {
          case 0: v = line[x]; break
          case 1: v = line[x] - a; break
          case 2: v = line[x] - b; break
          case 3: v = line[x] - ((a + b) >> 1); break
          default: {
            const p = a + b - c
            const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c)
            v = line[x] - (pa <= pb && pa <= pc ? a : pb <= pc ? b : c)
          }
        }
        candidate[x] = v & 0xff
        const signed = candidate[x] > 127 ? 256 - candidate[x] : candidate[x]
        score += signed
      }
      if (score < bestScore) {
        bestScore = score
        bestType = type
        best = Buffer.from(candidate)
      }
    }

    out[y * (stride + 1)] = bestType
    best.copy(out, y * (stride + 1) + 1)
    prev = line
  }
  return out
}

function encodeOpaquePng(rgba, width, height) {
  const rgb = Buffer.alloc(width * height * 3)
  for (let i = 0, j = 0; i < width * height; i++, j += 3) {
    // 図案は全面塗りなので、アルファは常に255になっている前提。
    rgb[j] = rgba[i * 4]
    rgb[j + 1] = rgba[i * 4 + 1]
    rgb[j + 2] = rgba[i * 4 + 2]
  }

  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(width, 0)
  ihdr.writeUInt32BE(height, 4)
  ihdr[8] = 8 // bit depth
  ihdr[9] = 2 // color type: truecolour(アルファなし)
  ihdr[10] = 0 // deflate
  ihdr[11] = 0 // filter method 0
  ihdr[12] = 0 // non-interlaced

  const idat = zlib.deflateSync(filterScanlines(rgb, width, height), { level: 9 })
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', idat),
    chunk('IEND', Buffer.alloc(0)),
  ])
}

/** 書き出したPNGを読み直し、全チャンクのCRCとIEND、展開可否まで検証する。 */
function verifyPng(file, expectedSize) {
  const buf = fs.readFileSync(file)
  if (buf.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') {
    throw new Error(`${file}: PNGシグネチャが不正`)
  }

  let offset = 8
  let sawEnd = false
  const idat = []
  while (offset + 8 <= buf.length) {
    const length = buf.readUInt32BE(offset)
    const type = buf.subarray(offset + 4, offset + 8).toString('latin1')
    if (offset + 12 + length > buf.length) throw new Error(`${file}: ${type} チャンクが途中で切れている`)
    if (crc32(buf.subarray(offset + 4, offset + 8 + length)) !== buf.readUInt32BE(offset + 8 + length)) {
      throw new Error(`${file}: ${type} チャンクのCRCが一致しない`)
    }
    if (type === 'IHDR') {
      const w = buf.readUInt32BE(offset + 8)
      const h = buf.readUInt32BE(offset + 12)
      if (w !== expectedSize || h !== expectedSize) {
        throw new Error(`${file}: ${w}x${h} は期待する ${expectedSize}x${expectedSize} と違う`)
      }
      if (buf[offset + 17] !== 2) throw new Error(`${file}: アルファ付きで書き出されている`)
    }
    if (type === 'IDAT') idat.push(buf.subarray(offset + 8, offset + 8 + length))
    offset += 12 + length
    if (type === 'IEND') { sawEnd = true; break }
  }
  if (!sawEnd) throw new Error(`${file}: IENDチャンクがない`)
  if (offset !== buf.length) throw new Error(`${file}: IENDの後ろに余分なデータがある`)

  const raw = zlib.inflateSync(Buffer.concat(idat))
  const expectedRaw = expectedSize * (expectedSize * 3 + 1)
  if (raw.length !== expectedRaw) {
    throw new Error(`${file}: 展開後が ${raw.length} バイト(期待: ${expectedRaw})`)
  }
  return buf.length
}

const source = readSource()
const bounds = artBounds(source)

for (const { file, size, variant } of OUTPUTS) {
  const svg = buildSvg(source, variant, bounds)
  const { pixels } = renderRgba(svg, size)

  for (let i = 3; i < pixels.length; i += 4) {
    if (pixels[i] !== 255) throw new Error(`${file}: 透明なピクセルが混じっている`)
  }

  const target = path.join(PUBLIC_DIR, file)
  fs.writeFileSync(target, encodeOpaquePng(pixels, size, size))
  const bytes = verifyPng(target, size)
  console.log(`ok  ${file.padEnd(24)} ${size}x${size}  ${bytes} bytes`)
}
