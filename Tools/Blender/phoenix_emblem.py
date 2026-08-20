"""The phoenix, as a flat outline any prop can wear.

One transcription of `PhoenixShape` — `Views/Wrapped/ArchetypeSymbols.swift` —
shared by every builder that stamps the bird on something. The laptop's lid was
the first; the drinks carry the same mark on their labels, and because both read
these control points the emblem on a bottle and the emblem on the player card
are one shape rather than two drawings that happen to resemble each other.

Design space is PhoenixShape's own 200x200 box with y running down the screen.
`outline` hands back (x, z) with z running up and the bird centred on the origin,
which is what an extruded badge wants.
"""

from __future__ import annotations

# Each entry is (control, end) for one quadratic segment; the run starts at the
# head and closes back onto it.
START = (100.0, 12.0)
CURVES = (
    ((112.0, 28.0), (124.0, 54.0)),     # 頭の右斜面
    ((172.0, 58.0), (193.0, 98.0)),     # 丸い肩から右翼の先端へ
    ((150.0, 100.0), (127.0, 116.0)),   # 翼の下側は深い凹
    ((135.0, 150.0), (143.0, 192.0)),   # 右尾の先端へ
    ((112.0, 162.0), (100.0, 148.0)),   # 尾の間の谷
    ((88.0, 162.0), (57.0, 192.0)),     # 左尾の先端へ
    ((65.0, 150.0), (73.0, 116.0)),     # 左尾から翼の下側へ
    ((50.0, 100.0), (7.0, 98.0)),       # 左翼の先端へ
    ((28.0, 58.0), (76.0, 54.0)),       # 左翼の上側、丸い肩
    ((88.0, 28.0), (100.0, 12.0)),      # 頭の左斜面
)
SAMPLES = 7          # per segment; 70 points around the whole bird
SPAN = 180.0         # design-space head (12) to tail (192)
CENTRE_Y = 102.0     # design-space midpoint, so the bird sits centred
EYE = (100.0, 50.0, 8.0)  # centre x, centre y, radius


def quad_bezier(p0, p1, p2, samples: int) -> list[tuple[float, float]]:
    """Points along one quadratic segment, excluding the start."""
    points = []
    for step in range(1, samples + 1):
        t = step / samples
        inv = 1.0 - t
        points.append((
            inv * inv * p0[0] + 2 * inv * t * p1[0] + t * t * p2[0],
            inv * inv * p0[1] + 2 * inv * t * p1[1] + t * t * p2[1],
        ))
    return points


def outline(height: float) -> list[tuple[float, float]]:
    """The bird's outline in (x, z), head up, centred, `height` from head to tail."""
    scale = height / SPAN
    design = [START]
    cursor = START
    for control, end in CURVES:
        design.extend(quad_bezier(cursor, control, end, SAMPLES))
        cursor = end
    # The last segment closes back onto the head; drop the duplicate point.
    design.pop()
    return [
        ((x - 100.0) * scale, (CENTRE_Y - y) * scale)
        for x, y in design
    ]


def eye_circle(height: float, segments: int = 12) -> list[tuple[float, float]]:
    """The eye, in the same (x, z) frame as `outline` at the same height."""
    import math

    scale = height / SPAN
    eye_x, eye_y, eye_r = EYE
    radius = eye_r * scale
    centre_x = (eye_x - 100.0) * scale
    centre_z = (CENTRE_Y - eye_y) * scale
    return [
        (
            centre_x + math.cos(2 * math.pi * index / segments) * radius,
            centre_z + math.sin(2 * math.pi * index / segments) * radius,
        )
        for index in range(segments)
    ]
