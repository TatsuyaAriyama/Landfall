"""Shared lightweight hull meshing for Landfall's voyage ships."""

from __future__ import annotations


Section = tuple[float, float, float, float]
Point = tuple[float, float, float]
Face = tuple[int, ...]

DEFAULT_RING_FACTORS = (
    -1.0, -0.94, -0.84, -0.72, -0.54, -0.32, 0.0,
    0.32, 0.54, 0.72, 0.84, 0.94, 1.0,
)


def profile_at(sections: list[Section], x: float) -> tuple[float, float, float]:
    """Interpolate sheer, half-beam and keel without moving authored stations."""
    x = max(sections[0][0], min(sections[-1][0], x))
    for index, (start, end) in enumerate(zip(sections, sections[1:])):
        if start[0] <= x <= end[0]:
            t = (x - start[0]) / (end[0] - start[0])
            previous = sections[max(0, index - 1)]
            following = sections[min(len(sections) - 1, index + 2)]

            def interpolate(component: int) -> float:
                p0, p1 = previous[component], start[component]
                p2, p3 = end[component], following[component]
                return 0.5 * (
                    2 * p1
                    + (-p0 + p2) * t
                    + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                    + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t
                )

            return tuple(interpolate(component) for component in range(1, 4))
    return sections[-1][1:]


def rounded_hull_mesh(
    sections: list[Section],
    subdivisions: int = 4,
    ring_factors: tuple[float, ...] = DEFAULT_RING_FACTORS,
) -> tuple[list[Point], list[tuple[Face, float]], list[Face], list[Section]]:
    """Build a sub-500-vertex rounded hull and return faces with beam position.

    The beam midpoint lets a caller split topsides and immersed hull materials
    without rebuilding or slightly misaligning the shared surface.
    """
    sampled: list[Section] = []
    for start, end in zip(sections, sections[1:]):
        for step in range(subdivisions):
            x = start[0] + (end[0] - start[0]) * step / subdivisions
            top, width, keel = profile_at(sections, x)
            sampled.append((x, top, width, keel))
    sampled.append(sections[-1])

    def height(top: float, keel: float, beam_fraction: float) -> float:
        beam = abs(beam_fraction)
        if beam <= 0.72:
            lift = 0.15 * (beam / 0.72) ** 2
        else:
            t = (beam - 0.72) / 0.28
            lift = 0.15 + 0.85 * t * t * (3 - 2 * t)
        return keel + (top - keel) * lift

    vertices = [
        (x, height(top, keel, beam), width * beam)
        for x, top, width, keel in sampled
        for beam in ring_factors
    ]
    ring_count = len(ring_factors)
    strips: list[tuple[Face, float]] = []
    for index in range(len(sampled) - 1):
        a, b = index * ring_count, (index + 1) * ring_count
        for strip in range(ring_count - 1):
            face = (a + strip, b + strip, b + strip + 1, a + strip + 1)
            beam_midpoint = abs((ring_factors[strip] + ring_factors[strip + 1]) * 0.5)
            strips.append((face, beam_midpoint))
    caps = [
        tuple(range(ring_count - 1, -1, -1)),
        tuple(range((len(sampled) - 1) * ring_count, len(sampled) * ring_count)),
    ]
    return vertices, strips, caps, sampled
