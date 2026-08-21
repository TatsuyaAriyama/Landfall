"""Build the Garden Estate ship — the second hull a player can sail.

`build_landfall_boat.py` builds the boat everyone starts with: a warm wooden
fishing sloop. This one is the same size and rig, rebuilt in the estate's
vocabulary — an iron hull under a granite deck, spear-picket railings, urns
either side of the mast, roses over the rail and two lamps burning at the
stern quarters. The colours come from `build_garden_ironwork.ironwork_materials`
so the ship and the twelve garden props agree on one black and one granite.

Two rules hold this file to the runtime:

* Only the two sail meshes carry contract material names (`LF_BoatMainSail`,
  `LF_BoatJib`). Those are the surfaces the player recolours, and the only ones
  `VoyageSceneKit.makeBoatModel` rewrites. Everything else keeps a garden name
  so the estate's own iron and granite survive into the game.
* `Navigator_Anchor` sits where the starting boat's does, at (0.74, 0.68, 0.18),
  so the navigator stands on the bow terrace at exactly the same height and the
  deck cameras need no per-ship tuning.

Coordinates are authored X=forward, Y=up, Z=beam — Three.js/SceneKit's frame,
not Blender's. The root carries the 90° rotation that makes that editable.

    blender --background --python Tools/Blender/build_garden_estate_ship.py
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
os.environ["KEELMIRA_ASSET_IDS"] = "__garden_estate_ship_helpers_only__"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_home_island_asset_set_02 as kit  # noqa: E402
import build_garden_ironwork as ironwork  # noqa: E402

os.environ["KEELMIRA_ASSET_IDS"] = _requested


ASSET_ID = "garden_estate_ship"
ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "Landfall/Resources"

UP = math.radians(-90)  # Stand a primitive's local Z axis up in authored space.


def upright(spin: float = 0.0) -> tuple[float, float, float]:
    """Rotation that points a cylinder or cone at the authored sky, with an
    optional spin about that new axis."""
    return (UP, spin, 0.0)


def materials() -> dict[str, bpy.types.Material]:
    """The estate palette, plus the cloth and planting this hull needs."""
    mats = ironwork.ironwork_materials()
    mats.update(
        {
            # The two names the runtime recolours. Sails are seen from both
            # sides, so they cannot be backface culled like the solid props.
            #
            # Roughness 0.82 rather than the starting boat's 0.96: the estate's
            # cloth is a close-woven linen that catches the moon along its
            # curve, closer to the conservatory awning than to working canvas.
            "main_sail": kit.material("LF_BoatMainSail", "#EADEBD", 0.82, double_sided=True),
            "jib": kit.material("LF_BoatJib", "#EADEBD", 0.82, double_sided=True),
            "brass": kit.material("LF_GardenBrass", "#A8873F", 0.52, metallic=0.55),
            "leaf": kit.material("LF_GardenLeaf", "#356A4B", 0.85),
            "leaf_deep": kit.material("LF_GardenLeafDeep", "#254B39", 0.88),
            "bloom": kit.material("LF_GardenBloom", "#C4636A", 0.74),
            "bloom_light": kit.material("LF_GardenBloomLight", "#DC8E93", 0.72),
        }
    )
    return mats


# Stations run stern (-X) to the raised, narrow bow (+X): x, sheer, half beam,
# keel. The sheer is deliberately straighter than the starting boat's — a garden
# launch is a formal shape, and the rise is saved for the last two stations.
SECTIONS = [
    (-1.16, 0.50, 0.25, 0.02),
    (-0.88, 0.50, 0.41, -0.16),
    (-0.42, 0.51, 0.52, -0.30),
    (0.08, 0.53, 0.55, -0.32),
    (0.58, 0.56, 0.50, -0.26),
    (1.02, 0.62, 0.35, -0.06),
    (1.32, 0.73, 0.16, 0.22),
    (1.46, 0.86, 0.03, 0.52),
]


def profile(x: float) -> tuple[float, float, float]:
    """Sheer, half beam and keel anywhere along the hull, so railings and
    fittings sit on the hull rather than near it."""
    x = max(SECTIONS[0][0], min(SECTIONS[-1][0], x))
    for start, end in zip(SECTIONS, SECTIONS[1:]):
        if start[0] <= x <= end[0]:
            t = (x - start[0]) / (end[0] - start[0])
            return tuple(a + (b - a) * t for a, b in zip(start[1:], end[1:]))
    return SECTIONS[-1][1:]


def station(x: float) -> tuple[float, float]:
    top, width, _ = profile(x)
    return top, width


def hull_samples() -> list[float]:
    """Every station plus the midpoints between them. A run of beams drawn
    station to station shows its facets on a hull this size; halving the step
    is enough to read as one curve without doubling the ship's triangles."""
    samples: list[float] = []
    for start, end in zip(SECTIONS, SECTIONS[1:]):
        samples += [start[0], (start[0] + end[0]) / 2]
    samples.append(SECTIONS[-1][0])
    return samples


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
    """A run of rail or rigging drawn as straight beams between points. Blender
    curves do not survive the USD export cleanly; the estate set draws its
    arches this way too."""
    for index, (start, end) in enumerate(zip(points, points[1:])):
        kit.add_beam(f"{prefix}_{index}", start, end, radius, mat, root, objects, vertices=vertices)


def sail_mesh(
    name: str,
    anchor_x: float,
    base_y: float,
    height: float,
    width: float,
    direction: float,
    bulge: float,
    mat: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    rows: int = 9,
    cols: int = 7,
) -> bpy.types.Object:
    """The same tapered, bellied sheet the starting boat sets. The runtime's
    wind shader reads the mesh's own bounding box, so the two ships flutter
    from one piece of code."""
    vertices: list[tuple[float, float, float]] = []
    for row in range(rows + 1):
        v = row / rows
        row_width = width * (1 - v) * (1 + 0.12 * math.sin(math.pi * v))
        for col in range(cols + 1):
            u = col / cols
            vertices.append(
                (
                    anchor_x + direction * u * row_width,
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


def leech_points(
    anchor_x: float,
    base_y: float,
    height: float,
    width: float,
    direction: float,
    steps: int,
) -> list[tuple[float, float]]:
    """The sail's free edge, sampled from the same formula the sheet is built
    from, so a hem hung off it never floats away from the cloth."""
    points: list[tuple[float, float]] = []
    for step in range(steps + 1):
        v = step / steps
        row_width = width * (1 - v) * (1 + 0.12 * math.sin(math.pi * v))
        points.append((anchor_x + direction * row_width, base_y + v * height))
    return points


def scallop_hem(
    name: str,
    points: list[tuple[float, float]],
    direction: float,
    mat: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    *,
    arc: int = 5,
) -> bpy.types.Object:
    """A scalloped edge on the leech — the estate's awning hem, in the sail's
    own material so it still takes the colour the player picked. This is what
    tells the eye the cloth is drawing-room linen and not a working canvas."""
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        span_x, span_y = x1 - x0, y1 - y0
        length = math.hypot(span_x, span_y)
        if length < 1e-6:
            continue
        along_x, along_y = span_x / length, span_y / length
        # Away from the sail: the interior lies on the side the sheet was
        # swept towards, so the outward normal flips with `direction`.
        out_x, out_y = along_y * direction, -along_x * direction
        centre_x, centre_y = (x0 + x1) / 2, (y0 + y1) / 2
        radius = length / 2
        hub = len(vertices)
        vertices.append((centre_x, centre_y, 0.0))
        for index in range(arc + 1):
            angle = math.pi * index / arc
            vertices.append(
                (
                    centre_x + along_x * math.cos(angle) * radius + out_x * math.sin(angle) * radius,
                    centre_y + along_y * math.cos(angle) * radius + out_y * math.sin(angle) * radius,
                    0.0,
                )
            )
        faces += [(hub, hub + 1 + index, hub + 2 + index) for index in range(arc)]
    return kit.mesh_object(name, vertices, faces, mat, root, objects)


def build() -> None:
    kit.reset_scene()
    mats = materials()

    root = kit.make_root(ASSET_ID, "Garden_Estate_Ship", size_class="large")
    root["integration_status"] = "voyage_ship"
    # Author in the runtime's frame and let the root hold the conversion.
    root.rotation_euler.x = math.pi / 2
    objects: list[bpy.types.Object] = []

    # Where the navigator stands. Matching the starting boat's anchor is what
    # lets one camera rig serve both hulls.
    anchor = bpy.data.objects.new("Navigator_Anchor", None)
    anchor.location = (0.74, 0.68, 0.18)
    anchor.parent = root
    bpy.context.collection.objects.link(anchor)

    # --- Hull -------------------------------------------------------------
    # Two hulls sharing one set of stations: pale granite topsides above the
    # gilt line, dark iron below it. One dark hull disappears into the night
    # sea at voyage distance; the estate's own wall-and-railing contrast is
    # what keeps this ship legible when it is 80 points tall.
    hull_vertices: list[tuple[float, float, float]] = []
    for x, top, width, keel in SECTIONS:
        hull_vertices.extend(
            [
                (x, top, -width),
                (x, keel + 0.13, -width * 0.72),
                (x, keel, 0),
                (x, keel + 0.13, width * 0.72),
                (x, top, width),
            ]
        )
    topside_faces: list[tuple[int, ...]] = []
    bottom_faces: list[tuple[int, ...]] = []
    for index in range(len(SECTIONS) - 1):
        a = index * 5
        b = (index + 1) * 5
        for strip in range(4):
            face = (a + strip, b + strip, b + strip + 1, a + strip + 1)
            # Strips 0 and 3 are the topsides; 1 and 2 are the turn of the bilge.
            (topside_faces if strip in (0, 3) else bottom_faces).append(face)
    topside_faces.append((0, 1, 2, 3, 4))
    bottom_faces.append(tuple(range((len(SECTIONS) - 1) * 5, len(SECTIONS) * 5)))
    kit.mesh_object("Hull_Topsides", hull_vertices, topside_faces, mats["stone"], root, objects)
    kit.mesh_object("Hull_Bottom", hull_vertices, bottom_faces, mats["iron_light"], root, objects)

    # A gilt line at the waterline. The estate gilds its gates; this is the
    # same restraint applied to a hull, and it is the only warm colour below
    # the deck.
    for side in (-1, 1):
        points = []
        for x in hull_samples():
            top, width, keel = profile(x)
            # Ride the planking, not a cylinder around it: the topside strip
            # tucks in from `width` at the sheer to `width * 0.72` at the turn
            # of the bilge, and a line drawn at full beam floats off the stern
            # where the hull narrows fastest.
            y = keel + (top - keel) * 0.52
            turn = keel + 0.13
            t = min(1.0, max(0.0, (y - turn) / max(top - turn, 0.0001)))
            points.append((x, y, side * (width * (0.72 + 0.28 * t) + 0.008)))
        chain(
            f"Hull_Gilt_{'P' if side < 0 else 'S'}",
            points,
            0.013,
            mats["brass"],
            root,
            objects,
            vertices=5,
        )

    # --- Deck -------------------------------------------------------------
    deck_vertices: list[tuple[float, float, float]] = []
    for x, top, width, _ in SECTIONS[:-1]:
        deck_vertices += [(x, top + 0.015, -width * 0.90), (x, top + 0.015, width * 0.90)]
    # Wound to face the sky. The kit's materials are backface culled, so a
    # deck laid the other way round is simply not there from above.
    deck_faces = [
        (index * 2, index * 2 + 1, (index + 1) * 2 + 1, (index + 1) * 2)
        for index in range(len(SECTIONS) - 2)
    ]
    kit.mesh_object("Deck_Flags", deck_vertices, deck_faces, mats["stone_light"], root, objects)

    # Paler joints across the deck. Three are enough to read as flagstones from
    # the voyage camera; more turns the deck into a grating.
    for x in (-0.74, -0.28, 0.22):
        top, width = station(x)
        kit.add_box(
            f"Deck_Joint_{x}",
            (x, top + 0.020, 0),
            (0.035, 0.014, width * 1.72),
            mats["stone_deep"],
            root,
            objects,
            bevel=0.004,
        )

    # The bow terrace the navigator stands on: a granite slab on a wider plinth.
    kit.add_box("Bow_Terrace_Plinth", (0.76, 0.575, 0), (0.50, 0.05, 0.68), mats["stone"], root, objects, bevel=0.012)
    kit.add_box("Bow_Terrace", (0.76, 0.615, 0), (0.44, 0.10, 0.60), mats["stone_light"], root, objects, bevel=0.014)

    # Granite coping caps the sheer, the way the estate's walls are capped.
    for side in (-1, 1):
        points = []
        for x in hull_samples():
            top, width = station(x)
            points.append((x, top + 0.022, side * width))
        chain(
            f"Coping_{'P' if side < 0 else 'S'}",
            points,
            0.034,
            mats["stone_light"],
            root,
            objects,
        )

    # --- Railings ---------------------------------------------------------
    # The fence, bent round a hull: square bars under four-sided spear heads,
    # a thin iron top rail tying them together, and a ring in every gap. The
    # pitch is the fence's, scaled to the hull — widen it and the rings stop
    # being tangent to their neighbours, which is when a railing starts to
    # read as a fire escape.
    picket_pitch = 0.17
    picket_stations = [-1.02 + index * picket_pitch for index in range(13)]
    for side in (-1, 1):
        tag = "P" if side < 0 else "S"
        tops: list[tuple[float, float, float]] = []
        for index, x in enumerate(picket_stations):
            top, width = station(x)
            z = side * (width - 0.012)
            base = top + 0.052
            head_base = base + 0.19
            kit.add_box(
                f"Picket_{tag}_{index}",
                (x, base + 0.095, z),
                (0.024, 0.19, 0.024),
                mats["iron"],
                root,
                objects,
                bevel=0.004,
            )
            kit.add_cone(
                f"Picket_{tag}_{index}_Head",
                (x, head_base + 0.028, z),
                0.026,
                0.0,
                0.056,
                mats["iron"],
                root,
                objects,
                vertices=4,
                rotation=upright(math.radians(45)),
            )
            tops.append((x, head_base - 0.018, z))
        chain(f"Top_Rail_{tag}", tops, 0.014, mats["iron"], root, objects, vertices=5)

        # The rings sit in the railing's own plane, which is the plane a torus
        # already lies in here: no rotation, or they lie flat like quoits.
        for index, (x0, x1) in enumerate(zip(picket_stations, picket_stations[1:])):
            x = (x0 + x1) / 2
            top, width = station(x)
            kit.add_torus(
                f"Rail_Ring_{tag}_{index}",
                (x, top + 0.147, side * (width - 0.012)),
                0.072,
                0.010,
                mats["iron_light"],
                root,
                objects,
                major_segments=8,
                minor_segments=4,
            )

        # Roses spilling over the rail, four to a side. The estate's planting
        # is what keeps an iron ship from reading as a gunboat.
        for index, x in enumerate((-0.62, -0.20, 0.22, 0.60)):
            top, width = station(x)
            z = side * (width + 0.03)
            kit.add_ico(
                f"Rail_Rose_Leaves_{tag}_{index}",
                (x, top + 0.11, z),
                (0.085, 0.075, 0.055),
                mats["leaf"] if index % 2 == 0 else mats["leaf_deep"],
                root,
                objects,
                irregularity=0.16,
            )
            kit.add_ico(
                f"Rail_Rose_Bloom_{tag}_{index}",
                (x - 0.03, top + 0.15, z + side * 0.02),
                (0.034, 0.034, 0.030),
                mats["bloom"] if index % 2 == 0 else mats["bloom_light"],
                root,
                objects,
                irregularity=0.10,
            )

    # --- Cockpit ----------------------------------------------------------
    # Two granite thwarts on iron scrolls: the estate's bench, cut to fit.
    for index, x in enumerate((-0.50, -0.86)):
        top, width = station(x)
        kit.add_box(
            f"Thwart_{index}",
            (x, 0.618, 0),
            (0.15, 0.045, width * 1.28),
            mats["stone"],
            root,
            objects,
            bevel=0.012,
        )
        for side in (-1, 1):
            tag = "P" if side < 0 else "S"
            z = side * width * 0.46
            kit.add_beam(
                f"Thwart_{index}_Leg_{tag}",
                (x, top + 0.015, z),
                (x, 0.600, z),
                0.014,
                mats["iron"],
                root,
                objects,
                vertices=5,
            )
            # The scroll eye under the seat: the garden bench's own detail.
            kit.add_torus(
                f"Thwart_{index}_Scroll_{tag}",
                (x, 0.578, z),
                0.036,
                0.009,
                mats["iron_light"],
                root,
                objects,
                major_segments=8,
                minor_segments=4,
            )

    kit.add_beam("Tiller", (-1.08, 0.66, 0), (-0.62, 0.70, 0.07), 0.020, mats["iron"], root, objects)
    kit.add_ico("Tiller_Knob", (-0.60, 0.705, 0.075), (0.036, 0.036, 0.036), mats["brass"], root, objects, irregularity=0.05)
    kit.add_box("Rudder", (-1.12, 0.06, 0), (0.19, 0.42, 0.042), mats["iron_light"], root, objects, rotation=(0, 0, math.radians(-8)), bevel=0.016)

    # A granite transom plate under a scrolled iron crest — the stern is the
    # face the following islands see.
    kit.add_box("Transom_Plate", (-1.18, 0.350, 0), (0.04, 0.22, 0.28), mats["stone_light"], root, objects, bevel=0.012)
    # The house plate. Every gate on the estate carries one; so does the stern.
    kit.add_cylinder("Transom_Plaque", (-1.21, 0.350, 0), 0.062, 0.018, mats["brass"], root, objects, vertices=10, rotation=(0, math.radians(90), 0))
    # A crest of three rings across the transom, standing in the transom's own
    # plane so it is the stern — not the side — that carries the ironwork.
    for index, (z, radius) in enumerate(((0.0, 0.060), (-0.125, 0.042), (0.125, 0.042))):
        kit.add_torus(
            f"Transom_Crest_{index}",
            (-1.20, 0.545, z),
            radius,
            0.011,
            mats["iron"],
            root,
            objects,
            major_segments=10,
            minor_segments=4,
            rotation=(0, math.radians(90), 0),
        )

    # --- Lamps ------------------------------------------------------------
    # The street lamp, halved, one on each quarter. Same flame as the island's
    # lantern post, so a lit ship and a lit shore agree.
    for side in (-1, 1):
        tag = "P" if side < 0 else "S"
        z = side * 0.27
        kit.add_cylinder(f"Lamp_{tag}_Foot", (-1.00, 0.55, z), 0.062, 0.06, mats["iron"], root, objects, vertices=8, rotation=upright())
        kit.add_beam(f"Lamp_{tag}_Post", (-1.00, 0.56, z), (-1.00, 1.08, z), 0.017, mats["iron"], root, objects)
        kit.add_torus(f"Lamp_{tag}_Scroll", (-1.00, 0.86, z), 0.055, 0.010, mats["iron"], root, objects, major_segments=10, minor_segments=4)
        kit.add_cylinder(f"Lamp_{tag}_Base", (-1.00, 1.09, z), 0.075, 0.045, mats["iron"], root, objects, vertices=8, rotation=upright())
        kit.add_cone(f"Lamp_{tag}_Glass", (-1.00, 1.19, z), 0.072, 0.055, 0.16, mats["glass"], root, objects, vertices=8, rotation=upright())
        kit.add_ico(f"Lamp_{tag}_Glow", (-1.00, 1.18, z), (0.042, 0.042, 0.055), mats["glow"], root, objects, irregularity=0.04)
        kit.add_cone(f"Lamp_{tag}_Roof", (-1.00, 1.30, z), 0.10, 0.012, 0.09, mats["iron"], root, objects, vertices=8, rotation=upright())
        kit.add_ico(f"Lamp_{tag}_Finial", (-1.00, 1.37, z), (0.022, 0.022, 0.028), mats["iron"], root, objects, irregularity=0.05)

    # --- Planting ---------------------------------------------------------
    # Urns either side of the mast, clipped into cones. They sit outboard of
    # the sail's belly so nothing clips when the wind shader pushes it.
    for side in (-1, 1):
        tag = "P" if side < 0 else "S"
        z = side * 0.38
        kit.add_cylinder(f"Urn_{tag}_Foot", (0.02, 0.555, z), 0.048, 0.045, mats["stone"], root, objects, vertices=8, rotation=upright())
        kit.add_cone(f"Urn_{tag}_Body", (0.02, 0.635, z), 0.052, 0.085, 0.13, mats["stone_light"], root, objects, vertices=10, rotation=upright())
        kit.add_cylinder(f"Urn_{tag}_Lip", (0.02, 0.702, z), 0.090, 0.022, mats["stone_light"], root, objects, vertices=10, rotation=upright())
        kit.add_cone(f"Urn_{tag}_Topiary", (0.02, 0.795, z), 0.082, 0.0, 0.18, mats["leaf_deep"], root, objects, vertices=8, rotation=upright())
        kit.add_ico(f"Urn_{tag}_Bloom", (0.02, 0.745, z + side * 0.06), (0.028, 0.028, 0.026), mats["bloom_light"], root, objects, irregularity=0.10)

    # The estate keeps time by a sundial; so does the ship. Offset to port so
    # the bowsprit passes clear of the dial.
    kit.add_cylinder("Sundial_Pedestal", (1.02, 0.61, -0.16), 0.050, 0.16, mats["stone_light"], root, objects, vertices=8, rotation=upright())
    kit.add_cylinder("Sundial_Plate", (1.02, 0.695, -0.16), 0.082, 0.018, mats["brass"], root, objects, vertices=12, rotation=upright())
    kit.add_cone("Sundial_Gnomon", (1.02, 0.735, -0.16), 0.048, 0.0, 0.07, mats["brass"], root, objects, vertices=3, rotation=(math.radians(-58), 0, 0))

    # --- Rig --------------------------------------------------------------
    kit.add_beam("Mast", (0.06, 0.50, 0), (0.06, 2.56, 0), 0.032, mats["iron"], root, objects, vertices=8)
    for y in (0.62, 0.86):
        kit.add_cylinder(f"Mast_Collar_{y}", (0.06, y, 0), 0.050, 0.028, mats["brass"], root, objects, vertices=8, rotation=upright())
    # Scroll brackets at the mast foot, the street lamp's join reused: a bar
    # out to the deck with a curl at the end. A mast standing straight out of
    # a deck is a flagpole.
    for index, direction in enumerate((1, -1)):
        outer = 0.06 + direction * 0.26
        kit.add_beam(
            f"Mast_Bracket_{index}",
            (0.06 + direction * 0.04, 0.94, 0),
            (outer, 0.60, 0),
            0.015,
            mats["iron"],
            root,
            objects,
            vertices=5,
        )
        kit.add_torus(
            f"Mast_Bracket_Curl_{index}",
            (outer, 0.615, 0),
            0.034,
            0.010,
            mats["iron_light"],
            root,
            objects,
            major_segments=10,
            minor_segments=4,
        )

    kit.add_beam("Bowsprit", (0.98, 0.70, 0), (1.70, 0.94, 0), 0.021, mats["iron"], root, objects)
    # Gammon iron: a collar square to the bowsprit, not a hoop hung beside it.
    kit.add_torus(
        "Bowsprit_Collar",
        (1.34, 0.82, 0),
        0.044,
        0.011,
        mats["iron_light"],
        root,
        objects,
        major_segments=10,
        minor_segments=4,
        rotation=(0, math.radians(90), math.radians(18.4)),
    )
    # The stem head curls back over the bow the way the gate's top rail does.
    kit.add_beam("Stem_Head", (1.44, 0.90, 0), (1.30, 1.02, 0), 0.014, mats["iron"], root, objects, vertices=5)
    kit.add_torus("Stem_Curl", (1.26, 1.05, 0), 0.042, 0.011, mats["iron"], root, objects, major_segments=10, minor_segments=4)

    # The two sheets, and the estate's trim on them: a scalloped leech, a
    # brass boltrope along the foot and a brass eyelet at each lower corner.
    # The cloth itself is finer than the starting boat's canvas — the sail
    # material's roughness carries that, and the runtime only ever rewrites
    # the colour, so the weave survives every palette the player picks.
    for spec in (
        ("Main_Sail", 0.02, 0.80, 1.66, 1.00, -1.0, 0.13, "main_sail", 9, 7, 12),
        ("Jib", 0.14, 0.82, 1.52, 1.00, 1.0, 0.09, "jib", 8, 6, 10),
    ):
        name, anchor_x, base_y, height, width, direction, bulge, key, rows, cols, hem = spec
        sail_mesh(
            name, anchor_x, base_y, height, width, direction, bulge,
            mats[key], root, objects, rows=rows, cols=cols,
        )
        scallop_hem(
            f"{name}_Hem",
            leech_points(anchor_x, base_y, height, width, direction, hem),
            direction,
            mats[key],
            root,
            objects,
        )
        foot_end = anchor_x + direction * width
        kit.add_beam(
            f"{name}_Boltrope",
            (anchor_x, base_y, 0),
            (foot_end, base_y, 0),
            0.010,
            mats["brass"],
            root,
            objects,
            vertices=5,
        )
        for corner, x in ((f"{name}_Tack", anchor_x), (f"{name}_Clew", foot_end)):
            kit.add_torus(
                f"{corner}_Eyelet",
                (x, base_y, 0),
                0.026,
                0.008,
                mats["brass"],
                root,
                objects,
                major_segments=8,
                minor_segments=4,
            )

    # Wire rigging, thinner than the starting boat's rope: this rig is iron.
    kit.add_beam("Forestay", (0.06, 2.50, 0), (1.66, 0.94, 0), 0.008, mats["iron"], root, objects, vertices=5)
    kit.add_beam("Backstay", (0.06, 2.50, 0), (-1.12, 0.54, -0.22), 0.008, mats["iron"], root, objects, vertices=5)
    for side in (-1, 1):
        top, width = station(0.10)
        kit.add_beam(
            f"Shroud_{'P' if side < 0 else 'S'}",
            (0.06, 1.86, 0),
            (0.10, top + 0.04, side * (width - 0.02)),
            0.007,
            mats["iron"],
            root,
            objects,
            vertices=5,
        )

    # A weathervane instead of a pennant: the masthead of a garden, not a fleet.
    kit.add_cylinder("Vane_Pivot", (0.06, 2.60, 0), 0.014, 0.07, mats["brass"], root, objects, vertices=6, rotation=upright())
    kit.add_box("Vane_Blade", (-0.07, 2.66, 0), (0.26, 0.10, 0.008), mats["brass"], root, objects, bevel=0.004)
    kit.add_cone("Vane_Point", (0.16, 2.66, 0), 0.048, 0.0, 0.10, mats["brass"], root, objects, vertices=4, rotation=(0, math.radians(90), 0))
    kit.add_box("Vane_Tail", (-0.22, 2.66, 0), (0.09, 0.15, 0.007), mats["brass"], root, objects, rotation=(0, 0, math.radians(18)), bevel=0.004)

    # Bake every part's own rotation into its mesh before the exporter joins
    # them by material. A joined group inherits the transform of whichever
    # member went in first, and a rail beam's tilted frame turns the ship's
    # bounding box into a box a metre wider than the hull. The Home Island
    # moors the boat by measuring that box, so a loose one parks the ship
    # out in the water.
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


if os.environ.get("KEELMIRA_ASSET_IDS") != "__garden_estate_ship_helpers_only__":
    build()
