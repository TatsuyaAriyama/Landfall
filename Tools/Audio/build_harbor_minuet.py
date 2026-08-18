#!/usr/bin/env python3
"""Render "Harbor Minuet", the original KeelMira main theme.

The score is intentionally kept as data below so the bundled audio can always be
reproduced.  It quotes no existing composition: G major, 3/4, 32 bars, ABA' + coda.
The B-D-G rising figure is KeelMira's recurring departure-and-return motif.
Only the Python standard library and macOS' ``afconvert`` are required.
"""

from __future__ import annotations

import argparse
import math
import random
import subprocess
import tempfile
import wave
from array import array
from pathlib import Path


RATE = 44_100
EIGHTH = 0.40
BAR = EIGHTH * 6
TAIL = 2.2

# chord: bass + three-note upper voicing
# melody: (eighth-note offset, MIDI note, length in eighth notes, velocity)
SCORE = [
    # A — the B-D-G "homeward" motif and its answer. Every melodic landing is
    # a triad tone; short releases keep one harmony from clouding the next.
    ([43, 55, 59, 62], [(0, 71, 2, .105), (2, 74, 2, .110), (4, 79, 2, .118)]),
    ([42, 54, 57, 62], [(0, 78, 3, .112), (3, 74, 2, .094), (5, 69, 1, .080)]),
    ([40, 52, 55, 59], [(0, 76, 2, .098), (2, 79, 2, .110), (4, 83, 2, .116)]),
    ([38, 50, 54, 59], [(0, 83, 3, .108), (3, 78, 2, .096), (5, 74, 1, .080)]),
    ([36, 48, 52, 55], [(0, 79, 2, .106), (2, 76, 2, .094), (4, 72, 2, .088)]),
    ([47, 55, 59, 62], [(0, 71, 2, .092), (2, 74, 2, .102), (4, 79, 2, .112)]),
    ([45, 57, 60, 64], [(0, 69, 2, .086), (2, 72, 2, .094), (4, 76, 2, .102)]),
    ([38, 50, 54, 57], [(0, 78, 4, .108), (4, 74, 2, .084)]),
    # B — the view opens beyond the breakwater
    ([38, 50, 54, 57], [(0, 74, 2, .094), (2, 78, 2, .106), (4, 81, 2, .114)]),
    ([40, 52, 55, 59], [(0, 83, 3, .114), (3, 79, 2, .100), (5, 76, 1, .086)]),
    ([36, 48, 52, 55], [(0, 79, 2, .104), (2, 76, 2, .094), (4, 72, 2, .086)]),
    ([38, 50, 54, 57], [(0, 74, 2, .092), (2, 69, 2, .084), (4, 78, 2, .106)]),
    ([36, 48, 52, 55], [(0, 76, 2, .098), (2, 79, 2, .110), (4, 84, 2, .120)]),
    ([40, 52, 55, 59], [(0, 83, 2, .116), (2, 79, 2, .104), (4, 76, 2, .092)]),
    ([38, 50, 54, 57], [(0, 81, 2, .108), (2, 78, 2, .098), (4, 74, 2, .086)]),
    ([43, 55, 59, 62], [(0, 71, 2, .090), (2, 74, 2, .100), (4, 79, 2, .112)]),
    # A' — the theme returns one octave brighter in places
    ([43, 55, 59, 62], [(0, 71, 1, .092), (1, 74, 1, .096), (2, 79, 2, .114), (4, 83, 2, .120)]),
    ([42, 54, 57, 62], [(0, 81, 2, .108), (2, 78, 2, .100), (4, 74, 2, .088)]),
    ([40, 52, 55, 59], [(0, 76, 2, .098), (2, 79, 2, .110), (4, 83, 2, .118)]),
    ([38, 50, 54, 59], [(0, 86, 2, .118), (2, 83, 2, .110), (4, 78, 2, .098)]),
    ([36, 48, 52, 55], [(0, 79, 2, .108), (2, 76, 2, .096), (4, 72, 2, .088)]),
    ([47, 55, 59, 62], [(0, 71, 2, .092), (2, 74, 2, .102), (4, 79, 2, .112)]),
    ([45, 57, 60, 64], [(0, 69, 2, .086), (2, 72, 2, .094), (4, 76, 2, .102)]),
    ([38, 50, 54, 57], [(0, 78, 5, .110)]),
    # Coda — ropes settle, then the opening can return naturally
    ([36, 48, 52, 55], [(0, 72, 2, .090), (2, 76, 2, .098), (4, 79, 2, .108)]),
    ([47, 55, 59, 62], [(0, 71, 2, .092), (2, 74, 2, .102), (4, 79, 2, .112)]),
    ([45, 57, 60, 64], [(0, 69, 2, .086), (2, 72, 2, .094), (4, 76, 2, .102)]),
    ([38, 50, 54, 57], [(0, 69, 2, .084), (2, 74, 2, .098), (4, 78, 2, .108)]),
    ([43, 55, 59, 62], [(0, 71, 2, .092), (2, 74, 2, .102), (4, 79, 2, .114)]),
    ([40, 52, 55, 59], [(0, 67, 2, .082), (2, 71, 2, .092), (4, 76, 2, .104)]),
    ([38, 50, 54, 57], [(0, 69, 2, .084), (2, 74, 2, .094), (4, 78, 2, .106)]),
    ([43, 55, 59, 62], [(0, 79, 5, .116)]),
]


def validate_score() -> None:
    """Keep the main theme consonant and prevent accidental note overlaps."""
    for bar_number, (chord, melody) in enumerate(SCORE, start=1):
        chord_tones = {note % 12 for note in chord}
        if len(chord_tones) != 3:
            raise ValueError(f"bar {bar_number}: accompaniment is not a triad")
        for index, (step, note, length, _) in enumerate(melody):
            if note % 12 not in chord_tones:
                raise ValueError(f"bar {bar_number}: melody note {note} is outside the triad")
            next_step = melody[index + 1][0] if index + 1 < len(melody) else 6
            if step + length * .92 > next_step:
                raise ValueError(f"bar {bar_number}: melody notes overlap")


def midi_hz(note: int) -> float:
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def stereo_gains(pan: float) -> tuple[float, float]:
    angle = (max(-1.0, min(1.0, pan)) + 1.0) * math.pi / 4.0
    return math.cos(angle), math.sin(angle)


def add_piano(left: array, right: array, note: int, start: float, duration: float,
              level: float, pan: float) -> None:
    first = max(0, int(start * RATE))
    count = min(len(left) - first, int(duration * RATE))
    if count <= 0:
        return
    frequency = midi_hz(note)
    left_gain, right_gain = stereo_gains(pan)
    for offset in range(count):
        time = offset / RATE
        # Notes used to overlap by more than a quarter second. A short natural
        # release preserves legato in the melody without producing seconds
        # against the following note or the next bar's harmony.
        attack = min(1.0, time / 0.012)
        release_start = max(0.04, duration - 0.16)
        release = 1.0 if time < release_start else max(0.0, (duration - time) / 0.16)
        decay = math.exp(-time * 1.58)
        value = (
            math.sin(math.tau * frequency * time) * .73
            + math.sin(math.tau * frequency * 2.003 * time) * math.exp(-time * 2.6) * .21
            + math.sin(math.tau * frequency * 3.009 * time) * math.exp(-time * 4.0) * .06
        ) * attack * release * decay * level
        left[first + offset] += value * left_gain
        right[first + offset] += value * right_gain


def render_wav(path: Path) -> float:
    duration = len(SCORE) * BAR + TAIL
    frame_count = int(duration * RATE)
    left = array("f", [0.0]) * frame_count
    right = array("f", [0.0]) * frame_count

    for bar_index, (chord, melody) in enumerate(SCORE):
        start = bar_index * BAR
        dynamic = .86 + .10 * math.sin(math.pi * bar_index / (len(SCORE) - 1))
        bass, *upper = chord

        # Classical waltz pulse: bass on one, light upper chords on two and three.
        add_piano(left, right, bass, start, EIGHTH * 1.52, .068 * dynamic, -.30)
        for beat, chord_pan in ((2, -.12), (4, .02)):
            for voice, note in enumerate(upper):
                add_piano(
                    left, right, note, start + beat * EIGHTH,
                    EIGHTH * 1.42, (.038 - voice * .003) * dynamic, chord_pan + voice * .08,
                )

        for step, note, length, velocity in melody:
            add_piano(
                left, right, note, start + step * EIGHTH + .018,
                length * EIGHTH * .92, velocity * dynamic, .16 + (note - 74) * .018,
            )

    # Short wooden-room reflections. In-place feedback makes each later echo softer.
    for delay_sec, gain, cross in ((.14, .10, .018), (.26, .06, .016), (.39, .028, .012)):
        delay = int(delay_sec * RATE)
        for index in range(delay, frame_count):
            old_left = left[index - delay]
            old_right = right[index - delay]
            left[index] += old_left * gain + old_right * cross
            right[index] += old_right * gain + old_left * cross

    # Deterministic, barely audible tape/room air prevents a sterile digital floor.
    rng = random.Random(0xA17DE)
    room = 0.0
    peak = 0.0
    fade_in = int(.55 * RATE)
    fade_out = int(2.0 * RATE)
    for index in range(frame_count):
        room += (rng.random() * 2.0 - 1.0 - room) * .012
        envelope = min(1.0, index / fade_in)
        if index >= frame_count - fade_out:
            envelope *= max(0.0, (frame_count - index) / fade_out)
        left[index] = (left[index] + room * .0007) * envelope
        right[index] = (right[index] - room * .0007) * envelope
        peak = max(peak, abs(left[index]), abs(right[index]))

    gain = .86 / max(peak, 1e-6)
    pcm = array("h")
    for l_value, r_value in zip(left, right):
        pcm.append(round(max(-1.0, min(1.0, l_value * gain)) * 32767))
        pcm.append(round(max(-1.0, min(1.0, r_value * gain)) * 32767))

    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())
    return duration


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path, help="destination .m4a file")
    parser.add_argument("--bitrate", type=int, default=160_000)
    args = parser.parse_args()
    if args.output.suffix.lower() != ".m4a":
        parser.error("output must use the .m4a extension")

    validate_score()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="keelmira-main-theme-") as temp:
        wav_path = Path(temp) / "keelmira_main_theme.wav"
        duration = render_wav(wav_path)
        subprocess.run(
            [
                "/usr/bin/afconvert", str(wav_path), "-o", str(args.output),
                "-f", "m4af", "-d", "aac", "-b", str(args.bitrate), "-q", "96",
            ],
            check=True,
        )
    print(f"Rendered {args.output} ({duration:.2f}s)")


if __name__ == "__main__":
    main()
