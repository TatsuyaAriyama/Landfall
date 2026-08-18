#!/usr/bin/env python3
"""Render the three-minute Harbor Minuet, KeelMira's calm main theme.

Every sound is synthesized here. There are no voices, samples, or borrowed music.
"""

from __future__ import annotations

import argparse
import math
import wave
from pathlib import Path

import numpy as np


SAMPLE_RATE = 44_100
BPM = 72.0
BEAT = 60.0 / BPM
BAR = BEAT * 3.0
BAR_COUNT = 72
RNG = np.random.default_rng(20260810)
DITHER_RNG = np.random.default_rng(20260811)


def frequency(note: float) -> float:
    return 440.0 * 2.0 ** ((note - 69.0) / 12.0)


def adsr(t: np.ndarray, duration: float, attack: float, decay: float,
         sustain: float, release: float) -> np.ndarray:
    result = np.full_like(t, sustain)
    attack_mask = t < attack
    result[attack_mask] = np.sin(np.clip(t[attack_mask] / max(attack, 1e-5), 0, 1) * math.pi / 2) ** 2
    decay_mask = (t >= attack) & (t < attack + decay)
    decay_position = (t[decay_mask] - attack) / max(decay, 1e-5)
    result[decay_mask] = 1.0 - (1.0 - sustain) * decay_position
    release_start = max(duration - release, attack + decay)
    release_mask = t >= release_start
    release_position = (t[release_mask] - release_start) / max(duration - release_start, 1e-5)
    result[release_mask] *= np.cos(np.clip(release_position, 0, 1) * math.pi / 2) ** 2
    return result


def partials(phase: np.ndarray, hz: float, spectrum: list[tuple[float, float]]) -> np.ndarray:
    output = np.zeros_like(phase)
    for ratio, level in spectrum:
        if hz * ratio < SAMPLE_RATE * .46:
            output += level * np.sin(phase * ratio)
    return output


def synth(kind: str, note: float, duration: float, level: float) -> np.ndarray:
    count = max(1, int(duration * SAMPLE_RATE))
    t = np.arange(count, dtype=np.float64) / SAMPLE_RATE
    hz = frequency(note)
    phase = 2 * math.pi * hz * t

    if kind == "mooring_felt":
        body = partials(phase, hz, [(1, 1), (2, .27), (3, .12), (4.01, .048), (5.98, .018)])
        wood = .13 * np.sin(phase * .5) if hz < 220 else 0.0
        noise = RNG.normal(0, 1, count)
        softened = np.convolve(noise, np.ones(11) / 11, mode="same")
        signal = (body + wood) * np.exp(-t * (1.0 + hz / 2300))
        signal += softened * np.exp(-t * 48) * .018
        env = adsr(t, duration, .018, .22, .58, min(1.25, duration * .38))
    elif kind == "rope_harp":
        signal = partials(phase, hz, [(1, 1), (2, .31), (3, .15), (4, .066), (5, .027)])
        signal *= np.exp(-t * (1.42 + hz / 1900))
        env = adsr(t, duration, .014, .16, .43, min(.95, duration * .42))
    elif kind == "horizon_strings":
        vibrato = .0018 * np.sin(2 * math.pi * 4.65 * t) + .0007 * np.sin(2 * math.pi * 5.2 * t)
        p = phase + hz * vibrato
        signal = partials(p, hz, [(1, 1), (2, .19), (3, .105), (4, .040), (5, .022)])
        env = adsr(t, duration, 1.25, .75, .79, min(1.65, duration * .32))
    elif kind == "tide_cello":
        vibrato = .0024 * np.sin(2 * math.pi * 4.35 * t)
        p = phase + hz * vibrato
        signal = partials(p, hz, [(1, 1), (2, .29), (3, .16), (4, .055), (5, .024)])
        env = adsr(t, duration, .34, .44, .75, min(1.15, duration * .31))
    elif kind == "deep_harbor":
        signal = np.zeros_like(t)
        for cents, width in [(-7, .29), (0, .43), (6, .27)]:
            detuned = hz * 2 ** (cents / 1200)
            p = 2 * math.pi * detuned * t
            signal += width * partials(p, detuned, [(1, 1), (2, .10), (3, .045)])
        env = adsr(t, duration, 1.35, .8, .78, min(1.9, duration * .34))
    elif kind == "buoy_bell":
        signal = partials(phase, hz, [(1, .85), (1.49, .24), (2.34, .15), (3.16, .065), (4.72, .026)])
        signal *= np.exp(-t * .88)
        env = adsr(t, duration, .016, .13, .52, min(1.6, duration * .52))
    elif kind == "dock_wood":
        signal = partials(phase, hz, [(1, 1), (2.04, .18), (3.9, .055)]) * np.exp(-t * 9.5)
        env = adsr(t, duration, .012, .055, .25, min(.32, duration * .46))
    else:
        raise ValueError(kind)
    return (signal * env * level).astype(np.float32)


def pan(value: float) -> tuple[float, float]:
    angle = (np.clip(value, -1, 1) + 1) * math.pi / 4
    return float(math.cos(angle)), float(math.sin(angle))


def add_note(track: np.ndarray, start: float, duration: float, note: float,
             level: float, kind: str, pan_value: float = 0) -> None:
    sample = synth(kind, note, duration, level)
    begin = int(start * SAMPLE_RATE)
    end = min(begin + len(sample), len(track))
    if begin < 0 or begin >= end:
        return
    left, right = pan(pan_value)
    track[begin:end, 0] += sample[:end - begin] * left
    track[begin:end, 1] += sample[:end - begin] * right


PROGRESSIONS = [
    [(34, 46, 50, 53, 60), (33, 45, 48, 53, 57), (31, 43, 46, 50, 53), (29, 41, 45, 50, 53),
     (39, 51, 55, 58, 62), (38, 46, 50, 53, 58), (36, 48, 51, 55, 62), (41, 48, 53, 58, 60)],
    [(34, 46, 50, 53, 60), (33, 45, 48, 53, 57), (31, 43, 46, 50, 53), (29, 41, 45, 48, 53),
     (39, 51, 55, 58, 62), (38, 46, 50, 53, 58), (36, 48, 51, 55, 62), (41, 48, 53, 58, 60)],
    [(38, 46, 50, 53, 58), (39, 51, 55, 58, 62), (39, 51, 53, 57, 60), (29, 41, 45, 48, 53),
     (31, 43, 46, 50, 57), (36, 48, 51, 55, 58), (41, 48, 53, 57, 60), (34, 46, 50, 53, 55)],
    [(31, 43, 46, 50, 57), (29, 41, 45, 48, 53), (39, 51, 55, 58, 62), (38, 46, 50, 53, 58),
     (36, 48, 51, 55, 62), (34, 43, 46, 50, 55), (33, 45, 48, 51, 55), (38, 45, 50, 55, 60)],
    [(31, 43, 46, 50, 57), (29, 41, 45, 48, 53), (39, 51, 55, 58, 62), (38, 46, 50, 53, 58),
     (36, 48, 51, 55, 62), (34, 43, 46, 50, 55), (33, 45, 50, 57, 60), (31, 43, 46, 50, 57)],
    [(39, 51, 55, 58, 65), (38, 46, 50, 55, 58), (36, 48, 51, 55, 58), (34, 43, 46, 50, 55),
     (32, 44, 48, 51, 55), (31, 43, 46, 51, 55), (41, 53, 56, 60, 67), (46, 53, 58, 63, 65)],
    [(39, 51, 55, 58, 63), (38, 46, 50, 55, 58), (36, 48, 51, 55, 62), (31, 43, 46, 50, 58),
     (32, 44, 48, 51, 55), (31, 43, 46, 51, 55), (41, 48, 53, 58, 60), (41, 48, 53, 57, 60)],
    [(34, 46, 50, 53, 60), (33, 45, 48, 53, 57), (31, 43, 46, 50, 53), (29, 41, 45, 48, 53),
     (39, 51, 55, 58, 62), (38, 46, 50, 53, 58), (36, 48, 51, 55, 62), (41, 48, 53, 58, 60)],
    [(38, 46, 50, 53, 58), (39, 51, 55, 58, 62), (34, 46, 53, 58, 60), (41, 48, 53, 58, 60),
     (31, 43, 46, 50, 53), (39, 51, 55, 58, 60), (34, 46, 53, 57, 60), (34, 46, 50, 53, 55)],
]

CHORDS = [chord for section in PROGRESSIONS for chord in section]
SECTION_TARGETS_DB = np.array([-20.6, -20.1, -19.9, -20.2, -20.3, -19.7, -20.1, -19.9, -20.8])

HARBOR_THEME = [
    [(0, 1.5, 74), (1.5, .5, 77), (2, 1, 79)],
    [(0, 1, 77), (1, 1, 74), (2, 1, 72)],
    [(0, 1, 72), (1, 1, 74), (2, .5, 77), (2.5, .5, 75)],
    [(0, 2, 74), (2, 1, 70)],
]


def section_blend(bar: int) -> float:
    """A gentle two-bar swell that prevents new sections from snapping in."""
    within = bar % 8
    if within < 2:
        return .76 + .12 * within
    if within > 5:
        return 1.0 - .10 * (within - 5)
    return 1.0


def add_theme(track: np.ndarray, first_bar: int, transpose: int, kind: str,
              level: float, pan_value: float, lower_answer: bool = False) -> None:
    for relative_bar, notes in enumerate(HARBOR_THEME):
        for offset, duration, note in notes:
            add_note(track, (first_bar + relative_bar) * BAR + offset * BEAT,
                     duration * BEAT + .72, note + transpose, level, kind, pan_value)
            if lower_answer:
                add_note(track, (first_bar + relative_bar) * BAR + offset * BEAT + .085,
                         duration * BEAT + 1.0, note + transpose - 9,
                         level * .32, "horizon_strings", -.22)


def render() -> np.ndarray:
    frame_count = int(BAR_COUNT * BAR * SAMPLE_RATE)
    track = np.zeros((frame_count, 2), dtype=np.float32)

    for bar, chord in enumerate(CHORDS):
        section = bar // 8
        start = bar * BAR
        blend = section_blend(bar)

        # One low mooring tone and long upper harmony create a breathing 3/4.
        add_note(track, start, BAR + 1.4, chord[0], .046 * blend, "deep_harbor", 0)
        for index, note in enumerate(chord[2:]):
            section_width = .82 if section in (5, 6) else .68
            level = (.027 if section in (0, 4, 8) else .033) * blend
            add_note(track, start, BAR + 1.25, note + 12, level,
                     "horizon_strings", (-section_width, 0, section_width)[index])

        # The harp suggests water without becoming a continuous mechanical pattern.
        if bar % 2 == 0 or section in (1, 5, 7):
            figure = [chord[1], chord[2], chord[3], chord[2], chord[4], chord[3]]
            for step, note in enumerate(figure):
                human = float(RNG.uniform(-.010, .010))
                add_note(track, start + step * .5 * BEAT + human, 1.32,
                         note + 12, (.047 if step in (0, 3) else .035) * blend,
                         "rope_harp", -.30 if step % 2 == 0 else .30)

        # Cello phrases breathe over two bars; there is no repeating percussion.
        if section not in (0, 4, 8) and bar % 2 == 0:
            add_note(track, start + .06, 2 * BAR + .8, chord[1], .041 * blend,
                     "tide_cello", -.06)

        # Soft wood only marks an occasional mooring point.
        if bar in (0, 16, 32, 48, 64):
            add_note(track, start, .58, chord[1] + 12, .036, "dock_wood", -.10)

    # Intro fragments are distant and sparse.
    for bar, note, side in [(0, 74, -.28), (3, 77, .28), (6, 79, -.18)]:
        add_note(track, bar * BAR + .05, 3.7, note - 12, .032, "buoy_bell", side)

    # Main statements, minor trio, open horizon, and final return.
    add_theme(track, 8, 0, "mooring_felt", .083, .04)
    add_theme(track, 16, 0, "mooring_felt", .072, .06, lower_answer=True)
    add_theme(track, 24, -12, "tide_cello", .068, -.08)
    add_theme(track, 40, 5, "mooring_felt", .076, .04, lower_answer=True)
    add_theme(track, 56, 0, "mooring_felt", .078, .03, lower_answer=True)

    # A few low buoy notes define the harbor without bright, intrusive chimes.
    for bar, note, side in [(12, 70, .32), (28, 67, -.30), (44, 75, .28),
                            (52, 72, -.26), (60, 70, .24), (68, 65, -.20)]:
        add_note(track, bar * BAR + .04, 4.2, note, .028, "buoy_bell", side)

    # Coda retains only the opening three-note gesture.
    for offset, duration, note in HARBOR_THEME[0]:
        add_note(track, 64 * BAR + offset * BEAT, duration * BEAT + .8,
                 note - 12, .050, "mooring_felt", .02)

    # Zero-padded wooden-dock reflections: no tail is wrapped into the opening.
    dry = track.copy()
    wet = np.zeros_like(dry)
    for delay, gain, cross in [(0.045, .085, False), (0.079, .070, True), (.127, .052, False),
                               (.191, .038, True), (.72, .028, False), (1.31, .020, True),
                               (2.08, .014, False), (2.74, .009, True)]:
        shift = int(delay * SAMPLE_RATE)
        if shift >= len(dry):
            continue
        wet[shift:, 0] += dry[:-shift, 1 if cross else 0] * gain
        wet[shift:, 1] += dry[:-shift, 0 if cross else 1] * gain
    mix = dry * .92 + wet

    # Nine-section loudness contour; expression comes from range and orchestration.
    section_frames = len(mix) // len(SECTION_TARGETS_DB)
    centers = []
    required = []
    for index, target_db in enumerate(SECTION_TARGETS_DB):
        begin = index * section_frames
        end = len(mix) if index == len(SECTION_TARGETS_DB) - 1 else begin + section_frames
        rms = max(float(np.sqrt(np.mean(mix[begin:end] ** 2))), 1e-8)
        centers.append((begin + end - 1) * .5)
        required.append(target_db - 20 * math.log10(rms))
    section_gain_db = np.interp(np.arange(len(mix)), centers, required)
    mix *= np.power(10, section_gain_db / 20)[:, None].astype(np.float32)

    # A restrained one-second ride reduces cadence-to-theme jumps without pumping.
    ride_centers = []
    ride_gains = []
    for begin in range(0, len(mix), SAMPLE_RATE):
        end = min(begin + SAMPLE_RATE, len(mix))
        rms = max(float(np.sqrt(np.mean(mix[begin:end] ** 2))), 1e-8)
        local_db = 20 * math.log10(rms)
        ride_centers.append((begin + end - 1) * .5)
        ride_gains.append(np.clip((-20.0 - local_db) * .76, -4.4, 3.5))
    ride_curve_db = np.interp(np.arange(len(mix)), ride_centers, ride_gains)
    mix *= np.power(10, ride_curve_db / 20)[:, None].astype(np.float32)

    # Stereo-linked, low-ratio peak control.
    linked = np.max(np.abs(mix), axis=1)
    threshold = 10 ** (-14 / 20)
    over = np.maximum(linked / threshold, 1.0)
    gain = np.power(over, (1 / 1.40) - 1)
    mix *= gain[:, None].astype(np.float32)

    rms = float(np.sqrt(np.mean(mix ** 2)))
    if rms > 0:
        mix *= (10 ** (-19.8 / 20)) / rms
    peak = float(np.max(np.abs(mix)))
    if peak > .52:
        mix *= .52 / peak

    # Complete the cadence before the playlist fades in Beacon Rondo.
    fade_frames = int(2.45 * SAMPLE_RATE)
    fade = np.cos(np.linspace(0, math.pi / 2, fade_frames, dtype=np.float32)) ** 2
    mix[-fade_frames:] *= fade[:, None]
    return mix.astype(np.float32)


def write_wave(path: Path, audio: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    dither = (DITHER_RNG.random(audio.shape) - DITHER_RNG.random(audio.shape)) / 32768.0
    pcm = (np.clip(audio + dither, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(pcm.tobytes())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    audio = render()
    write_wave(args.output, audio)
    print(f"Rendered {len(audio) / SAMPLE_RATE:.3f}s to {args.output}")


if __name__ == "__main__":
    main()
