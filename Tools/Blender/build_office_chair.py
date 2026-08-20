"""Build the chair: the task chair that belongs to the desk.

Sized from `build_office_desk.py` rather than invented separately. The desk's
top stands at 0.420; this seat stands at 0.250, so the top clears the seat by
0.170 — the same drop a real desk has over a real chair, read against the same
navigator who is about 0.95 tall. The seat is 0.400 across against the desk's
1.060, which is the proportion one chair has to one desk.

Same palette as the desk, down to the hex values: black laminate over a steel
frame, with the silver only on the small hardware. Standing them side by side
should read as one bought set, not two black props. The desk's pink is matched
the same way, so ``office_chair_pink`` pairs with ``office_desk_pink`` — only
the palette differs, every dimension and socket below is shared.

The chair carries one seat socket. It faces -Y like every other seated prop,
and its approach socket is behind the backrest: a chair pulled up to a desk is
entered from the open side, and the navigator ends up facing the desk with the
backrest at their back. `HomeIslandAssetCatalog.contactSlots` pairs that with
`facesAwayFromApproach`.
"""

from __future__ import annotations

import math
import os
import shutil
import sys
from pathlib import Path

import bpy


os.environ["KEELMIRA_ASSET_IDS"] = "__office_chair_helpers_only__"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_home_island_asset_set_02 as kit  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "Landfall/Resources"

# The authored envelope. The desk's own numbers are quoted where they set one.
DESK_TOP_Z = 0.420      # build_office_desk.py TOP_Z
SEAT_Z = 0.250          # the seat surface: 0.170 of knee room under the desk
SEAT_W = 0.400
SEAT_D = 0.380
SEAT_T = 0.062
BASE_R = 0.270          # star radius, just inside the desk's 0.260 half-depth
CASTER_R = 0.030
SPOKES = 5
BACK_TILT = math.radians(-13)  # negative leans the top back, as on the desk


def finish(asset_id: str, root: bpy.types.Object, objects: list[bpy.types.Object], sockets) -> None:
    root["integration_status"] = "home_island_placeable"
    root["seat_capacity"] = 1
    root["seat_socket_schema"] = 1
    kit.export_asset(asset_id, root, objects, sockets)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(kit.READY_DIR / f"{asset_id}.usdz", RUNTIME_DIR / f"{asset_id}.usdz")


# One palette per colour, taken from the desk of the same colour. A chair is
# upholstered rather than laminated, so only the roughness moves.
PALETTES = {
    "office_chair": {
        "suffix": "",
        "pad": "#23272B",
        "pad_edge": "#15181B",
        "frame": "#2E3339",
        "frame_dark": "#1B1F23",
        "caster": "#101315",
        "lever": "#98A0A7",
    },
    "office_chair_pink": {
        "suffix": "Pink",
        # office_desk_pink's top and frame, so the pair reads as one set.
        "pad": "#EE9DB4",
        "pad_edge": "#C8788F",
        "frame": "#8A6A74",
        "frame_dark": "#6B4F58",
        "caster": "#4A353C",
        "lever": "#F1DCE2",
    },
}


def chair_materials(asset_id: str) -> dict[str, bpy.types.Material]:
    palette = PALETTES[asset_id]
    suffix = palette["suffix"]
    return {
        key: kit.material(f"LF_Chair{name}{suffix}", palette[key], roughness, metallic=metallic)
        for key, name, roughness, metallic in (
            ("pad", "Pad", 0.68, 0.0),
            ("pad_edge", "PadEdge", 0.62, 0.0),
            ("frame", "Frame", 0.56, 0.30),
            ("frame_dark", "FrameDark", 0.60, 0.26),
            ("caster", "Caster", 0.72, 0.0),
            ("lever", "Lever", 0.40, 0.42),
        )
    }


def build_office_chair(asset_id: str = "office_chair") -> None:
    kit.reset_scene()
    root = kit.make_root(asset_id, asset_id.title(), "small")
    objects: list[bpy.types.Object] = []
    mats = chair_materials(asset_id)

    # The seat: a pad over a thin shell, the same two-layer trick the desk top
    # uses to stop a single box from reading as a slab.
    kit.add_box(
        "Chair_Seat_Pad",
        (0.0, 0.0, SEAT_Z - SEAT_T * 0.5),
        (SEAT_W, SEAT_D, SEAT_T),
        mats["pad"],
        root,
        objects,
        bevel=0.016,
    )
    kit.add_box(
        "Chair_Seat_Shell",
        (0.0, 0.0, SEAT_Z - SEAT_T - 0.010),
        (SEAT_W - 0.026, SEAT_D - 0.026, 0.020),
        mats["pad_edge"],
        root,
        objects,
        bevel=0.006,
    )
    # The mechanism housing under the seat, and the tilt lever on the right.
    kit.add_box(
        "Chair_Mechanism",
        (0.0, 0.010, SEAT_Z - SEAT_T - 0.044),
        (0.170, 0.190, 0.050),
        mats["frame_dark"],
        root,
        objects,
        bevel=0.006,
    )
    kit.add_cylinder(
        "Chair_Tilt_Lever",
        (0.128, -0.052, SEAT_Z - SEAT_T - 0.040),
        0.011,
        0.110,
        mats["lever"],
        root,
        objects,
        vertices=8,
        rotation=(math.pi / 2, 0, 0),
    )

    # Gas column: sleeve over cylinder, so it reads as height-adjustable.
    kit.add_cylinder(
        "Chair_Column",
        (0.0, 0.0, 0.152),
        0.030,
        0.150,
        mats["frame"],
        root,
        objects,
        vertices=10,
    )
    kit.add_cylinder(
        "Chair_Column_Sleeve",
        (0.0, 0.0, 0.098),
        0.042,
        0.096,
        mats["frame_dark"],
        root,
        objects,
        vertices=10,
    )
    kit.add_cylinder(
        "Chair_Base_Hub",
        (0.0, 0.0, 0.058),
        0.068,
        0.044,
        mats["frame_dark"],
        root,
        objects,
        vertices=12,
    )

    # Five-star base. Each spoke is authored along +Y and turned into place, so
    # the casters land on a circle of radius BASE_R.
    spoke_length = BASE_R - 0.030
    for index in range(SPOKES):
        angle = math.tau * index / SPOKES
        radius = spoke_length * 0.5 + 0.026
        kit.add_box(
            f"Chair_Base_Spoke_{index + 1}",
            (
                math.cos(angle) * radius,
                math.sin(angle) * radius,
                0.052,
            ),
            (0.052, spoke_length, 0.030),
            mats["frame_dark"],
            root,
            objects,
            rotation=(0, 0, angle - math.pi / 2),
            bevel=0.006,
        )
        # A caster, not a puck: the wheel's axle lies across the spoke, which
        # is the detail that tells the island this chair rolls.
        kit.add_cylinder(
            f"Chair_Caster_{index + 1}",
            (
                math.cos(angle) * BASE_R,
                math.sin(angle) * BASE_R,
                CASTER_R,
            ),
            CASTER_R,
            0.026,
            mats["caster"],
            root,
            objects,
            vertices=10,
            rotation=(math.pi / 2, 0, angle - math.pi / 2),
        )

    # Backrest: a spine off the back of the seat carrying a padded panel that
    # leans back by BACK_TILT. Its top lands at about 0.60 — head height for a
    # seated navigator, and well clear of the desk it is pushed under.
    kit.add_box(
        "Chair_Back_Spine",
        (0.0, SEAT_D * 0.5 - 0.026, SEAT_Z + 0.058),
        (0.086, 0.052, 0.150),
        mats["frame"],
        root,
        objects,
        rotation=(BACK_TILT, 0, 0),
        bevel=0.008,
    )
    kit.add_box(
        "Chair_Back_Pad",
        (0.0, SEAT_D * 0.5 + 0.012, SEAT_Z + 0.212),
        (0.336, 0.056, 0.250),
        mats["pad"],
        root,
        objects,
        rotation=(BACK_TILT, 0, 0),
        bevel=0.020,
    )
    # The lumbar band: the same darker line the desk carries under its top lip.
    kit.add_box(
        "Chair_Back_Lumbar",
        (0.0, SEAT_D * 0.5 - 0.004, SEAT_Z + 0.112),
        (0.300, 0.048, 0.036),
        mats["pad_edge"],
        root,
        objects,
        rotation=(BACK_TILT, 0, 0),
        bevel=0.008,
    )

    # The seat socket marks the surface a navigator's weight rests on. The
    # approach socket sits behind the backrest: the chair is entered from the
    # open side and left the same way, so a desk in front never blocks sitting.
    sockets = (
        kit.add_socket(
            "SeatSocket_Seat",
            (0.0, 0.010, SEAT_Z),
            root,
            slot_id="seat",
            purpose="seat",
        ),
        kit.add_socket(
            "SeatApproach_Seat",
            (0.0, 0.640, 0.0),
            root,
            slot_id="seat",
            purpose="approach",
        ),
    )

    finish(asset_id, root, objects, sockets)


for chair_id in PALETTES:
    build_office_chair(chair_id)
print(f"OFFICE_CHAIR_COMPLETE={len(PALETTES)} DESK_TOP_Z={DESK_TOP_Z}")
