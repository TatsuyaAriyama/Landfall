#!/usr/bin/env python3
"""Render KeelMira's original home-island theme, "Leeward Cove".

All instruments, percussion, room reflections, and dither are synthesized in
this file.  It uses no samples, recordings, voices, or quoted musical material.
The fixed score and fixed random seeds make the PCM and AAC output reproducible.

Run with:
    uv run --with numpy python Tools/Audio/render_leeward_cove.py \
        Landfall/Resources/leeward_cove.m4a
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
BPM = 94.0
BEAT = 60.0 / BPM
BAR = BEAT * 4.0
BAR_COUNT = 76
DURATION = BAR_COUNT * BAR
FRAME_COUNT = round(DURATION * SAMPLE_RATE)
FADE_OUT_SECONDS = 2.4
DRUM_SEED = 0x4C454557
DITHER_SEED = 0x434F5645

SECTIONS = (
    ("intro", 8),
    ("A", 16),
    ("B", 16),
    ("tide_break", 8),
    ("A_prime", 16),
    ("outro", 12),
)


def hz(note: float) -> float:
    return 440.0 * 2.0 ** ((note - 69.0) / 12.0)


def equal_power_pan(value: float) -> tuple[float, float]:
    angle = (float(np.clip(value, -1.0, 1.0)) + 1.0) * math.pi / 4.0
    return math.cos(angle), math.sin(angle)


def shaped_envelope(
    time: np.ndarray,
    duration: float,
    attack: float,
    release: float,
    decay: float,
    sustain: float,
) -> np.ndarray:
    attack_curve = np.sin(
        np.clip(time / max(attack, 1e-5), 0.0, 1.0) * math.pi / 2.0
    ) ** 2
    body = sustain + (1.0 - sustain) * np.exp(-time * decay)
    release_start = max(attack, duration - release)
    release_curve = np.ones_like(time)
    mask = time >= release_start
    release_curve[mask] = np.cos(
        np.clip(
            (time[mask] - release_start) / max(duration - release_start, 1e-5),
            0.0,
            1.0,
        )
        * math.pi
        / 2.0
    ) ** 2
    return attack_curve * body * release_curve


def synth_tone(kind: str, note: float, duration: float) -> np.ndarray:
    count = max(1, round(duration * SAMPLE_RATE))
    time = np.arange(count, dtype=np.float64) / SAMPLE_RATE
    frequency = hz(note)
    phase = math.tau * frequency * time

    if kind == "soft_ep":
        # A rounded tine body: enough second harmonic to read on an iPhone,
        # without the glassy transient of a bright electric piano preset.
        body = (
            np.sin(phase)
            + .235 * np.sin(phase * 2.002 + .08)
            + .082 * np.sin(phase * 3.997 + .21) * np.exp(-time * 1.8)
            + .028 * np.sin(phase * 6.01) * np.exp(-time * 3.2)
        )
        tremolo = 1.0 + .025 * np.sin(math.tau * 4.7 * time + note * .17)
        envelope = shaped_envelope(time, duration, .018, .52, 1.08, .49)
        signal = body * tremolo * envelope
    elif kind == "wood_pluck":
        body = (
            np.sin(phase)
            + .30 * np.sin(phase * 2.01 + .15)
            + .13 * np.sin(phase * 3.94 + .37)
            + .052 * np.sin(phase * 6.12 + .8)
        )
        knock = np.sin(phase * .49 + .2) * np.exp(-time * 42.0) * .14
        envelope = shaped_envelope(time, duration, .006, .18, 5.2, .06)
        signal = (body * np.exp(-time * 2.45) + knock) * envelope
    elif kind == "round_bass":
        pitch_drop = .42 * np.exp(-time * 24.0)
        bass_phase = phase + pitch_drop
        body = (
            np.sin(bass_phase)
            + .16 * np.sin(bass_phase * 2.0 + .12)
            + .035 * np.sin(bass_phase * 3.0) * np.exp(-time * 4.0)
        )
        envelope = shaped_envelope(time, duration, .012, .24, 3.4, .17)
        signal = body * envelope
    elif kind == "thin_vibes":
        body = (
            np.sin(phase)
            + .115 * np.sin(phase * 4.003 + .18)
            + .055 * np.sin(phase * 6.011 + .6)
        )
        motor = .90 + .10 * np.sin(math.tau * 5.15 * time + .4)
        envelope = shaped_envelope(time, duration, .009, 1.15, .88, .29)
        signal = body * motor * envelope
    else:
        raise ValueError(f"unknown tone: {kind}")
    return signal.astype(np.float32)


def add_sample(
    track: np.ndarray,
    sample: np.ndarray,
    start: float,
    level: float,
    pan_value: float = 0.0,
) -> None:
    begin = round(start * SAMPLE_RATE)
    if begin < 0 or begin >= len(track):
        return
    end = min(begin + len(sample), len(track))
    if end <= begin:
        return
    left, right = equal_power_pan(pan_value)
    track[begin:end, 0] += sample[: end - begin] * (level * left)
    track[begin:end, 1] += sample[: end - begin] * (level * right)


def add_note(
    track: np.ndarray,
    kind: str,
    note: float,
    start: float,
    duration: float,
    level: float,
    pan_value: float = 0.0,
) -> None:
    add_sample(track, synth_tone(kind, note, duration), start, level, pan_value)


def event_rng(start: float, salt: int) -> np.random.Generator:
    frame = round(start * SAMPLE_RATE)
    seed = (DRUM_SEED ^ (frame * 0x45D9F3B) ^ (salt * 0x119DE1F3)) & 0xFFFFFFFF
    return np.random.default_rng(seed)


def high_pass_noise(noise: np.ndarray, width: int) -> np.ndarray:
    kernel = np.ones(width, dtype=np.float32) / width
    return noise - np.convolve(noise, kernel, mode="same")


def synth_kick(start: float) -> np.ndarray:
    duration = .36
    count = round(duration * SAMPLE_RATE)
    time = np.arange(count, dtype=np.float64) / SAMPLE_RATE
    instantaneous_hz = 48.0 + 38.0 * np.exp(-time * 25.0)
    phase = math.tau * np.cumsum(instantaneous_hz) / SAMPLE_RATE
    body = np.sin(phase) * np.exp(-time * 11.4)
    click = event_rng(start, 1).normal(0.0, 1.0, count).astype(np.float32)
    click = high_pass_noise(click, 19) * np.exp(-time * 72.0) * .035
    return (body + click).astype(np.float32)


def synth_brush(start: float, accent: float) -> np.ndarray:
    duration = .31
    count = round(duration * SAMPLE_RATE)
    time = np.arange(count, dtype=np.float64) / SAMPLE_RATE
    noise = event_rng(start, 2).normal(0.0, 1.0, count).astype(np.float32)
    fibers = high_pass_noise(noise, 41)
    envelope = (1.0 - np.exp(-time * 115.0)) * np.exp(-time * (10.2 / accent))
    low = np.sin(math.tau * 178.0 * time + .3) * np.exp(-time * 20.0) * .10
    return (fibers * envelope * .48 + low).astype(np.float32)


def synth_shaker(start: float, strength: float) -> np.ndarray:
    duration = .105
    count = round(duration * SAMPLE_RATE)
    time = np.arange(count, dtype=np.float64) / SAMPLE_RATE
    noise = event_rng(start, 3).normal(0.0, 1.0, count).astype(np.float32)
    grit = high_pass_noise(noise, 23)
    envelope = (1.0 - np.exp(-time * 190.0)) * np.exp(-time * (39.0 / strength))
    return (grit * envelope * .24).astype(np.float32)


# Independently authored harmony.  Each tuple is bass plus a spacious EP
# voicing; it was composed for this renderer and not inferred from a reference.
EMAJ9 = (40, 56, 59, 63, 66)
CSM11 = (37, 52, 56, 59, 66)
AMAJ9 = (33, 52, 56, 59, 61)
B13SUS = (35, 54, 57, 61, 64)
FSM9 = (30, 52, 57, 61, 68)
GSM7 = (32, 54, 59, 63, 66)
EMAJ9_GS = (32, 52, 56, 59, 66)
AMAJ9_CS = (37, 52, 56, 59, 64)
BSUS_A = (33, 54, 57, 61, 64)
CSM9 = (37, 52, 56, 59, 63)
D6_9 = (38, 54, 57, 59, 64)
EMAJ6_B = (35, 52, 56, 59, 61)
FSM11 = (30, 52, 57, 59, 64)
B7SUS = (35, 52, 57, 59, 66)

INTRO_HARMONY = (EMAJ9, CSM11, AMAJ9, B13SUS, EMAJ9_GS, FSM9, AMAJ9, B13SUS)
A_HARMONY = (
    EMAJ9, CSM11, AMAJ9, B13SUS, EMAJ9_GS, GSM7, FSM9, B13SUS,
    EMAJ9, AMAJ9_CS, FSM11, B13SUS, CSM9, AMAJ9, FSM9, B7SUS,
)
B_HARMONY = (
    AMAJ9, BSUS_A, GSM7, CSM9, FSM9, AMAJ9_CS, EMAJ9_GS, B13SUS,
    D6_9, AMAJ9_CS, EMAJ6_B, CSM9, FSM11, AMAJ9, B13SUS, B7SUS,
)
BREAK_HARMONY = (CSM11, AMAJ9, EMAJ9_GS, B13SUS, FSM9, AMAJ9_CS, EMAJ9, B13SUS)
APRIME_HARMONY = (
    EMAJ9, CSM9, AMAJ9, B13SUS, EMAJ9_GS, GSM7, FSM11, B7SUS,
    AMAJ9, BSUS_A, EMAJ9_GS, CSM9, FSM9, AMAJ9_CS, B13SUS, EMAJ9,
)
OUTRO_HARMONY = (
    AMAJ9, BSUS_A, EMAJ9_GS, CSM9, FSM9, AMAJ9, B13SUS, EMAJ9_GS,
    FSM11, AMAJ9_CS, B7SUS, EMAJ9,
)
HARMONY = (
    INTRO_HARMONY
    + A_HARMONY
    + B_HARMONY
    + BREAK_HARMONY
    + APRIME_HARMONY
    + OUTRO_HARMONY
)


# New four-bar phrases. Events are (beat offset, duration in beats, MIDI note).
THEME_A = (
    ((.50, .72, 71), (1.52, .50, 68), (2.28, 1.08, 66)),
    ((.26, .70, 64), (1.24, .52, 66), (2.06, 1.36, 71)),
    ((.76, .48, 73), (1.52, .50, 71), (2.54, .92, 68)),
    ((.28, .70, 66), (1.28, 1.58, 64)),
)
THEME_B = (
    ((.28, .66, 73), (1.26, .48, 71), (2.24, 1.18, 68)),
    ((.74, .50, 66), (1.50, .48, 69), (2.48, .96, 71)),
    ((.24, .72, 71), (1.48, .48, 66), (2.26, 1.20, 75)),
    ((.76, .48, 73), (1.54, 1.60, 68)),
)
THEME_APRIME = (
    ((.26, .48, 76), (1.02, .48, 71), (1.78, .66, 68), (2.76, .70, 66)),
    ((.52, .70, 64), (1.52, .48, 68), (2.30, 1.08, 71)),
    ((.26, .48, 73), (1.04, .48, 76), (1.80, .58, 71), (2.72, .74, 68)),
    ((.52, .66, 66), (1.50, 1.48, 64)),
)


def section_level(bar: int) -> float:
    if bar < 8:
        return .55 + bar * .035
    if bar < 24:
        return .86 + .05 * math.sin((bar - 8) * math.pi / 15.0)
    if bar < 40:
        return .98
    if bar < 45:
        return .55 - (bar - 40) * .065
    if bar < 48:
        return .25
    if bar < 64:
        return .91
    return max(.22, .80 - (bar - 64) * .052)


def add_harmony(track: np.ndarray) -> None:
    for bar, chord in enumerate(HARMONY):
        start = bar * BAR
        amount = section_level(bar)
        duration = BAR * (.91 if bar < 72 else 1.45)
        for voice, note in enumerate(chord[1:]):
            width = (-.44, -.15, .16, .44)[voice]
            level = (.0265 - voice * .0016) * amount
            add_note(track, "soft_ep", note, start + .018, duration, level, width)

        # Wooden replies are irregular and always subordinate to the EP.
        if bar < 8:
            offsets = (1.48, 3.20) if bar >= 3 else (2.72,)
        elif 40 <= bar < 48:
            offsets = (2.64,) if bar in (40, 42, 45) else ()
        elif bar >= 70:
            offsets = (1.64,) if bar in (70, 72) else ()
        else:
            offsets = (.52, 1.54, 2.76, 3.50) if bar % 2 == 0 else (.78, 2.02, 3.26)
        upper = chord[1:]
        for index, offset in enumerate(offsets):
            note = upper[(bar + index * 2) % len(upper)] + 12
            human = ((bar * 17 + index * 11) % 9 - 4) * .0017
            add_note(
                track, "wood_pluck", note, start + (offset * BEAT) + human,
                .44, .032 * amount, -.28 if index % 2 == 0 else .26,
            )


def add_phrase(
    track: np.ndarray,
    first_bar: int,
    phrase: tuple[tuple[tuple[float, float, int], ...], ...],
    repeats: int,
    level: float,
    use_vibes_on_repeat: bool,
) -> None:
    for repeat in range(repeats):
        for relative_bar, events in enumerate(phrase):
            bar = first_bar + repeat * len(phrase) + relative_bar
            for event, (offset, length, note) in enumerate(events):
                start = bar * BAR + offset * BEAT
                kind = "thin_vibes" if use_vibes_on_repeat and repeat > 0 else "soft_ep"
                event_level = level * (.78 if kind == "thin_vibes" else 1.0)
                add_note(
                    track, kind, note, start, length * BEAT + (.75 if kind == "soft_ep" else 1.25),
                    event_level, .10 + event * .055,
                )


def add_bass(track: np.ndarray) -> None:
    for bar, chord in enumerate(HARMONY):
        if bar < 8 or 40 <= bar < 48 or bar >= 71:
            continue
        amount = section_level(bar)
        start = bar * BAR
        pattern = ((0.0, .74, chord[0]), (2.50, .52, chord[0] + 7))
        if bar % 4 == 3:
            pattern += ((3.34, .38, chord[0] + 12),)
        for offset, length, note in pattern:
            add_note(
                track, "round_bass", note, start + offset * BEAT,
                length * BEAT + .16, .080 * amount, 0.0,
            )


def add_drums(track: np.ndarray) -> None:
    swing = .56
    for bar in range(8, 71):
        if 40 <= bar < 48:
            # The tide break reaches its emptiest point around 120 seconds.
            if bar in (40, 43):
                start = bar * BAR + 3.02 * BEAT
                add_sample(track, synth_brush(start, .72), start, .018, .10)
            continue
        amount = section_level(bar)
        if bar >= 64:
            amount *= max(.22, 1.0 - (bar - 64) * .12)
        bar_start = bar * BAR

        kick_events = (0.0, 2.72) if bar % 2 == 0 else (0.0, 3.26)
        if bar % 4 == 3:
            kick_events += (1.74,)
        for offset in kick_events:
            start = bar_start + offset * BEAT
            add_sample(track, synth_kick(start), start, .075 * amount, -.02)

        for beat_index, accent in ((1, .84), (3, 1.0)):
            start = bar_start + beat_index * BEAT + .018
            add_sample(
                track, synth_brush(start, accent), start,
                (.033 if beat_index == 1 else .041) * amount, .08,
            )

        for eighth in range(8):
            offset = eighth * .5
            if eighth % 2 == 1:
                offset += swing - .5
            start = bar_start + offset * BEAT + ((bar + eighth) % 5 - 2) * .0012
            strength = 1.0 if eighth in (2, 6) else .78
            side = -.40 if eighth % 2 == 0 else .38
            add_sample(
                track, synth_shaker(start, strength), start,
                .021 * amount * strength, side,
            )


def add_vibes(track: np.ndarray) -> None:
    # Sparse lantern-like accents; never a continuous countermelody.
    events = (
        (26, 76, -.30), (30, 80, .28), (35, 78, -.22), (39, 83, .26),
        (50, 80, -.28), (55, 83, .25), (59, 78, -.24), (63, 76, .22),
        (66, 80, -.20), (69, 76, .18), (72, 73, -.16), (74, 71, .12),
    )
    for bar, note, side in events:
        add_note(
            track, "thin_vibes", note, bar * BAR + .54 * BEAT,
            2.15, .027 * section_level(bar), side,
        )


def add_room(track: np.ndarray) -> None:
    dry = track.copy()
    for delay_seconds, gain, cross in (
        (.083, .072, .010),
        (.147, .048, .014),
        (.239, .031, .013),
        (.371, .018, .009),
    ):
        delay = round(delay_seconds * SAMPLE_RATE)
        track[delay:, 0] += dry[:-delay, 0] * gain + dry[:-delay, 1] * cross
        track[delay:, 1] += dry[:-delay, 1] * gain + dry[:-delay, 0] * cross


def master(track: np.ndarray) -> tuple[np.ndarray, float, float]:
    # Gentle saturation catches isolated drum peaks without flattening the EP.
    track[:] = np.tanh(track * 1.24) / 1.24

    fade_in = round(.42 * SAMPLE_RATE)
    track[:fade_in] *= np.sin(
        np.linspace(0.0, math.pi / 2.0, fade_in, endpoint=False, dtype=np.float32)
    )[:, None] ** 2
    fade_out = round(FADE_OUT_SECONDS * SAMPLE_RATE)
    track[-fade_out:] *= np.cos(
        np.linspace(0.0, math.pi / 2.0, fade_out, endpoint=True, dtype=np.float32)
    )[:, None] ** 2
    track[-1] = 0.0

    rms = float(np.sqrt(np.mean(np.square(track, dtype=np.float64))))
    target_rms = 10.0 ** (-19.85 / 20.0)
    track *= target_rms / max(rms, 1e-9)
    # A second, level-aware soft ceiling reduces only the isolated kick/brush
    # crest. Re-normalizing afterwards keeps the long-term app BGM level near
    # -20 dBFS instead of lowering the entire piece for a handful of samples.
    track[:] = np.tanh(track * 2.0) / 2.0
    # Remove the minute per-channel DC left by the asymmetric arrangement.  A
    # fade-shaped correction keeps both endpoints at zero instead of exposing
    # a constant offset underneath the final 2.4-second fade.
    dc_window = np.ones(FRAME_COUNT, dtype=np.float32)
    dc_window[:fade_in] = np.sin(
        np.linspace(0.0, math.pi / 2.0, fade_in, endpoint=False, dtype=np.float32)
    ) ** 2
    dc_window[-fade_out:] = np.cos(
        np.linspace(0.0, math.pi / 2.0, fade_out, endpoint=True, dtype=np.float32)
    ) ** 2
    correction = np.sum(track, axis=0, dtype=np.float64) / np.sum(
        dc_window, dtype=np.float64
    )
    track -= dc_window[:, None] * correction
    track[-1] = 0.0
    shaped_rms = float(np.sqrt(np.mean(np.square(track, dtype=np.float64))))
    track *= target_rms / max(shaped_rms, 1e-9)
    peak_limit = 10.0 ** (-5.35 / 20.0)
    peak = float(np.max(np.abs(track)))
    if peak > peak_limit:
        track *= peak_limit / peak

    final_rms = float(np.sqrt(np.mean(np.square(track, dtype=np.float64))))
    final_peak = float(np.max(np.abs(track)))
    return track, 20.0 * math.log10(final_rms), 20.0 * math.log10(final_peak)


def render_pcm() -> tuple[np.ndarray, float, float]:
    if sum(bars for _, bars in SECTIONS) != BAR_COUNT:
        raise ValueError("section bar counts must total 76")
    if len(HARMONY) != BAR_COUNT:
        raise ValueError("harmony must contain exactly 76 bars")

    track = np.zeros((FRAME_COUNT, 2), dtype=np.float32)
    add_harmony(track)
    add_phrase(track, 8, THEME_A, 4, .047, True)
    add_phrase(track, 24, THEME_B, 4, .045, True)
    add_phrase(track, 48, THEME_APRIME, 4, .044, True)
    add_bass(track)
    add_drums(track)
    add_vibes(track)
    add_room(track)
    return master(track)


def write_wav(path: Path, track: np.ndarray) -> None:
    rng = np.random.default_rng(DITHER_SEED)
    dither = (rng.random(track.shape) - rng.random(track.shape)) / 65536.0
    pcm = np.clip(track + dither, -1.0, 1.0)
    pcm = np.round(pcm * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(pcm.tobytes())


def normalize_mp4_timestamps(path: Path) -> None:
    """Make afconvert's otherwise deterministic M4A container byte-stable."""
    data = bytearray(path.read_bytes())
    containers = {b"moov", b"trak", b"mdia"}
    timed_headers = {b"mvhd", b"tkhd", b"mdhd"}

    def visit(start: int, end: int) -> None:
        position = start
        while position + 8 <= end:
            size = int.from_bytes(data[position : position + 4], "big")
            kind = bytes(data[position + 4 : position + 8])
            header_size = 8
            if size == 1:
                if position + 16 > end:
                    raise ValueError("truncated 64-bit MP4 atom")
                size = int.from_bytes(data[position + 8 : position + 16], "big")
                header_size = 16
            elif size == 0:
                size = end - position
            atom_end = position + size
            if size < header_size or atom_end > end:
                raise ValueError(f"invalid MP4 atom {kind!r}")
            payload = position + header_size

            if kind in timed_headers:
                if payload + 4 > atom_end:
                    raise ValueError(f"truncated MP4 header {kind!r}")
                field_width = 8 if data[payload] == 1 else 4
                time_start = payload + 4
                time_end = time_start + field_width * 2
                if time_end > atom_end:
                    raise ValueError(f"truncated MP4 timestamps {kind!r}")
                data[time_start:time_end] = bytes(field_width * 2)
            if kind in containers:
                visit(payload, atom_end)
            position = atom_end

    visit(0, len(data))
    path.write_bytes(data)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="destination .m4a file")
    parser.add_argument("--bitrate", type=int, default=176_000)
    args = parser.parse_args()
    if args.output.suffix.lower() != ".m4a":
        parser.error("output must use the .m4a extension")
    if not 160_000 <= args.bitrate <= 192_000:
        parser.error("bitrate must be between 160000 and 192000")

    track, rms_dbfs, peak_dbfs = render_pcm()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="keelmira-leeward-cove-") as temp:
        wav_path = Path(temp) / "leeward_cove.wav"
        write_wav(wav_path, track)
        subprocess.run(
            [
                "/usr/bin/afconvert", str(wav_path), "-o", str(args.output),
                "-f", "m4af", "-d", "aac", "-b", str(args.bitrate), "-q", "96",
            ],
            check=True,
        )
        normalize_mp4_timestamps(args.output)
    print(
        f"Rendered {args.output} | {DURATION:.3f}s | "
        f"PCM RMS {rms_dbfs:.2f} dBFS | PCM peak {peak_dbfs:.2f} dBFS"
    )


if __name__ == "__main__":
    main()
