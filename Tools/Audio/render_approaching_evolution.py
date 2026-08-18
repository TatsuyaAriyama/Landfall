#!/usr/bin/env python3
"""Render KeelMira's original three-minute piano boss theme, Approaching Evolution.

The concert grand is rendered offline with macOS's bundled General MIDI sound
bank.  Only the finished mix is distributed; the sound bank is never copied.
All score data, orchestration, percussion, room response, and mastering are
generated here.  There are no voices or borrowed musical phrases.

Run with:
    uv run --with numpy --with scipy python render_approaching_evolution.py
"""

from __future__ import annotations

import argparse
import math
import subprocess
import tempfile
import wave
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from scipy import signal
from scipy.io import wavfile


SAMPLE_RATE = 44_100
DOTTED_QUARTER_BPM = 96.0
EIGHTH = 60.0 / DOTTED_QUARTER_BPM / 3.0
BAR = EIGHTH * 12.0
BAR_COUNT = 72
DURATION = BAR * BAR_COUNT
FRAME_COUNT = int(round(DURATION * SAMPLE_RATE))
SCORE_SEED = 20260821
ROOM_SEED = 20260822
DITHER_SEED = 20260823


@dataclass(frozen=True)
class Chord:
    bass: int
    upper: tuple[int, ...]


# Open voicings keep minor seconds above middle C and the bass uncluttered.
CHORD = {
    "Dm9": Chord(38, (53, 57, 62, 64)),
    "Dm9/C": Chord(36, (53, 57, 62, 64)),
    "BbL": Chord(34, (57, 62, 64, 65)),
    "Asus": Chord(33, (55, 58, 62, 64)),
    "Dm/A": Chord(33, (53, 57, 62, 64)),
    "EbL/Bb": Chord(34, (50, 55, 57, 58)),
    "Gm9": Chord(31, (58, 62, 65, 69)),
    "A7b9": Chord(33, (55, 58, 61, 64)),
    "Dm": Chord(38, (53, 57, 62, 65)),
    "Dm/C": Chord(36, (53, 57, 62, 65)),
    "Bb": Chord(34, (57, 62, 65, 69)),
    "Ehalf": Chord(40, (50, 55, 58, 62)),
    "Fmaj9": Chord(41, (52, 57, 64, 67)),
    "C/E": Chord(40, (55, 60, 64, 67)),
    "D/Fs": Chord(42, (50, 57, 62, 66)),
    "EbL": Chord(39, (50, 55, 57, 58)),
    "Ehalf/E": Chord(40, (50, 55, 58, 62)),
    "FmM7": Chord(41, (56, 60, 64, 67)),
    "Fsdim": Chord(42, (57, 60, 63, 66)),
    "Gm/G": Chord(43, (58, 62, 65, 69)),
    "AbL": Chord(44, (55, 60, 62, 63)),
    "Am/C": Chord(36, (57, 60, 64, 69)),
    "F/A": Chord(33, (52, 57, 60, 64)),
    "Dm/F": Chord(41, (50, 57, 62, 64)),
    "C9/D": Chord(38, (52, 55, 60, 62)),
    "BbL/D": Chord(38, (57, 62, 64, 65)),
    "A7/Cs": Chord(37, (55, 58, 61, 64)),
    "Gm6": Chord(31, (52, 58, 62, 67)),
    "Ebmaj9": Chord(39, (50, 55, 58, 65)),
    "Bb/D": Chord(38, (53, 57, 62, 65)),
    "DmM9": Chord(38, (53, 57, 61, 64)),
    "Csdim": Chord(37, (52, 55, 58, 61)),
    "Gm/Bb": Chord(34, (55, 58, 62, 67)),
    "F/C": Chord(36, (53, 57, 60, 65)),
    "EbL2": Chord(39, (50, 55, 57, 58)),
    "D5": Chord(38, (57, 62, 64, 69)),
}

PROGRESSION_NAMES = (
    # 1-8: awakening
    "Dm9", "Dm9/C", "BbL", "Asus", "Dm/A", "EbL/Bb", "Gm9", "A7b9",
    # 9-16: first form
    "Dm", "BbL", "Gm9", "A7b9", "Dm/C", "Bb", "Ehalf", "A7b9",
    # 17-24: adaptation
    "Fmaj9", "C/E", "Dm9", "BbL", "Gm9", "D/Fs", "EbL", "Asus",
    # 25-32: chromatic mutation staircase
    "Dm9", "EbL", "Ehalf/E", "FmM7", "Fsdim", "Gm/G", "AbL", "A7b9",
    # 33-40: exposed core
    "Dm9", "Am/C", "Bb", "F/A", "Gm9", "Dm/F", "Ehalf", "Asus",
    # 41-48: second form
    "Dm9", "C9/D", "BbL/D", "A7/Cs", "Dm/F", "Gm6", "Ehalf", "A7b9",
    # 49-56: self-replication
    "Gm9", "Ebmaj9", "Bb/D", "A7b9", "DmM9", "Csdim", "Gm/Bb", "Asus",
    # 57-64: apex
    "Dm9", "F/C", "Bb", "Gm9", "EbL2", "Bb/D", "Ehalf", "A7b9",
    # 65-72: afterimage
    "Dm9", "BbL/D", "Gm6", "Asus", "DmM9", "Dm/A", "D5", "Dm9",
)
PROGRESSION = tuple(CHORD[name] for name in PROGRESSION_NAMES)

# The rewritten opening uses direct functional motion.  Keeping these chords
# separate protects every form after 20 seconds from accidental reharmonizing.
INTRO_PROGRESSION_NAMES = (
    "Dm9", "Dm9/C", "Bb", "Asus", "Gm9", "Dm/F", "Ehalf", "A7b9",
)
INTRO_PROGRESSION = tuple(CHORD[name] for name in INTRO_PROGRESSION_NAMES)

# Explicit 12/8 events make the opening one continuous, evolving piano phrase.
# Each tuple is (eighth-note offset, length, MIDI pitch, velocity, channel).
INTRO_PIANO_EVENTS = (
    (
        (0, 5.2, 38, 46, 2), (0, 4.8, 50, 44, 2),
        (0, 4.0, 53, 42, 1), (0, 10.8, 45, 41, 2),
        (3, 1.8, 57, 50, 0), (5, 2.6, 62, 56, 0),
        (8, 1.6, 65, 55, 0), (10, 1.7, 64, 51, 0),
    ),
    (
        (0, 5.2, 36, 47, 2), (6, 4.8, 43, 42, 2),
        (2, 1.7, 57, 52, 0), (4, 2.5, 62, 58, 0),
        (7, 1.6, 65, 56, 0), (9, 2.2, 64, 53, 0),
    ),
    (
        (0, 5.0, 34, 50, 2), (6, 4.6, 41, 44, 2),
        (1, 1.7, 57, 54, 0), (3, 1.7, 62, 56, 0),
        (5, 1.8, 65, 58, 0), (8, 1.6, 69, 60, 0),
        (10, 1.7, 65, 57, 0),
    ),
    (
        (0, 5.0, 33, 52, 2), (6, 4.7, 40, 46, 2),
        (1, 1.7, 57, 53, 0), (3, 2.3, 62, 59, 0),
        (6, 1.7, 64, 57, 0), (8, 1.7, 67, 61, 0),
        (10, 1.7, 64, 55, 0),
    ),
    (
        (0, 2.5, 31, 54, 2), (3, 2.2, 38, 48, 2),
        (6, 2.4, 43, 54, 2), (9, 2.0, 38, 49, 2),
        (0, 1.3, 58, 56, 0), (1, 1.4, 62, 59, 0),
        (3, 1.3, 65, 59, 0), (4, 1.4, 69, 62, 0),
        (6, 1.3, 62, 58, 0), (7, 1.4, 65, 61, 0),
        (9, 1.3, 69, 63, 0), (10, 1.4, 70, 64, 0),
    ),
    (
        (0, 2.5, 41, 57, 2), (3, 2.2, 48, 50, 2),
        (6, 2.4, 41, 57, 2), (9, 2.0, 45, 52, 2),
        (0, 1.3, 57, 59, 0), (1, 1.4, 62, 62, 0),
        (3, 1.3, 65, 62, 0), (4, 1.4, 69, 65, 0),
        (6, 1.3, 62, 61, 0), (7, 1.4, 64, 63, 0),
        (9, 1.3, 65, 65, 0), (10, 1.4, 69, 67, 0),
    ),
    (
        (0, 2.4, 40, 59, 2), (3, 2.1, 46, 53, 2),
        (6, 2.2, 52, 59, 2), (9, 1.8, 46, 54, 2),
        (0, .78, 55, 61, 0), (1, .78, 58, 62, 0),
        (2, .78, 62, 63, 0), (3, .78, 64, 63, 0),
        (4, .78, 67, 65, 0), (5, .78, 70, 67, 0),
        (6, .78, 62, 64, 0), (7, .78, 64, 66, 0),
        (8, .78, 67, 68, 0), (9, .78, 70, 71, 0),
        (10, .78, 67, 68, 0), (11, .78, 64, 65, 0),
    ),
    (
        (0, 2.4, 33, 61, 2), (3, 2.2, 40, 55, 2),
        (6, 2.2, 45, 62, 2), (9, 1.35, 33, 63, 2),
        (0, .78, 57, 62, 0), (1, .78, 61, 65, 0),
        (2, .78, 64, 64, 0), (3, .78, 67, 66, 0),
        (4, .78, 64, 64, 0), (5, .78, 61, 67, 0),
        (6, .78, 58, 68, 0), (7, .78, 61, 70, 0),
        (8, .78, 64, 69, 0), (9, 1.25, 67, 71, 0),
        (11, .65, 61, 72, 0),
    ),
)

THEME_A = (
    ((62, 3), (65, 1), (69, 2), (67, 2), (64, 1), (65, 3)),
    # C natural keeps the rising C-D gesture intact when this DNA is reharmonized
    # over Bb, C, Gm, and Eb; C-sharp made those later forms sound mistuned.
    ((72, 2), (74, 2), (69, 3), (70, 1), (65, 1), (64, 1), (62, 2)),
)
THEME_B = (
    ((65, 3), (64, 3), (60, 2), (62, 4)),
    ((57, 3), (58, 2), (60, 1), (62, 6)),
)


@dataclass
class Note:
    start: float
    duration: float
    pitch: int
    velocity: int
    channel: int = 0


class Score:
    def __init__(self) -> None:
        self.notes: list[Note] = []

    def add(self, start: float, duration: float, pitch: int,
            velocity: float, channel: int = 0) -> None:
        if start >= DURATION or duration <= 0 or not 0 <= pitch <= 127:
            return
        self.notes.append(Note(
            max(0.0, start),
            min(duration, DURATION - start - 1 / SAMPLE_RATE),
            pitch,
            int(np.clip(round(velocity), 1, 127)),
            channel,
        ))


def bar_time(bar: int) -> float:
    return bar * BAR


def add_melody(
    score: Score,
    melody: tuple[tuple[tuple[int, int], ...], ...],
    start_bar: int,
    velocity: int,
    transpose: int = 0,
    time_scale: float = 1.0,
    mutation: tuple[int, int] | None = None,
    octave_double: bool = False,
    channel: int = 0,
) -> None:
    elapsed = 0.0
    serial = 0
    for phrase_bar in melody:
        within = 0
        for pitch, units in phrase_bar:
            changed = pitch
            if mutation is not None and serial == mutation[0]:
                changed += mutation[1]
            start = bar_time(start_bar) + (elapsed + within * EIGHTH) * time_scale
            duration = units * EIGHTH * time_scale * 0.91
            score.add(start, duration, changed + transpose, velocity, channel)
            if octave_double:
                score.add(start, duration * 0.96, changed + transpose - 12,
                          velocity - 9, channel + 4)
            within += units
            serial += 1
        elapsed += BAR


def add_theme_bar(score: Score, theme_bar: int, bar: int, velocity: int,
                  mutation_index: int, direction: int) -> None:
    within = 0
    for index, (pitch, units) in enumerate(THEME_A[theme_bar]):
        mutated = pitch + (direction if index == mutation_index else 0)
        score.add(bar_time(bar) + within * EIGHTH, units * EIGHTH * .89,
                  mutated, velocity, 0)
        within += units


def add_arpeggio(score: Score, bar: int, velocity: int, sparse: bool = False) -> None:
    chord = PROGRESSION[bar]
    upper = list(chord.upper)
    # Each dotted beat says low -> high -> inner; register changes carry dynamics.
    for beat in range(4):
        order = (
            upper[beat % len(upper)],
            min(86, upper[-1] + 12),
            upper[(beat + 2) % len(upper)] + (12 if upper[(beat + 2) % len(upper)] < 58 else 0),
        )
        for cell, pitch in enumerate(order):
            if sparse and cell == 1 and beat % 2:
                continue
            accent = 5 if cell == 0 else (2 if cell == 1 else 0)
            start = bar_time(bar) + (beat * 3 + cell) * EIGHTH
            score.add(start, EIGHTH * (1.48 if cell == 2 else 1.13),
                      pitch, velocity + accent, 1)


def add_bass_piano(score: Score, bar: int, velocity: int,
                   chromatic_legato: bool = False) -> None:
    chord = PROGRESSION[bar]
    bass = chord.bass
    fifth = bass + 7
    if chromatic_legato:
        score.add(bar_time(bar), BAR * .91, bass, velocity, 2)
        score.add(bar_time(bar), BAR * .88, bass + 12, velocity - 5, 3)
        return
    for offset, pitch, trim in ((0, bass, 0), (6, fifth, -5)):
        score.add(bar_time(bar) + offset * EIGHTH, EIGHTH * 2.65,
                  pitch, velocity + trim, 2)


def add_transition_run(score: Score, bar: int, velocity: int) -> None:
    chord = PROGRESSION[bar]
    pool = sorted(set(chord.upper + tuple(p + 12 for p in chord.upper)))
    pool = [p for p in pool if 57 <= p <= 86]
    start = bar_time(bar) + BAR * .58
    step = EIGHTH / 2
    for index in range(10):
        pitch = pool[index % len(pool)]
        if index >= len(pool):
            pitch = min(86, pitch + 5)
        score.add(start + index * step, step * .77, pitch,
                  velocity + min(index, 6), 1)


def add_legacy_intro(score: Score) -> None:
    """The previous opening, retained only to reconstruct the protected tail."""
    for bar in range(8):
        chord = PROGRESSION[bar]
        score.add(bar_time(bar), EIGHTH * 2.4, chord.bass + 12, 46 + bar, 2)
        if bar % 2 == 0:
            fragment = THEME_A[(bar // 2) % 2]
            cursor = 0
            for pitch, units in fragment[:3]:
                score.add(bar_time(bar) + (3 + cursor) * EIGHTH,
                          units * EIGHTH * .96, pitch, 53 + bar, 0)
                cursor += units
        else:
            for idx, pitch in enumerate(chord.upper[::2]):
                score.add(bar_time(bar) + (5 + idx * 3) * EIGHTH,
                          EIGHTH * 2.4, pitch, 47 + bar, 1)


def add_rewritten_intro(score: Score) -> None:
    """A coherent piano evolution from a low pedal to the bar-eight dominant."""
    for bar, events in enumerate(INTRO_PIANO_EVENTS):
        for offset, length, pitch, velocity, channel in events:
            score.add(
                bar_time(bar) + offset * EIGHTH,
                length * EIGHTH,
                pitch,
                velocity,
                channel,
            )


def piano_score(rewritten_intro: bool = True) -> Score:
    score = Score()
    if rewritten_intro:
        add_rewritten_intro(score)
    else:
        add_legacy_intro(score)

    # First form.
    for bar in range(8, 16):
        add_arpeggio(score, bar, 49 + (bar - 8))
        add_bass_piano(score, bar, 55 + (bar - 8) // 2)
    add_melody(score, THEME_A, 8, 78)
    add_melody(score, THEME_A, 12, 84, mutation=(3, -1))
    add_transition_run(score, 15, 62)

    # Adaptation: B appears; A migrates into the tenor hand.
    for bar in range(16, 24):
        add_arpeggio(score, bar, 55 + (bar - 16) // 2)
        add_bass_piano(score, bar, 58)
    add_melody(score, THEME_B, 16, 85)
    add_melody(score, THEME_A, 20, 82, transpose=-12, channel=3)
    add_transition_run(score, 23, 66)

    # Mutation staircase: one DNA note changes in every bar over rising roots.
    for bar in range(24, 32):
        add_arpeggio(score, bar, 57 + (bar - 24) * 2)
        add_bass_piano(score, bar, 63 + (bar - 24), chromatic_legato=True)
        phrase_bar = (bar - 24) % 2
        mutation_index = (bar - 24) % len(THEME_A[phrase_bar])
        add_theme_bar(score, phrase_bar, bar, 86 + (bar - 24) * 2,
                      mutation_index, 1 if bar % 2 == 0 else -1)
    add_transition_run(score, 31, 76)

    # Exposed core: the theme breathes at half speed.
    for bar in range(32, 40):
        if bar % 2 == 0:
            add_arpeggio(score, bar, 43 + (bar - 32), sparse=True)
        score.add(bar_time(bar), BAR * .82, PROGRESSION[bar].bass + 12,
                  48 + (bar - 32), 2)
    add_melody(score, THEME_A, 32, 77, time_scale=2.0)

    # Second form: upper-octave DNA with horn-sized spacing in the left hand.
    for bar in range(40, 48):
        add_arpeggio(score, bar, 62 + (bar - 40))
        add_bass_piano(score, bar, 66 + (bar - 40) // 2)
    add_melody(score, THEME_A, 40, 94, transpose=12)
    add_melody(score, THEME_A, 44, 99, transpose=12, mutation=(9, 1))
    add_transition_run(score, 47, 76)

    # Self replication: a lower piano canon enters one bar after the source.
    for bar in range(48, 56):
        add_arpeggio(score, bar, 65 + (bar - 48))
        # 3:2 bass: three attacks across two dotted beats.
        chord = PROGRESSION[bar]
        for cell, unit in enumerate((0, 2, 4, 6, 8, 10)):
            score.add(bar_time(bar) + unit * EIGHTH, EIGHTH * 1.42,
                      chord.bass + (12 if cell % 2 else 0), 62 + cell, 2)
    add_melody(score, THEME_A, 48, 97)
    add_melody(score, THEME_A, 49, 76, transpose=-12, channel=3)
    add_melody(score, THEME_A, 52, 102, mutation=(4, 1))
    add_melody(score, THEME_A, 53, 79, transpose=-12, channel=3)
    add_transition_run(score, 55, 80)

    # Apex: piano octaves carry A; bar 63 empties before the dominant strike.
    for bar in range(56, 64):
        if bar != 62:
            add_arpeggio(score, bar, 70 + min(7, bar - 56))
            add_bass_piano(score, bar, 74 + min(6, bar - 56))
    add_melody(score, THEME_A, 56, 108, octave_double=True)
    add_melody(score, THEME_A, 60, 111, mutation=(6, -1), octave_double=True)
    # Maximum tension remains below D6 and avoids a brittle high-register roll.
    for pitch, delay in zip((45, 52, 58, 61, 64, 67, 70, 73), range(8)):
        score.add(bar_time(63) + delay * EIGHTH * 1.35,
                  EIGHTH * 1.6, pitch, 86 + delay * 2, 1 if pitch > 57 else 2)

    # Afterimage: one last A, then steadily fewer notes and a D-minor(add9) rest.
    add_melody(score, THEME_A, 64, 96, octave_double=True)
    for bar in range(64, 70):
        density = max(1, 6 - (bar - 64))
        chord = PROGRESSION[bar]
        score.add(bar_time(bar), BAR * .66, chord.bass + 12, 65 - (bar - 64) * 3, 2)
        for idx, pitch in enumerate(chord.upper[:density]):
            score.add(bar_time(bar) + (3 + idx * 2) * EIGHTH,
                      EIGHTH * 1.7, pitch, 66 - (bar - 64) * 3, 1)
    for pitch in (50, 57, 62, 64, 69):
        score.add(bar_time(70), BAR * 1.65, pitch, 58, 1)
    for pitch, velocity in ((38, 70), (45, 62), (50, 66), (65, 58), (76, 54)):
        score.add(bar_time(71), BAR * .99, pitch, velocity, 1 if pitch >= 60 else 2)
    return score


def score_chord(bar: int, rewritten_intro: bool) -> Chord:
    if rewritten_intro and bar < 8:
        return INTRO_PROGRESSION[bar]
    return PROGRESSION[bar]


def supporting_scores(rewritten_intro: bool = True) -> dict[str, tuple[int, Score]]:
    strings = Score()
    cello = Score()
    horn = Score()
    timpani = Score()

    for bar in range(BAR_COUNT):
        chord = score_chord(bar, rewritten_intro)
        section = bar // 8
        # The quiet core deliberately uses cello only.
        if section >= 1 and section != 4 and bar < 70:
            base_velocity = (27, 34, 42, 46, 36, 52, 55, 61, 42)[section]
            for voice, pitch in enumerate(chord.upper[-3:]):
                strings.add(bar_time(bar) + .035 * voice, BAR * .91,
                            pitch + (12 if pitch < 55 else 0),
                            base_velocity - voice * 2, voice)
        if bar < 70:
            cello_velocity = (25, 34, 44, 49, 39, 47, 50, 56, 37)[section]
            cello.add(bar_time(bar), BAR * .86, chord.bass + 12,
                      cello_velocity, 0)
            if section in (3, 4, 5, 7):
                cello.add(bar_time(bar) + BAR / 2, BAR * .36,
                          chord.bass + 19, cello_velocity - 6, 1)

    # Thin string canon and the B counter-theme at the apex.
    add_melody(strings, THEME_A, 49, 45, transpose=-12, channel=5)
    add_melody(strings, THEME_A, 53, 49, transpose=-12, channel=5)
    add_melody(strings, THEME_B, 58, 58, channel=6)

    # Rounded horn responses at structural cadences, never continuous walls.
    for bar in (11, 22, 43, 46, 51, 55, 59, 63):
        chord = PROGRESSION[bar]
        velocity = 45 + max(0, bar // 8) * 4
        for voice, pitch in enumerate(chord.upper[:3]):
            horn.add(bar_time(bar) + BAR * .49 + voice * .025,
                     BAR * .43, pitch - 12, min(82, velocity), voice)

    # Timpani only on dotted beats one and three; no constant barrage.
    for bar in list(range(24, 32)) + list(range(40, 48)) + list(range(56, 64)):
        if bar == 62:
            continue
        velocity = 46 + (bar // 8) * 5
        root = max(38, min(50, PROGRESSION[bar].bass + 7))
        timpani.add(bar_time(bar), EIGHTH * 2.55, root, min(88, velocity), 0)
        timpani.add(bar_time(bar) + EIGHTH * 6, EIGHTH * 2.35,
                    max(36, root - 5), min(82, velocity - 5), 0)

    return {
        "strings": (48, strings),
        "cello": (42, cello),
        "horn": (60, horn),
        "timpani": (47, timpani),
    }


def write_event_file(score: Score, path: Path) -> None:
    groups: dict[tuple[int, int], list[Note]] = defaultdict(list)
    for note in score.notes:
        groups[(note.channel, note.pitch)].append(note)

    timed: list[tuple[int, str, int, int, int]] = []
    for (channel, pitch), notes in groups.items():
        notes.sort(key=lambda note: note.start)
        for index, note in enumerate(notes):
            start = int(round(note.start * SAMPLE_RATE))
            end = int(round((note.start + note.duration) * SAMPLE_RATE))
            if index + 1 < len(notes):
                next_start = int(round(notes[index + 1].start * SAMPLE_RATE))
                end = min(end, next_start - 16)
            end = max(start + 1, min(end, FRAME_COUNT - 1))
            timed.append((start, "on", pitch, note.velocity, channel))
            timed.append((end, "off", pitch, 0, channel))

    timed.sort(key=lambda item: (item[0], item[1] == "on", item[4], item[2]))
    lines = ["#frame\ttype\tnote\tvelocity\tchannel"]
    lines.extend("\t".join(map(str, event)) for event in timed)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def render_sampler_stem(
    name: str,
    program: int,
    score: Score,
    helper_binary: Path,
    directory: Path,
) -> np.ndarray:
    events = directory / f"{name}.tsv"
    output = directory / f"{name}.wav"
    write_event_file(score, events)
    subprocess.run(
        [str(helper_binary), str(events), str(output), str(FRAME_COUNT), str(program)],
        check=True,
    )
    sample_rate, audio = wavfile.read(output)
    if sample_rate != SAMPLE_RATE or audio.shape != (FRAME_COUNT, 2):
        raise RuntimeError(f"unexpected {name} stem format: {sample_rate}, {audio.shape}")
    return audio.astype(np.float32, copy=False)


def filter_audio(audio: np.ndarray, highpass: float, lowpass: float) -> np.ndarray:
    sos = signal.butter(3, (highpass, lowpass), btype="bandpass",
                        fs=SAMPLE_RATE, output="sos")
    return signal.sosfilt(sos, audio, axis=0).astype(np.float32)


def rms(audio: np.ndarray) -> float:
    return float(np.sqrt(np.mean(np.square(audio, dtype=np.float64)) + 1e-15))


def normalize_stem(audio: np.ndarray, target_db: float) -> np.ndarray:
    current = rms(audio)
    if current < 1e-8:
        return audio
    return audio * np.float32(10 ** (target_db / 20) / current)


def normalize_active(audio: np.ndarray, target_db: float) -> np.ndarray:
    """Normalize sparse accents by active blocks, never by whole-track silence."""
    block = SAMPLE_RATE // 4
    usable = len(audio) - len(audio) % block
    powers = np.mean(audio[:usable].reshape(-1, block, 2).astype(np.float64) ** 2,
                     axis=(1, 2))
    peak_power = float(np.max(powers, initial=0.0))
    active = powers[powers > peak_power * 10 ** (-24 / 10)]
    if not len(active):
        return audio
    current = math.sqrt(float(np.mean(active)))
    return audio * np.float32(10 ** (target_db / 20) / max(current, 1e-9))


def stereo_room(audio: np.ndarray) -> np.ndarray:
    rng = np.random.default_rng(ROOM_SEED)
    length = int(2.45 * SAMPLE_RATE)
    t = np.arange(length, dtype=np.float64) / SAMPLE_RATE
    decay = np.exp(-t * 2.25)
    impulse = np.zeros((length, 2), dtype=np.float64)
    early_left = ((.023, .38), (.041, .25), (.067, .19), (.109, .13))
    early_right = ((.029, .36), (.047, .23), (.079, .18), (.127, .12))
    for channel, taps in enumerate((early_left, early_right)):
        for delay, gain in taps:
            impulse[int(delay * SAMPLE_RATE), channel] += gain
        noise = rng.normal(0, 1, length)
        noise = signal.sosfilt(
            signal.butter(2, (170, 6_800), btype="bandpass", fs=SAMPLE_RATE, output="sos"),
            noise,
        )
        impulse[:, channel] += noise * decay * .0105
    impulse /= max(np.max(np.abs(impulse)), 1e-9)

    mono = audio.mean(axis=1)
    wet = np.empty_like(audio)
    wet[:, 0] = signal.fftconvolve(mono, impulse[:, 0], mode="full")[:FRAME_COUNT]
    wet[:, 1] = signal.fftconvolve(mono, impulse[:, 1], mode="full")[:FRAME_COUNT]
    wet = normalize_stem(wet, -29.5)
    return audio + wet


def procedural_low_percussion() -> np.ndarray:
    rng = np.random.default_rng(SCORE_SEED)
    output = np.zeros((FRAME_COUNT, 2), dtype=np.float32)

    def mix(start: float, sound: np.ndarray, pan: float = 0.0) -> None:
        first = int(round(start * SAMPLE_RATE))
        if first >= FRAME_COUNT:
            return
        sound = sound[: FRAME_COUNT - first]
        left = math.sqrt((1 - pan) * .5)
        right = math.sqrt((1 + pan) * .5)
        output[first:first + len(sound), 0] += sound * left
        output[first:first + len(sound), 1] += sound * right

    def bass_drum(strength: float) -> np.ndarray:
        duration = 1.65
        count = int(duration * SAMPLE_RATE)
        t = np.arange(count, dtype=np.float64) / SAMPLE_RATE
        frequency_curve = 82 * np.exp(-t * 8.0) + 43
        phase = 2 * math.pi * np.cumsum(frequency_curve) / SAMPLE_RATE
        body = np.sin(phase) + .17 * np.sin(phase * 2.01)
        envelope = (1 - np.exp(-t * 46)) * np.exp(-t * 3.15)
        noise = signal.sosfilt(
            signal.butter(2, 165, btype="lowpass", fs=SAMPLE_RATE, output="sos"),
            rng.normal(0, 1, count),
        )
        return ((body * envelope + noise * np.exp(-t * 15) * .055) * strength).astype(np.float32)

    def low_metal(strength: float) -> np.ndarray:
        duration = 3.8
        count = int(duration * SAMPLE_RATE)
        t = np.arange(count, dtype=np.float64) / SAMPLE_RATE
        envelope = (1 - np.exp(-t * 25)) * np.exp(-t * .92)
        sound = np.zeros(count)
        for hz, level, detune in ((112, .42, 0), (173, .23, .13), (267, .14, -.17), (391, .06, .21)):
            sound += level * np.sin(2 * math.pi * (hz + detune) * t + rng.uniform(0, math.tau))
        return (sound * envelope * strength).astype(np.float32)

    for bar in range(24, 32):
        mix(bar_time(bar), bass_drum(.075 + (bar - 24) * .004), -.08)
    for bar in range(40, 48):
        if bar % 2 == 0:
            mix(bar_time(bar), bass_drum(.09 + (bar - 40) * .004), .06)
    for bar in range(56, 64):
        if bar != 62:
            mix(bar_time(bar), bass_drum(.105 + (bar - 56) * .004), -.04)
            mix(bar_time(bar) + BAR / 2, bass_drum(.073), .05)
    for boundary in (8, 16, 24, 32, 40, 48, 56, 64):
        mix(bar_time(boundary) - .12, low_metal(.045 if boundary < 48 else .06),
            -.22 if boundary % 16 else .22)
    return output


def continuous_resonance(rewritten_intro: bool = True) -> np.ndarray:
    """A quiet, dark soundboard breath prevents holes without becoming a pad lead."""
    rng = np.random.default_rng(SCORE_SEED + 1)
    output = np.zeros((FRAME_COUNT, 2), dtype=np.float32)
    overlap = .42
    for bar in range(BAR_COUNT):
        chord = score_chord(bar, rewritten_intro)
        start = max(0.0, bar_time(bar) - overlap / 2)
        duration = min(BAR + overlap, DURATION - start)
        count = int(round(duration * SAMPLE_RATE))
        t = np.arange(count, dtype=np.float64) / SAMPLE_RATE
        fade = np.ones(count)
        edge = min(int(overlap * SAMPLE_RATE), count // 2)
        fade[:edge] = np.sin(np.linspace(0, math.pi / 2, edge)) ** 2
        fade[-edge:] = np.cos(np.linspace(0, math.pi / 2, edge)) ** 2
        signal_mono = np.zeros(count)
        for pitch, amount in ((chord.bass + 12, .62), (chord.bass + 19, .25),
                              (chord.upper[0], .13)):
            hz = 440 * 2 ** ((pitch - 69) / 12)
            detune = rng.uniform(-.22, .22)
            phase = rng.uniform(0, math.tau)
            signal_mono += amount * np.sin(2 * math.pi * (hz + detune) * t + phase)
            signal_mono += amount * .07 * np.sin(2 * math.pi * hz * 2.002 * t + phase * .37)
        tremolo = .92 + .08 * np.sin(2 * math.pi * (.13 + bar % 3 * .011) * t + bar)
        sound = (signal_mono * fade * tremolo * .012).astype(np.float32)
        first = int(round(start * SAMPLE_RATE))
        sound = sound[:FRAME_COUNT - first]
        pan = -.12 if bar % 2 else .12
        output[first:first + len(sound), 0] += sound * math.sqrt((1 - pan) * .5)
        output[first:first + len(sound), 1] += sound * math.sqrt((1 + pan) * .5)
    return output


def structural_safety_automation(audio: np.ndarray) -> np.ndarray:
    """Match sparse/dense hand-offs so a new form never arrives as a volume shock."""
    points = np.array((
        (0.0, 0.0),
        (19.65, 0.0),
        (20.0, -5.2),
        (25.0, 0.0),
        (79.55, 0.0),
        (80.0, 5.4),
        (99.55, 5.4),
        (100.0, -4.1),
        (105.0, 0.0),
        (154.55, 0.0),
        (155.0, 2.6),
        (158.0, 0.0),
        (164.55, 0.0),
        (165.0, 5.3),
        (170.0, 2.0),
        (174.60, 0.0),
        (180.0, 0.0),
    ))
    frames = points[:, 0] * SAMPLE_RATE
    gain_db = np.interp(np.arange(len(audio)), frames, points[:, 1])
    return audio * np.power(10.0, gain_db / 20.0).astype(np.float32)[:, None]


SECTION_TARGETS = np.array((-22.4, -20.8, -20.0, -19.3, -21.8, -19.9, -19.3, -18.8, -21.0))


def shape_sections(audio: np.ndarray) -> np.ndarray:
    """Long-window rider: musical dynamics remain, structural jumps do not."""
    hop = SAMPLE_RATE // 4
    block_count = math.ceil(len(audio) / hop)
    padded = np.pad(audio, ((0, block_count * hop - len(audio)), (0, 0)))
    powers = np.mean(padded.reshape(block_count, hop, 2).astype(np.float64) ** 2,
                     axis=(1, 2))
    # A one-second detector ignores individual hammer attacks.
    powers = np.convolve(powers, np.ones(4) / 4, mode="same")
    current_db = 10 * np.log10(np.maximum(powers, 1e-12))
    times = (np.arange(block_count) + .5) * hop / SAMPLE_RATE
    centers = np.arange(9) * 20.0 + 10.0
    target_db = np.interp(times, centers, SECTION_TARGETS,
                          left=SECTION_TARGETS[0], right=SECTION_TARGETS[-1])
    requested = np.clip(target_db - current_db, -7.0, 9.0)
    # Five-second raised-cosine smoothing plus a 0.45 dB/s slew ceiling.
    window = signal.windows.hann(21)
    window /= window.sum()
    gain_db = np.convolve(requested, window, mode="same")
    maximum_step = .45 * hop / SAMPLE_RATE
    for index in range(1, len(gain_db)):
        gain_db[index] = np.clip(gain_db[index],
                                 gain_db[index - 1] - maximum_step,
                                 gain_db[index - 1] + maximum_step)
    for index in range(len(gain_db) - 2, -1, -1):
        gain_db[index] = np.clip(gain_db[index],
                                 gain_db[index + 1] - maximum_step,
                                 gain_db[index + 1] + maximum_step)
    positions = (np.arange(block_count) + .5) * hop
    sample_db = np.interp(np.arange(len(audio)), positions, gain_db,
                          left=gain_db[0], right=gain_db[-1])
    return audio * np.power(10.0, sample_db / 20.0).astype(np.float32)[:, None]


def gentle_master(audio: np.ndarray) -> np.ndarray:
    audio = filter_audio(audio, 29.0, 10_200.0)
    audio -= np.mean(audio, axis=0, dtype=np.float64).astype(np.float32)

    # Linked 10 ms detector, 1.5:1 compression, then broad interpolation.
    block = 441
    pad = (-len(audio)) % block
    detector = np.pad(audio, ((0, pad), (0, 0)))
    detector = detector.reshape(-1, block, 2)
    levels = np.sqrt(np.mean(detector.astype(np.float64) ** 2, axis=(1, 2)) + 1e-12)
    level_db = 20 * np.log10(levels)
    threshold = -20.0
    compressed_db = np.where(level_db > threshold,
                             threshold + (level_db - threshold) / 1.62,
                             level_db)
    gain_db = compressed_db - level_db
    smoothing = signal.windows.hann(31)
    smoothing /= smoothing.sum()
    gain_db = np.convolve(gain_db, smoothing, mode="same")
    positions = np.arange(len(gain_db)) * block + block / 2
    sample_gain_db = np.interp(np.arange(len(audio)), positions, gain_db,
                               left=gain_db[0], right=gain_db[-1])
    audio *= np.power(10.0, sample_gain_db / 20.0).astype(np.float32)[:, None]

    # Soft saturation catches isolated piano hammer peaks without flattening attacks.
    drive = 1.10
    audio = np.tanh(audio * drive).astype(np.float32) / math.tanh(drive)
    current_rms_db = 20 * math.log10(max(rms(audio), 1e-9))
    audio *= np.float32(10 ** ((-19.15 - current_rms_db) / 20))
    peak = float(np.max(np.abs(audio)))
    ceiling = 10 ** (-5.4 / 20)
    if peak > ceiling:
        audio *= np.float32(ceiling / peak)

    # Natural final cadence, with a 2.4 s raised-cosine tail and no silent hole.
    fade_frames = int(2.4 * SAMPLE_RATE)
    fade = np.cos(np.linspace(0, math.pi / 2, fade_frames, dtype=np.float64)) ** 2
    audio[-fade_frames:] *= fade.astype(np.float32)[:, None]
    return audio


def write_pcm24(path: Path, audio: np.ndarray) -> None:
    rng = np.random.default_rng(DITHER_SEED)
    dither = (rng.random(audio.shape) - rng.random(audio.shape)) / (2 ** 24)
    integers = np.clip(np.round((audio.astype(np.float64) + dither) * 8_388_607),
                       -8_388_608, 8_388_607).astype(np.int32)
    unsigned = integers.astype(np.uint32)
    packed = np.empty((integers.size, 3), dtype=np.uint8)
    flattened = unsigned.ravel()
    packed[:, 0] = flattened & 0xFF
    packed[:, 1] = (flattened >> 8) & 0xFF
    packed[:, 2] = (flattened >> 16) & 0xFF
    with wave.open(str(path), "wb") as destination:
        destination.setnchannels(2)
        destination.setsampwidth(3)
        destination.setframerate(SAMPLE_RATE)
        destination.writeframes(packed.tobytes())


def assemble_master(stems: dict[str, np.ndarray], rewritten_intro: bool) -> np.ndarray:
    """Mix one score variant through the exact same deterministic signal path."""
    # DLS grand is mono-compatible; subtle spectral stereo delays and the room
    # create width without phasey bass.  Piano remains 6-12 dB above each support.
    piano = filter_audio(stems["piano"], 30, 10_500)
    delay = 31
    piano_width = piano.copy()
    piano_width[delay:, 0] += piano[:-delay, 0] * .085
    piano_width[delay * 2:, 1] += piano[:-delay * 2, 1] * .075
    mix = normalize_stem(piano_width, -22.2)
    mix += normalize_stem(filter_audio(stems["strings"], 70, 7_500), -31.5)
    mix += normalize_stem(filter_audio(stems["cello"], 42, 5_800), -31.5)
    mix += normalize_active(filter_audio(stems["horn"], 65, 6_200), -31.0)
    mix += normalize_active(filter_audio(stems["timpani"], 36, 4_200), -30.0)
    mix += normalize_active(procedural_low_percussion(), -30.5)
    mix += normalize_stem(continuous_resonance(rewritten_intro), -29.5)
    mix = structural_safety_automation(mix)
    mix = stereo_room(mix)
    mix = shape_sections(mix)
    return gentle_master(mix)


def protect_existing_forms(candidate: np.ndarray, legacy: np.ndarray) -> np.ndarray:
    """Use the new intro, then restore the proven master before bar nine."""
    intro_end = int(round(8 * BAR * SAMPLE_RATE))
    crossfade_start = int(round(19.90 * SAMPLE_RATE))
    count = intro_end - crossfade_start
    phase = np.linspace(0, math.pi / 2, count, endpoint=False)
    candidate_gain = np.cos(phase) ** 2
    legacy_gain = np.sin(phase) ** 2

    protected = legacy.copy()
    protected[:crossfade_start] = candidate[:crossfade_start]
    protected[crossfade_start:intro_end] = (
        candidate[crossfade_start:intro_end] * candidate_gain[:, None]
        + legacy[crossfade_start:intro_end] * legacy_gain[:, None]
    )
    # From exactly 20.000 seconds onward, `protected` remains the legacy master.
    return protected.astype(np.float32, copy=False)


def render(output: Path, keep_stems: Path | None) -> None:
    script_dir = Path(__file__).resolve().parent
    helper_source = script_dir / "render_approaching_evolution_piano.swift"
    with tempfile.TemporaryDirectory(prefix="approaching-evolution-") as temporary:
        work = Path(temporary)
        helper_binary = work / "sampler-renderer"
        subprocess.run(["swiftc", str(helper_source), "-o", str(helper_binary)], check=True)

        stems: dict[str, np.ndarray] = {}
        stems["piano"] = render_sampler_stem(
            "piano", 0, piano_score(rewritten_intro=True), helper_binary, work
        )
        for name, (program, score) in supporting_scores(rewritten_intro=True).items():
            stems[name] = render_sampler_stem(name, program, score, helper_binary, work)

        legacy_stems = dict(stems)
        legacy_stems["piano"] = render_sampler_stem(
            "legacy-piano", 0, piano_score(rewritten_intro=False), helper_binary, work
        )
        legacy_cello_program, legacy_cello_score = supporting_scores(
            rewritten_intro=False
        )["cello"]
        legacy_stems["cello"] = render_sampler_stem(
            "legacy-cello", legacy_cello_program, legacy_cello_score,
            helper_binary, work,
        )

        candidate_master = assemble_master(stems, rewritten_intro=True)
        legacy_master = assemble_master(legacy_stems, rewritten_intro=False)
        master = protect_existing_forms(candidate_master, legacy_master)

        if keep_stems is not None:
            keep_stems.mkdir(parents=True, exist_ok=True)
            for name, stem in stems.items():
                wavfile.write(keep_stems / f"approaching_evolution_{name}.wav",
                              SAMPLE_RATE, stem.astype(np.float32))

    output.parent.mkdir(parents=True, exist_ok=True)
    write_pcm24(output, master)


def main() -> None:
    default_output = Path(__file__).resolve().parent / "approaching_evolution.wav"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", nargs="?", type=Path, default=default_output)
    parser.add_argument("--keep-stems", type=Path)
    args = parser.parse_args()
    render(args.output.resolve(), args.keep_stems.resolve() if args.keep_stems else None)


if __name__ == "__main__":
    main()
