"""Split the harbor council table into two placeable pieces.

The arrival commons used to ship one fixed ``harbor_council_table`` — a round
map table with four stools welded to it. Players asked to arrange that
furniture themselves, so the same authored shapes are re-emitted here as two
independent, origin-grounded props: the table (now with its own base, since it
no longer stands on the deck) and a single chair carrying one seat socket.
Dimensions and materials are copied from the original so a table ringed with
four chairs rebuilds the old look exactly.
"""

from __future__ import annotations

import math
import os
import shutil
import sys
from pathlib import Path

import bpy


os.environ["KEELMIRA_ASSET_IDS"] = "__council_furniture_helpers_only__"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_home_island_asset_set_02 as kit  # noqa: E402
import build_harbor_commons as harbor  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "Landfall/Resources"


def finish(
    asset_id: str,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    sockets: tuple[bpy.types.Object, ...] = (),
) -> None:
    root["integration_status"] = "home_island_placeable"
    kit.export_asset(asset_id, root, objects, sockets)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(kit.READY_DIR / f"{asset_id}.usdz", RUNTIME_DIR / f"{asset_id}.usdz")


def build_council_table() -> None:
    kit.reset_scene()
    root = kit.make_root("council_table", "Council_Table", "medium")
    objects: list[bpy.types.Object] = []
    mats = harbor.harbor_materials("CouncilTable")
    kit.add_cylinder("Council_Table_Top", (0, 0, 0.88), 0.80, 0.14, mats["sun"], root, objects, vertices=20)
    kit.add_cylinder("Council_Map_Inlay", (0, 0, 0.956), 0.60, 0.018, mats["green"], root, objects, vertices=20)
    kit.add_cylinder("Council_Table_Pedestal", (0, 0, 0.44), 0.17, 0.78, mats["deep"], root, objects, vertices=10)
    # The fixed version leaned on the gathering deck for its footing. A splayed
    # base lets the table stand anywhere on the island without looking driven
    # into the ground.
    kit.add_cone("Council_Table_Base", (0, 0, 0.055), 0.44, 0.30, 0.11, mats["wet"], root, objects, vertices=14)
    kit.add_torus("Council_Table_BaseRing", (0, 0, 0.11), 0.33, 0.026, mats["wood"], root, objects, major_segments=14, minor_segments=4)
    finish("council_table", root, objects)


def build_council_chair() -> None:
    kit.reset_scene()
    root = kit.make_root("council_chair", "Council_Chair", "small")
    root["seat_capacity"] = 1
    root["seat_socket_schema"] = 1
    objects: list[bpy.types.Object] = []
    mats = harbor.harbor_materials("CouncilChair")
    # The chair faces -Y: the backrest sits behind the seat and the approach
    # socket in front, which is the seating convention the runtime expects.
    kit.add_cone("Council_Chair_Foot", (0, 0, 0.035), 0.24, 0.19, 0.07, mats["wet"], root, objects, vertices=12)
    kit.add_cylinder("Council_Chair_Leg", (0, 0, 0.23), 0.09, 0.46, mats["wet"], root, objects, vertices=8)
    kit.add_cylinder("Council_Chair_Seat", (0, 0, 0.47), 0.31, 0.14, mats["wood"], root, objects, vertices=12)
    for post_x in (-0.18, 0.18):
        kit.add_beam(
            f"Council_Chair_Post_{post_x:+.2f}",
            (post_x, 0.23, 0.46),
            (post_x, 0.27, 0.74),
            0.035,
            mats["wet"],
            root,
            objects,
            vertices=6,
        )
    kit.add_box(
        "Council_Chair_Back",
        (0, 0.27, 0.73),
        (0.52, 0.12, 0.42),
        mats["sun"],
        root,
        objects,
        bevel=0.035,
    )
    sockets = (
        kit.add_socket("SeatSocket_Seat", (0, 0, 0.58), root, slot_id="seat", purpose="seat"),
        kit.add_socket("SeatApproach_Seat", (0, -0.83, 0), root, slot_id="seat", purpose="approach"),
    )
    finish("council_chair", root, objects, sockets)


BUILDERS = (
    ("council_table", build_council_table),
    ("council_chair", build_council_chair),
)

requested_ids = {
    value.strip()
    for value in os.environ.get("KEELMIRA_COUNCIL_ASSET_IDS", "").split(",")
    if value.strip()
}
selected_builders = [
    builder
    for asset_id, builder in BUILDERS
    if not requested_ids or asset_id in requested_ids
]

for builder in selected_builders:
    builder()

print(f"COUNCIL_FURNITURE_COMPLETE={len(selected_builders)}")
