#!/usr/bin/env python3
"""Render "Beacon Rondo", KeelMira's second original instrumental theme.

The three-minute master is generated without samples, voices, or third-party music.
"""

from __future__ import annotations

import argparse
import math
import wave
from pathlib import Path

import numpy as np


SAMPLE_RATE = 44_100
BPM = 96.0
BEAT = 60.0 / BPM
BAR = BEAT * 4.0
BAR_COUNT = 72
RNG = np.random.default_rng(20260809)


def frequency(note: float) -> float:
    return 440.0 * 2.0 ** ((note - 69.0) / 12.0)


def envelope(t: np.ndarray, duration: float, attack: float, decay: float,
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


def harmonics(phase: np.ndarray, partials: list[tuple[float, float]]) -> np.ndarray:
    output = np.zeros_like(phase)
    fundamental = (phase[-1] - phase[0]) / max(len(phase) - 1, 1) * SAMPLE_RATE / (2 * math.pi)
    for ratio, level in partials:
        if fundamental * ratio < SAMPLE_RATE * 0.47:
            output += level * np.sin(phase * ratio)
    return output


def synth(kind: str, note: float, duration: float, level: float) -> np.ndarray:
    count = max(1, int(duration * SAMPLE_RATE))
    t = np.arange(count, dtype=np.float64) / SAMPLE_RATE
    hz = frequency(note)
    phase = 2 * math.pi * hz * t

    if kind == "wire":
        body = harmonics(phase, [(1, 1.0), (2, .28), (3, .19), (4, .10), (6, .045), (8, .022)])
        transient = RNG.normal(0, 1, count) * np.exp(-t * 82) * .028
        signal = body * np.exp(-t * (2.35 + hz / 1800)) + transient
        env = envelope(t, duration, .005, .08, .32, min(.48, duration * .45))
    elif kind == "glass_reed":
        vibrato = .0022 * np.sin(2 * math.pi * 5.35 * t) + .0007 * np.sin(2 * math.pi * 3.7 * t)
        carrier = phase + hz * vibrato
        fm_index = 1.15 * np.exp(-t * .8) + .22
        signal = np.sin(carrier + fm_index * np.sin(carrier * 2.01))
        signal += .16 * np.sin(carrier * 3.0) + .055 * np.sin(carrier * 5.0)
        env = envelope(t, duration, .032, .20, .73, min(.42, duration * .28))
    elif kind == "air_reed":
        vibrato = .003 * np.sin(2 * math.pi * 4.8 * t)
        signal = np.sin(phase + hz * vibrato) + .11 * np.sin(phase * 2) + .045 * np.sin(phase * 3)
        noise = RNG.normal(0, 1, count)
        noise = np.concatenate(([0.0], np.diff(noise))) * .006
        signal += noise
        env = envelope(t, duration, .10, .30, .69, min(.58, duration * .30))
    elif kind == "pad":
        signal = np.zeros_like(t)
        for cents, width in [(-10, .31), (0, .45), (9, .30)]:
            detuned = hz * 2 ** (cents / 1200)
            p = 2 * math.pi * detuned * t
            signal += width * harmonics(p, [(1, 1.0), (3, .11), (5, .035), (7, .014)])
        env = envelope(t, duration, .78, .65, .76, min(1.25, duration * .28))
    elif kind == "sub":
        signal = np.sin(phase) + .20 * np.sin(phase * 2) + .065 * np.sin(phase * 3)
        env = envelope(t, duration, .025, .12, .72, min(.28, duration * .25))
    elif kind == "mallet":
        signal = harmonics(phase, [(1, 1.0), (3.98, .22), (9.7, .075), (10.8, .035)])
        signal *= np.exp(-t * (3.1 + hz / 2000))
        env = envelope(t, duration, .003, .055, .28, min(.38, duration * .38))
    elif kind == "metal":
        signal = harmonics(phase, [(1, .7), (1.414, .24), (2.37, .17), (3.76, .08), (5.22, .035)])
        signal *= np.exp(-t * 3.9)
        env = envelope(t, duration, .002, .04, .25, min(.42, duration * .45))
    else:
        raise ValueError(kind)
    return (signal * env * level).astype(np.float32)


def pan(pan_value: float) -> tuple[float, float]:
    angle = (np.clip(pan_value, -1, 1) + 1) * math.pi / 4
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


def add_kick(track: np.ndarray, start: float, level: float) -> None:
    duration = .42
    count = int(duration * SAMPLE_RATE)
    t = np.arange(count, dtype=np.float64) / SAMPLE_RATE
    phase = 2 * math.pi * (72 * t - 29 * t * t / duration)
    sample = np.sin(phase) * np.exp(-t * 11) * level
    begin = int(start * SAMPLE_RATE)
    end = min(begin + count, len(track))
    track[begin:end, 0] += sample[:end - begin] * .707
    track[begin:end, 1] += sample[:end - begin] * .707


def add_click(track: np.ndarray, start: float, level: float, pan_value: float) -> None:
    duration = .075
    count = int(duration * SAMPLE_RATE)
    t = np.arange(count, dtype=np.float64) / SAMPLE_RATE
    noise = RNG.normal(0, 1, count)
    bright = np.concatenate(([0.0], np.diff(noise)))
    sample = (bright * .16 + np.sin(2 * math.pi * 1_280 * t) * .12) * np.exp(-t * 61) * level
    begin = int(start * SAMPLE_RATE)
    end = min(begin + count, len(track))
    left, right = pan(pan_value)
    track[begin:end, 0] += sample[:end - begin] * left
    track[begin:end, 1] += sample[:end - begin] * right


def add_hat(track: np.ndarray, start: float, level: float, pan_value: float) -> None:
    duration = .12
    count = int(duration * SAMPLE_RATE)
    t = np.arange(count, dtype=np.float64) / SAMPLE_RATE
    noise = RNG.normal(0, 1, count)
    high = np.concatenate(([0.0], np.diff(noise)))
    sample = high * np.exp(-t * 38) * level * .13
    begin = int(start * SAMPLE_RATE)
    end = min(begin + count, len(track))
    left, right = pan(pan_value)
    track[begin:end, 0] += sample[:end - begin] * left
    track[begin:end, 1] += sample[:end - begin] * right


PROGRESSIONS = [
    [(40, 52, 56, 59, 66), (47, 54, 59, 63, 68), (45, 52, 56, 61, 63), (47, 54, 59, 64, 66),
     (37, 49, 52, 56, 59), (47, 51, 56, 59, 63), (45, 52, 57, 59, 64), (47, 54, 59, 64, 66)],
    [(40, 52, 56, 59, 66), (39, 47, 54, 59, 63), (37, 49, 52, 56, 59), (45, 52, 56, 61, 64),
     (44, 52, 56, 59, 64), (42, 49, 52, 56, 61), (47, 52, 57, 59, 64), (47, 54, 57, 64, 66)],
    [(40, 52, 56, 59, 66), (40, 50, 54, 57, 61), (37, 49, 52, 57, 61), (37, 49, 52, 56, 59),
     (42, 49, 52, 57, 61), (47, 52, 57, 59, 64), (40, 52, 56, 59, 66), (47, 54, 59, 64, 66)],
    [(37, 49, 52, 56, 59), (47, 51, 56, 59, 63), (45, 52, 56, 61, 64), (44, 52, 56, 59, 64),
     (42, 49, 52, 57, 61), (40, 49, 52, 56, 61), (38, 50, 54, 57, 61), (47, 54, 57, 64, 66)],
    [(37, 49, 52, 56, 59), (45, 52, 56, 61, 64), (47, 52, 56, 59, 64), (47, 54, 59, 63, 66),
     (42, 49, 52, 57, 61), (44, 51, 56, 59, 63), (45, 52, 56, 61, 64), (47, 54, 57, 64, 66)],
    [(40, 52, 55, 59, 66), (36, 48, 52, 55, 59), (43, 50, 55, 59, 62), (38, 50, 54, 57, 62),
     (45, 48, 52, 55, 59), (40, 47, 52, 55, 59), (36, 48, 52, 55, 66), (47, 51, 57, 62, 65)],
    [(37, 49, 52, 56, 59), (45, 52, 56, 61, 64), (47, 52, 56, 59, 64), (47, 54, 59, 64, 66),
     (42, 49, 52, 57, 61), (44, 51, 56, 59, 63), (45, 52, 56, 61, 64), (47, 54, 57, 64, 66)],
    [(40, 52, 56, 59, 66), (39, 47, 54, 59, 63), (37, 49, 52, 56, 59), (45, 52, 56, 61, 64),
     (44, 52, 56, 59, 64), (42, 49, 52, 56, 61), (38, 50, 54, 57, 61), (47, 54, 57, 64, 66)],
    [(40, 52, 56, 59, 66), (40, 50, 54, 57, 61), (37, 49, 52, 57, 61), (37, 49, 52, 56, 59),
     (42, 49, 52, 57, 61), (47, 52, 57, 59, 64), (40, 52, 56, 59, 66), (40, 52, 56, 59, 61)],
]

CHORDS = [chord for section in PROGRESSIONS for chord in section]
SECTION_LEVELS = [.35, .55, .62, .70, .82, .86, .43, .74, .52]

MAJOR_MOTIF = [
    [(0, 1.5, 71), (1.5, .5, 76), (2, 1, 75), (3, 1, 73)],
    [(0, 1, 68), (1, 1, 71), (2, 1.5, 66), (3.5, .5, 64)],
]
MIXOLYDIAN_MOTIF = [
    [(0, 1.5, 71), (1.5, .5, 76), (2, 1, 74), (3, 1, 73)],
    [(0, 1, 68), (1, 1, 71), (2, 1.5, 66), (3.5, .5, 64)],
]
MINOR_MOTIF = [
    [(0, 1.5, 71), (1.5, .5, 76), (2, 1, 74), (3, 1, 72)],
    [(0, 1, 67), (1, 1, 71), (2, 1.5, 66), (3.5, .5, 64)],
]


def render() -> np.ndarray:
    frame_count = int(BAR_COUNT * BAR * SAMPLE_RATE)
    track = np.zeros((frame_count, 2), dtype=np.float32)

    for bar, chord in enumerate(CHORDS):
        section = bar // 8
        density = SECTION_LEVELS[section]
        start = bar * BAR

        # Breathing, harmonically restrained pad.
        for index, chord_note in enumerate(chord[2:]):
            add_note(track, start, BAR + .72, chord_note + 12,
                     .027 + density * .025, "pad", (-.58, .02, .58)[index])

        # Muted-wire 3+3+2 engine: accents at 0, 3, and 6 eighth notes.
        figure = [chord[1], chord[2], chord[3], chord[2], chord[4], chord[3], chord[2], chord[4]]
        for step, chord_note in enumerate(figure):
            accented = step in (0, 3, 6)
            amount = (.067 if accented else .044) * (.55 + density)
            human = float(RNG.uniform(-.006, .006))
            add_note(track, start + step * .5 * BEAT + human, .72,
                     chord_note + 12, amount, "wire", -.37 if step % 2 == 0 else .37)

        # Marimba-like low answers establish a second, non-piano identity.
        add_note(track, start, 1.05, chord[1], .062 * (.65 + density), "mallet", -.11)
        add_note(track, start + 1.5 * BEAT, .88, chord[2], .041 * (.65 + density), "mallet", .13)
        add_note(track, start + 3 * BEAT, .72, chord[3], .038 * (.65 + density), "mallet", .08)

        if 16 <= bar < 64:
            add_note(track, start, 1.22, chord[0], .072 * density, "sub", 0)
            add_note(track, start + 2 * BEAT, .92, chord[1], .046 * density, "sub", 0)

        if 16 <= bar < 64 and not 48 <= bar < 56:
            add_kick(track, start, .095 * density)
            add_click(track, start + 1.5 * BEAT, .44 * density, -.20)
            add_kick(track, start + 3 * BEAT, .055 * density)
            add_click(track, start + 3.5 * BEAT, .34 * density, .20)
        if 16 <= bar < 64:
            for step in range(8):
                add_hat(track, start + step * .5 * BEAT,
                        (.20 if step in (0, 3, 6) else .12) * density,
                        -.45 if step % 2 == 0 else .45)

        if bar in (0, 8, 24, 40, 48, 56, 64):
            add_note(track, start, 3.2, chord[4] + 12, .052 + density * .025,
                     "metal", -.28 if section % 2 == 0 else .28)

    # State the hook in changing modes, registers, and instrumental colors.
    for section in range(1, 9):
        first_bar = section * 8
        if section == 5:
            motif = MINOR_MOTIF
        elif section in (2, 8):
            motif = MIXOLYDIAN_MOTIF
        else:
            motif = MAJOR_MOTIF
        repetitions = 2 if section in (1, 2, 5, 8) else 3
        for repetition in range(repetitions):
            pair_start = first_bar + repetition * 2
            octave = 0 if section < 6 else 12 if section == 7 else 0
            kind = "glass_reed" if section not in (3, 5) else "air_reed"
            base_level = .087 if section < 4 else .103 if section < 7 else .116
            for relative_bar, notes in enumerate(motif):
                for offset, duration, note in notes:
                    add_note(track, (pair_start + relative_bar) * BAR + offset * BEAT,
                             duration * BEAT + .22, note + octave, base_level,
                             kind, .04)

        # Contrapuntal answer appears after the first statement.
        if section in (2, 3, 4, 6, 7):
            answer_start = first_bar + 4
            answer = [(0, 1, 59), (1, 1, 61), (2, 1.5, 64), (3.5, .5, 66),
                      (4, 1, 68), (5, 1, 66), (6, 1, 64), (7, 1, 61)]
            for beat_offset, duration, note in answer:
                add_note(track, answer_start * BAR + beat_offset * BEAT,
                         duration * BEAT + .30, note, .060, "air_reed", -.20)

    # Complete ending: a quiet E6/9 sonority fades to silence for playlist transition.
    final_start = 70 * BAR
    for note, side in [(52, 0), (56, -.28), (59, .28), (61, -.48), (66, .48)]:
        add_note(track, final_start, 2 * BAR, note + (12 if note > 52 else 0),
                 .055, "pad", side)

    # Dark chamber: longer and less reflective than the first theme's wooden room.
    dry = track.copy()
    wet = np.zeros_like(dry)
    for delay, gain, cross in [(0.61, .070, False), (0.83, .058, True), (1.17, .043, False),
                               (1.71, .031, True), (2.43, .022, False), (2.91, .016, True)]:
        shift = int(delay * SAMPLE_RATE)
        wet[:, 0] += np.roll(dry[:, 1 if cross else 0], shift) * gain
        wet[:, 1] += np.roll(dry[:, 0 if cross else 1], shift + 53) * gain
    mix = dry * .91 + wet

    # Long, interpolated section gain keeps orchestration changes from becoming
    # volume jumps. The small target differences preserve the rise and release of
    # the composition without making the home screen suddenly loud.
    section_targets_db = np.array(
        [-20.7, -19.9, -19.6, -19.3, -19.0, -19.3, -19.8, -18.9, -20.0],
        dtype=np.float64,
    )
    section_frames = len(mix) // len(section_targets_db)
    measured_db = []
    centers = []
    for section_index, target_db in enumerate(section_targets_db):
        begin = section_index * section_frames
        end = len(mix) if section_index == len(section_targets_db) - 1 else begin + section_frames
        section_rms = max(float(np.sqrt(np.mean(mix[begin:end] * mix[begin:end]))), 1e-8)
        measured_db.append(20 * math.log10(section_rms))
        centers.append((begin + end - 1) * .5)

    required_gain_db = section_targets_db - np.array(measured_db)
    gain_db = np.interp(
        np.arange(len(mix), dtype=np.float64),
        np.array(centers),
        required_gain_db,
    )
    mix *= np.power(10.0, gain_db / 20.0)[:, None].astype(np.float32)

    # Program-dependent volume riding softens a loud new motif after a quiet
    # cadence. Interpolation between one-second measurements avoids pumping.
    ride_centers = []
    ride_gain_db = []
    ride_target_db = -19.5
    ride_block = SAMPLE_RATE
    for begin in range(0, len(mix), ride_block):
        end = min(begin + ride_block, len(mix))
        block_rms = max(float(np.sqrt(np.mean(mix[begin:end] * mix[begin:end]))), 1e-8)
        block_db = 20 * math.log10(block_rms)
        ride_centers.append((begin + end - 1) * .5)
        ride_gain_db.append(np.clip((ride_target_db - block_db) * .80, -5.5, 5.5))
    ride_curve_db = np.interp(
        np.arange(len(mix), dtype=np.float64),
        np.array(ride_centers),
        np.array(ride_gain_db),
    )
    mix *= np.power(10.0, ride_curve_db / 20.0)[:, None].astype(np.float32)

    # A low-ratio peak compressor catches isolated mallet and drum transients.
    threshold = 10 ** (-13.0 / 20.0)
    magnitude = np.abs(mix)
    over = np.maximum(magnitude / threshold, 1.0)
    mix *= np.power(over, (1.0 / 1.65) - 1.0)

    # Conservative final gain leaves headroom for AAC encoding and the wave layer.
    rms = float(np.sqrt(np.mean(mix * mix)))
    target_rms = 10 ** (-19.5 / 20)
    if rms > 0:
        mix *= target_rms / rms
    peak = float(np.max(np.abs(mix)))
    if peak > .82:
        mix *= .82 / peak

    # Musicological fade rather than a hard sample boundary; track 1 fades in next.
    fade_frames = int(2.3 * SAMPLE_RATE)
    fade = np.cos(np.linspace(0, math.pi / 2, fade_frames, dtype=np.float32)) ** 2
    mix[-fade_frames:] *= fade[:, None]
    return mix.astype(np.float32)


def write_wave(path: Path, audio: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(audio, -1, 1) * 32767).astype("<i2")
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
