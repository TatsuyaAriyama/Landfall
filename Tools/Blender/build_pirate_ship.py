"""Build the pirate ship — the third hull a player can sail.

Where the Garden Estate is formal and swept clean, this one is the opposite
reading of the same sea: a tarred, rust-striped hull under a solid bulwark, a
square sail gone ragged at the foot, ratlines up to a crow's nest, a black flag
at the masthead and a chest nobody has opened in a while.

The rig is the real difference. The other two ships set a fore-and-aft main
whose foot sweeps the whole deck at head height, which is why their decks stay
almost bare. A square sail hangs from a yard well above the deck, so this hull
can carry a raised quarterdeck, a wheel, a crow's nest and cargo without a sail
passing through any of it.

The same two rules hold this file to the runtime:

* Only the two sail meshes carry contract material names (`LF_BoatMainSail`,
  `LF_BoatJib`). They are the surfaces `VoyageSceneKit.makeBoatModel` recolours;
  everything else keeps a pirate name so the tar and rust survive into the game.
* `Navigator_Anchor` sits where the other two ships put it, at
  (0.74, 0.68, 0.18) — here that is the forecastle, raised to the same height
  the Garden Estate's bow terrace stands at.

Coordinates are authored X=forward, Y=up, Z=beam — SceneKit's frame, not
Blender's. The root carries the 90° rotation that makes that editable.

    blender --background --python Tools/Blender/build_pirate_ship.py
"""

from __future__ import annotations

import math
import os
import shutil
import sys
from pathlib import Path

import bpy


# The kit builds its own ten props when run as a script. Import it as a library.
_requested = os.environ.get("KEELMIRA_ASSET_IDS", "")
os.environ["KEELMIRA_ASSET_IDS"] = "__pirate_ship_helpers_only__"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_home_island_asset_set_02 as kit  # noqa: E402

os.environ["KEELMIRA_ASSET_IDS"] = _requested


ASSET_ID = "pirate_ship"
ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "Landfall/Resources"

UP = math.radians(-90)  # Stand a primitive's local Z axis up in authored space.


def upright(spin: float = 0.0) -> tuple[float, float, float]:
    """Rotation that points a cylinder or cone at the authored sky, with an
    optional spin about that new axis."""
    return (UP, spin, 0.0)


def materials() -> dict[str, bpy.types.Material]:
    """Tarred wood and rust, kept inside the warm palette the starting boat
    already uses — this is the same sea, sailed by someone rougher."""
    return {
        "tar": kit.material("LF_PirateTar", "#33231A", 0.94),
        "hull": kit.material("LF_PirateHull", "#4A3120", 0.92),
        # The bulwark is a thin wall the camera sees from inboard and out,
        # so it cannot be backface culled the way the closed hull is.
        "bulwark": kit.material("LF_PirateBulwark", "#4A3120", 0.92, double_sided=True),
        "strake": kit.material("LF_PirateStrake", "#7A3B22", 0.90),
        "deck": kit.material("LF_PirateDeck", "#6B5136", 0.95),
        "deck_worn": kit.material("LF_PirateDeckWorn", "#836646", 0.96),
        "gold": kit.material("LF_PirateGold", "#B98B3C", 0.48, metallic=0.55),
        "iron": kit.material("LF_PirateIron", "#3A3833", 0.80, metallic=0.28),
        "rope": kit.material("LF_PirateRope", "#B7A277", 1.0),
        "bone": kit.material("LF_PirateBone", "#E8E2D0", 0.86),
        "flag": kit.material("LF_PirateFlag", "#17130F", 0.92, double_sided=True),
        "glass": kit.material("LF_PirateLampGlass", "#E4C388", 0.34),
        # The same flame the island's lantern post and the estate's lamps burn.
        "glow": kit.material("LF_PirateLampGlow", "#F3C065", 0.28, emission="#FF9A3C", emission_strength=2.4),
        # The cloth: coarser than either of the other two ships. The runtime
        # only ever rewrites the colour, so this weave survives every palette.
        "patch": kit.material("LF_PirateSailPatch", "#B3A075", 0.99, double_sided=True),
        "main_sail": kit.material("LF_BoatMainSail", "#EADEBD", 0.99, double_sided=True),
        "jib": kit.material("LF_BoatJib", "#EADEBD", 0.99, double_sided=True),
    }


# Stations run stern (-X) to bow (+X): x, sheer, half beam, keel. Both ends
# rise and the waist dips — the galleon sheer. It is the line that reads as
# "pirate" from a hundred points away, before any flag is legible.
SECTIONS = [
    (-1.20, 0.62, 0.30, 0.04),
    (-0.92, 0.56, 0.44, -0.14),
    (-0.45, 0.52, 0.55, -0.30),
    (0.08, 0.51, 0.58, -0.33),
    (0.60, 0.53, 0.52, -0.27),
    (1.05, 0.60, 0.36, -0.05),
    (1.35, 0.72, 0.16, 0.24),
    (1.50, 0.86, 0.03, 0.54),
]


def profile(x: float) -> tuple[float, float, float]:
    """Sheer, half beam and keel anywhere along the hull, so fittings sit on
    the hull rather than near it. A Catmull-Rom span keeps the authored
    stations exact while removing the straight kinks between them."""
    x = max(SECTIONS[0][0], min(SECTIONS[-1][0], x))
    for index, (start, end) in enumerate(zip(SECTIONS, SECTIONS[1:])):
        if start[0] <= x <= end[0]:
            t = (x - start[0]) / (end[0] - start[0])
            previous = SECTIONS[max(0, index - 1)]
            following = SECTIONS[min(len(SECTIONS) - 1, index + 2)]

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
    return SECTIONS[-1][1:]


def station(x: float) -> tuple[float, float]:
    top, width, _ = profile(x)
    return top, width


def hull_samples() -> list[float]:
    """Every station plus the midpoints between them: a run of beams drawn
    station to station shows its facets on a hull this size."""
    samples: list[float] = []
    for start, end in zip(SECTIONS, SECTIONS[1:]):
        samples += [start[0], (start[0] + end[0]) / 2]
    samples.append(SECTIONS[-1][0])
    return samples


def hull_sections(subdivisions: int = 4) -> list[tuple[float, float, float, float]]:
    """Sample the authored hull curve densely enough for a clean mobile
    silhouette. This stays below five hundred vertices, but avoids asking
    lighting normals to hide an eight-station outline."""
    sections: list[tuple[float, float, float, float]] = []
    for start, end in zip(SECTIONS, SECTIONS[1:]):
        for step in range(subdivisions):
            x = start[0] + (end[0] - start[0]) * step / subdivisions
            top, width, keel = profile(x)
            sections.append((x, top, width, keel))
    sections.append(SECTIONS[-1])
    return sections


HULL_RING_FACTORS = (-1.0, -0.94, -0.84, -0.72, -0.54, -0.32, 0.0,
                     0.32, 0.54, 0.72, 0.84, 0.94, 1.0)


def hull_ring_height(top: float, keel: float, beam_fraction: float) -> float:
    """Rounded cross-section preserving the original hard-working shape:
    broad below the waterline, then quickly rising into near-vertical sides."""
    beam = abs(beam_fraction)
    if beam <= 0.72:
        lift = 0.15 * (beam / 0.72) ** 2
    else:
        t = (beam - 0.72) / 0.28
        smooth = t * t * (3 - 2 * t)
        lift = 0.15 + 0.85 * smooth
    return keel + (top - keel) * lift


def chain(
    prefix: str,
    points: list[tuple[float, float, float]],
    radius: float,
    mat: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    *,
    vertices: int = 6,
) -> None:
    """A run of rail or rigging drawn as straight beams between points."""
    for index, (start, end) in enumerate(zip(points, points[1:])):
        kit.add_beam(f"{prefix}_{index}", start, end, radius, mat, root, objects, vertices=vertices)


def lug_sail(
    name: str,
    head_fore: tuple[float, float],
    head_aft: tuple[float, float],
    foot_fore: tuple[float, float],
    foot_aft: tuple[float, float],
    belly: float,
    mat: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    *,
    cols: int = 8,
    rows: int = 6,
    tatter: float = 0.30,
) -> bpy.types.Object:
    """A four-cornered lug sail: top edge slung along the yard, foot torn.

    A true square sail hangs athwartships, which is correct for the period and
    wrong for this app — every camera that matters looks at the boat from
    abeam, and an athwartships sail is a sliver from there. A lug hangs in the
    fore-and-aft plane like the other two ships' mains, so it shows its whole
    face to the same cameras, while still being slung high enough off a yard to
    leave the deck, the wheel and the quarterdeck clear.

    The tear is cut into the sail's own bottom row rather than added as
    separate geometry: it has to be one mesh so the player's sail colour and
    the runtime's wind shader both reach it. The estate ship scallops its hem
    for the same reason, from the opposite end of the same idea.
    """
    vertices: list[tuple[float, float, float]] = []
    for row in range(rows + 1):
        v = row / rows
        for col in range(cols + 1):
            u = col / cols
            top_x = head_fore[0] + (head_aft[0] - head_fore[0]) * u
            top_y = head_fore[1] + (head_aft[1] - head_fore[1]) * u
            bottom_x = foot_fore[0] + (foot_aft[0] - foot_fore[0]) * u
            bottom_y = foot_fore[1] + (foot_aft[1] - foot_fore[1]) * u
            y = top_y + (bottom_y - top_y) * v
            if row == rows:
                # Deterministic ragged foot. Alternating deep and shallow bites
                # read as torn canvas; an even fringe reads as a curtain.
                bite = abs(math.sin(col * 2.27 + 0.6))
                y -= tatter * (0.10 + 0.90 * bite * bite)
            vertices.append(
                (
                    top_x + (bottom_x - top_x) * v,
                    y,
                    belly * math.sin(math.pi * u) * math.sin(math.pi * min(0.06 + v * 0.9, 1)),
                )
            )
    faces: list[tuple[int, ...]] = []
    for row in range(rows):
        for col in range(cols):
            a = row * (cols + 1) + col
            b = a + 1
            d = a + cols + 1
            faces += [(a, d, b), (b, d, d + 1)]
    return kit.mesh_object(name, vertices, faces, mat, root, objects)


def staysail(
    name: str,
    anchor_x: float,
    base_y: float,
    height: float,
    width: float,
    bulge: float,
    mat: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    *,
    rows: int = 8,
    cols: int = 6,
) -> bpy.types.Object:
    """The headsail, built from the same tapered sheet the other two ships use
    so all three flutter from one piece of runtime code."""
    vertices: list[tuple[float, float, float]] = []
    for row in range(rows + 1):
        v = row / rows
        row_width = width * (1 - v) * (1 + 0.12 * math.sin(math.pi * v))
        for col in range(cols + 1):
            u = col / cols
            vertices.append(
                (
                    anchor_x + u * row_width,
                    base_y + v * height,
                    bulge * math.sin(math.pi * u) * math.sin(math.pi * min(v * 0.92 + 0.05, 1)),
                )
            )
    faces: list[tuple[int, ...]] = []
    for row in range(rows):
        for col in range(cols):
            a = row * (cols + 1) + col
            b = a + 1
            d = a + cols + 1
            faces += [(a, d, b), (b, d, d + 1)]
    return kit.mesh_object(name, vertices, faces, mat, root, objects)


def lug_point(
    head_fore: tuple[float, float],
    head_aft: tuple[float, float],
    foot_fore: tuple[float, float],
    foot_aft: tuple[float, float],
    u: float,
    v: float,
) -> tuple[float, float]:
    """Any point on the lug sail, from the same bilinear map the cloth uses.
    Trim placed with this cannot drift off the sail when the corners move."""
    top_x = head_fore[0] + (head_aft[0] - head_fore[0]) * u
    top_y = head_fore[1] + (head_aft[1] - head_fore[1]) * u
    bottom_x = foot_fore[0] + (foot_aft[0] - foot_fore[0]) * u
    bottom_y = foot_fore[1] + (foot_aft[1] - foot_fore[1]) * u
    return (top_x + (bottom_x - top_x) * v, top_y + (bottom_y - top_y) * v)


def build() -> None:
    kit.reset_scene()
    mats = materials()

    root = kit.make_root(ASSET_ID, "Pirate_Ship", size_class="large")
    root["integration_status"] = "voyage_ship"
    root.rotation_euler.x = math.pi / 2
    objects: list[bpy.types.Object] = []

    anchor = bpy.data.objects.new("Navigator_Anchor", None)
    anchor.location = (0.74, 0.68, 0.18)
    anchor.parent = root
    bpy.context.collection.objects.link(anchor)

    # --- Hull -------------------------------------------------------------
    # Rust-red topsides over a tarred bottom, split at the turn of the bilge
    # exactly where the gold line runs.
    sampled_sections = hull_sections()
    ring_count = len(HULL_RING_FACTORS)
    hull_vertices = [
        (x, hull_ring_height(top, keel, beam), width * beam)
        for x, top, width, keel in sampled_sections
        for beam in HULL_RING_FACTORS
    ]
    topside_faces: list[tuple[int, ...]] = []
    bottom_faces: list[tuple[int, ...]] = []
    for index in range(len(sampled_sections) - 1):
        a = index * ring_count
        b = (index + 1) * ring_count
        for strip in range(ring_count - 1):
            face = (a + strip, b + strip, b + strip + 1, a + strip + 1)
            beam_midpoint = abs(
                (HULL_RING_FACTORS[strip] + HULL_RING_FACTORS[strip + 1]) * 0.5
            )
            (topside_faces if beam_midpoint >= 0.72 else bottom_faces).append(face)
    # End caps use the topside colour; the tar remains a continuous immersed
    # shell instead of becoming a dark polygon pasted over bow and transom.
    topside_faces += [
        tuple(range(ring_count - 1, -1, -1)),
        tuple(range((len(sampled_sections) - 1) * ring_count,
                    len(sampled_sections) * ring_count)),
    ]
    topsides = kit.mesh_object(
        "Hull_Topsides", hull_vertices, topside_faces, mats["hull"], root, objects
    )
    bottom = kit.mesh_object(
        "Hull_Bottom", hull_vertices, bottom_faces, mats["tar"], root, objects
    )
    for hull_part in (topsides, bottom):
        for polygon in hull_part.data.polygons:
            polygon.use_smooth = len(polygon.vertices) == 4

    # A rust band along the topsides and a thin gold line under it. Two lines
    # rather than one: a single stripe on a dark hull disappears at night.
    for side in (-1, 1):
        tag = "P" if side < 0 else "S"
        for label, fraction, radius, material in (
            ("Strake", 0.74, 0.030, mats["strake"]),
            ("Gilt", 0.56, 0.012, mats["gold"]),
        ):
            points = []
            for x in hull_samples():
                top, width, keel = profile(x)
                y = keel + (top - keel) * fraction
                turn = keel + 0.13
                t = min(1.0, max(0.0, (y - turn) / max(top - turn, 0.0001)))
                points.append((x, y, side * (width * (0.72 + 0.28 * t) + 0.008)))
            chain(f"Hull_{label}_{tag}", points, radius, material, root, objects, vertices=5)

    # --- Decks ------------------------------------------------------------
    deck_vertices: list[tuple[float, float, float]] = []
    for x, top, width, _ in SECTIONS[:-1]:
        deck_vertices += [(x, top + 0.015, -width * 0.90), (x, top + 0.015, width * 0.90)]
    deck_faces = [
        (index * 2, index * 2 + 1, (index + 1) * 2 + 1, (index + 1) * 2)
        for index in range(len(SECTIONS) - 2)
    ]
    kit.mesh_object("Main_Deck", deck_vertices, deck_faces, mats["deck"], root, objects)

    # Planking, laid fore-and-aft the way a deck actually runs.
    for index, z in enumerate((-0.34, -0.12, 0.12, 0.34)):
        kit.add_box(
            f"Deck_Plank_{index}",
            (-0.15, 0.535, z),
            (1.70, 0.012, 0.030),
            mats["deck_worn"],
            root,
            objects,
            bevel=0.004,
        )

    # Forecastle: the raised bow deck the navigator stands on, at the same
    # height the other two ships put their standing surface.
    kit.add_box("Forecastle_Plinth", (0.78, 0.575, 0), (0.54, 0.05, 0.70), mats["tar"], root, objects, bevel=0.012)
    kit.add_box("Forecastle", (0.78, 0.615, 0), (0.48, 0.10, 0.62), mats["deck"], root, objects, bevel=0.014)
    for index, z in enumerate((-0.18, 0.18)):
        kit.add_box(f"Forecastle_Plank_{index}", (0.78, 0.667, z), (0.44, 0.010, 0.030), mats["deck_worn"], root, objects, bevel=0.003)

    # Quarterdeck: the stern platform the wheel stands on. The square rig is
    # what makes room for it — a boomed mainsail would sweep straight through.
    kit.add_box("Quarterdeck_Face", (-0.62, 0.60, 0), (0.06, 0.20, 0.86), mats["tar"], root, objects, bevel=0.010)
    kit.add_box("Quarterdeck", (-0.90, 0.685, 0), (0.62, 0.09, 0.86), mats["deck"], root, objects, bevel=0.014)
    for index, z in enumerate((-0.24, 0.0, 0.24)):
        kit.add_box(f"Quarterdeck_Plank_{index}", (-0.90, 0.733, z), (0.58, 0.010, 0.028), mats["deck_worn"], root, objects, bevel=0.003)
    # Two steps up from the waist, so the deck reads as reachable.
    for index, (x, y) in enumerate(((-0.55, 0.575), (-0.62, 0.630))):
        kit.add_box(f"Quarterdeck_Step_{index}", (x, y, 0), (0.10, 0.045, 0.40), mats["deck_worn"], root, objects, bevel=0.008)

    # --- Bulwark ----------------------------------------------------------
    # A solid wall instead of the estate's open railing, broken by gun ports.
    # Built as one strip that follows the hull rather than a row of boxes: on
    # a curved sheer every box sits at its own beam, and the wall comes out as
    # a staircase of separate blocks instead of a side.
    bulwark_samples = [-1.14 + index * 0.13 for index in range(19)]
    port_segments = {3, 8, 13}
    wall_height, wall_thickness = 0.22, 0.05
    for side in (-1, 1):
        tag = "P" if side < 0 else "S"
        vertices: list[tuple[float, float, float]] = []
        for x in bulwark_samples:
            top, width = station(x)
            outer = side * (width - 0.008)
            inner = side * (width - 0.008 - wall_thickness)
            vertices += [
                (x, top, outer),
                (x, top + wall_height, outer),
                (x, top + wall_height, inner),
                (x, top, inner),
            ]
        faces: list[tuple[int, ...]] = []
        for index in range(len(bulwark_samples) - 1):
            if index in port_segments:
                continue
            a, b = index * 4, (index + 1) * 4
            # Outer skin, capping face, inner skin.
            faces += [
                (a + 0, b + 0, b + 1, a + 1),
                (a + 1, b + 1, b + 2, a + 2),
                (a + 2, b + 2, b + 3, a + 3),
            ]
            # Close the run wherever it meets a gap, so a port is a hole in a
            # wall with thickness rather than a slice through paper.
            if index - 1 in port_segments:
                faces.append((a + 0, a + 1, a + 2, a + 3))
            if index + 1 in port_segments:
                faces.append((b + 0, b + 1, b + 2, b + 3))
        kit.mesh_object(f"Bulwark_{tag}", vertices, faces, mats["bulwark"], root, objects)

        # A dark panel set behind each opening. Without it the port is a
        # window onto the sea and stops reading as a gun port at all.
        for index in sorted(port_segments):
            x = (bulwark_samples[index] + bulwark_samples[index + 1]) / 2
            top, width = station(x)
            kit.add_box(
                f"Gun_Port_{tag}_{index}",
                (x, top + wall_height * 0.52, side * (width - 0.075)),
                (0.115, wall_height * 0.66, 0.035),
                mats["tar"],
                root,
                objects,
                bevel=0.006,
            )

        # Cap rail along the top of the wall, worn paler than the wall itself.
        points = []
        for x in hull_samples():
            if x < -1.16 or x > 1.16:
                continue
            top, width = station(x)
            points.append((x, top + wall_height + 0.020, side * (width - 0.030)))
        chain(f"Cap_Rail_{tag}", points, 0.030, mats["deck_worn"], root, objects)

    # --- Rig --------------------------------------------------------------
    mast_foot, mast_head = 0.50, 2.55
    kit.add_beam("Mast", (0.06, mast_foot, 0), (0.06, mast_head, 0), 0.040, mats["tar"], root, objects, vertices=8, end_radius=0.028)
    for y in (0.66, 1.32, 2.02):
        kit.add_torus(f"Mast_Hoop_{y}", (0.06, y, 0), 0.052, 0.011, mats["iron"], root, objects, major_segments=8, minor_segments=4, rotation=upright())

    # The yard peaks aft, the way a lug is slung. Its fore end drops low over
    # the waist and its aft end rides high over the quarterdeck — that diagonal
    # is the ship's whole silhouette from abeam.
    yard_fore = (0.52, 1.66)
    yard_aft = (-1.02, 2.26)
    kit.add_beam("Yard", (yard_fore[0], yard_fore[1], 0), (yard_aft[0], yard_aft[1], 0), 0.026, mats["tar"], root, objects, vertices=7, end_radius=0.016)
    kit.add_torus("Yard_Sling", (0.06, 1.84, 0), 0.062, 0.013, mats["rope"], root, objects, major_segments=8, minor_segments=4)
    lug_head_fore, lug_head_aft = (0.50, 1.68), (-1.00, 2.24)
    lug_foot_fore, lug_foot_aft = (0.42, 1.18), (-0.98, 1.36)
    lug_sail(
        "Main_Sail",
        head_fore=lug_head_fore,
        head_aft=lug_head_aft,
        foot_fore=lug_foot_fore,
        foot_aft=lug_foot_aft,
        belly=0.14,
        mat=mats["main_sail"],
        root=root,
        objects=objects,
    )
    # Bolt rope along the head and the foot. A sail this size is a blank
    # panel without an edge on it, and the rope is what a torn sail is still
    # holding together by.
    for label, (start, end) in (
        ("Head", (lug_head_fore, lug_head_aft)),
        ("Foot", (lug_foot_fore, lug_foot_aft)),
    ):
        kit.add_beam(
            f"Bolt_Rope_{label}",
            (start[0], start[1], 0.012),
            (end[0], end[1], 0.012),
            0.010,
            mats["rope"],
            root,
            objects,
            vertices=4,
        )

    # Two squares of mismatched canvas. They keep their own colour whatever
    # the player picks for the sail, which is what makes them read as repairs
    # rather than as decoration.
    for index, (u, v, size, spin) in enumerate(((0.30, 0.42, 0.20, 0.18), (0.62, 0.66, 0.15, -0.24))):
        px, py = lug_point(lug_head_fore, lug_head_aft, lug_foot_fore, lug_foot_aft, u, v)
        depth = 0.14 * math.sin(math.pi * u) * math.sin(math.pi * min(0.06 + v * 0.9, 1))
        kit.add_box(
            f"Sail_Patch_{index}",
            (px, py, depth + 0.010),
            (size, size * 0.86, 0.006),
            mats["patch"],
            root,
            objects,
            rotation=(0, 0, spin),
            bevel=0.004,
        )

    # Reef points: the short ropes the sail is gathered with, left hanging.
    for index in range(5):
        u = 0.16 + index * 0.17
        x = 0.46 - u * 1.46
        y = 1.55 + u * 0.16
        kit.add_beam(f"Reef_Point_{index}", (x, y, 0.10), (x - 0.01, y - 0.15, 0.10), 0.006, mats["rope"], root, objects, vertices=4)

    kit.add_beam("Bowsprit", (1.02, 0.72, 0), (1.78, 0.98, 0), 0.026, mats["tar"], root, objects)
    kit.add_beam("Forestay", (0.06, mast_head - 0.10, 0), (1.74, 0.97, 0), 0.009, mats["rope"], root, objects, vertices=5)
    kit.add_beam("Backstay", (0.06, mast_head - 0.10, 0), (-1.14, 0.66, -0.22), 0.009, mats["rope"], root, objects, vertices=5)
    staysail("Jib", 0.66, 0.98, 0.95, 1.02, 0.10, mats["jib"], root, objects)

    # Ratlines: shrouds from the rail to the top, with rungs between them.
    # This is the detail that says "someone climbs this ship" — the estate's
    # rigging is wire nobody is meant to touch.
    for side in (-1, 1):
        tag = "P" if side < 0 else "S"
        top, width = station(0.10)
        foot_z = side * (width - 0.06)
        pairs = ((0.30, 0.10), (-0.24, 0.10))
        anchors = []
        for label, (foot_x, _) in zip(("Fwd", "Aft"), pairs):
            start = (foot_x, top + 0.24, foot_z)
            end = (0.06, 2.08, side * 0.10)
            kit.add_beam(f"Shroud_{tag}_{label}", start, end, 0.010, mats["rope"], root, objects, vertices=5)
            anchors.append((start, end))
        for step in range(1, 6):
            t = step / 6
            points = []
            for start, end in anchors:
                points.append(tuple(a + (b - a) * t for a, b in zip(start, end)))
            kit.add_beam(f"Ratline_{tag}_{step}", points[0], points[1], 0.006, mats["rope"], root, objects, vertices=4)

    # Crow's nest, above the yard so the sail passes clear of it.
    nest_y = 2.14
    kit.add_cylinder("Crows_Nest_Floor", (0.06, nest_y, 0), 0.17, 0.035, mats["deck"], root, objects, vertices=10, rotation=upright())
    for index in range(10):
        angle = math.tau * index / 10
        kit.add_beam(
            f"Crows_Nest_Stave_{index}",
            (0.06 + math.cos(angle) * 0.155, nest_y, math.sin(angle) * 0.155),
            (0.06 + math.cos(angle) * 0.165, nest_y + 0.15, math.sin(angle) * 0.165),
            0.012,
            mats["tar"],
            root,
            objects,
            vertices=4,
        )
    kit.add_torus("Crows_Nest_Hoop", (0.06, nest_y + 0.14, 0), 0.168, 0.012, mats["iron"], root, objects, major_segments=12, minor_segments=4, rotation=upright())

    # --- Colours at the masthead -------------------------------------------
    # A black flag with a skull. Three plates and two bones is all the detail
    # that survives at voyage distance, and it is all the flag needs.
    flag_vertices = [
        (0.06, mast_head, 0.004),
        (0.06, mast_head - 0.26, 0.004),
        (-0.46, mast_head - 0.30, 0.02),
        (-0.46, mast_head - 0.06, 0.02),
    ]
    kit.mesh_object("Black_Flag", flag_vertices, [(0, 1, 2, 3)], mats["flag"], root, objects)
    kit.add_ico("Flag_Skull", (-0.20, mast_head - 0.15, 0.016), (0.052, 0.050, 0.008), mats["bone"], root, objects, subdivisions=1, irregularity=0.04)
    kit.add_box("Flag_Jaw", (-0.20, mast_head - 0.205, 0.016), (0.055, 0.022, 0.010), mats["bone"], root, objects, bevel=0.003)
    for index, spin in enumerate((0.6, -0.6)):
        kit.add_box(f"Flag_Bone_{index}", (-0.20, mast_head - 0.17, 0.020), (0.155, 0.018, 0.008), mats["bone"], root, objects, rotation=(0, 0, spin), bevel=0.003)

    # --- Stern -------------------------------------------------------------
    kit.add_box("Transom_Panel", (-1.22, 0.40, 0), (0.05, 0.30, 0.44), mats["hull"], root, objects, bevel=0.012)
    kit.add_box("Transom_Band", (-1.24, 0.545, 0), (0.03, 0.045, 0.46), mats["gold"], root, objects, bevel=0.006)
    for index, z in enumerate((-0.13, 0.13)):
        kit.add_cylinder(f"Transom_Window_{index}", (-1.25, 0.44, z), 0.055, 0.02, mats["glow"], root, objects, vertices=8, rotation=(0, math.radians(90), 0))
    kit.add_box("Rudder", (-1.20, 0.02, 0), (0.20, 0.46, 0.045), mats["tar"], root, objects, rotation=(0, 0, math.radians(-8)), bevel=0.016)

    # The stern lantern: the biggest single light on any of the three ships.
    kit.add_beam("Stern_Lantern_Post", (-1.16, 0.73, 0), (-1.20, 0.92, 0), 0.016, mats["iron"], root, objects)
    kit.add_cylinder("Stern_Lantern_Base", (-1.20, 0.935, 0), 0.058, 0.035, mats["iron"], root, objects, vertices=6, rotation=upright())
    kit.add_cone("Stern_Lantern_Glass", (-1.20, 1.015, 0), 0.062, 0.046, 0.13, mats["glass"], root, objects, vertices=6, rotation=upright())
    kit.add_ico("Stern_Lantern_Glow", (-1.20, 1.010, 0), (0.034, 0.034, 0.046), mats["glow"], root, objects, irregularity=0.04)
    kit.add_cone("Stern_Lantern_Roof", (-1.20, 1.105, 0), 0.080, 0.010, 0.07, mats["iron"], root, objects, vertices=6, rotation=upright())
    kit.add_ico("Stern_Lantern_Finial", (-1.20, 1.155, 0), (0.018, 0.018, 0.022), mats["iron"], root, objects, irregularity=0.05)

    # Ship's wheel, standing in its own plane so it is a wheel from the side.
    wheel_x, wheel_y = -0.78, 0.90
    kit.add_box("Wheel_Pedestal", (wheel_x, 0.78, 0), (0.12, 0.16, 0.20), mats["tar"], root, objects, bevel=0.012)
    kit.add_torus("Wheel_Rim", (wheel_x, wheel_y, 0), 0.135, 0.016, mats["deck_worn"], root, objects, major_segments=12, minor_segments=4)
    kit.add_cylinder("Wheel_Hub", (wheel_x, wheel_y, 0), 0.036, 0.06, mats["iron"], root, objects, vertices=8, rotation=(0, math.radians(90), 0))
    for index in range(6):
        angle = math.tau * index / 6 + 0.26
        kit.add_beam(
            f"Wheel_Spoke_{index}",
            (wheel_x, wheel_y, 0),
            (wheel_x + math.cos(angle) * 0.185, wheel_y + math.sin(angle) * 0.185, 0),
            0.011,
            mats["deck_worn"],
            root,
            objects,
            vertices=4,
        )

    # --- Cargo -------------------------------------------------------------
    # The chest, barrels and coiled rope are the whole reason the deck was
    # cleared. A pirate ship with an empty waist is a hull, not a story.
    chest_x, chest_z = -0.30, -0.24
    kit.add_box("Chest_Body", (chest_x, 0.615, chest_z), (0.30, 0.17, 0.22), mats["tar"], root, objects, bevel=0.012)
    kit.add_box("Chest_Lid", (chest_x, 0.712, chest_z), (0.31, 0.06, 0.23), mats["hull"], root, objects, rotation=(0, 0, math.radians(-7)), bevel=0.014)
    for index, offset in enumerate((-0.09, 0.09)):
        kit.add_box(f"Chest_Band_{index}", (chest_x + offset, 0.655, chest_z), (0.030, 0.26, 0.235), mats["gold"], root, objects, bevel=0.005)
    kit.add_ico("Chest_Lock", (chest_x + 0.155, 0.665, chest_z), (0.016, 0.032, 0.030), mats["gold"], root, objects, irregularity=0.05)

    for index, (x, z, radius, height) in enumerate((
        (0.42, 0.30, 0.105, 0.24),
        (0.30, 0.36, 0.095, 0.22),
        (-0.02, -0.36, 0.100, 0.23),
    )):
        top, _ = station(x)
        base = top + 0.015
        kit.add_cylinder(f"Barrel_{index}", (x, base + height / 2, z), radius, height, mats["hull"], root, objects, vertices=10, rotation=upright())
        for band in (0.28, 0.72):
            kit.add_torus(
                f"Barrel_{index}_Hoop_{band}",
                (x, base + height * band, z),
                radius * 1.02,
                0.010,
                mats["iron"],
                root,
                objects,
                major_segments=10,
                minor_segments=4,
                rotation=upright(),
            )

    for index, (x, z) in enumerate(((-0.46, 0.30), (0.52, -0.30))):
        top, _ = station(x)
        for ring, radius in enumerate((0.105, 0.078)):
            kit.add_torus(
                f"Rope_Coil_{index}_{ring}",
                (x, top + 0.030 + ring * 0.024, z),
                radius,
                0.016,
                mats["rope"],
                root,
                objects,
                major_segments=10,
                minor_segments=4,
                rotation=upright(),
            )

    # Anchor, catted against the bow where it hangs on a working ship.
    top, width = station(1.02)
    anchor_z = -(width + 0.02)
    kit.add_beam("Anchor_Shank", (1.02, top - 0.02, anchor_z), (0.86, top - 0.40, anchor_z), 0.022, mats["iron"], root, objects, vertices=6)
    kit.add_beam("Anchor_Stock", (1.06, top - 0.08, anchor_z), (0.94, top - 0.14, anchor_z - 0.02), 0.014, mats["iron"], root, objects, vertices=5)
    for index, spin in enumerate((0.9, -0.35)):
        kit.add_beam(
            f"Anchor_Arm_{index}",
            (0.86, top - 0.38, anchor_z),
            (0.86 + math.cos(spin) * 0.16, top - 0.38 - math.sin(abs(spin)) * 0.10, anchor_z + (0.13 if index else -0.13)),
            0.016,
            mats["iron"],
            root,
            objects,
            vertices=5,
        )
    kit.add_torus("Anchor_Ring", (1.04, top - 0.01, anchor_z), 0.038, 0.010, mats["iron"], root, objects, major_segments=8, minor_segments=4)

    # --- Export -------------------------------------------------------------
    # Bake each part's own rotation into its mesh before the exporter joins by
    # material: a joined group inherits the first member's transform, and a
    # tilted beam's frame inflates the ship's bounding box. The Home Island
    # moors the boat by measuring that box.
    bpy.ops.object.select_all(action="DESELECT")
    meshes = [obj for obj in objects if obj.type == "MESH"]
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    kit.export_asset(ASSET_ID, root, objects, sockets=(anchor,))
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(kit.READY_DIR / f"{ASSET_ID}.usdz", RUNTIME_DIR / f"{ASSET_ID}.usdz")
    print(f"RUNTIME={RUNTIME_DIR / f'{ASSET_ID}.usdz'}")


if os.environ.get("KEELMIRA_ASSET_IDS") != "__pirate_ship_helpers_only__":
    build()
