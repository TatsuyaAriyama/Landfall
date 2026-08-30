"""Build the standalone pieces used by Home Island's arrival commons.

Each piece remains an independent USDZ so the harbor can be recomposed later
without replacing one monolithic scene. Editable Blender sources and review
renders are emitted beside the runtime resources in one deterministic pass.
"""

from __future__ import annotations

import math
import os
import shutil
import sys
from pathlib import Path

import bpy


os.environ["KEELMIRA_ASSET_IDS"] = "__harbor_commons_helpers_only__"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_home_island_asset_set_02 as kit  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "Landfall/Resources"


def finish(
    asset_id: str,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    sockets: tuple[bpy.types.Object, ...] = (),
) -> None:
    root["integration_status"] = "home_island_fixed_harbor"
    kit.export_asset(asset_id, root, objects, sockets)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(
        kit.READY_DIR / f"{asset_id}.usdz",
        RUNTIME_DIR / f"{asset_id}.usdz",
    )


def harbor_materials(prefix: str) -> dict[str, bpy.types.Material]:
    return {
        "deep": kit.material(f"LF_{prefix}WoodDeep", "#352A24", 0.99),
        "wet": kit.material(f"LF_{prefix}WoodWet", "#4A382D", 0.98),
        "wood": kit.material(f"LF_{prefix}Wood", "#735A43", 0.97),
        "sun": kit.material(f"LF_{prefix}WoodSun", "#A18863", 0.98),
        "rope": kit.material(f"LF_{prefix}Rope", "#A38358", 1.0),
        "iron": kit.material(f"LF_{prefix}Iron", "#293331", 0.84, metallic=0.22),
        "cloth": kit.material(
            f"LF_{prefix}Canvas",
            "#D5B56D",
            0.95,
            double_sided=True,
        ),
        "accent": kit.material(f"LF_{prefix}Accent", "#C66D3E", 0.92),
        "green": kit.material(f"LF_{prefix}HarborGreen", "#28584D", 0.96),
        "glow": kit.material(
            f"LF_{prefix}Glow",
            "#F4C66B",
            0.32,
            emission="#FF9B3D",
            emission_strength=2.0,
        ),
    }


def boarding_float_materials() -> dict[str, bpy.types.Material]:
    """The fixed jetty's material ladder, repeated under float-specific names.

    Keeping this palette local avoids silently changing the other harbor props
    while making a future float rebuild deterministic with the fixed pier.
    """
    return {
        "deck_worn": kit.material("LF_BoardingFloatDeckWorn", "#826D50", 0.92),
        "deck": kit.material("LF_BoardingFloatDeck", "#6E573B", 0.90),
        "deck_grey": kit.material("LF_BoardingFloatDeckGrey", "#5A5142", 0.95),
        "deck_new": kit.material("LF_BoardingFloatDeckNew", "#8A5C31", 0.86),
        "pile_sun": kit.material("LF_BoardingFloatPileSun", "#4C4336", 0.94),
        "pile_wet": kit.material("LF_BoardingFloatPileWet", "#293A35", 0.74),
        "pile_deep": kit.material("LF_BoardingFloatPileDeep", "#182420", 0.90),
        "frame": kit.material("LF_BoardingFloatFrame", "#302319", 0.94),
        "frame_deep": kit.material("LF_BoardingFloatFrameDeep", "#1B1713", 0.98),
        "rope": kit.material("LF_BoardingFloatRope", "#AB9063", 0.98),
        "rope_dark": kit.material("LF_BoardingFloatRopeDark", "#735A3B", 0.98),
        "iron": kit.material(
            "LF_BoardingFloatIron",
            "#182126",
            0.52,
            metallic=0.52,
        ),
        "rust": kit.material(
            "LF_BoardingFloatRust",
            "#70412B",
            0.76,
            metallic=0.18,
        ),
    }


def build_harbor_boarding_float() -> None:
    kit.reset_scene()
    root = kit.make_root("harbor_boarding_float", "Harbor_Boarding_Float", "medium")
    objects: list[bpy.types.Object] = []
    mats = boarding_float_materials()

    # Low deck: dimensions and height are consumed by HomeIslandMetrics. Full
    # transverse planks repeat the fixed pier's construction direction; the
    # older alternating cream boards made this read as a separate plastic kit.
    plank_tones = (
        "deck_worn", "deck", "deck", "deck_grey", "deck",
        "deck_worn", "deck", "deck_new", "deck", "deck_grey",
        "deck", "deck_worn", "deck_new", "deck", "deck_grey",
        "deck", "deck_worn",
    )
    for index in range(17):
        y = -1.42 + index * 0.177
        kit.add_box(
            f"Float_Plank_{index + 1:02}",
            (0, y, -0.28 + (0.006 if index % 3 == 0 else 0)),
            (1.34, 0.158, 0.105),
            mats[plank_tones[index]],
            root,
            objects,
            rotation=(0, 0, math.radians((index % 3 - 1) * 0.35)),
            bevel=0.015,
        )

    # Two stringers and four crossheads carry the walking surface. The dark
    # gap between boards and frame is the same contact-shadow device used on
    # the upper jetty.
    for x in (-0.46, 0.46):
        kit.add_box(
            f"Float_Stringer_{'L' if x < 0 else 'R'}",
            (x, 0, -0.42),
            (0.14, 3.04, 0.17),
            mats["frame_deep"],
            root,
            objects,
            bevel=0.018,
        )
    for index, y in enumerate((-1.30, -0.44, 0.44, 1.30), 1):
        kit.add_box(
            f"Float_Crosshead_{index:02}",
            (0, y, -0.43),
            (1.46, 0.13, 0.16),
            mats["frame"],
            root,
            objects,
            bevel=0.014,
        )

    # Concealed rectangular pontoons replace the wheel-like exposed logs.
    # Their dark, wet material keeps buoyancy visible without competing with
    # the deck and matches the fixed pier's submerged framing.
    for x in (-0.43, 0.43):
        side = "L" if x < 0 else "R"
        kit.add_box(
            f"Float_Pontoon_{side}",
            (x, 0, -0.61),
            (0.34, 2.78, 0.32),
            mats["pile_deep"],
            root,
            objects,
            bevel=0.075,
        )

    # The connector uses the same timber treads over dark side stringers. Its
    # footprint and four rises remain unchanged, preserving arrival walking.
    for side_y in (-0.46, 0.46):
        kit.add_beam(
            f"Connector_Stringer_{'A' if side_y < 0 else 'B'}",
            (-0.66, side_y, -0.34),
            (-1.48, side_y, 0.56),
            0.048,
            mats["frame_deep"],
            root,
            objects,
            vertices=7,
        )
    for index in range(4):
        x = -0.79 - index * 0.20
        z = -0.18 + index * 0.18
        kit.add_box(
            f"Pier_Connector_Step_{index + 1}",
            (x, 0.02, z),
            (0.34, 1.02, 0.13),
            mats["deck_worn"] if index > 1 else mats["deck"],
            root,
            objects,
            bevel=0.018,
        )

    # Proper end posts make the sloped rope a handrail rather than two sticks
    # floating beside the stairs.
    for side_y in (-0.49, 0.49):
        side = "A" if side_y < 0 else "B"
        kit.add_cylinder(
            f"Connector_Low_Post_{side}",
            (-0.70, side_y, 0.10),
            0.055,
            0.66,
            mats["pile_sun"],
            root,
            objects,
            vertices=8,
        )
        kit.add_cylinder(
            f"Connector_High_Post_{side}",
            (-1.40, side_y, 0.68),
            0.055,
            0.58,
            mats["pile_sun"],
            root,
            objects,
            vertices=8,
        )
        kit.add_beam(
            f"Connector_Rail_{side}",
            (-0.70, side_y, 0.41),
            (-1.40, side_y, 0.96),
            0.028,
            mats["rope"],
            root,
            objects,
            vertices=7,
        )

    # Two driven guide piles let the platform follow the tide. Metal collars
    # tie them to the frame, making the object read specifically as a floating
    # berth rather than a short duplicate pier.
    for y, label in ((-1.31, "Bow"), (1.31, "Stern")):
        for name, z, depth, mat in (
            ("Deep", -0.75, 0.70, mats["pile_deep"]),
            ("Wet", -0.18, 0.44, mats["pile_wet"]),
            ("Sun", 0.31, 0.54, mats["pile_sun"]),
        ):
            kit.add_cylinder(
                f"Guide_Pile_{label}_{name}",
                (0.76, y, z),
                0.105,
                depth,
                mat,
                root,
                objects,
                vertices=9,
            )
        kit.add_torus(
            f"Guide_Collar_{label}",
            (0.76, y, -0.29),
            0.126,
            0.020,
            mats["iron"],
            root,
            objects,
            major_segments=12,
            minor_segments=4,
        )
        kit.add_cylinder(
            f"Guide_Pile_Cap_{label}",
            (0.76, y, 0.595),
            0.117,
            0.040,
            mats["deck_grey"],
            root,
            objects,
            vertices=9,
        )

    # The boat-facing rope terminates at a broad central gate. Gate posts are
    # lower and slimmer than the guide piles, matching the hierarchy of the
    # upper jetty rather than repeating four identical poles.
    gate_half_length = 0.62
    for y, label in ((-gate_half_length, "Bow"), (gate_half_length, "Stern")):
        kit.add_cylinder(
            f"Boarding_Gate_Post_{label}",
            (0.68, y, 0.08),
            0.070,
            0.72,
            mats["pile_sun"],
            root,
            objects,
            vertices=8,
        )
        kit.add_cylinder(
            f"Boarding_Gate_Cap_{label}",
            (0.68, y, 0.455),
            0.080,
            0.034,
            mats["deck_grey"],
            root,
            objects,
            vertices=8,
        )
        kit.add_box(
            f"Boarding_Gate_Heel_{label}",
            (0.69, y, -0.24),
            (0.10, 0.20, 0.16),
            mats["iron"],
            root,
            objects,
            bevel=0.010,
        )

    for index, (start, end) in enumerate(
        ((-1.32, -gate_half_length), (gate_half_length, 1.32)),
        1,
    ):
        middle = (start + end) * 0.5
        outer_height = 0.49
        gate_height = 0.41
        for tier, drop, radius, mat in (
            ("Upper", 0.00, 0.023, mats["rope"]),
            ("Lower", 0.24, 0.020, mats["rope_dark"]),
        ):
            kit.add_beam(
                f"Float_{tier}_Rope_{index}",
                (0.70, start, outer_height - drop),
                (0.68, middle, min(outer_height, gate_height) - 0.09 - drop),
                radius,
                mat,
                root,
                objects,
                vertices=7,
            )
            kit.add_beam(
                f"Float_{tier}_Rope_Return_{index}",
                (0.68, middle, min(outer_height, gate_height) - 0.09 - drop),
                (0.68, end, gate_height - drop),
                radius,
                mat,
                root,
                objects,
                vertices=7,
            )

    # A split rubbing wale and two hanging fenders protect the boat side while
    # preserving the authored central boarding opening.
    for index, (start, end) in enumerate(
        ((-1.45, -gate_half_length), (gate_half_length, 1.45)),
        1,
    ):
        kit.add_box(
            f"Rubbing_Wale_{index}",
            (0.70, (start + end) * 0.5, -0.36),
            (0.12, end - start, 0.20),
            mats["pile_wet"],
            root,
            objects,
            bevel=0.018,
        )
        y = (start + end) * 0.5
        kit.add_beam(
            f"Float_Fender_Lanyard_{index}",
            (0.73, y, -0.21),
            (0.81, y, -0.43),
            0.014,
            mats["rope_dark"],
            root,
            objects,
            vertices=5,
        )
        kit.add_cylinder(
            f"Float_Fender_{index}",
            (0.82, y, -0.55),
            0.062,
            0.26,
            mats["iron"],
            root,
            objects,
            vertices=8,
        )

    # Low cleats repeat the upper pier's ironwork without adding more posts.
    for y in (-1.22, 1.22):
        kit.add_cylinder(
            f"Mooring_Cleat_Pin_{'Bow' if y < 0 else 'Stern'}",
            (-0.46, y, -0.12),
            0.027,
            0.20,
            mats["iron"],
            root,
            objects,
            vertices=7,
        )
        kit.add_beam(
            f"Mooring_Cleat_Arm_{'Bow' if y < 0 else 'Stern'}",
            (-0.58, y, -0.03),
            (-0.34, y, -0.03),
            0.030,
            mats["iron"],
            root,
            objects,
            vertices=7,
        )

    # Sparse fixings catch close-range light without returning to a tile grid.
    for index in range(1, 17, 3):
        y = -1.42 + index * 0.177
        for x in (-0.52, 0.52):
            kit.add_cylinder(
                f"Float_Deck_Nail_{index + 1:02}_{'L' if x < 0 else 'R'}",
                (x, y, -0.22),
                0.015,
                0.014,
                mats["iron"],
                root,
                objects,
                vertices=6,
            )
    finish("harbor_boarding_float", root, objects)


def build_harbor_sail_canopy() -> None:
    kit.reset_scene()
    root = kit.make_root("harbor_sail_canopy", "Harbor_Sail_Canopy", "large")
    objects: list[bpy.types.Object] = []
    mats = harbor_materials("SailCanopy")
    corners = ((-1.65, -1.18), (1.65, -1.18), (-1.65, 1.18), (1.65, 1.18))
    for index, (x, y) in enumerate(corners, 1):
        top = 2.63 if index in (1, 4) else 2.35
        kit.add_cylinder(
            f"Canopy_Post_{index}",
            (x, y, top * 0.5),
            0.075,
            top,
            mats["wood"],
            root,
            objects,
            vertices=8,
            rotation=(math.radians((index % 2) * 1.2), math.radians((index - 2) * 0.6), 0),
        )
        kit.add_torus(
            f"Canopy_Post_Lashing_{index}",
            (x, y, top - 0.14),
            0.085,
            0.018,
            mats["rope"],
            root,
            objects,
            major_segments=12,
            minor_segments=4,
        )
    vertices = [
        (-1.62, -1.15, 2.49),
        (1.62, -1.15, 2.23),
        (1.62, 1.15, 2.50),
        (-1.62, 1.15, 2.23),
        (0, 0, 2.20),
    ]
    kit.mesh_object(
        "Canopy_Tensioned_Sail",
        vertices,
        [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)],
        mats["cloth"],
        root,
        objects,
    )
    for index, (a, b) in enumerate(((0, 1), (1, 2), (2, 3), (3, 0)), 1):
        kit.add_beam(
            f"Canopy_Edge_Rope_{index}",
            vertices[a],
            vertices[b],
            0.022,
            mats["rope"],
            root,
            objects,
            vertices=7,
        )
    finish("harbor_sail_canopy", root, objects)


def build_harbor_council_table() -> None:
    kit.reset_scene()
    root = kit.make_root("harbor_council_table", "Harbor_Council_Table", "medium")
    root["seat_capacity"] = 4
    root["seat_socket_schema"] = 1
    objects: list[bpy.types.Object] = []
    mats = harbor_materials("CouncilTable")
    kit.add_cylinder("Council_Table_Top", (0, 0, 0.88), 0.80, 0.14, mats["sun"], root, objects, vertices=20)
    kit.add_cylinder("Council_Map_Inlay", (0, 0, 0.956), 0.60, 0.018, mats["green"], root, objects, vertices=20)
    kit.add_cylinder("Council_Table_Pedestal", (0, 0, 0.44), 0.17, 0.78, mats["deep"], root, objects, vertices=10)
    chair_radius = 1.55
    backrest_radius = 1.86
    approach_radius = 2.38
    for index, angle in enumerate((0, math.pi / 2, math.pi, math.pi * 1.5), 1):
        x = math.cos(angle) * chair_radius
        y = math.sin(angle) * chair_radius
        kit.add_cylinder(f"Council_Stool_{index}", (x, y, 0.47), 0.31, 0.14, mats["wood"], root, objects, vertices=12)
        kit.add_cylinder(f"Council_Stool_Leg_{index}", (x, y, 0.23), 0.09, 0.46, mats["wet"], root, objects, vertices=8)
        # The backrest sits outside the stool, making the inward seating
        # direction legible before the player interacts with it.
        back_x = math.cos(angle) * backrest_radius
        back_y = math.sin(angle) * backrest_radius
        kit.add_box(
            f"Council_Chair_Back_{index}",
            (back_x, back_y, 0.73),
            (0.52, 0.12, 0.42),
            mats["sun"],
            root,
            objects,
            rotation=(0, 0, angle + math.pi / 2),
            bevel=0.035,
        )
    sockets: list[bpy.types.Object] = []
    for slot_id, angle in zip(("north", "east", "south", "west"), (math.pi / 2, 0, -math.pi / 2, math.pi)):
        x = math.cos(angle) * chair_radius
        y = math.sin(angle) * chair_radius
        sockets.append(kit.add_socket(f"SeatSocket_{slot_id.title()}", (x, y, 0.58), root, slot_id=slot_id, purpose="seat"))
        sockets.append(kit.add_socket(f"SeatApproach_{slot_id.title()}", (math.cos(angle) * approach_radius, math.sin(angle) * approach_radius, 0), root, slot_id=slot_id, purpose="approach"))
    finish("harbor_council_table", root, objects, tuple(sockets))


def build_harbor_arc_bench() -> None:
    kit.reset_scene()
    root = kit.make_root("harbor_arc_bench", "Harbor_Arc_Bench", "medium")
    root["seat_capacity"] = 3
    root["seat_socket_schema"] = 1
    objects: list[bpy.types.Object] = []
    mats = harbor_materials("ArcBench")
    segments = ((-1.05, -0.08, -0.10), (0, 0, 0), (1.05, -0.08, 0.10))
    for index, (x, y, yaw) in enumerate(segments, 1):
        kit.add_box(f"Arc_Seat_{index}", (x, y, 0.52), (1.16, 0.50, 0.14), mats["sun"] if index == 2 else mats["wood"], root, objects, rotation=(0, 0, yaw), bevel=0.045)
        kit.add_box(f"Arc_Back_{index}", (x, y + 0.24, 0.92), (1.16, 0.13, 0.55), mats["wood"], root, objects, rotation=(math.radians(-5), 0, yaw), bevel=0.04)
        for leg_x in (-0.38, 0.38):
            kit.add_beam(f"Arc_Leg_{index}_{leg_x:+.1f}", (x + leg_x, y, 0.05), (x + leg_x, y, 0.46), 0.07, mats["deep"], root, objects, vertices=7)
    sockets: list[bpy.types.Object] = []
    for slot_id, x in (("left", -1.05), ("center", 0), ("right", 1.05)):
        sockets.append(kit.add_socket(f"SeatSocket_{slot_id.title()}", (x, -0.08 if x else 0, 0.62), root, slot_id=slot_id, purpose="seat"))
        sockets.append(kit.add_socket(f"SeatApproach_{slot_id.title()}", (x, -1.12, 0), root, slot_id=slot_id, purpose="approach"))
    finish("harbor_arc_bench", root, objects, tuple(sockets))


def build_harbor_welcome_beacon() -> None:
    kit.reset_scene()
    root = kit.make_root("harbor_welcome_beacon", "Harbor_Welcome_Beacon", "small")
    objects: list[bpy.types.Object] = []
    mats = harbor_materials("WelcomeBeacon")
    kit.add_cylinder("Beacon_Post", (0, 0, 1.16), 0.095, 2.32, mats["wood"], root, objects, vertices=9)
    kit.add_box("Beacon_Crossarm", (0.30, 0, 2.08), (0.78, 0.13, 0.13), mats["deep"], root, objects, rotation=(0, 0, math.radians(-3)), bevel=0.022)
    kit.add_beam("Beacon_Hanger", (0.61, 0, 2.06), (0.61, 0, 1.72), 0.018, mats["iron"], root, objects, vertices=6)
    kit.add_cylinder("Beacon_Lantern", (0.61, 0, 1.62), 0.13, 0.28, mats["glow"], root, objects, vertices=8)
    kit.add_cone("Beacon_Lantern_Roof", (0.61, 0, 1.82), 0.20, 0.02, 0.17, mats["iron"], root, objects, vertices=8)
    pennant = [(0.05, 0, 1.88), (-0.72, 0, 1.70), (0.05, 0, 1.48)]
    kit.mesh_object("Beacon_Pennant", pennant, [(0, 1, 2)], mats["accent"], root, objects)
    for z in (0.18, 0.27, 0.36):
        kit.add_torus("Beacon_Base_Rope", (0, 0, z), 0.105, 0.018, mats["rope"], root, objects, major_segments=12, minor_segments=4)
    finish("harbor_welcome_beacon", root, objects)


BUILDERS = (
    ("harbor_boarding_float", build_harbor_boarding_float),
    ("harbor_sail_canopy", build_harbor_sail_canopy),
    ("harbor_council_table", build_harbor_council_table),
    ("harbor_arc_bench", build_harbor_arc_bench),
    ("harbor_welcome_beacon", build_harbor_welcome_beacon),
)

requested_ids = {
    value.strip()
    for value in os.environ.get("KEELMIRA_HARBOR_ASSET_IDS", "").split(",")
    if value.strip()
}
selected_builders = [
    builder
    for asset_id, builder in BUILDERS
    if not requested_ids or asset_id in requested_ids
]

for builder in selected_builders:
    builder()

print(f"HARBOR_COMMONS_COMPLETE={len(selected_builders)}")
