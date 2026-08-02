import { storage } from "./storage";

// 計測中のBGM。すべてWebAudioでの生成音(音源ファイル不使用・権利問題なし)。
// - waves: 低くフィルタした波の音。ゆっくり満ち引きする
// - piano: 6/8拍子のオリジナル・ノクターン。分散和音と旋律が波の上を進む
// 音量は控えめに固定。集中の邪魔をしないことが最優先。

export type SoundMode = "off" | "waves" | "piano";

const PREF_KEY = "timer.sound";

export function soundPref(): SoundMode {
  const v = storage.get(PREF_KEY);
  return v === "waves" || v === "piano" ? v : "off";
}

export function setSoundPref(mode: SoundMode) {
  storage.set(PREF_KEY, mode);
}

let ctx: AudioContext | null = null;
let master: GainNode | null = null;
let pianoTimer: number | null = null;
let current: SoundMode = "off";

function ensureCtx(): AudioContext {
  if (!ctx) {
    ctx = new AudioContext();
    master = ctx.createGain();
    master.gain.value = 0;
    master.connect(ctx.destination);
  }
  void ctx.resume();
  return ctx;
}

/// 波: ホワイトノイズ → ローパス → うねる音量(2つの遅いLFOを重ねて自然に)。
function buildWaves(target: GainNode) {
  const c = ensureCtx();
  const buffer = c.createBuffer(1, c.sampleRate * 4, c.sampleRate);
  const data = buffer.getChannelData(0);
  for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
  const src = c.createBufferSource();
  src.buffer = buffer;
  src.loop = true;
  const filter = c.createBiquadFilter();
  filter.type = "lowpass";
  filter.frequency.value = 420;
  const swell = c.createGain();
  swell.gain.value = 0.5;
  for (const [freq, depth] of [
    [0.07, 0.3],
    [0.045, 0.2],
  ] as const) {
    const lfo = c.createOscillator();
    lfo.frequency.value = freq;
    const lfoGain = c.createGain();
    lfoGain.gain.value = depth;
    lfo.connect(lfoGain);
    lfoGain.connect(swell.gain);
    lfo.start();
  }
  src.connect(filter);
  filter.connect(swell);
  swell.connect(target);
  src.start();
}

/// MIDIノート番号から周波数へ。
function noteHz(midi: number): number {
  return 440 * 2 ** ((midi - 69) / 12);
}

/// ピアノの一音。基音は長く、倍音は早く消えるよう別々の包絡線を持たせる。
/// 単純なオシレーターの「電子音」ではなく、鍵盤を打った直後だけ明るく、
/// その後は丸く沈む響きにする。
function playPianoTone(
  target: AudioNode,
  midi: number,
  at: number,
  duration: number,
  velocity: number,
  pan: number,
) {
  const c = ensureCtx();
  const filter = c.createBiquadFilter();
  filter.type = "lowpass";
  filter.frequency.setValueAtTime(4200, at);
  filter.frequency.exponentialRampToValueAtTime(1350, at + Math.min(1.8, duration));

  const panner = c.createStereoPanner();
  panner.pan.value = pan;
  filter.connect(panner);
  panner.connect(target);

  const partials: Array<{
    ratio: number;
    type: OscillatorType;
    level: number;
    release: number;
  }> = [
    { ratio: 1, type: "triangle", level: 0.72, release: 1 },
    { ratio: 2, type: "sine", level: 0.22, release: 0.55 },
    { ratio: 3, type: "sine", level: 0.07, release: 0.32 },
  ];

  for (const partial of partials) {
    const release = Math.max(0.7, duration * partial.release);
    const env = c.createGain();
    const peak = Math.max(0.0002, velocity * partial.level);
    env.gain.setValueAtTime(0.0001, at);
    env.gain.linearRampToValueAtTime(peak, at + 0.012);
    env.gain.exponentialRampToValueAtTime(Math.max(0.0002, peak * 0.58), at + 0.16);
    env.gain.exponentialRampToValueAtTime(0.0001, at + release);

    const osc = c.createOscillator();
    osc.type = partial.type;
    osc.frequency.value = noteHz(midi) * partial.ratio;
    // ごく小さな揺らぎだけを左右交互に与え、完全な電子的ユニゾンを避ける。
    osc.detune.value = midi % 2 === 0 ? 1.1 : -1.1;
    osc.connect(env);
    env.connect(filter);
    osc.start(at);
    osc.stop(at + release + 0.05);
  }
}

interface ClassicalBar {
  /// 左手の分散和音。低音→内声→高音。
  chord: [number, number, number, number];
  /// [6/8内の開始位置, MIDI音程, 長さ(8分音符単位), 強さ]
  melody: Array<[number, number, number, number]>;
}

// 「海上のノクターン」— D major / B minor、全16小節。
// 既存曲の引用ではなく、このアプリのためのオリジナル進行と旋律。
const CLASSICAL_SCORE: ClassicalBar[] = [
  { chord: [38, 45, 50, 54], melody: [[0, 74, 3, 0.11], [3, 69, 2, 0.085], [5, 78, 1, 0.095]] },
  { chord: [37, 45, 49, 52], melody: [[0, 76, 2, 0.1], [2, 73, 2, 0.09], [4, 69, 2, 0.08]] },
  { chord: [35, 42, 47, 50], melody: [[0, 71, 2, 0.09], [2, 74, 3, 0.11], [5, 69, 1, 0.075]] },
  { chord: [42, 49, 54, 57], melody: [[0, 73, 3, 0.1], [3, 69, 2, 0.08], [5, 66, 1, 0.07]] },
  { chord: [43, 50, 55, 59], melody: [[0, 71, 2, 0.085], [2, 74, 2, 0.1], [4, 79, 2, 0.115]] },
  { chord: [42, 45, 50, 54], melody: [[0, 78, 3, 0.105], [3, 76, 2, 0.09], [5, 74, 1, 0.08]] },
  { chord: [40, 47, 50, 55], melody: [[0, 76, 2, 0.09], [2, 79, 2, 0.105], [4, 74, 2, 0.085]] },
  { chord: [45, 52, 55, 61], melody: [[0, 73, 2, 0.095], [2, 71, 2, 0.08], [4, 69, 2, 0.075]] },
  { chord: [35, 42, 47, 50], melody: [[0, 71, 3, 0.085], [3, 74, 2, 0.1], [5, 78, 1, 0.11]] },
  { chord: [43, 50, 55, 59], melody: [[0, 79, 2, 0.115], [2, 78, 2, 0.095], [4, 74, 2, 0.085]] },
  { chord: [38, 45, 50, 54], melody: [[0, 76, 2, 0.09], [2, 74, 3, 0.105], [5, 69, 1, 0.07]] },
  { chord: [45, 52, 57, 61], melody: [[0, 73, 2, 0.095], [2, 76, 2, 0.105], [4, 81, 2, 0.115]] },
  { chord: [40, 47, 50, 55], melody: [[0, 79, 2, 0.105], [2, 76, 2, 0.09], [4, 74, 2, 0.08]] },
  { chord: [42, 47, 50, 54], melody: [[0, 71, 3, 0.085], [3, 74, 3, 0.1]] },
  { chord: [43, 50, 55, 59], melody: [[0, 79, 2, 0.11], [2, 78, 2, 0.095], [4, 76, 2, 0.085]] },
  { chord: [45, 52, 57, 62], melody: [[0, 74, 2, 0.1], [2, 73, 2, 0.085], [4, 74, 2, 0.105]] },
];

const EIGHTH_NOTE_SEC = 0.42;
const BAR_SEC = EIGHTH_NOTE_SEC * 6;
const CLASSICAL_CYCLE_SEC = BAR_SEC * CLASSICAL_SCORE.length;

function buildPianoRoom(target: GainNode): GainNode {
  const c = ensureCtx();
  const input = c.createGain();
  const dry = c.createGain();
  const wet = c.createGain();
  const reverb = c.createConvolver();

  dry.gain.value = 0.88;
  wet.gain.value = 0.2;

  // 小さな木造船室のような、2.8秒で消える柔らかい残響。
  const length = Math.floor(c.sampleRate * 2.8);
  const impulse = c.createBuffer(2, length, c.sampleRate);
  for (let channel = 0; channel < impulse.numberOfChannels; channel++) {
    const samples = impulse.getChannelData(channel);
    for (let i = 0; i < length; i++) {
      const decay = (1 - i / length) ** 3.1;
      samples[i] = (Math.random() * 2 - 1) * decay * 0.58;
    }
  }
  reverb.buffer = impulse;

  input.connect(dry);
  dry.connect(target);
  input.connect(reverb);
  reverb.connect(wet);
  wet.connect(target);
  return input;
}

function scheduleClassicalCycle(target: AudioNode, start: number) {
  for (let barIndex = 0; barIndex < CLASSICAL_SCORE.length; barIndex++) {
    const bar = CLASSICAL_SCORE[barIndex];
    const barStart = start + barIndex * BAR_SEC;
    const [bass, inner, middle, high] = bar.chord;

    // 左手: 低音を小節頭に置き、その上を6/8の波のような分散和音が往復する。
    playPianoTone(target, bass, barStart, BAR_SEC * 0.94, 0.07, -0.28);
    const arpeggio = [middle, high, inner, high, middle, high];
    arpeggio.forEach((note, step) => {
      const breathe = step === 0 ? 0.004 : 0;
      playPianoTone(
        target,
        note,
        barStart + step * EIGHTH_NOTE_SEC + breathe,
        EIGHTH_NOTE_SEC * 4.8,
        step === 0 ? 0.047 : 0.04,
        -0.12 + step * 0.035,
      );
    });

    // 右手: 長短を混ぜた旋律。小節の終わりを少し空け、呼吸を作る。
    for (const [step, note, length, velocity] of bar.melody) {
      playPianoTone(
        target,
        note,
        barStart + step * EIGHTH_NOTE_SEC + 0.025,
        length * EIGHTH_NOTE_SEC * 1.35,
        velocity,
        0.2 + (note - 74) * 0.018,
      );
    }
  }
}

function startClassicalPiano(target: GainNode) {
  const c = ensureCtx();
  const room = buildPianoRoom(target);

  const scheduleCycle = (start: number) => {
    if (current !== "piano") return;
    // バックグラウンドでタイマーが遅延した場合、過去に予約されるはずだった
    // 全音を復帰時に一斉発音させず、次の小節群を静かに現在から始め直す。
    const safeStart = Math.max(start, c.currentTime + 0.08);
    scheduleClassicalCycle(room, safeStart);
    // 次の周回は少し前に予約し、バックグラウンド復帰時にも音切れしにくくする。
    const delay = Math.max(
      1000,
      (safeStart + CLASSICAL_CYCLE_SEC - c.currentTime - 3) * 1000,
    );
    pianoTimer = window.setTimeout(
      () => scheduleCycle(safeStart + CLASSICAL_CYCLE_SEC),
      delay,
    );
  };

  scheduleCycle(c.currentTime + 0.08);
}

export function startSound(mode: SoundMode) {
  stopSound();
  if (mode === "off") return;
  const c = ensureCtx();
  current = mode;
  master = c.createGain();
  master.gain.setValueAtTime(0, c.currentTime);
  master.gain.linearRampToValueAtTime(mode === "waves" ? 0.16 : 0.2, c.currentTime + 1.2);
  master.connect(c.destination);
  if (mode === "waves") {
    buildWaves(master);
  } else {
    // クラシックでは波を遠景へ下げ、旋律を邪魔しない程度にだけ残す。
    const distantSea = c.createGain();
    distantSea.gain.value = 0.13;
    distantSea.connect(master);
    buildWaves(distantSea);
    startClassicalPiano(master);
  }
}

export function stopSound() {
  if (pianoTimer !== null) {
    clearTimeout(pianoTimer);
    pianoTimer = null;
  }
  if (ctx && master && current !== "off") {
    const m = master;
    m.gain.linearRampToValueAtTime(0, ctx.currentTime + 0.5);
    setTimeout(() => m.disconnect(), 700);
  }
  current = "off";
}

/// 船をつついた時などの、ごく短いやわらかな一音(チャイムより控えめ)。
export function playPlink() {
  const c = ensureCtx();
  const now = c.currentTime;
  const env = c.createGain();
  env.gain.setValueAtTime(0, now);
  env.gain.linearRampToValueAtTime(0.13, now + 0.015);
  env.gain.exponentialRampToValueAtTime(0.0001, now + 0.65);
  const osc = c.createOscillator();
  osc.type = "sine";
  osc.frequency.value = 783.99; // G5
  osc.connect(env);
  env.connect(c.destination);
  osc.start(now);
  osc.stop(now + 0.7);
}

/// 港の試練への一撃。playPlinkより少し重い短い音 — 低めの二声+短いノイズの
/// 立ち上がりで「当たった」感を出す(生成音のみ。警告音にはしない)。
export function playStrike() {
  const c = ensureCtx();
  const now = c.currentTime;
  // 芯: 低めの正弦2声(基音+5度)。すばやく減衰する。
  for (const [freq, gain] of [
    [196.0, 0.16], // G3
    [293.66, 0.09], // D4
  ] as const) {
    const env = c.createGain();
    env.gain.setValueAtTime(0, now);
    env.gain.linearRampToValueAtTime(gain, now + 0.012);
    env.gain.exponentialRampToValueAtTime(0.0001, now + 0.55);
    const osc = c.createOscillator();
    osc.type = "sine";
    osc.frequency.setValueAtTime(freq * 1.12, now);
    osc.frequency.exponentialRampToValueAtTime(freq, now + 0.09);
    osc.connect(env);
    env.connect(c.destination);
    osc.start(now);
    osc.stop(now + 0.6);
  }
  // 立ち上がりの飛沫: ごく短いローパスノイズ。
  const len = Math.floor(c.sampleRate * 0.12);
  const buffer = c.createBuffer(1, len, c.sampleRate);
  const data = buffer.getChannelData(0);
  for (let i = 0; i < len; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / len);
  const src = c.createBufferSource();
  src.buffer = buffer;
  const filter = c.createBiquadFilter();
  filter.type = "lowpass";
  filter.frequency.value = 900;
  const env = c.createGain();
  env.gain.setValueAtTime(0.1, now);
  env.gain.exponentialRampToValueAtTime(0.0001, now + 0.12);
  src.connect(filter);
  filter.connect(env);
  env.connect(c.destination);
  src.start(now);
}

/// ポモドーロの区切りの合図。短くやわらかい二音(強制的な警告音にしない)。
export function playChime() {
  const c = ensureCtx();
  const now = c.currentTime;
  for (const [freq, at] of [
    [659.25, 0],
    [880.0, 0.22],
  ] as const) {
    const env = c.createGain();
    env.gain.setValueAtTime(0, now + at);
    env.gain.linearRampToValueAtTime(0.2, now + at + 0.02);
    env.gain.exponentialRampToValueAtTime(0.0001, now + at + 1.4);
    const osc = c.createOscillator();
    osc.type = "sine";
    osc.frequency.value = freq;
    osc.connect(env);
    env.connect(c.destination);
    osc.start(now + at);
    osc.stop(now + at + 1.5);
  }
}
