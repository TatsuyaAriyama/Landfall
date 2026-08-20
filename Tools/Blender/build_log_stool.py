"""Build the log stool: the seat that used to be welded to the campfire.

Three of these came fixed in a ring around ``campfire_circle``, which meant a
player could have the fire or the seating but never one without the other.
The same log is authored here as its own prop with its own seat socket, so it
can be set beside a fire, a desk, or nothing at all.

It is cut from the campfire's own wood — the hex values below are that
builder's — so a ring of stools around the fire still reads as one camp. Sized
against the benches rather than against the old ring: the seat lands at 0.40,
which is where `driftwood_bench` puts a navigator, and the log is one person
long.
"""

from __future__ import annotations

import math
import os
import shutil
import sys
from pathlib import Path

import bpy


os.environ["KEELMIRA_ASSET_IDS"] = "__log_stool_helpers_only__"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_home_island_asset_set_02 as kit  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "Landfall/Resources"

# The authored envelope. The seat is the top of the log, and the runtime reads
# it from SeatSocket_Seat — change one, change the other.
LOG_R = 0.190           # the log's own radius
SEAT_Z = 0.400          # the surface a navigator sits on: driftwood_bench's height
LOG_Z = SEAT_Z - LOG_R  # the log's axis
HALF_LENGTH = 0.520     # one person long, not a bench
TIP_R = 0.172           # the far end of the taper


def finish(asset_id: str, root: bpy.types.Object, objects: list[bpy.types.Object], sockets) -> None:
    root["integration_status"] = "home_island_placeable"
    root["seat_capacity"] = 1
    root["seat_socket_schema"] = 1
    kit.export_asset(asset_id, root, objects, sockets)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(kit.READY_DIR / f"{asset_id}.usdz", RUNTIME_DIR / f"{asset_id}.usdz")


def stool_materials() -> dict[str, bpy.types.Material]:
    # build_campfire_circle.py's palette, hex for hex.
    return {
        "wood": kit.material("LF_LogStoolWood", "#624734", 0.96),
        "wood_deep": kit.material("LF_LogStoolWoodDeep", "#3B2D25", 0.98),
        "wood_light": kit.material("LF_LogStoolWoodLight", "#87684A", 0.96),
        "cut": kit.material("LF_LogStoolCutWood", "#B2966D", 0.97),
        "heart": kit.material("LF_LogStoolHeartwood", "#6E5636", 0.97),
        "moss": kit.material("LF_LogStoolMoss", "#53684D", 1.0),
    }


def build_log_stool() -> None:
    kit.reset_scene()
    root = kit.make_root("log_stool", "Log_Stool", "small")
    objects: list[bpy.types.Object] = []
    mats = stool_materials()

    # The log itself, lying across the front. Twelve sides: enough that the
    # seat does not read as a plank from above, few enough to stay faceted.
    # It tapers along its length — a section of trunk is never a machined
    # cylinder, and the narrow end tells the player which way it was felled.
    kit.add_cone(
        "Stool_Log",
        (0.0, 0.0, LOG_Z),
        LOG_R,
        TIP_R,
        HALF_LENGTH * 2,
        mats["wood"],
        root,
        objects,
        vertices=12,
        rotation=(0, math.pi / 2, 0),
    )
    # Bark: two ridges down the flanks, left and right of where a navigator
    # sits. They catch light the smooth barrel cannot, and they stay off the
    # top so the seat still looks sat-on.
    for index, (across, up, mat) in enumerate(
        (
            (-0.88, -0.34, mats["wood_deep"]),
            (0.88, -0.28, mats["wood_light"]),
        ),
        1,
    ):
        kit.add_beam(
            f"Stool_Bark_Ridge_{index}",
            (-HALF_LENGTH * 0.84, across * LOG_R, LOG_Z + up * LOG_R),
            (HALF_LENGTH * 0.84, across * TIP_R, LOG_Z + up * TIP_R),
            0.028,
            mat,
            root,
            objects,
            vertices=6,
        )

    # Both ends are saw cuts: a pale face with the darker heartwood inside it.
    for side, x, end_radius in (("A", -HALF_LENGTH, LOG_R), ("B", HALF_LENGTH, TIP_R)):
        direction = 1.0 if x > 0 else -1.0
        kit.add_cylinder(
            f"Stool_Cut_{side}",
            (x + direction * 0.006, 0.0, LOG_Z),
            end_radius * 0.97,
            0.014,
            mats["cut"],
            root,
            objects,
            vertices=12,
            rotation=(0, math.pi / 2, 0),
        )
        kit.add_cylinder(
            f"Stool_Heartwood_{side}",
            (x + direction * 0.014, 0.0, LOG_Z),
            end_radius * 0.42,
            0.010,
            mats["heart"],
            root,
            objects,
            vertices=10,
            rotation=(0, math.pi / 2, 0),
        )

    # Two chocks across the underside. A log left on sand rolls; these are what
    # a person actually wedges under it, and they carry the whole prop's weight
    # visually so the log is not floating on a shadow.
    for index, x in enumerate((-0.30, 0.30), 1):
        kit.add_beam(
            f"Stool_Chock_{index}",
            (x, -0.155, 0.062),
            (x, 0.155, 0.062),
            0.070,
            mats["wood_deep"],
            root,
            objects,
            vertices=8,
        )

    # A knot on one flank and moss at the shaded end: the two marks that stop
    # a turned cylinder from reading as machined.
    kit.add_cylinder(
        "Stool_Knot",
        (0.16, -LOG_R * 0.86, LOG_Z + 0.045),
        0.042,
        0.026,
        mats["wood_deep"],
        root,
        objects,
        vertices=8,
        rotation=(math.pi / 2, 0, 0),
    )
    kit.add_ico(
        "Stool_Moss",
        (-HALF_LENGTH * 0.70, LOG_R * 0.74, LOG_Z + LOG_R * 0.20),
        (0.13, 0.024, 0.075),
        mats["moss"],
        root,
        objects,
        irregularity=0.16,
    )
    kit.add_ico(
        "Stool_Moss_Foot",
        (HALF_LENGTH * 0.62, -0.17, 0.016),
        (0.10, 0.055, 0.014),
        mats["moss"],
        root,
        objects,
        irregularity=0.18,
    )

    # One seat, in the middle of the log. A stool has no backrest, so the
    # navigator walks up to the front, turns, and sits facing back out — the
    # same way the benches are entered, and why the approach is at -Y.
    sockets = (
        kit.add_socket(
            "SeatSocket_Seat",
            (0.0, 0.0, SEAT_Z),
            root,
            slot_id="seat",
            purpose="seat",
        ),
        kit.add_socket(
            "SeatApproach_Seat",
            (0.0, -0.780, 0.0),
            root,
            slot_id="seat",
            purpose="approach",
        ),
    )

    finish("log_stool", root, objects, sockets)


build_log_stool()
print(f"LOG_STOOL_COMPLETE=1 SEAT_Z={SEAT_Z}")
