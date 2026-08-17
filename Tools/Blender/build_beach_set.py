"""Build the five beach props: parasol, swim ring, watermelon, palm, sandcastle.

Everything here is sized against the navigator rather than against real metres.
The cottage door the navigator walks through is 1.01 units tall, so one
navigator is very close to **0.95 units**, and each prop is authored at the size
it should read beside one: a parasol just clears the head, a sandcastle reaches
the knee, a palm stands about three navigators tall. Each asset therefore ships
with a default scale of 1.0 and needs no further calibration.
"""

from __future__ import annotations

import math
import os
import shutil
import sys
from pathlib import Path

import bpy


os.environ["KEELMIRA_ASSET_IDS"] = "__beach_set_helpers_only__"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_home_island_asset_set_02 as kit  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "Landfall/Resources"

NAVIGATOR_HEIGHT = 0.95


def finish(asset_id: str, root: bpy.types.Object, objects: list[bpy.types.Object]) -> None:
    root["integration_status"] = "home_island_placeable"
    kit.export_asset(asset_id, root, objects)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(kit.READY_DIR / f"{asset_id}.usdz", RUNTIME_DIR / f"{asset_id}.usdz")


def beach_materials() -> dict[str, bpy.types.Material]:
    return {
        "sand_light": kit.material("LF_BeachSandLight", "#E7DAB4", 0.98),
        "sand": kit.material("LF_BeachSand", "#D6C398", 0.98),
        "sand_wet": kit.material("LF_BeachSandWet", "#B9A277", 0.96),
        "pole": kit.material("LF_BeachPole", "#8A6A47", 0.94),
        "pole_dark": kit.material("LF_BeachPoleDark", "#5E4630", 0.96),
        "canvas": kit.material("LF_BeachCanvas", "#F0E5CB", 0.92, double_sided=True),
        "canvas_stripe": kit.material("LF_BeachCanvasStripe", "#E2795C", 0.92, double_sided=True),
        "ring_white": kit.material("LF_BeachRingWhite", "#F2ECE0", 0.78),
        "ring_red": kit.material("LF_BeachRingRed", "#D2554C", 0.78),
        "rope": kit.material("LF_BeachRope", "#C7A876", 1.0),
        "melon_skin": kit.material("LF_BeachMelonSkin", "#3E7A46", 0.82),
        "melon_stripe": kit.material("LF_BeachMelonStripe", "#27552F", 0.84),
        "melon_flesh": kit.material("LF_BeachMelonFlesh", "#DC5450", 0.80),
        "melon_rind": kit.material("LF_BeachMelonRind", "#EDE6CE", 0.86),
        "seed": kit.material("LF_BeachMelonSeed", "#33241D", 0.70),
        "bark": kit.material("LF_BeachPalmBark", "#8A6B4A", 0.95),
        "bark_dark": kit.material("LF_BeachPalmBarkDark", "#6B5136", 0.96),
        "frond_deep": kit.material("LF_BeachFrondDeep", "#2C5B46", 0.86),
        "frond": kit.material("LF_BeachFrond", "#3D7052", 0.84),
        "frond_light": kit.material("LF_BeachFrondLight", "#57905C", 0.82),
        "coconut": kit.material("LF_BeachCoconut", "#5B4634", 0.94),
        "flag": kit.material("LF_BeachFlag", "#E2795C", 0.90, double_sided=True),
        "shell": kit.material("LF_BeachShell", "#F1E4CC", 0.88),
    }


# ---------------------------------------------------------------------------
# Parasol — 1.18 tall, so its canopy clears the navigator's head by a hand.
# ---------------------------------------------------------------------------
def build_beach_parasol() -> None:
    kit.reset_scene()
    root = kit.make_root("beach_parasol", "Beach_Parasol", "medium")
    objects: list[bpy.types.Object] = []
    mats = beach_materials()

    kit.add_cone("Parasol_Foot", (0, 0, 0.028), 0.14, 0.10, 0.056, mats["sand"], root, objects, vertices=12)
    kit.add_cylinder("Parasol_Pole", (0, 0, 0.60), 0.021, 1.14, mats["pole"], root, objects, vertices=8)
    kit.add_cylinder("Parasol_Collar", (0, 0, 0.86), 0.030, 0.045, mats["pole_dark"], root, objects, vertices=8)

    # Eight canvas panels, alternating like a real beach parasol. Built as
    # wedges rather than a cone so the stripes are geometry, not a texture.
    apex = (0.0, 0.0, 1.18)
    rim_z = 0.955
    rim_radius = 0.52
    panels = 8
    for index in range(panels):
        start = math.tau * index / panels
        end = math.tau * (index + 1) / panels
        mid = (start + end) * 0.5
        vertices = [
            apex,
            (math.cos(start) * rim_radius, math.sin(start) * rim_radius, rim_z),
            # A scalloped mid-point keeps the hem from reading as a flat cone.
            (math.cos(mid) * rim_radius * 1.045, math.sin(mid) * rim_radius * 1.045, rim_z - 0.018),
            (math.cos(end) * rim_radius, math.sin(end) * rim_radius, rim_z),
        ]
        kit.mesh_object(
            f"Parasol_Panel_{index + 1:02}",
            vertices,
            [(0, 1, 2), (0, 2, 3)],
            mats["canvas_stripe"] if index % 2 else mats["canvas"],
            root,
            objects,
        )
        # Rib along every seam.
        kit.add_beam(
            f"Parasol_Rib_{index + 1:02}",
            apex,
            (math.cos(start) * rim_radius, math.sin(start) * rim_radius, rim_z),
            0.010,
            mats["pole_dark"],
            root,
            objects,
            vertices=5,
        )

    kit.add_ico("Parasol_Finial", (0, 0, 1.205), (0.032, 0.032, 0.040), mats["pole_dark"], root, objects, irregularity=0.04)

    for index, angle in enumerate((0.7, 2.9, 4.9), 1):
        kit.add_ico(
            f"Parasol_Pebble_{index:02}",
            (math.cos(angle) * 0.17, math.sin(angle) * 0.17, 0.022),
            (0.048, 0.036, 0.026),
            mats["sand_wet"],
            root,
            objects,
            irregularity=0.2,
        )
    finish("beach_parasol", root, objects)


# ---------------------------------------------------------------------------
# Swim ring — 0.45 across, about what the navigator can step through.
# ---------------------------------------------------------------------------
def build_swim_ring() -> None:
    kit.reset_scene()
    root = kit.make_root("swim_ring", "Swim_Ring", "small")
    objects: list[bpy.types.Object] = []
    mats = beach_materials()

    segments = 12
    major = 0.166
    minor = 0.058
    for index in range(segments):
        start = math.tau * index / segments
        end = math.tau * (index + 1) / segments
        kit.add_beam(
            f"Ring_Segment_{index + 1:02}",
            (math.cos(start) * major, math.sin(start) * major, minor),
            (math.cos(end) * major, math.sin(end) * major, minor),
            minor,
            mats["ring_red"] if index % 2 else mats["ring_white"],
            root,
            objects,
            vertices=8,
        )
    # A short grab rope across one side finishes the lifebuoy read.
    for index, angle in enumerate((0.55, 1.05), 1):
        kit.add_beam(
            f"Ring_Rope_{index:02}",
            (math.cos(angle) * (major - minor * 0.6), math.sin(angle) * (major - minor * 0.6), minor * 1.5),
            (math.cos(angle) * (major + minor * 0.6), math.sin(angle) * (major + minor * 0.6), minor * 1.5),
            0.008,
            mats["rope"],
            root,
            objects,
            vertices=5,
        )
    finish("swim_ring", root, objects)


# ---------------------------------------------------------------------------
# Watermelon — one whole melon at 0.17 across, plus two cut slices.
# ---------------------------------------------------------------------------
def build_watermelon() -> None:
    kit.reset_scene()
    root = kit.make_root("watermelon", "Watermelon", "small")
    objects: list[bpy.types.Object] = []
    mats = beach_materials()

    # Painting stripes onto a faceted ball never sits flush, so the melon is
    # built striped: eight meridian wedges of a lathed sphere, alternating tone.
    melon_radius = 0.086
    melon_height = 0.080
    melon_center = 0.082
    wedges = 8
    rings = 6
    for wedge in range(wedges):
        base_angle = math.tau * wedge / wedges
        step = math.tau / wedges * 0.5
        angles = (base_angle, base_angle + step, base_angle + step * 2)
        vertices: list[tuple[float, float, float]] = []
        for ring in range(rings + 1):
            phi = math.pi * ring / rings
            ring_radius = melon_radius * math.sin(phi)
            z = melon_center + melon_height * math.cos(phi)
            for angle in angles:
                vertices.append((math.cos(angle) * ring_radius, math.sin(angle) * ring_radius, z))
        faces: list[tuple[int, ...]] = []
        for ring in range(rings):
            for column in range(2):
                low = ring * 3 + column
                high = (ring + 1) * 3 + column
                faces.append((low, low + 1, high + 1, high))
        kit.mesh_object(
            f"Melon_Wedge_{wedge + 1:02}",
            vertices,
            faces,
            mats["melon_stripe"] if wedge % 2 else mats["melon_skin"],
            root,
            objects,
        )
    kit.add_beam(
        "Melon_Stem", (0.004, 0, 0.158), (0.020, 0.008, 0.186),
        0.010, mats["melon_stripe"], root, objects, vertices=5, end_radius=0.007,
    )

    # Two cut slices leaning beside it: a flesh wedge on its rind.
    for index, (x, y, yaw) in enumerate(((0.155, -0.02, 0.35), (0.225, 0.095, -0.6)), 1):
        flesh = [
            (-0.050, 0.0, 0.020), (0.050, 0.0, 0.020), (0.0, 0.0, 0.082),
            (-0.050, 0.026, 0.020), (0.050, 0.026, 0.020), (0.0, 0.026, 0.082),
        ]
        faces = [(0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]
        wedge = kit.mesh_object(f"Melon_Slice_{index:02}", flesh, faces, mats["melon_flesh"], root, objects)
        wedge.location = (x, y, 0)
        wedge.rotation_euler = (0, 0, yaw)
        rind = kit.add_box(
            f"Melon_Slice_Rind_{index:02}", (0, 0, 0), (0.112, 0.030, 0.020),
            mats["melon_rind"], root, objects, bevel=0.004,
        )
        rind.location = (x, y + 0.013, 0.010)
        rind.rotation_euler = (0, 0, yaw)
        skin = kit.add_box(
            f"Melon_Slice_Skin_{index:02}", (0, 0, 0), (0.116, 0.032, 0.009),
            mats["melon_skin"], root, objects, bevel=0.003,
        )
        skin.location = (x, y + 0.013, 0.0035)
        skin.rotation_euler = (0, 0, yaw)
        for seed_index, (sx, sz) in enumerate(((-0.020, 0.040), (0.019, 0.037), (0.0, 0.056)), 1):
            seed = kit.add_ico(
                f"Melon_Seed_{index:02}_{seed_index}", (0, 0, 0), (0.006, 0.003, 0.008),
                mats["seed"], root, objects, irregularity=0.05,
            )
            seed.location = (x + sx * math.cos(yaw), y + sx * math.sin(yaw) - 0.002, sz)
            seed.rotation_euler = (0, 0, yaw)
    finish("watermelon", root, objects)


# ---------------------------------------------------------------------------
# Palm tree — 2.9 tall, about three navigators, with a leaning ringed trunk.
# ---------------------------------------------------------------------------
def palm_trunk_point(t: float) -> tuple[float, float, float]:
    """The trunk's centre line: straight at the foot, leaning near the crown."""
    lean = 0.62 * t * t
    return (lean, 0.02 * math.sin(t * 3.1), 2.46 * t)


def build_palm_frond(
    index: int,
    origin: tuple[float, float, float],
    bearing: float,
    length: float,
    droop: float,
    mat: bpy.types.Material,
    rib_mat: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
) -> None:
    """One pinnate frond: a rib that arches up then falls, carrying leaflets.

    Built as a single mesh with a saw-tooth outline rather than as separate
    leaves — a palm needs a dozen leaflets a side to read, and that many
    primitives would cost more than the whole rest of the island.
    """
    stations = 9
    cosine = math.cos(bearing)
    sine = math.sin(bearing)

    def place(along: float, across: float, rise: float) -> tuple[float, float, float]:
        return (
            origin[0] + cosine * along - sine * across,
            origin[1] + sine * along + cosine * across,
            origin[2] + rise,
        )

    def rib_rise(t: float) -> float:
        # Up out of the crown, then over and down: the arc that makes a palm.
        return length * (0.42 * t - (0.85 + droop) * t * t)

    def half_width(t: float) -> float:
        return length * 0.30 * math.sin(math.pi * (t ** 0.62))

    # A continuous blade on each side of the rib, its outline stepping in and
    # out so the edge reads as leaflets. Building it as separate leaflets left
    # gaps that made the frond look like a bare skeleton.
    rib_points = []
    for station in range(stations + 1):
        t = station / stations
        rib_points.append(place(length * t, 0.0, rib_rise(t)))

    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for side in (-1.0, 1.0):
        edge_points = []
        for station in range(stations + 1):
            t = station / stations
            serration = 0.82 if station % 2 else 1.0
            edge_points.append(
                place(
                    length * (t + 0.035),
                    side * half_width(t) * serration,
                    rib_rise(t) - length * (0.05 + 0.13 * t),
                )
            )
        base = len(vertices)
        vertices.extend(rib_points)
        vertices.extend(edge_points)
        for station in range(stations):
            rib_low = base + station
            rib_high = base + station + 1
            edge_low = base + stations + 1 + station
            edge_high = base + stations + 2 + station
            faces.append((rib_low, edge_low, edge_high))
            faces.append((rib_low, edge_high, rib_high))

    kit.mesh_object(f"Palm_Frond_{index:02}", vertices, faces, mat, root, objects)

    # A visible rib keeps the blade from looking like paper.
    rib_stations = 4
    for section in range(rib_stations):
        t0 = section / rib_stations
        t1 = (section + 1) / rib_stations
        kit.add_beam(
            f"Palm_Frond_Rib_{index:02}_{section + 1}",
            place(length * t0, 0.0, rib_rise(t0)),
            place(length * t1, 0.0, rib_rise(t1)),
            0.013 * (1 - t0 * 0.7),
            rib_mat,
            root,
            objects,
            vertices=5,
            end_radius=0.013 * (1 - t1 * 0.75),
        )


def build_palm_tree() -> None:
    kit.reset_scene()
    root = kit.make_root("palm_tree", "Palm_Tree", "large")
    objects: list[bpy.types.Object] = []
    mats = beach_materials()

    # Twelve short segments with a pinched radius give the ring scars a palm
    # trunk is recognised by, and let the base flare into its root mass.
    segments = 12
    for index in range(segments):
        t0 = index / segments
        t1 = (index + 1) / segments
        taper0 = 0.115 - 0.058 * t0
        taper1 = 0.115 - 0.058 * t1
        ring0 = 1.0 + 0.085 * math.sin(t0 * math.pi * segments)
        ring1 = 1.0 + 0.085 * math.sin(t1 * math.pi * segments)
        kit.add_beam(
            f"Palm_Trunk_{index + 1:02}",
            palm_trunk_point(t0),
            palm_trunk_point(t1),
            taper0 * ring0,
            mats["bark"] if index % 2 else mats["bark_dark"],
            root,
            objects,
            vertices=9,
            end_radius=taper1 * ring1,
        )
    kit.add_cone("Palm_Base_Flare", (0, 0, 0.075), 0.185, 0.125, 0.150, mats["bark_dark"], root, objects, vertices=10)
    for index in range(5):
        angle = math.tau * index / 5 + 0.3
        kit.add_beam(
            f"Palm_Root_{index + 1:02}",
            (math.cos(angle) * 0.05, math.sin(angle) * 0.05, 0.14),
            (math.cos(angle) * 0.23, math.sin(angle) * 0.23, 0.010),
            0.052,
            mats["bark_dark"] if index % 2 else mats["bark"],
            root,
            objects,
            vertices=6,
            end_radius=0.016,
        )

    crown = palm_trunk_point(1.0)
    # Old frond bases left on the trunk, the way a palm keeps its scars.
    for index in range(6):
        angle = math.tau * index / 6 + 0.4
        kit.add_beam(
            f"Palm_Boot_{index + 1:02}",
            (crown[0], crown[1], crown[2] - 0.10),
            (
                crown[0] + math.cos(angle) * 0.115,
                crown[1] + math.sin(angle) * 0.115,
                crown[2] - 0.15,
            ),
            0.045,
            mats["bark_dark"],
            root,
            objects,
            vertices=5,
            end_radius=0.022,
        )

    frond_materials = (mats["frond"], mats["frond_deep"], mats["frond_light"])
    for index in range(9):
        bearing = math.tau * index / 9 + 0.22
        build_palm_frond(
            index + 1,
            (crown[0], crown[1], crown[2] + 0.02),
            bearing,
            0.78 + (index % 3) * 0.07,
            0.10 + (index % 3) * 0.16,
            frond_materials[index % len(frond_materials)],
            mats["frond_deep"],
            root,
            objects,
        )
    # Two short fronds still opening at the very top of the crown.
    for index, bearing in enumerate((1.1, 4.3), 10):
        build_palm_frond(
            index,
            (crown[0], crown[1], crown[2] + 0.06),
            bearing,
            0.44,
            -0.28,
            mats["frond_light"],
            mats["frond_deep"],
            root,
            objects,
        )

    # Slung below the frond bases so they stay visible from the ground.
    kit.add_ico("Palm_Crown_Cap", (crown[0], crown[1], crown[2] + 0.045), (0.085, 0.085, 0.055), mats["frond_deep"], root, objects, irregularity=0.06)
    for index, (angle, drop) in enumerate(((0.5, 0.24), (1.9, 0.28), (3.4, 0.23), (5.0, 0.27)), 1):
        kit.add_ico(
            f"Palm_Coconut_{index:02}",
            (
                crown[0] + math.cos(angle) * 0.105,
                crown[1] + math.sin(angle) * 0.105,
                crown[2] - drop,
            ),
            (0.060, 0.060, 0.054),
            mats["coconut"],
            root,
            objects,
            irregularity=0.07,
        )
    finish("palm_tree", root, objects)


# ---------------------------------------------------------------------------
# Sandcastle — knee height on the navigator, with a moat and a paper flag.
# ---------------------------------------------------------------------------
def build_sandcastle() -> None:
    kit.reset_scene()
    root = kit.make_root("sandcastle", "Sandcastle", "small")
    objects: list[bpy.types.Object] = []
    mats = beach_materials()

    kit.add_torus("Castle_Moat", (0, 0, 0.010), 0.225, 0.020, mats["sand_wet"], root, objects, major_segments=16, minor_segments=4)
    kit.add_cone("Castle_Base", (0, 0, 0.026), 0.205, 0.180, 0.052, mats["sand"], root, objects, vertices=14)

    corner = 0.112
    for index, (x, y) in enumerate(((-corner, -corner), (corner, -corner), (corner, corner), (-corner, corner)), 1):
        kit.add_cylinder(f"Castle_Tower_{index:02}", (x, y, 0.107), 0.038, 0.110, mats["sand_light"], root, objects, vertices=10)
        kit.add_cone(f"Castle_Tower_Cap_{index:02}", (x, y, 0.184), 0.046, 0.0, 0.044, mats["sand"], root, objects, vertices=10)

    # Curtain walls with a bucket-stamped battlement line.
    walls = (
        ((0, -corner, 0.098), (0.186, 0.036, 0.076), 0.0),
        ((0, corner, 0.098), (0.186, 0.036, 0.076), 0.0),
        ((-corner, 0, 0.098), (0.036, 0.186, 0.076), 0.0),
        ((corner, 0, 0.098), (0.036, 0.186, 0.076), 0.0),
    )
    for index, (location, dimensions, yaw) in enumerate(walls, 1):
        kit.add_box(f"Castle_Wall_{index:02}", location, dimensions, mats["sand_light"], root, objects, rotation=(0, 0, yaw), bevel=0.006)
    for index, (x, y) in enumerate(
        ((-0.056, -corner), (0.056, -corner), (-0.056, corner), (0.056, corner),
         (-corner, -0.056), (-corner, 0.056), (corner, -0.056), (corner, 0.056)), 1
    ):
        kit.add_box(f"Castle_Merlon_{index:02}", (x, y, 0.148), (0.034, 0.034, 0.030), mats["sand"], root, objects, bevel=0.004)

    kit.add_cylinder("Castle_Keep", (0, 0, 0.135), 0.062, 0.170, mats["sand_light"], root, objects, vertices=12)
    kit.add_cone("Castle_Keep_Cap", (0, 0, 0.248), 0.072, 0.0, 0.058, mats["sand"], root, objects, vertices=12)

    kit.add_beam("Castle_Flagstaff", (0, 0, 0.268), (0, 0, 0.352), 0.005, mats["pole_dark"], root, objects, vertices=5)
    kit.mesh_object(
        "Castle_Flag",
        [(0.004, 0, 0.348), (0.004, 0, 0.300), (0.086, -0.010, 0.326)],
        [(0, 1, 2)],
        mats["flag"],
        root,
        objects,
    )

    for index, (angle, distance, size) in enumerate(((1.2, 0.245, 0.030), (3.6, 0.255, 0.026), (5.4, 0.235, 0.028)), 1):
        kit.add_ico(
            f"Castle_Shell_{index:02}",
            (math.cos(angle) * distance, math.sin(angle) * distance, 0.010),
            (size, size * 0.78, size * 0.34),
            mats["shell"], root, objects, irregularity=0.14,
        )
    finish("sandcastle", root, objects)


BUILDERS = (
    ("beach_parasol", build_beach_parasol),
    ("swim_ring", build_swim_ring),
    ("watermelon", build_watermelon),
    ("palm_tree", build_palm_tree),
    ("sandcastle", build_sandcastle),
)

requested_ids = {
    value.strip()
    for value in os.environ.get("KEELMIRA_BEACH_ASSET_IDS", "").split(",")
    if value.strip()
}
selected_builders = [
    builder for asset_id, builder in BUILDERS
    if not requested_ids or asset_id in requested_ids
]

for builder in selected_builders:
    builder()

print(f"BEACH_SET_COMPLETE={len(selected_builders)}")
