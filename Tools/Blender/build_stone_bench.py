"""Build the stone bench: the driftwood bench's seat, carved in granite.

Every dimension that the game reads — overall length, seat height, backrest
height, and the four seat/approach sockets — is copied from
``build_driftwood_bench`` on purpose. The two benches are interchangeable in
Home Island: same footprint, same 62% ship scale, same two-person seating, and
a navigator sits on either at exactly the same height. Only the material and
the joinery change: planks lashed with iron become quarried slabs on masonry
piers, weathered by moss and lichen rather than by salt.
"""

from __future__ import annotations

import math
import os
import shutil
import sys
from pathlib import Path

import bpy


os.environ["KEELMIRA_ASSET_IDS"] = "__stone_bench_helpers_only__"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_home_island_asset_set_02 as kit  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "Landfall/Resources"

# The driftwood bench's authored envelope, kept here as named constants so the
# two benches cannot drift apart during a later tweak.
SEAT_TOP_Z = 0.660
SEAT_SLAB_THICKNESS = 0.150
BENCH_LENGTH = 2.70
LEG_X = 0.96
BACK_TILT = math.radians(-4)


def finish(asset_id: str, root: bpy.types.Object, objects: list[bpy.types.Object], sockets) -> None:
    root["integration_status"] = "home_island_placeable"
    kit.export_asset(asset_id, root, objects, sockets)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(kit.READY_DIR / f"{asset_id}.usdz", RUNTIME_DIR / f"{asset_id}.usdz")


def build_stone_bench() -> None:
    kit.reset_scene()
    root = kit.make_root("stone_bench", "Stone_Bench")
    root["seat_capacity"] = 2
    root["seat_socket_schema"] = 1
    objects: list[bpy.types.Object] = []
    mats = {
        "deep": kit.material("LF_StoneBenchDeep", "#38443F", 1.0),
        "shadow": kit.material("LF_StoneBenchShadow", "#525E57", 0.99),
        "stone": kit.material("LF_StoneBenchStone", "#737A6E", 0.98),
        "light": kit.material("LF_StoneBenchLight", "#9A9884", 0.97),
        "moss": kit.material("LF_StoneBenchMoss", "#5D7355", 1.0),
        "lichen": kit.material("LF_StoneBenchLichen", "#8B9670", 0.99),
    }

    seat_center_z = SEAT_TOP_Z - SEAT_SLAB_THICKNESS * 0.5
    half = BENCH_LENGTH * 0.5

    # Seat: two quarried slabs meeting over the centre pier. A single slab this
    # long reads as a poured plank; the joint is what makes it masonry. Each
    # slab covers exactly one seat socket.
    for index, (x, mat) in enumerate(((-0.685, mats["light"]), (0.685, mats["stone"])), 1):
        kit.add_box(
            f"StoneBench_Seat_{index:02}",
            (x, 0.01, seat_center_z),
            (half - 0.015, 0.58, SEAT_SLAB_THICKNESS),
            mat,
            root,
            objects,
            bevel=0.030,
        )
    # A recessed shadow course under the slabs. It stops the seat from floating
    # over the piers and gives the front edge a two-tone depth read.
    kit.add_box(
        "StoneBench_Seat_Course",
        (0, 0.02, seat_center_z - 0.104),
        (BENCH_LENGTH - 0.14, 0.50, 0.075),
        mats["shadow"],
        root,
        objects,
        bevel=0.018,
    )

    # Piers. Blocks rather than beams: stone is stacked, not lashed. The centre
    # pier carries the joint between the two seat slabs.
    for index, x in enumerate((-LEG_X, LEG_X), 1):
        kit.add_box(f"StoneBench_Pier_Foot_{index}", (x, 0.02, 0.045), (0.46, 0.62, 0.090), mats["deep"], root, objects, bevel=0.020)
        kit.add_box(f"StoneBench_Pier_Low_{index}", (x, 0.02, 0.190), (0.40, 0.55, 0.205), mats["stone"], root, objects, bevel=0.022)
        kit.add_box(f"StoneBench_Pier_High_{index}", (x, 0.02, 0.395), (0.36, 0.50, 0.210), mats["shadow"], root, objects, bevel=0.022)
    kit.add_box("StoneBench_Pier_Centre", (0, 0.03, 0.235), (0.30, 0.44, 0.480), mats["stone"], root, objects, bevel=0.024)
    kit.add_box("StoneBench_Pier_Centre_Cap", (0, 0.03, 0.495), (0.36, 0.48, 0.055), mats["deep"], root, objects, bevel=0.016)

    # Back posts and the backrest sit where the driftwood bench's do, so the
    # silhouette above the seat is unchanged and a navigator's back still meets
    # stone at the same height.
    # The piers continue upward *behind* the backrest rather than crossing it,
    # so the slab reads as one quarried piece resting against masonry.
    for index, x in enumerate((-LEG_X, LEG_X), 1):
        kit.add_box(
            f"StoneBench_Back_Post_{index}",
            (x, 0.325, 0.785),
            (0.30, 0.16, 0.520),
            mats["deep"],
            root,
            objects,
            rotation=(BACK_TILT, 0, 0),
            bevel=0.024,
        )
    for index, (x, mat) in enumerate(((-0.68, mats["light"]), (0.68, mats["stone"])), 1):
        kit.add_box(
            f"StoneBench_Backrest_{index:02}",
            (x, 0.28, 0.915),
            (1.31, 0.14, 0.27),
            mat,
            root,
            objects,
            rotation=(BACK_TILT, 0, 0),
            bevel=0.040,
        )
    # A carved rail line along the backrest: one groove is all the ornament a
    # low-poly prop can carry, and it separates the two backrest slabs.
    kit.add_box(
        "StoneBench_Backrest_Groove",
        (0, 0.255, 0.905),
        (BENCH_LENGTH - 0.42, 0.035, 0.045),
        mats["deep"],
        root,
        objects,
        rotation=(BACK_TILT, 0, 0),
        bevel=0.008,
    )
    # A keystone spanning the full backrest height at the joint, so the two
    # slabs read as locked together instead of merely abutting.
    kit.add_box(
        "StoneBench_Backrest_Keystone",
        (0, 0.272, 0.915),
        (0.17, 0.17, 0.30),
        mats["shadow"],
        root,
        objects,
        rotation=(BACK_TILT, 0, 0),
        bevel=0.022,
    )

    # Weathering. Moss creeps up from the ground on the shaded pier, lichen
    # blooms on the sunlit seat corner, and one chipped corner keeps the slab
    # from reading as machined.
    kit.add_ico("StoneBench_Moss_Pier", (-LEG_X - 0.06, -0.12, 0.13), (0.11, 0.20, 0.13), mats["moss"], root, objects, irregularity=0.20)
    kit.add_ico("StoneBench_Moss_Ground", (-1.02, 0.08, 0.050), (0.24, 0.22, 0.030), mats["moss"], root, objects, irregularity=0.22)
    kit.add_ico("StoneBench_Lichen_Seat", (0.98, -0.16, SEAT_TOP_Z - 0.008), (0.24, 0.11, 0.016), mats["lichen"], root, objects, irregularity=0.18)
    kit.add_ico("StoneBench_Lichen_Back", (-0.34, 0.20, 1.010), (0.16, 0.05, 0.032), mats["lichen"], root, objects, irregularity=0.20)
    kit.add_ico("StoneBench_Chip", (half - 0.06, -0.27, seat_center_z + 0.02), (0.07, 0.07, 0.06), mats["deep"], root, objects, irregularity=0.28)

    # Sockets copied verbatim from the driftwood bench: same slot ids, same
    # seat height, same 1.30 approach standoff. A seat authored anywhere else
    # would make the two benches feel like different furniture.
    seat_left = kit.add_socket("SeatSocket_Left", (-0.68, -0.02, 0.65), root, slot_id="left", purpose="seat")
    seat_right = kit.add_socket("SeatSocket_Right", (0.68, -0.02, 0.65), root, slot_id="right", purpose="seat")
    approach_left = kit.add_socket("SeatApproach_Left", (-0.68, -1.30, 0.0), root, slot_id="left", purpose="approach")
    approach_right = kit.add_socket("SeatApproach_Right", (0.68, -1.30, 0.0), root, slot_id="right", purpose="approach")

    finish("stone_bench", root, objects, (seat_left, seat_right, approach_left, approach_right))


build_stone_bench()
print("STONE_BENCH_COMPLETE=1")
