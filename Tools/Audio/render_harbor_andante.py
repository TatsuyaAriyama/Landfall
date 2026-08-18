#!/usr/bin/env python3
"""Render KeelMira's three-minute "Harbor Andante".

This fully synthesized instrumental is a calm sequel to Harbor Minuet.  It uses
no samples, voices, or borrowed recordings and is deterministic from score to
16-bit PCM output.
"""

from __future__ import annotations

import argparse
import math
import wave
from pathlib import Path

import numpy as np


SAMPLE_RATE = 44_100
BPM = 80.0
BEAT = 60.0 / BPM
BAR = BEAT * 4.0
BAR_COUNT = 60
FRAME_COUNT = round(BAR_COUNT * BAR * SAMPLE_RATE)
RANDOM_SEED = 2026081101
DITHER_SEED = 2026081102


def frequency(note: float) -> float:
    return 440.0 * 2.0 ** ((note - 69.0) / 12.0)


def envelope(t: np.ndarray, duration: float, attack: float, decay: float,
             sustain: float, release: float) -> np.ndarray:
    output = np.full_like(t, sustain)
    attack_mask = t < attack
    output[attack_mask] = np.sin(
        np.clip(t[attack_mask] / max(attack, 1e-5), 0, 1) * math.pi / 2
    ) ** 2
    decay_mask = (t >= attack) & (t < attack + decay)
    decay_position = (t[decay_mask] - attack) / max(decay, 1e-5)
    output[decay_mask] = 1.0 - (1.0 - sustain) * decay_position
    release_start = max(duration - release, attack + decay)
    release_mask = t >= release_start
    release_position = (t[release_mask] - release_start) / max(
        duration - release_start, 1e-5
    )
    output[release_mask] *= np.cos(
        np.clip(release_position, 0, 1) * math.pi / 2
    ) ** 2
    return output


def partials(phase: np.ndarray, hz: float,
             spectrum: tuple[tuple[float, float], ...]) -> np.ndarray:
    signal = np.zeros_like(phase)
    for ratio, level in spectrum:
        if hz * ratio < SAMPLE_RATE * .43:
            signal += level * np.sin(phase * ratio)
    return signal


def synth(kind: str, note: float, duration: float) -> np.ndarray:
    count = max(1, round(duration * SAMPLE_RATE))
    t = np.arange(count, dtype=np.float64) / SAMPLE_RATE
    hz = frequency(note)
    phase = 2 * math.pi * hz * t

    if kind == "mooring_felt":
        # Rounded felt transient: the upper partials vanish before they can tire
        # the ear during a long work session.
        body = partials(phase, hz, ((1, 1), (2, .20), (3, .070), (4, .020)))
        body *= np.exp(-t * (1.05 + hz / 2500))
        soft_hammer = np.sin(phase * .5) * np.exp(-t * 28) * (.025 if hz < 320 else .010)
        signal = body + soft_hammer
        env = envelope(t, duration, .022, .23, .58, min(1.15, duration * .42))
    elif kind == "rope_pulse":
        signal = partials(phase, hz, ((1, 1), (2, .17), (3, .052), (4, .012)))
        signal *= np.exp(-t * (1.55 + hz / 2100))
        env = envelope(t, duration, .025, .16, .42, min(.72, duration * .43))
    elif kind == "horizon_strings":
        signal = np.zeros_like(t)
        for cents, width in ((-5, .29), (0, .42), (6, .27)):
            detuned = hz * 2 ** (cents / 1200)
            detuned_phase = 2 * math.pi * detuned * t
            vibrato = .0012 * np.sin(2 * math.pi * 4.3 * t + cents)
            signal += width * partials(
                detuned_phase + detuned * vibrato,
                detuned,
                ((1, 1), (2, .115), (3, .042), (4, .012)),
            )
        env = envelope(t, duration, 1.45, .82, .82, min(2.0, duration * .34))
    elif kind == "tide_cello":
        vibrato = .0017 * np.sin(2 * math.pi * 4.15 * t)
        signal = partials(
            phase + hz * vibrato, hz, ((1, 1), (2, .20), (3, .070), (4, .018))
        )
        env = envelope(t, duration, .46, .50, .77, min(1.35, duration * .34))
    elif kind == "deep_harbor":
        signal = np.zeros_like(t)
        for cents, width in ((-4, .28), (0, .44), (5, .27)):
            detuned = hz * 2 ** (cents / 1200)
            detuned_phase = 2 * math.pi * detuned * t
            signal += width * partials(
                detuned_phase, detuned, ((1, 1), (2, .075), (3, .020))
            )
        env = envelope(t, duration, .65, .58, .79, min(1.55, duration * .35))
    else:
        raise ValueError(kind)
    return (signal * env).astype(np.float32)


def pan(value: float) -> tuple[float, float]:
    angle = (float(np.clip(value, -1, 1)) + 1) * math.pi / 4
    return math.cos(angle), math.sin(angle)


def add_note(track: np.ndarray, start: float, duration: float, note: float,
             level: float, kind: str, pan_value: float = 0.0) -> None:
    begin = round(start * SAMPLE_RATE)
    if begin < 0 or begin >= len(track):
        return
    sample = synth(kind, note, duration)
    end = min(begin + len(sample), len(track))
    left, right = pan(pan_value)
    track[begin:end, 0] += sample[:end - begin] * (level * left)
    track[begin:end, 1] += sample[:end - begin] * (level * right)


# Each voicing is (bass, root, fifth, ninth/colour, third/sus, seventh/sixth).
# It follows the sixty-bar composition sheet exactly.  Compact voicings keep
# every accompaniment note at or below A4 while common tones move smoothly.
DM9 = (38, 50, 57, 64, 53, 60)
DM9_C = (36, 50, 57, 64, 53, 60)
G6_B = (47, 55, 62, 64, 59, 64)
CMAJ9 = (36, 60, 55, 62, 64, 59)
FMAJ9 = (41, 53, 60, 67, 57, 64)
C_E = (40, 60, 55, 62, 64, 60)
G6_9 = (43, 55, 62, 69, 59, 64)
A7SUS = (45, 57, 64, 62, 62, 67)
CMAJ7_E = (40, 60, 55, 62, 64, 59)
FMAJ7 = (41, 53, 60, 64, 57, 64)
DM9_A = (45, 50, 57, 64, 53, 60)
EM7 = (40, 52, 59, 64, 55, 62)
BBMAJ9 = (34, 58, 65, 60, 62, 57)
C6_9 = (36, 60, 55, 62, 64, 57)
GM9 = (43, 55, 62, 69, 58, 65)
FMAJ7_A = (45, 53, 60, 67, 57, 64)
AM7 = (45, 57, 64, 59, 60, 67)
GM9_A = (45, 55, 62, 69, 58, 65)
F_A = (45, 53, 60, 57, 57, 60)
CMAJ7_D = (38, 60, 55, 62, 64, 59)
G6_D = (38, 55, 62, 64, 59, 64)
DMADD9 = (38, 50, 57, 64, 53, 57)

CHORDS = [
    # Intro, bars 1–8.
    DM9, DM9_C, G6_B, CMAJ9, FMAJ9, C_E, G6_9, A7SUS,
    # A, bars 9–20.
    DM9, CMAJ7_E, FMAJ7, G6_9, DM9_A, EM7, CMAJ9, A7SUS,
    BBMAJ9, C6_9, GM9, A7SUS,
    # A', bars 21–32.
    DM9, FMAJ7_A, CMAJ9, G6_B, BBMAJ9, AM7, GM9, C6_9,
    FMAJ9, C_E, GM9_A, A7SUS,
    # B, bars 33–44.
    FMAJ9, C_E, DM9, AM7, BBMAJ9, F_A, GM9, C6_9,
    AM7, DM9, G6_9, A7SUS,
    # A'', bars 45–56.
    DM9, DM9_C, G6_B, CMAJ9, FMAJ7, C_E, GM9, A7SUS,
    DM9, BBMAJ9, C6_9, GM9_A,
    # Coda, bars 57–60.
    DM9, CMAJ7_D, G6_D, DMADD9,
]
assert len(CHORDS) == BAR_COUNT

# The Minuet's small D-F-G homeward cell becomes a new, unhurried two-bar
# sentence in 4/4.  Events are (beat offset, duration in beats, MIDI note).
THEME_ALPHA = [
    [(0, 1.5, 74), (1.5, .5, 77), (2, 1, 79), (3, 1, 81)],
    [(0, 1, 79), (1, 1, 76), (2, 2, 74)],
    [(0, 1, 72), (1, 1, 76), (2, 1, 77), (3, 1, 81)],
    [(0, 1.5, 79), (1.5, .5, 76), (2, 2, 74)],
]

RESPONSE_BETA = [
    [(0, 1, 69), (1, 1, 72), (2, 2, 74)],
    [(0, 1, 71), (1, 1, 67), (2, 2, 76)],
    [(0, 1, 67), (1, 1, 71), (2, 1, 74), (3, 1, 76)],
    [(0, 1, 74), (1, 1, 76), (2, 2, 69)],
]

# Chord-aware inner answer.  It replaces the earlier literal -5 transposition,
# which created long F#/F and B/Bb clusters against the accompaniment.
RESPONSE_INNER = [
    [(0, 1, 62), (1, 1, 65), (2, 2, 67)],
    [(0, 1, 64), (1, 1, 62), (2, 2, 69)],
    [(0, 1, 60), (1, 1, 65), (2, 1, 67), (3, 1, 69)],
    [(0, 1, 67), (1, 1, 69), (2, 2, 62)],
]

CONTRAST_B = [
    [(0, 2, 69), (2, 1, 72), (3, 1, 76)],
    [(0, 1, 79), (1, 1, 76), (2, 2, 74)],
    [(0, 1, 77), (1, 1, 76), (2, 2, 74)],
    [(0, 4, 72)],
]

CADENCE = [
    [(0, 1.5, 70), (1.5, .5, 72), (2, 2, 74)],
    [(0, 1, 76), (1, 1, 74), (2, 2, 72)],
    [(0, 1, 67), (1, 1, 69), (2, 2, 72)],
    [(0, 1, 74), (1, 1, 72), (2, 2, 69)],
]

# Explicit inner-register variants remove sustained semitone clusters while
# retaining the written rhythm.  Their pitches are final MIDI values; no
# transpose is applied at the call site.
THEME_ALPHA_INNER = [
    [(0, 1.5, 62), (1.5, .5, 64), (2, 1, 67), (3, 1, 69)],
    [(0, 1, 67), (1, 1, 64), (2, 2, 62)],
    [(0, 1, 62), (1, 1, 64), (2, 1, 67), (3, 1, 69)],
    [(0, 1.5, 67), (1.5, .5, 64), (2, 2, 62)],
]

CADENCE_INNER_A = [
    [(0, 1.5, 57), (1.5, .5, 60), (2, 2, 62)],
    [(0, 1, 64), (1, 1, 62), (2, 2, 60)],
    [(0, 1, 55), (1, 1, 58), (2, 2, 60)],
    [(0, 1, 62), (1, 1, 60), (2, 2, 57)],
]

CADENCE_INNER_B = [
    [(0, 1.5, 57), (1.5, .5, 64), (2, 2, 62)],
    CADENCE_INNER_A[1],
    [(0, 1, 55), (1, 1, 57), (2, 2, 59)],
    CADENCE_INNER_A[3],
]

THEME_ALPHA_RETURN = [
    THEME_ALPHA[0],
    THEME_ALPHA[1],
    [(0, 1, 71), (1, 1, 74), (2, 1, 76), (3, 1, 79)],
    THEME_ALPHA[3],
]

RESPONSE_RETURN = [
    RESPONSE_BETA[0],
    RESPONSE_BETA[1],
    [(0, 1, 67), (1, 1, 65), (2, 1, 74), (3, 1, 76)],
    RESPONSE_BETA[3],
]

CADENCE_RETURN = [
    [(0, 1.5, 69), (1.5, .5, 72), (2, 2, 74)],
    [(0, 1, 77), (1, 1, 74), (2, 2, 72)],
    CADENCE[2],
    CADENCE[3],
]

PAD_OVERRIDES = {
    3: (55, 59, 62),   # Intro bar 4: G3/B3/D4, leaving the felt F4 clear.
    56: (57, 60, 62),  # Coda bar 57: A3/C4/D4 below the D-F-G motif.
}


def add_phrase(track: np.ndarray, first_bar: int,
               phrase: list[list[tuple[float, float, int]]], repetitions: int,
               level: float, kind: str = "mooring_felt", transpose: int = 0,
               pan_value: float = .05) -> None:
    for repetition in range(repetitions):
        for relative_bar, events in enumerate(phrase):
            bar = first_bar + repetition * len(phrase) + relative_bar
            for offset, duration, note in events:
                add_note(
                    track,
                    bar * BAR + offset * BEAT + .018,
                    duration * BEAT + .55,
                    note + transpose,
                    level * (1.0 - repetition * .018),
                    kind,
                    pan_value,
                )


def section_level(bar: int) -> float:
    if bar < 8:
        return .78 + bar * .025
    if bar < 20:
        return .96
    if bar < 32:
        return 1.0
    if bar < 44:
        return .94
    if bar < 56:
        return 1.01
    return max(.68, 1.0 - (bar - 56) * .09)


def render() -> np.ndarray:
    rng = np.random.default_rng(RANDOM_SEED)
    track = np.zeros((FRAME_COUNT, 2), dtype=np.float32)

    for bar, chord in enumerate(CHORDS):
        start = bar * BAR
        blend = section_level(bar)

        # Long mooring bass prevents the eighth-note current from feeling busy.
        add_note(track, start, BAR + 1.15, chord[0], .040 * blend,
                 "deep_harbor", -.02)

        # A constant but soft four-pair current supports concentration.  Tiny,
        # deterministic timing variations keep it human without changing tempo.
        pulse_notes = (chord[1], chord[2], chord[3], chord[4],
                       chord[2], chord[3], chord[5], chord[2])
        for step, note in enumerate(pulse_notes):
            timing = float(rng.uniform(-.009, .009))
            emphasis = 1.09 if step in (0, 4) else .91 if step % 2 else 1.0
            add_note(
                track, start + step * .5 * BEAT + timing, .73,
                note, .0295 * emphasis * blend, "rope_pulse",
                -.20 if step % 2 == 0 else .20,
            )

        # Pads share the Minuet's horizon colour but move by common tones.
        pad_level = .0185 if bar < 8 or bar >= 56 else .0225
        pad_notes = PAD_OVERRIDES.get(bar, (chord[3], chord[4], chord[5]))
        for index, note in enumerate(pad_notes):
            add_note(track, start, BAR + 1.38, note,
                     pad_level * blend, "horizon_strings",
                     (-.36, 0, .36)[index])

        # Cello appears only in alternating two-bar breaths, never as a pulse.
        if 8 <= bar < 56 and bar % 4 == 0:
            add_note(track, start + .06, 2 * BAR + .65, chord[1],
                     .031 * blend, "tide_cello", -.08)

    # An eight-bar introduction reveals only the contour, then the two-bar
    # statement/answer alternation keeps the center clear for the user's work.
    for bar, note in ((1, 62), (3, 65), (5, 67), (7, 69)):
        add_note(track, bar * BAR + .10, 2.35, note, .031,
                 "mooring_felt", .03)

    add_phrase(track, 8, THEME_ALPHA, 1, .066)
    add_phrase(track, 12, RESPONSE_BETA, 1, .052, pan_value=-.03)
    add_phrase(track, 16, CADENCE, 1, .049, pan_value=.02)

    # A' puts alpha one octave down in the cello/inner voice.  Felt gestures do
    # not double it in unison, leaving the register calm and transparent.
    add_phrase(track, 20, THEME_ALPHA_INNER, 1, .051, kind="tide_cello",
               pan_value=-.07)
    add_phrase(track, 24, RESPONSE_INNER, 1, .044, kind="mooring_felt",
               pan_value=.04)
    add_phrase(track, 28, CADENCE_INNER_A, 1, .046, kind="tide_cello",
               pan_value=-.06)

    add_phrase(track, 32, CONTRAST_B, 1, .054, pan_value=-.03)
    add_phrase(track, 36, RESPONSE_INNER, 1, .049, pan_value=.03)
    add_phrase(track, 40, CADENCE_INNER_B, 1, .047, kind="tide_cello",
               pan_value=-.06)

    add_phrase(track, 44, THEME_ALPHA_RETURN, 1, .067)
    add_phrase(track, 48, RESPONSE_RETURN, 1, .052, pan_value=-.03)
    add_phrase(track, 52, CADENCE_RETURN, 1, .049, pan_value=.02)

    # The coda remembers only D-F-G, settling on a low add9 colour.
    for offset, duration, note in ((0, 1.5, 62), (1.5, .5, 65),
                                   (2, 1, 67), (3, 1, 64)):
        add_note(track, 56 * BAR + offset * BEAT, duration * BEAT + .65,
                 note, .047, "mooring_felt", .02)
    add_note(track, 59 * BAR, BAR, 50, .036, "mooring_felt", -.02)
    add_note(track, 59 * BAR, BAR, 57, .026, "horizon_strings", .02)

    # Zero-padded dock reflections never wrap the ending into the opening.
    dry = track.copy()
    wet = np.zeros_like(dry)
    for delay, gain, cross in ((.071, .062, False), (.123, .050, True),
                               (.229, .035, False), (.413, .026, True),
                               (.79, .020, False), (1.31, .014, True),
                               (2.06, .009, False)):
        shift = round(delay * SAMPLE_RATE)
        wet[shift:, 0] += dry[:-shift, 1 if cross else 0] * gain
        wet[shift:, 1] += dry[:-shift, 0 if cross else 1] * gain
    mix = dry * .93 + wet

    # Wide, overlapping section gain ramps avoid entrances that call attention
    # to themselves.  The coda is quieter but the target moves continuously.
    targets_db = np.array([-20.8, -20.1, -19.9, -20.2, -19.8, -20.9])
    section_frames = len(mix) // len(targets_db)
    centers: list[float] = []
    required_db: list[float] = []
    for section, target_db in enumerate(targets_db):
        begin = section * section_frames
        end = len(mix) if section == len(targets_db) - 1 else begin + section_frames
        rms = max(float(np.sqrt(np.mean(mix[begin:end] ** 2))), 1e-8)
        centers.append((begin + end - 1) * .5)
        required_db.append(float(target_db) - 20 * math.log10(rms))
    contour_db = np.interp(np.arange(len(mix)), centers, required_db)
    mix *= np.power(10, contour_db / 20)[:, None].astype(np.float32)

    # Stereo-linked, low-ratio control catches combined piano/pad peaks only.
    linked = np.max(np.abs(mix), axis=1)
    threshold = 10 ** (-15.5 / 20)
    over = np.maximum(linked / threshold, 1.0)
    mix *= np.power(over, (1 / 1.27) - 1)[:, None].astype(np.float32)

    # Two continuous one-second gain rides counter the felt-piano decay between
    # attacks.  Linear interpolation means there are no gain steps; the second
    # pass corrects the small measurement shift caused by the first pass.  This
    # is deliberately a slow ride, not a fast compressor, so it cannot pump on
    # individual eighth notes.
    section_points = np.array([0.0, 24.0, 60.0, 96.0, 132.0, 168.0, 177.6])
    section_loudness = np.array([-20.8, -20.1, -19.9, -20.2, -19.8, -20.9, -21.0])
    for strength in (.88, .72):
        ride_centers: list[float] = []
        ride_db: list[float] = []
        for begin in range(0, len(mix), SAMPLE_RATE):
            end = min(begin + SAMPLE_RATE, len(mix))
            center = (begin + end - 1) * .5
            seconds = center / SAMPLE_RATE
            rms = max(float(np.sqrt(np.mean(mix[begin:end] ** 2))), 1e-8)
            local_db = 20 * math.log10(rms)
            target_db = float(np.interp(seconds, section_points, section_loudness))
            ride_centers.append(center)
            ride_db.append(float(np.clip((target_db - local_db) * strength, -4.5, 4.5)))
        ride_curve_db = np.interp(np.arange(len(mix)), ride_centers, ride_db)
        mix *= np.power(10, ride_curve_db / 20)[:, None].astype(np.float32)

    rms = float(np.sqrt(np.mean(mix ** 2)))
    if rms > 0:
        mix *= (10 ** (-20.0 / 20)) / rms
    peak = float(np.max(np.abs(mix)))
    peak_ceiling = 10 ** (-7.0 / 20)
    if peak > peak_ceiling:
        mix *= peak_ceiling / peak

    # Finish the cadence inside exactly three minutes for gapless playlist use.
    fade_in_frames = round(.60 * SAMPLE_RATE)
    fade_in = np.sin(np.linspace(0, math.pi / 2, fade_in_frames, dtype=np.float32)) ** 2
    mix[:fade_in_frames] *= fade_in[:, None]
    fade_frames = round(2.40 * SAMPLE_RATE)
    fade = np.cos(np.linspace(0, math.pi / 2, fade_frames, dtype=np.float32)) ** 2
    mix[-fade_frames:] *= fade[:, None]
    mix[0] = 0
    mix[-1] = 0
    return mix.astype(np.float32)


def write_wave(path: Path, audio: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    dither_rng = np.random.default_rng(DITHER_SEED)
    dither = (dither_rng.random(audio.shape) - dither_rng.random(audio.shape)) / 32768.0
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
