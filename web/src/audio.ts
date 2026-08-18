import { storage } from "./storage";
import { readTimer } from "./timer";

// 計測中の波音と、iOS版と同じKeelMiraオリジナルサウンドトラック。
// 音量は控えめに固定し、選んだ曲から4曲を順番に再生する。

export const VOYAGE_MUSIC_TRACKS = [
  {
    id: "harbor_minuet_main_theme",
    title: "Harbor Minuet",
    titleJa: "港のメヌエット",
  },
  {
    id: "beacon_rondo",
    title: "Beacon Rondo",
    titleJa: "灯標のロンド",
  },
  {
    id: "celestial_navigation_nocturne",
    title: "Celestial Navigation Nocturne",
    titleJa: "天測のノクターン",
  },
  {
    id: "approaching_evolution",
    title: "Approaching Evolution",
    titleJa: "接近する進化",
  },
] as const;

export type VoyageMusicTrack = (typeof VOYAGE_MUSIC_TRACKS)[number]["id"];
export type SoundMode = "off" | "waves" | VoyageMusicTrack;

const PREF_KEY = "timer.sound";
const HOME_MUSIC_PREF_KEY = "home.backgroundMusicEnabled";
const HOME_WAVES_PREF_KEY = "home.waveAmbienceEnabled";
export const HOME_MUSIC_PREF_EVENT = "landfall:home-music-preference";
export const HOME_WAVES_PREF_EVENT = "landfall:home-waves-preference";
const HOME_MUSIC_VOLUME = 0.22;
const HOME_WAVE_VOLUME = 0.095;
const HOME_WAVE_WITH_MUSIC_VOLUME = 0.062;
const TIMER_MUSIC_VOLUME = 0.34;

const voyageMusicTrackIds = new Set<string>(
  VOYAGE_MUSIC_TRACKS.map((track) => track.id),
);

export function isVoyageMusicTrack(value: string): value is VoyageMusicTrack {
  return voyageMusicTrackIds.has(value);
}

export function homeMusicEnabled(): boolean {
  return storage.get(HOME_MUSIC_PREF_KEY) === "on";
}

export function setHomeMusicEnabled(enabled: boolean): void {
  storage.set(HOME_MUSIC_PREF_KEY, enabled ? "on" : "off");
  // 設定ボタンのクリック中に開始することで、WebKitの自動再生制限も解除できる。
  if (enabled) startBackgroundMusic();
  else stopBackgroundMusic();
  if (typeof window !== "undefined") {
    window.dispatchEvent(new Event(HOME_MUSIC_PREF_EVENT));
  }
}

export function homeWavesEnabled(): boolean {
  return storage.get(HOME_WAVES_PREF_KEY) !== "off";
}

export function setHomeWavesEnabled(enabled: boolean): void {
  storage.set(HOME_WAVES_PREF_KEY, enabled ? "on" : "off");
  // クリック中に開始すると自動再生制限を解除できるが、
  // タイマー中やhidden時はその一瞬だけホーム音を鳴らさない。
  if (enabled && homeWavePlaybackAllowed()) startWaveAmbience();
  else stopWaveAmbience();
  if (typeof window !== "undefined") {
    window.dispatchEvent(new Event(HOME_WAVES_PREF_EVENT));
  }
}

export function soundPref(): SoundMode {
  const v = storage.get(PREF_KEY);
  return v === "waves" || (v !== null && isVoyageMusicTrack(v)) ? v : "off";
}

export function setSoundPref(mode: SoundMode) {
  storage.set(PREF_KEY, mode);
}

let ctx: AudioContext | null = null;
let master: GainNode | null = null;
let timerMusicAudio: HTMLAudioElement | null = null;
let timerMusicFadeFrame: number | null = null;
let timerMusicPlaybackGeneration = 0;
let homeAudio: HTMLAudioElement | null = null;
let homeFadeFrame: number | null = null;
let homePlaybackGeneration = 0;
let ambientWaveGraph: HomeWaveGraph | null = null;
let ambientWaveDisposeTimer: number | null = null;
let ambientWaveRequested = false;
let ambientWaveTarget = 0;
let activeSoundRun: TimerSoundRun | null = null;

function ensureCtx(): AudioContext {
  if (!ctx) {
    ctx = new AudioContext();
  }
  void ctx.resume();
  return ctx;
}

interface WaveHandle {
  stop(): void;
}

interface TimerSoundRun {
  output: GainNode;
  waves: WaveHandle[];
}

/// 波: ホワイトノイズ → ローパス → うねる音量(2つの遅いLFOを重ねて自然に)。
/// タイマーの1runごとに必ず破棄できるハンドルを返す。
function buildWaves(target: GainNode): WaveHandle {
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
  const sources: AudioScheduledSourceNode[] = [src];
  const nodes: AudioNode[] = [src, filter, swell];
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
    sources.push(lfo);
    nodes.push(lfo, lfoGain);
  }
  src.connect(filter);
  filter.connect(swell);
  swell.connect(target);
  src.start();
  let stopped = false;
  return {
    stop() {
      if (stopped) return;
      stopped = true;
      for (const source of sources) {
        try {
          source.stop();
        } catch {
          // すでに停止したsourceはdisconnectだけ行う。
        }
      }
      for (const node of nodes) node.disconnect();
    },
  };
}

interface HomeWaveGraph {
  output: GainNode;
  sources: AudioScheduledSourceNode[];
  nodes: AudioNode[];
}

interface WaveLayerOptions {
  noiseSeconds: number;
  driftSeconds: number;
  level: number;
  baseGain: number;
  driftDepth: number;
  highpass: number;
  lowpass: number;
  pan: number;
  playbackRate: number;
}

function makeNoiseSource(
  c: AudioContext,
  seconds: number,
  playbackRate = 1,
): AudioBufferSourceNode {
  const length = Math.max(2, Math.floor(c.sampleRate * seconds));
  const buffer = c.createBuffer(1, length, c.sampleRate);
  const data = buffer.getChannelData(0);
  const crossfadeSeconds = Math.min(seconds * 0.2, 0.5 + Math.random());
  const crossfadeSamples = Math.min(
    length - 1,
    Math.max(2, Math.floor(c.sampleRate * crossfadeSeconds)),
  );
  // 先頭直前のプリロールを用意し、末尾でそこへ等電力
  // crossfadeする。ループ後はプリロールの次の標本から始まるため、
  // 単に末尾と先頭を平均するよりホワイトノイズの連続性を保てる。
  const raw = new Float32Array(length + crossfadeSamples);
  for (let i = 0; i < raw.length; i++) raw[i] = Math.random() * 2 - 1;
  for (let i = 0; i < length; i++) data[i] = raw[crossfadeSamples + i];
  const tailStart = length - crossfadeSamples;
  for (let i = 0; i < crossfadeSamples; i++) {
    const phase = i / (crossfadeSamples - 1);
    const outgoing = Math.cos(phase * Math.PI * 0.5);
    const incoming = Math.sin(phase * Math.PI * 0.5);
    data[tailStart + i] =
      raw[crossfadeSamples + tailStart + i] * outgoing
      + raw[i] * incoming;
  }
  const source = c.createBufferSource();
  source.buffer = buffer;
  source.loop = true;
  source.playbackRate.value = playbackRate;
  return source;
}

/// ランダムな制御点をなめらかに結ぶ超低周波バッファ。
/// 各層で異なる素数寄りの長さにし、短い周期の繰り返しを感じさせない。
function makeDriftSource(c: AudioContext, seconds: number): AudioBufferSourceNode {
  const length = Math.max(2, Math.floor(c.sampleRate * seconds));
  const buffer = c.createBuffer(1, length, c.sampleRate);
  const data = buffer.getChannelData(0);
  const anchorCount = Math.max(9, Math.floor(seconds / 2.7));
  const anchors = Array.from(
    { length: anchorCount },
    () => Math.random() * 2 - 1,
  );
  // ループ境界に段差ができないよう最後は最初の値へ戻す。
  anchors.push(anchors[0]);
  for (let i = 0; i < length; i++) {
    const position = (i / length) * anchorCount;
    const index = Math.floor(position);
    const linear = position - index;
    const smooth = linear * linear * (3 - 2 * linear);
    data[i] = anchors[index] + (anchors[index + 1] - anchors[index]) * smooth;
  }
  const source = c.createBufferSource();
  source.buffer = buffer;
  source.loop = true;
  return source;
}

function addHomeWaveLayer(
  c: AudioContext,
  target: AudioNode,
  options: WaveLayerOptions,
  graph: HomeWaveGraph,
): void {
  const noise = makeNoiseSource(c, options.noiseSeconds, options.playbackRate);
  const highpass = c.createBiquadFilter();
  highpass.type = "highpass";
  highpass.frequency.value = options.highpass;
  highpass.Q.value = 0.55;
  const lowpass = c.createBiquadFilter();
  lowpass.type = "lowpass";
  lowpass.frequency.value = options.lowpass;
  lowpass.Q.value = 0.62;
  const envelope = c.createGain();
  envelope.gain.value = options.baseGain;
  const layerGain = c.createGain();
  layerGain.gain.value = options.level;
  const panner = c.createStereoPanner();
  panner.pan.value = options.pan;

  const drift = makeDriftSource(c, options.driftSeconds);
  const driftDepth = c.createGain();
  driftDepth.gain.value = options.driftDepth;
  drift.connect(driftDepth);
  driftDepth.connect(envelope.gain);

  noise.connect(highpass);
  highpass.connect(lowpass);
  lowpass.connect(envelope);
  envelope.connect(layerGain);
  layerGain.connect(panner);
  panner.connect(target);

  graph.sources.push(noise, drift);
  graph.nodes.push(
    noise,
    highpass,
    lowpass,
    envelope,
    layerGain,
    panner,
    drift,
    driftDepth,
  );
  noise.start(c.currentTime + 0.01);
  drift.start(c.currentTime + 0.01);
}

/// ホーム専用の三層ミックス。遠い海鳴り、寄せ波、泡の音域と
/// 揺れの長さを分け、同じ包絡線が同時に戻らないようにする。
function buildHomeWaveAmbience(c: AudioContext): HomeWaveGraph {
  const output = c.createGain();
  output.gain.value = 0;
  const compressor = c.createDynamicsCompressor();
  compressor.threshold.value = -23;
  compressor.knee.value = 15;
  compressor.ratio.value = 2.2;
  compressor.attack.value = 0.07;
  compressor.release.value = 0.78;
  compressor.connect(output);

  const graph: HomeWaveGraph = {
    output,
    sources: [],
    nodes: [compressor, output],
  };

  // 水平線の向こうの低い海鳴り。ほぼ中央に置く。
  addHomeWaveLayer(c, compressor, {
    noiseSeconds: 17.9,
    driftSeconds: 43.1,
    level: 0.42,
    baseGain: 0.56,
    driftDepth: 0.17,
    highpass: 32,
    lowpass: 245,
    pan: -0.08,
    playbackRate: 0.973,
  }, graph);
  // 左から岸へ寄せて広がる中域。
  addHomeWaveLayer(c, compressor, {
    noiseSeconds: 23.7,
    driftSeconds: 57.7,
    level: 0.34,
    baseGain: 0.39,
    driftDepth: 0.27,
    highpass: 170,
    lowpass: 1_480,
    pan: -0.24,
    playbackRate: 1.011,
  }, graph);
  // 砂浜で泡がほどける高域。少し右へ置き音場を開く。
  addHomeWaveLayer(c, compressor, {
    noiseSeconds: 11.3,
    driftSeconds: 31.9,
    level: 0.2,
    baseGain: 0.21,
    driftDepth: 0.16,
    highpass: 980,
    lowpass: 4_800,
    pan: 0.31,
    playbackRate: 1.027,
  }, graph);

  output.connect(c.destination);
  return graph;
}

function holdAudioParam(param: AudioParam, at: number): void {
  if (typeof param.cancelAndHoldAtTime === "function") {
    param.cancelAndHoldAtTime(at);
  } else {
    const value = param.value;
    param.cancelScheduledValues(at);
    param.setValueAtTime(value, at);
  }
}

function homeMusicIsPlaying(): boolean {
  return homeAudio !== null && !homeAudio.paused;
}

function homeWavePlaybackAllowed(): boolean {
  const visible = typeof document === "undefined" || !document.hidden;
  return visible && readTimer() === null;
}

function fadeAmbientWaves(target: number, seconds: number): void {
  if (!ctx || !ambientWaveGraph) return;
  const now = ctx.currentTime;
  holdAudioParam(ambientWaveGraph.output.gain, now);
  ambientWaveGraph.output.gain.linearRampToValueAtTime(target, now + seconds);
  ambientWaveTarget = target;
}

function updateAmbientWaveMusicMix(musicPlaying: boolean): void {
  if (!ambientWaveRequested || !ambientWaveGraph) return;
  fadeAmbientWaves(
    musicPlaying ? HOME_WAVE_WITH_MUSIC_VOLUME : HOME_WAVE_VOLUME,
    1.1,
  );
}

function disposeHomeWaveGraph(graph: HomeWaveGraph): void {
  for (const source of graph.sources) {
    try {
      source.stop();
    } catch {
      // 停止済みのAudioScheduledSourceNodeはそのまま破棄できる。
    }
  }
  for (const node of graph.nodes) node.disconnect();
}

/// タイマー外で流すホーム専用の波音。`buildWaves` のタイマー音とは
/// グラフと寿命を分け、代表BGMとも独立してミックスできる。
export function startWaveAmbience(): void {
  // pointer/keyboardの再試行にも必ず同じガードを通し、React側の
  // timer state反映が1tick遅れてもホーム音を割り込ませない。
  if (!homeWavePlaybackAllowed()) {
    stopWaveAmbience();
    return;
  }
  const c = ensureCtx();
  if (ambientWaveDisposeTimer !== null) {
    clearTimeout(ambientWaveDisposeTimer);
    ambientWaveDisposeTimer = null;
  }
  if (!ambientWaveGraph) {
    ambientWaveGraph = buildHomeWaveAmbience(c);
  }
  const target = homeMusicIsPlaying()
    ? HOME_WAVE_WITH_MUSIC_VOLUME
    : HOME_WAVE_VOLUME;
  if (ambientWaveRequested && Math.abs(ambientWaveTarget - target) < 0.000_5) return;
  ambientWaveRequested = true;
  fadeAmbientWaves(target, 1.8);
}

export function stopWaveAmbience(): void {
  if (!ctx || !ambientWaveGraph || !ambientWaveRequested) return;
  ambientWaveRequested = false;
  fadeAmbientWaves(0, 0.9);
  const graph = ambientWaveGraph;
  if (ambientWaveDisposeTimer !== null) clearTimeout(ambientWaveDisposeTimer);
  ambientWaveDisposeTimer = window.setTimeout(() => {
    ambientWaveDisposeTimer = null;
    if (ambientWaveRequested || ambientWaveGraph !== graph) return;
    disposeHomeWaveGraph(graph);
    ambientWaveGraph = null;
    ambientWaveTarget = 0;
  }, 1_100);
}

function timerMusicUrl(track: VoyageMusicTrack): string {
  return new URL(`audio/${track}.m4a?v=ios-playlist-1`, document.baseURI).href;
}

function fadeTimerMusic(
  audio: HTMLAudioElement,
  target: number,
  durationMs: number,
): void {
  if (timerMusicFadeFrame !== null) cancelAnimationFrame(timerMusicFadeFrame);
  const initial = audio.volume;
  const startedAt = performance.now();
  const tick = (now: number) => {
    if (timerMusicAudio !== audio) return;
    const ratio = Math.min(1, Math.max(0, (now - startedAt) / durationMs));
    audio.volume = initial + (target - initial) * ratio;
    if (ratio < 1) {
      timerMusicFadeFrame = requestAnimationFrame(tick);
    } else {
      timerMusicFadeFrame = null;
    }
  };
  timerMusicFadeFrame = requestAnimationFrame(tick);
}

function startTimerMusic(track: VoyageMusicTrack): void {
  const audio = new Audio(timerMusicUrl(track));
  audio.loop = false;
  audio.preload = "auto";
  audio.volume = 0;
  timerMusicAudio = audio;
  const generation = ++timerMusicPlaybackGeneration;
  audio.addEventListener("ended", () => {
    if (generation !== timerMusicPlaybackGeneration || timerMusicAudio !== audio) return;
    const index = VOYAGE_MUSIC_TRACKS.findIndex(({ id }) => id === track);
    const next = VOYAGE_MUSIC_TRACKS[(index + 1) % VOYAGE_MUSIC_TRACKS.length];
    timerMusicAudio = null;
    startTimerMusic(next.id);
  }, { once: true });
  void audio.play().then(() => {
    if (generation !== timerMusicPlaybackGeneration || timerMusicAudio !== audio) {
      audio.pause();
      return;
    }
    fadeTimerMusic(audio, TIMER_MUSIC_VOLUME, 350);
  }).catch(() => {
    // 自動再生の制限や読み込み失敗時は、UIとタイマー自体を止めない。
  });
}

export function startSound(mode: SoundMode) {
  // タイマー開始時はホームテーマから静かに主導権を受け取る。
  stopWaveAmbience();
  stopBackgroundMusic();
  stopSound();
  if (mode === "off") return;
  if (isVoyageMusicTrack(mode)) {
    startTimerMusic(mode);
    return;
  }
  const c = ensureCtx();
  const output = c.createGain();
  output.gain.setValueAtTime(0, c.currentTime);
  output.gain.linearRampToValueAtTime(0.16, c.currentTime + 1.2);
  output.connect(c.destination);
  const run: TimerSoundRun = { output, waves: [] };
  activeSoundRun = run;
  master = output;
  run.waves.push(buildWaves(output));
}

export function stopSound() {
  timerMusicPlaybackGeneration += 1;
  if (timerMusicFadeFrame !== null) {
    cancelAnimationFrame(timerMusicFadeFrame);
    timerMusicFadeFrame = null;
  }
  if (timerMusicAudio) {
    timerMusicAudio.pause();
    timerMusicAudio.currentTime = 0;
    timerMusicAudio = null;
  }
  const run = activeSoundRun;
  activeSoundRun = null;
  if (ctx && run) {
    holdAudioParam(run.output.gain, ctx.currentTime);
    run.output.gain.linearRampToValueAtTime(0, ctx.currentTime + 0.5);
    // run自身をcaptureし、この700msの間に始まった新runの
    // source/LFOやmasterを巻き込まない。
    setTimeout(() => {
      for (const waves of run.waves) waves.stop();
      run.output.disconnect();
      if (master === run.output) master = null;
    }, 700);
  }
}

function ensureHomeAudio(): HTMLAudioElement {
  if (!homeAudio) {
    homeAudio = new Audio(
      new URL("audio/harbor_minuet_main_theme.m4a?v=ios-playlist-1", document.baseURI).href,
    );
    homeAudio.loop = true;
    homeAudio.preload = "auto";
    homeAudio.volume = 0;
  }
  return homeAudio;
}

function fadeHomeAudio(
  audio: HTMLAudioElement,
  target: number,
  durationMs: number,
  completed?: () => void,
): void {
  if (homeFadeFrame !== null) cancelAnimationFrame(homeFadeFrame);
  const initial = audio.volume;
  const startedAt = performance.now();
  const tick = (now: number) => {
    const ratio = Math.min(1, Math.max(0, (now - startedAt) / durationMs));
    audio.volume = initial + (target - initial) * ratio;
    if (ratio < 1) {
      homeFadeFrame = requestAnimationFrame(tick);
    } else {
      homeFadeFrame = null;
      completed?.();
    }
  };
  homeFadeFrame = requestAnimationFrame(tick);
}

/// ホーム・軌跡・航海誌・港で流すKeelMiraメインテーマ「港のメヌエット」。
/// ブラウザの自動再生制限で初回が拒否された場合は、次の操作時に再試行される。
export function startBackgroundMusic(): void {
  if (typeof document !== "undefined" && document.hidden) {
    stopBackgroundMusic();
    return;
  }
  const audio = ensureHomeAudio();
  if (!audio.paused) {
    if (audio.volume < HOME_MUSIC_VOLUME) fadeHomeAudio(audio, HOME_MUSIC_VOLUME, 900);
    updateAmbientWaveMusicMix(true);
    return;
  }
  stopSound();
  const generation = ++homePlaybackGeneration;
  audio.volume = 0;
  void audio.play().then(() => {
    if (generation !== homePlaybackGeneration) {
      audio.pause();
      return;
    }
    updateAmbientWaveMusicMix(true);
    fadeHomeAudio(audio, HOME_MUSIC_VOLUME, 1600);
  }).catch(() => {
    // Safari/Chromeの初回自動再生拒否は正常。次のpointer/keyboard操作で再試行する。
  });
}

export function stopBackgroundMusic(): void {
  homePlaybackGeneration += 1;
  // hiddenに入った後はrAFが停止・大幅間引きされるため、
  // 通常のフェード完了を待たずここで確実にpauseする。
  const hidden = typeof document !== "undefined" && document.hidden;
  if (hidden && homeFadeFrame !== null) {
    cancelAnimationFrame(homeFadeFrame);
    homeFadeFrame = null;
  }
  if (hidden && homeAudio) {
    homeAudio.volume = 0;
    homeAudio.pause();
    homeAudio.currentTime = 0;
    updateAmbientWaveMusicMix(false);
    return;
  }
  if (!homeAudio || homeAudio.paused) {
    updateAmbientWaveMusicMix(false);
    return;
  }
  const audio = homeAudio;
  fadeHomeAudio(audio, 0, 550, () => {
    audio.pause();
    audio.currentTime = 0;
    updateAmbientWaveMusicMix(false);
  });
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
