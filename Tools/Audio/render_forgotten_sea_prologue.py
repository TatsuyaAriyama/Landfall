#!/usr/bin/env python3
"""Render KeelMira's original "Forgotten Sea Prologue".

The 52-second cue is synthesized entirely by this file. It uses no samples,
voices, borrowed melodies, impulse responses, or third-party musical assets.
Fixed random seeds make every generated layer reproducible.

Examples:
    uv run --with numpy python render_forgotten_sea_prologue.py output.wav
    uv run --with numpy python render_forgotten_sea_prologue.py output.m4a
"""

from __future__ import annotations

import argparse
import math
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np


SAMPLE_RATE = 44_100
DURATION = 52.0
FRAME_COUNT = int(SAMPLE_RATE * DURATION)

SEA_RNG = np.random.default_rng(0xF09E_77E1)
LEFT_WASH_RNG = np.random.default_rng(0xA11C_E5EA)
RIGHT_WASH_RNG = np.random.default_rng(0xB04D_C0A5)
NOTE_RNG = np.random.default_rng(0x51A2_1E55)
DITHER_RNG = np.random.default_rng(0xD17E_2026)


def frequency(note: float) -> float:
    return 440.0 * 2.0 ** ((note - 69.0) / 12.0)


def stereo_gains(pan: float) -> tuple[float, float]:
    angle = (float(np.clip(pan, -1, 1)) + 1) * math.pi / 4
    return math.cos(angle), math.sin(angle)


def smoothstep(values: np.ndarray) -> np.ndarray:
    clipped = np.clip(values, 0, 1)
    return clipped * clipped * (3 - 2 * clipped)


def add_sample(
    track: np.ndarray,
    sample: np.ndarray,
    start: float,
    pan: float = 0,
) -> None:
    begin = max(0, int(start * SAMPLE_RATE))
    end = min(len(track), begin + len(sample))
    if begin >= end:
        return
    left, right = stereo_gains(pan)
    track[begin:end, 0] += sample[: end - begin] * left
    track[begin:end, 1] += sample[: end - begin] * right


def add_felt_note(
    track: np.ndarray,
    start: float,
    note: float,
    duration: float,
    level: float,
    pan: float,
    brightness: float = 1.0,
) -> None:
    count = max(1, int(duration * SAMPLE_RATE))
    time = np.arange(count, dtype=np.float64) / SAMPLE_RATE
    hz = frequency(note)
    phase = 2 * math.pi * hz * time

    body = (
        np.sin(phase) * .78
        + np.sin(phase * 2.003 + .11) * .19 * np.exp(-time * 1.25)
        + np.sin(phase * 3.997 + .29) * .065 * np.exp(-time * 2.45)
        + np.sin(phase * 6.011 + .47) * .018 * brightness * np.exp(-time * 5.6)
    )
    hammer_noise = NOTE_RNG.normal(0, 1, count)
    hammer_noise = np.concatenate(([0.0], np.diff(hammer_noise)))
    body += hammer_noise * .0065 * brightness * np.exp(-time * 72)

    attack = np.sin(np.clip(time / .026, 0, 1) * math.pi / 2) ** 2
    decay = np.exp(-time * (1.02 + hz / 2_600))
    release = np.ones_like(time)
    release_frames = min(count, int(.72 * SAMPLE_RATE))
    release[-release_frames:] = np.cos(
        np.linspace(0, math.pi / 2, release_frames, dtype=np.float64)
    ) ** 2
    sample = (body * attack * decay * release * level).astype(np.float32)
    add_sample(track, sample, start, pan)


def add_distant_bell(
    track: np.ndarray,
    start: float,
    note: float,
    duration: float,
    level: float,
    pan: float,
) -> None:
    count = max(1, int(duration * SAMPLE_RATE))
    time = np.arange(count, dtype=np.float64) / SAMPLE_RATE
    hz = frequency(note)
    sample = np.zeros(count, dtype=np.float64)
    # Slightly inharmonic partials suggest an old beacon bell without a sample.
    for ratio, partial_level, decay in [
        (1.0, .72, .66),
        (1.493, .25, .94),
        (2.018, .16, 1.24),
        (2.711, .075, 1.68),
        (4.087, .031, 2.25),
    ]:
        phase = 2 * math.pi * hz * ratio * time + ratio * .23
        sample += np.sin(phase) * partial_level * np.exp(-time * decay)
    attack = np.sin(np.clip(time / .018, 0, 1) * math.pi / 2) ** 2
    release = np.cos(np.clip((time - duration + 1.4) / 1.4, 0, 1) * math.pi / 2) ** 2
    sample = (sample * attack * release * level).astype(np.float32)
    add_sample(track, sample, start, pan)


def add_mist_pad(
    track: np.ndarray,
    start: float,
    note: float,
    duration: float,
    level: float,
    pan: float,
) -> None:
    count = max(1, int(duration * SAMPLE_RATE))
    time = np.arange(count, dtype=np.float64) / SAMPLE_RATE
    hz = frequency(note)
    sample = np.zeros(count, dtype=np.float64)
    for cents, amount in [(-7.5, .30), (0, .43), (6.2, .29)]:
        detuned = hz * 2 ** (cents / 1_200)
        phase = 2 * math.pi * detuned * time
        sample += amount * (
            np.sin(phase) + .12 * np.sin(phase * 2 + .17) + .035 * np.sin(phase * 3 + .41)
        )
    attack = np.sin(np.clip(time / 1.8, 0, 1) * math.pi / 2) ** 2
    release = np.cos(np.clip((time - duration + 2.6) / 2.6, 0, 1) * math.pi / 2) ** 2
    movement = .965 + .035 * np.sin(2 * math.pi * .071 * time + note)
    sample = (sample * attack * release * movement * level).astype(np.float32)
    add_sample(track, sample, start, pan)


def interpolated_noise(
    rng: np.random.Generator,
    control_rate: float,
) -> np.ndarray:
    hop = SAMPLE_RATE / control_rate
    control_count = int(math.ceil(FRAME_COUNT / hop)) + 2
    controls = rng.normal(0, 1, control_count).astype(np.float32)
    control_positions = np.arange(control_count, dtype=np.float32) * hop
    frame_positions = np.arange(FRAME_COUNT, dtype=np.float32)
    output = np.interp(frame_positions, control_positions, controls).astype(np.float32)
    standard_deviation = max(float(np.std(output)), 1e-6)
    return output / standard_deviation


def wave_envelope() -> np.ndarray:
    output = np.full(FRAME_COUNT, .13, dtype=np.float32)
    waves = [
        (2.1, .64, 1.7, 4.2),
        (8.7, .83, 2.2, 5.1),
        (17.0, .71, 1.8, 4.7),
        (25.2, .92, 2.4, 5.5),
        (34.3, .66, 1.9, 4.5),
        (43.5, .48, 2.1, 4.1),
    ]
    for crest, strength, attack, release in waves:
        begin = max(0, int((crest - attack) * SAMPLE_RATE))
        peak = min(FRAME_COUNT, int(crest * SAMPLE_RATE))
        end = min(FRAME_COUNT, int((crest + release) * SAMPLE_RATE))
        if begin < peak:
            values = np.linspace(0, 1, peak - begin, endpoint=False, dtype=np.float32)
            output[begin:peak] += smoothstep(values) * strength
        if peak < end:
            values = np.linspace(0, 1, end - peak, endpoint=False, dtype=np.float32)
            remaining = 1 - smoothstep(values)
            output[peak:end] += remaining * remaining * strength
    return np.clip(output, 0, 1.2)


def add_sea(track: np.ndarray) -> None:
    envelope = wave_envelope()

    distant = interpolated_noise(SEA_RNG, 115)
    distant -= interpolated_noise(SEA_RNG, 13) * .74
    distant /= max(float(np.std(distant)), 1e-6)

    seconds = np.arange(FRAME_COUNT, dtype=np.float32) / SAMPLE_RATE
    hull_resonance = (
        np.sin(2 * math.pi * 47.0 * seconds + .19 * np.sin(2 * math.pi * .067 * seconds))
        + .42 * np.sin(2 * math.pi * 73.0 * seconds + .8)
    ).astype(np.float32)
    center = distant * (.010 + envelope * .014) + hull_resonance * (.0025 + envelope * .0018)
    track[:, 0] += center
    track[:, 1] += center

    for channel, rng in ((0, LEFT_WASH_RNG), (1, RIGHT_WASH_RNG)):
        wash = interpolated_noise(rng, 2_150)
        wash -= interpolated_noise(rng, 330) * .67
        wash /= max(float(np.std(wash)), 1e-6)
        texture = wash * (.0032 + envelope * .0078)
        track[:, channel] += texture
        track[:, 1 - channel] += texture * .16


def add_score(track: np.ndarray) -> None:
    # Slow, unresolved mist harmonies carry the story's loss without a pulse.
    dark_harmonies = [
        (0.0, 38, 13.5, .0125, -.10),
        (0.4, 45, 12.4, .0080, .11),
        (8.0, 34, 13.2, .0115, -.08),
        (8.4, 41, 12.0, .0076, .10),
        (16.3, 33, 12.5, .0120, -.09),
        (16.7, 40, 11.6, .0077, .10),
        (24.8, 36, 12.7, .0118, -.07),
        (25.1, 43, 11.9, .0074, .10),
        (33.0, 38, 10.4, .0110, -.06),
        (33.3, 45, 9.7, .0072, .08),
    ]
    for start, note, duration, level, pan in dark_harmonies:
        add_mist_pad(track, start, note, duration, level, pan)

    # Each bell is deliberately isolated, like a beacon being lost in fog.
    for start, note, duration, level, pan in [
        (3.7, 74, 5.3, .020, -.31),
        (11.5, 69, 5.7, .017, .28),
        (20.5, 65, 5.4, .015, -.24),
        (29.1, 62, 5.8, .014, .23),
        (36.2, 57, 5.5, .011, -.14),
    ]:
        add_distant_bell(track, start, note, duration, level, pan)

    # Sparse felt notes leave enough room for every line of on-screen prose.
    for start, note, duration, level, pan, brightness in [
        (6.8, 62, 4.3, .027, .10, .72),
        (14.7, 60, 4.5, .024, -.08, .68),
        (22.9, 57, 4.7, .022, .08, .64),
        (30.8, 53, 4.8, .021, -.06, .62),
        (35.5, 50, 4.4, .018, .04, .58),
    ]:
        add_felt_note(track, start, note, duration, level, pan, brightness)

    # A newly composed three-note rise opens the harmony into a warm G 6/9.
    # It is intentionally small: hope survives, but the voyage has only begun.
    for start, note, level, pan in [
        (40.1, 59, .030, -.12),
        (42.5, 62, .032, .05),
        (45.0, 67, .035, .14),
        (48.0, 69, .019, .20),
    ]:
        add_felt_note(track, start, note, 5.0, level, pan, .84)

    for start, note, duration, level, pan in [
        (38.7, 43, 13.0, .0105, -.08),
        (39.0, 50, 12.7, .0072, .08),
        (39.4, 55, 12.2, .0066, -.16),
        (39.7, 59, 11.8, .0064, .15),
        (40.0, 64, 11.5, .0048, .23),
    ]:
        add_mist_pad(track, start, note, duration, level, pan)

    add_distant_bell(track, 45.2, 67, 5.8, .0105, .18)


def add_generated_space(track: np.ndarray) -> np.ndarray:
    dry = track.copy()
    wet = np.zeros_like(track)
    # Zero-padded delays form the entire room response; nothing is wrapped.
    for delay, gain, cross in [
        (.083, .075, False),
        (.149, .058, True),
        (.271, .046, False),
        (.463, .034, True),
        (.821, .026, False),
        (1.337, .018, True),
        (2.173, .011, False),
    ]:
        shift = int(delay * SAMPLE_RATE)
        wet[shift:, 0] += dry[:-shift, 1 if cross else 0] * gain
        wet[shift:, 1] += dry[:-shift, 0 if cross else 1] * gain
    return dry * .94 + wet


def master(track: np.ndarray) -> np.ndarray:
    mix = add_generated_space(track)
    mix -= np.mean(mix, axis=0, keepdims=True).astype(np.float32)

    # Gentle saturation rounds isolated bell transients without flattening waves.
    mix = (np.tanh(mix * 1.08) / math.tanh(1.08)).astype(np.float32)

    rms = max(float(np.sqrt(np.mean(mix * mix))), 1e-8)
    mix *= (10 ** (-22.2 / 20)) / rms
    peak = float(np.max(np.abs(mix)))
    if peak > .48:
        mix *= .48 / peak

    fade_in_frames = int(1.8 * SAMPLE_RATE)
    fade_out_frames = int(3.1 * SAMPLE_RATE)
    fade_in = np.sin(
        np.linspace(0, math.pi / 2, fade_in_frames, dtype=np.float32)
    ) ** 2
    fade_out = np.cos(
        np.linspace(0, math.pi / 2, fade_out_frames, dtype=np.float32)
    ) ** 2
    mix[:fade_in_frames] *= fade_in[:, None]
    mix[-fade_out_frames:] *= fade_out[:, None]
    mix[0] = 0
    mix[-1] = 0
    return mix.astype(np.float32)


def render() -> np.ndarray:
    track = np.zeros((FRAME_COUNT, 2), dtype=np.float32)
    add_sea(track)
    add_score(track)
    return master(track)


def write_wave(path: Path, audio: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    dither = (
        DITHER_RNG.random(audio.shape, dtype=np.float32)
        - DITHER_RNG.random(audio.shape, dtype=np.float32)
    ) / 32_768
    pcm = (np.clip(audio + dither, -1, 1) * 32_767).astype("<i2")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(pcm.tobytes())


def write_output(path: Path, audio: np.ndarray, bitrate: int) -> None:
    suffix = path.suffix.lower()
    if suffix == ".wav":
        write_wave(path, audio)
        return
    if suffix != ".m4a":
        raise ValueError("output must use the .wav or .m4a extension")

    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="keelmira-forgotten-sea-") as temporary:
        wave_path = Path(temporary) / "forgotten_sea_prologue.wav"
        write_wave(wave_path, audio)
        subprocess.run(
            [
                "/usr/bin/afconvert",
                str(wave_path),
                "-o",
                str(path),
                "-f",
                "m4af",
                "-d",
                "aac",
                "-b",
                str(bitrate),
                "-q",
                "127",
                "--no-filler",
            ],
            check=True,
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path, help="destination .wav or .m4a file")
    parser.add_argument("--bitrate", type=int, default=192_000)
    args = parser.parse_args()

    audio = render()
    write_output(args.output, audio, args.bitrate)
    peak = float(np.max(np.abs(audio)))
    rms_db = 20 * math.log10(max(float(np.sqrt(np.mean(audio * audio))), 1e-8))
    print(
        f"Rendered {len(audio) / SAMPLE_RATE:.3f}s to {args.output} "
        f"(RMS {rms_db:.2f} dBFS, peak {20 * math.log10(max(peak, 1e-8)):.2f} dBFS)"
    )


if __name__ == "__main__":
    main()
