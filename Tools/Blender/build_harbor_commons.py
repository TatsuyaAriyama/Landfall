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


def build_harbor_boarding_float() -> None:
    kit.reset_scene()
    root = kit.make_root("harbor_boarding_float", "Harbor_Boarding_Float", "medium")
    objects: list[bpy.types.Object] = []
    mats = harbor_materials("BoardingFloat")

    # Low deck: its authored negative height puts it close to the boat deck
    # after Home Island's common surface offset is applied.
    for index in range(17):
        y = -1.42 + index * 0.177
        kit.add_box(
            f"Float_Plank_{index + 1:02}",
            (0, y, -0.28 + (0.006 if index % 3 == 0 else 0)),
            (1.34, 0.158, 0.105),
            mats["sun"] if index % 4 == 0 else mats["wood"],
            root,
            objects,
            rotation=(0, 0, math.radians((index % 3 - 1) * 0.35)),
            bevel=0.015,
        )
    for x in (-0.46, 0.46):
        kit.add_box(
            f"Float_Stringer_{'L' if x < 0 else 'R'}",
            (x, 0, -0.42),
            (0.14, 3.04, 0.17),
            mats["deep"],
            root,
            objects,
            bevel=0.018,
        )
    for x in (-0.47, 0.47):
        kit.add_cylinder(
            f"Floatation_Log_{'L' if x < 0 else 'R'}",
            (x, 0, -0.61),
            0.17,
            2.78,
            mats["wet"],
            root,
            objects,
            vertices=9,
            rotation=(math.pi / 2, 0, 0),
        )

    # The landward connector rises in four readable steps to the main pier.
    for index in range(4):
        x = -0.79 - index * 0.20
        z = -0.18 + index * 0.18
        kit.add_box(
            f"Pier_Connector_Step_{index + 1}",
            (x, 0.02, z),
            (0.34, 1.02, 0.13),
            mats["sun"] if index > 1 else mats["wood"],
            root,
            objects,
            bevel=0.018,
        )
    for side_y in (-0.49, 0.49):
        kit.add_beam(
            f"Connector_Rail_{'A' if side_y < 0 else 'B'}",
            (-0.72, side_y, -0.02),
            (-1.40, side_y, 0.67),
            0.035,
            mats["rope"],
            root,
            objects,
            vertices=7,
        )

    # The boat-facing rail stops at a broad central boarding gate. Posts frame
    # the opening, but no rope crosses the gangplank or the navigator's path.
    # The opposite side remains open toward the stair connector.
    gate_half_length = 0.62
    for y in (-1.32, -gate_half_length, gate_half_length, 1.32):
        kit.add_cylinder(
            f"Outer_Post_{y:+.2f}",
            (0.68, y, 0.02),
            0.075,
            1.30,
            mats["wet"],
            root,
            objects,
            vertices=8,
        )
    for index, (start, end) in enumerate(
        ((-1.32, -gate_half_length), (gate_half_length, 1.32)),
        1,
    ):
        middle = (start + end) * 0.5
        kit.add_beam(
            f"Float_Upper_Rope_{index}",
            (0.68, start, 0.58),
            (0.68, middle, 0.49),
            0.023,
            mats["rope"],
            root,
            objects,
            vertices=7,
        )
        kit.add_beam(
            f"Float_Upper_Rope_Return_{index}",
            (0.68, middle, 0.49),
            (0.68, end, 0.58),
            0.023,
            mats["rope"],
            root,
            objects,
            vertices=7,
        )
    for y in (-1.22, 1.22):
        kit.add_cylinder(
            f"Mooring_Bollard_{'Bow' if y < 0 else 'Stern'}",
            (-0.50, y, 0.04),
            0.06,
            0.62,
            mats["iron"],
            root,
            objects,
            vertices=8,
        )
    finish("harbor_boarding_float", root, objects)


def build_harbor_gathering_deck() -> None:
    kit.reset_scene()
    root = kit.make_root("harbor_gathering_deck", "Harbor_Gathering_Deck", "large")
    objects: list[bpy.types.Object] = []
    mats = harbor_materials("GatheringDeck")
    for index in range(22):
        y = -1.48 + index * 0.142
        inset = 0.18 * abs(y) / 1.55
        kit.add_box(
            f"Commons_Plank_{index + 1:02}",
            (0, y, 0.14 + (0.004 if index % 4 == 0 else 0)),
            (5.80 - inset, 0.126, 0.11),
            (mats["sun"], mats["wood"], mats["wood"], mats["wet"])[index % 4],
            root,
            objects,
            rotation=(0, 0, math.radians((index % 5 - 2) * 0.18)),
            bevel=0.016,
        )
    for y in (-1.30, 0, 1.30):
        kit.add_box(
            f"Commons_Underbeam_{y:+.1f}",
            (0, y, 0.03),
            (5.55, 0.15, 0.18),
            mats["deep"],
            root,
            objects,
            bevel=0.018,
        )
    # A flush compass rose gives arriving players a natural meeting point.
    kit.add_cylinder("Commons_Compass_Ring", (0, 0, 0.205), 0.64, 0.022, mats["green"], root, objects, vertices=32)
    kit.add_box("Commons_Compass_NS", (0, 0, 0.223), (0.15, 1.04, 0.018), mats["accent"], root, objects, rotation=(0, 0, math.pi / 4), bevel=0.01)
    kit.add_box("Commons_Compass_EW", (0, 0, 0.225), (0.15, 1.04, 0.018), mats["sun"], root, objects, rotation=(0, 0, -math.pi / 4), bevel=0.01)
    finish("harbor_gathering_deck", root, objects)


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
    for index, angle in enumerate((0, math.pi / 2, math.pi, math.pi * 1.5), 1):
        x = math.cos(angle) * 1.25
        y = math.sin(angle) * 1.25
        kit.add_cylinder(f"Council_Stool_{index}", (x, y, 0.47), 0.31, 0.14, mats["wood"], root, objects, vertices=12)
        kit.add_cylinder(f"Council_Stool_Leg_{index}", (x, y, 0.23), 0.09, 0.46, mats["wet"], root, objects, vertices=8)
    sockets: list[bpy.types.Object] = []
    for slot_id, angle in zip(("north", "east", "south", "west"), (math.pi / 2, 0, -math.pi / 2, math.pi)):
        x = math.cos(angle) * 1.25
        y = math.sin(angle) * 1.25
        sockets.append(kit.add_socket(f"SeatSocket_{slot_id.title()}", (x, y, 0.58), root, slot_id=slot_id, purpose="seat"))
        sockets.append(kit.add_socket(f"SeatApproach_{slot_id.title()}", (math.cos(angle) * 1.92, math.sin(angle) * 1.92, 0), root, slot_id=slot_id, purpose="approach"))
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
    build_harbor_boarding_float,
    build_harbor_gathering_deck,
    build_harbor_sail_canopy,
    build_harbor_council_table,
    build_harbor_arc_bench,
    build_harbor_welcome_beacon,
)

for builder in BUILDERS:
    builder()

print(f"HARBOR_COMMONS_COMPLETE={len(BUILDERS)}")
