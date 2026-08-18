#!/usr/bin/env python3
"""Render KeelMira's three-minute Celestial Navigation Nocturne.

The soundtrack is fully synthesized: no samples, voices, or borrowed music.
"""

from __future__ import annotations

import argparse
import math
import wave
from pathlib import Path

import numpy as np


SAMPLE_RATE = 44_100
DOTTED_BPM = 64.0
DOTTED_BEAT = 60.0 / DOTTED_BPM
EIGHTH = DOTTED_BEAT / 3.0
BAR = DOTTED_BEAT * 4.0
BAR_COUNT = 48
RNG = np.random.default_rng(20260812)
DITHER_RNG = np.random.default_rng(20260813)


def frequency(note: float) -> float:
    return 440.0 * 2.0 ** ((note - 69.0) / 12.0)


def envelope(t: np.ndarray, duration: float, attack: float, decay: float,
             sustain: float, release: float) -> np.ndarray:
    output = np.full_like(t, sustain)
    attack_mask = t < attack
    output[attack_mask] = np.sin(np.clip(t[attack_mask] / max(attack, 1e-5), 0, 1) * math.pi / 2) ** 2
    decay_mask = (t >= attack) & (t < attack + decay)
    position = (t[decay_mask] - attack) / max(decay, 1e-5)
    output[decay_mask] = 1 - (1 - sustain) * position
    release_start = max(duration - release, attack + decay)
    release_mask = t >= release_start
    position = (t[release_mask] - release_start) / max(duration - release_start, 1e-5)
    output[release_mask] *= np.cos(np.clip(position, 0, 1) * math.pi / 2) ** 2
    return output


def partials(phase: np.ndarray, hz: float, spectrum: list[tuple[float, float]]) -> np.ndarray:
    signal = np.zeros_like(phase)
    for ratio, level in spectrum:
        if hz * ratio < SAMPLE_RATE * .46:
            signal += level * np.sin(phase * ratio)
    return signal


def synth(kind: str, note: float, duration: float, level: float) -> np.ndarray:
    count = max(1, int(duration * SAMPLE_RATE))
    t = np.arange(count, dtype=np.float64) / SAMPLE_RATE
    hz = frequency(note)
    phase = 2 * math.pi * hz * t

    if kind == "nylon":
        body = partials(phase, hz, [(1, 1), (2, .24), (3, .105), (4, .047), (5, .020)])
        body += .045 * np.sin(phase * .5) if hz < 250 else 0.0
        signal = body * np.exp(-t * (1.36 + hz / 2200))
        env = envelope(t, duration, .014, .15, .46, min(.95, duration * .40))
    elif kind == "harmonic":
        signal = partials(phase, hz, [(1, .82), (2, .14), (3, .035)])
        signal *= np.exp(-t * 1.12)
        env = envelope(t, duration, .022, .14, .58, min(1.15, duration * .48))
    elif kind == "aurora":
        signal = np.zeros_like(t)
        for cents, width in [(-6, .28), (0, .42), (7, .26)]:
            detuned = hz * 2 ** (cents / 1200)
            p = 2 * math.pi * detuned * t
            signal += width * partials(p, detuned, [(1, 1), (2, .12), (3, .045), (5, .012)])
        env = envelope(t, duration, 1.55, .85, .80, min(2.2, duration * .34))
    elif kind == "vibraphone":
        signal = partials(phase, hz, [(1, .90), (2, .08), (3.97, .035)])
        signal *= np.exp(-t * .73)
        env = envelope(t, duration, .012, .12, .56, min(1.45, duration * .46))
    elif kind == "current_bass":
        signal = np.sin(phase) + .12 * np.sin(phase * 2) + .025 * np.sin(phase * 3)
        env = envelope(t, duration, .21, .35, .76, min(.92, duration * .28))
    elif kind == "ceramic":
        signal = partials(phase, hz, [(1, .86), (2.71, .10), (4.16, .030)])
        signal *= np.exp(-t * 1.55)
        env = envelope(t, duration, .009, .08, .43, min(.78, duration * .42))
    elif kind == "star_grain":
        carrier = np.sin(phase + .13 * np.sin(phase * 2.0))
        env = np.sin(np.linspace(0, math.pi, count)) ** 2
        signal = carrier
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
    [(36, 48, 51, 55, 62), (32, 44, 48, 51, 55), (31, 43, 46, 51, 55), (43, 50, 55, 60, 62),
     (36, 48, 51, 55, 58), (41, 53, 56, 60, 63), (38, 50, 53, 56, 60), (43, 50, 55, 60, 62)],
    [(36, 48, 51, 55, 58), (34, 43, 50, 55, 58), (32, 44, 48, 51, 55), (31, 43, 46, 51, 55),
     (41, 53, 56, 60, 63), (39, 48, 51, 55, 60), (38, 50, 53, 56, 60), (43, 50, 55, 59, 62)],
    [(39, 51, 55, 58, 65), (38, 50, 53, 58, 62), (36, 48, 51, 55, 58), (34, 43, 50, 55, 58),
     (32, 44, 48, 51, 55), (31, 43, 46, 51, 55), (41, 53, 56, 60, 63), (46, 53, 58, 63, 65)],
    [(41, 53, 56, 60, 63), (39, 48, 51, 56, 60), (37, 49, 53, 56, 60), (36, 44, 48, 53, 56),
     (34, 46, 49, 53, 56), (32, 41, 48, 53, 56), (38, 50, 53, 56, 60), (43, 50, 55, 60, 62)],
    [(36, 48, 51, 55, 58), (34, 46, 51, 55, 58), (32, 44, 48, 51, 55), (31, 43, 46, 50, 55),
     (41, 53, 56, 60, 63), (39, 48, 51, 55, 60), (38, 50, 53, 56, 60), (43, 50, 55, 59, 62)],
    [(36, 48, 51, 55, 62), (32, 44, 48, 51, 55), (31, 43, 46, 51, 55), (34, 46, 50, 53, 58),
     (41, 53, 56, 60, 63), (32, 44, 48, 51, 55), (43, 50, 55, 60, 62), (36, 48, 51, 55, 62)],
]

CHORDS = [chord for section in PROGRESSIONS for chord in section]
SECTION_TARGETS_DB = np.array([-20.7, -20.0, -19.8, -20.3, -19.5, -20.5])

CELESTIAL_THEME = [
    [(0, 3, 67), (3, 2, 72), (5, 1, 74), (6, 3, 75), (9, 3, 74)],
    [(0, 3, 72), (3, 3, 70), (6, 2, 67), (8, 1, 65), (9, 3, 67)],
]

MAJOR_VARIANT = [
    [(0, 3, 70), (3, 2, 75), (5, 1, 77), (6, 3, 79), (9, 3, 77)],
    [(0, 3, 75), (3, 3, 74), (6, 2, 70), (8, 1, 68), (9, 3, 70)],
]


def section_blend(bar: int) -> float:
    within = bar % 8
    if within < 2:
        return .78 + .11 * within
    if within > 5:
        return 1.0 - .09 * (within - 5)
    return 1.0


def add_theme(track: np.ndarray, first_bar: int, motif: list[list[tuple[float, float, int]]],
              repetitions: int, level: float, alternate: bool = False) -> None:
    for repetition in range(repetitions):
        pair_start = first_bar + repetition * 2
        for relative_bar, notes in enumerate(motif):
            for offset, duration, note in notes:
                kind = "vibraphone" if alternate and (repetition + relative_bar) % 2 else "nylon"
                note_level = level * (.82 if kind == "vibraphone" else 1.0)
                add_note(track, (pair_start + relative_bar) * BAR + offset * EIGHTH,
                         duration * EIGHTH + .64, note, note_level, kind,
                         .10 if kind == "vibraphone" else -.04)


def render() -> np.ndarray:
    frame_count = int(BAR_COUNT * BAR * SAMPLE_RATE)
    track = np.zeros((frame_count, 2), dtype=np.float32)

    for bar, chord in enumerate(CHORDS):
        section = bar // 8
        start = bar * BAR
        blend = section_blend(bar)

        # Four slow guitar points make 12/8 breathe without a drum pulse.
        figure = [chord[1], chord[2], chord[4], chord[3]]
        for point, note in enumerate(figure):
            human = float(RNG.uniform(-.014, .014))
            add_note(track, start + point * 3 * EIGHTH + human, 3.05 * EIGHTH,
                     note + 12, (.043 if point == 0 else .036) * blend,
                     "nylon", -.24 if point % 2 == 0 else .24)

        add_note(track, start, 6.1 * EIGHTH, chord[0], .044 * blend, "current_bass", 0)
        add_note(track, start + 6 * EIGHTH, 6.0 * EIGHTH, chord[1], .034 * blend, "current_bass", 0)

        # Sustained constellations change range rather than loudness.
        for index, note in enumerate(chord[2:]):
            width = .44 if section in (0, 3, 5) else .52
            add_note(track, start, BAR + 1.6, note + 12, (.023 + section * .0008) * blend,
                     "aurora", (-width, 0, width)[index])

        if section == 3 and bar % 2 == 0:
            add_note(track, start + .08, 2 * BAR + .9, chord[2], .030, "aurora", -.12)

        # Deterministic sine grains stay well below the theme.
        grain_count = 0 if section in (0, 5) else 1 if bar % 2 else 2
        for grain_index in range(grain_count):
            offset = float(RNG.uniform(.35, BAR - .55))
            note = chord[2 + ((bar + grain_index) % 3)] + 12
            add_note(track, start + offset, float(RNG.uniform(.28, .48)), note,
                     .012, "star_grain", float(RNG.uniform(-.40, .40)))

    # Opening constellation: only the first three notes are visible.
    for bar, note, side in [(0, 67, -.30), (2, 72, .26), (5, 74, -.16)]:
        add_note(track, bar * BAR + .12, 3.1, note, .020, "harmonic", side)

    add_theme(track, 8, CELESTIAL_THEME, 4, .070)
    add_theme(track, 16, MAJOR_VARIANT, 4, .067, alternate=True)
    add_theme(track, 32, CELESTIAL_THEME, 4, .071, alternate=True)
    add_theme(track, 40, CELESTIAL_THEME, 2, .052)

    # Sparse ceramic stars mark the six chapters without sounding like harbor bells.
    for bar, note, side in [(7, 79, .35), (15, 75, -.32), (23, 82, .30),
                            (31, 77, -.28), (39, 79, .26), (45, 72, -.22)]:
        add_note(track, bar * BAR + .05, 2.7, note - 12, .014, "ceramic", side)

    # Wide-night zero-padded delays; no pre-echo is wrapped into the beginning.
    dry = track.copy()
    wet = np.zeros_like(dry)
    for delay, gain, cross in [(.31, .060, False), (.47, .050, True), (.73, .040, False),
                               (1.09, .031, True), (1.63, .023, False), (2.41, .016, True),
                               (3.37, .010, False)]:
        shift = int(delay * SAMPLE_RATE)
        wet[shift:, 0] += dry[:-shift, 1 if cross else 0] * gain
        wet[shift:, 1] += dry[:-shift, 0 if cross else 1] * gain
    mix = dry * .91 + wet

    # Continuous chapter balancing keeps orchestration changes gentle.
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

    # Restrained one-second riding reduces theme entrances without flattening phrases.
    ride_centers = []
    ride_gains = []
    for begin in range(0, len(mix), SAMPLE_RATE):
        end = min(begin + SAMPLE_RATE, len(mix))
        rms = max(float(np.sqrt(np.mean(mix[begin:end] ** 2))), 1e-8)
        local_db = 20 * math.log10(rms)
        ride_centers.append((begin + end - 1) * .5)
        ride_gains.append(np.clip((-19.9 - local_db) * .78, -4.8, 3.6))
    ride_curve_db = np.interp(np.arange(len(mix)), ride_centers, ride_gains)
    mix *= np.power(10, ride_curve_db / 20)[:, None].astype(np.float32)

    # Stereo-linked low-ratio peak control.
    linked = np.max(np.abs(mix), axis=1)
    threshold = 10 ** (-14.5 / 20)
    over = np.maximum(linked / threshold, 1.0)
    mix *= np.power(over, (1 / 1.33) - 1)[:, None].astype(np.float32)

    rms = float(np.sqrt(np.mean(mix ** 2)))
    if rms > 0:
        mix *= (10 ** (-22.0 / 20)) / rms
    peak = float(np.max(np.abs(mix)))
    if peak > .40:
        mix *= .40 / peak

    fade_frames = int(2.55 * SAMPLE_RATE)
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
