// 計測中のBGM。すべてWebAudioでの生成音(音源ファイル不使用・権利問題なし)。
// - waves: 低くフィルタした波の音。ゆっくり満ち引きする
// - piano: ペンタトニックのやわらかい単音が、波の下でぽつぽつと鳴る
// 音量は控えめに固定。集中の邪魔をしないことが最優先。

export type SoundMode = "off" | "waves" | "piano";

const PREF_KEY = "timer.sound";

export function soundPref(): SoundMode {
  const v = localStorage.getItem(PREF_KEY);
  return v === "waves" || v === "piano" ? v : "off";
}

export function setSoundPref(mode: SoundMode) {
  localStorage.setItem(PREF_KEY, mode);
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

/// ピアノ: 三角波+わずかなデチューンの2声、長い減衰。Cメジャーペンタトニック。
const NOTES = [261.63, 293.66, 329.63, 392.0, 440.0, 523.25];

function playNote(target: GainNode) {
  const c = ensureCtx();
  const freq = NOTES[Math.floor(Math.random() * NOTES.length)];
  const now = c.currentTime;
  const env = c.createGain();
  env.gain.setValueAtTime(0, now);
  env.gain.linearRampToValueAtTime(0.16, now + 0.03);
  env.gain.exponentialRampToValueAtTime(0.0001, now + 3.4);
  const filter = c.createBiquadFilter();
  filter.type = "lowpass";
  filter.frequency.value = 1400;
  for (const detune of [0, 4]) {
    const osc = c.createOscillator();
    osc.type = "triangle";
    osc.frequency.value = freq;
    osc.detune.value = detune;
    osc.connect(env);
    osc.start(now);
    osc.stop(now + 3.6);
  }
  env.connect(filter);
  filter.connect(target);
}

function scheduleNextNote(target: GainNode) {
  pianoTimer = window.setTimeout(
    () => {
      playNote(target);
      scheduleNextNote(target);
    },
    2600 + Math.random() * 3200,
  );
}

export function startSound(mode: SoundMode) {
  stopSound();
  if (mode === "off") return;
  const c = ensureCtx();
  current = mode;
  master = c.createGain();
  master.gain.setValueAtTime(0, c.currentTime);
  master.gain.linearRampToValueAtTime(mode === "waves" ? 0.16 : 0.12, c.currentTime + 1.2);
  master.connect(c.destination);
  buildWaves(master);
  if (mode === "piano") {
    playNote(master);
    scheduleNextNote(master);
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
