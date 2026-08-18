"""Build the seaside gramophone: a small horn player for the Home Island.

Sized against the navigator like the mailbox: one navigator is about 0.95
units, so this tops out near 0.43 and reads as a tabletop machine set down on
the sand rather than a floor cabinet. Shipped at a default scale of 1.0.

The palette stays on the coast: a driftwood cabinet, a cream platter, one
seafoam pinstripe, and the coral horn taking the whole accent budget — the horn
is the silhouette, so nothing else competes with it.
"""

from __future__ import annotations

import math
import os
import shutil
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Vector


os.environ["KEELMIRA_ASSET_IDS"] = "__seaside_gramophone_helpers_only__"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_home_island_asset_set_02 as kit  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "Landfall/Resources"


def finish(asset_id: str, root: bpy.types.Object, objects: list[bpy.types.Object]) -> None:
    root["integration_status"] = "home_island_placeable"
    kit.export_asset(asset_id, root, objects)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(kit.READY_DIR / f"{asset_id}.usdz", RUNTIME_DIR / f"{asset_id}.usdz")


def orient(obj: bpy.types.Object, direction: Vector) -> None:
    """Point an object's local +Z down `direction`, the way add_beam does."""
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")


def gramophone_materials() -> dict[str, bpy.types.Material]:
    return {
        "wood": kit.material("LF_GramophoneWood", "#9C7A54", 0.94),
        "wood_dark": kit.material("LF_GramophoneWoodDark", "#5E4630", 0.96),
        "horn": kit.material("LF_GramophoneHorn", "#E2795C", 0.86),
        "platter": kit.material("LF_GramophonePlatter", "#F1E4CC", 0.90),
        "record": kit.material("LF_GramophoneRecord", "#2C4A46", 0.84),
        "trim": kit.material("LF_GramophoneTrim", "#5FAA9C", 0.90),
        "sand": kit.material("LF_GramophoneSand", "#C9B489", 0.98),
    }


def build_seaside_gramophone() -> None:
    kit.reset_scene()
    root = kit.make_root("seaside_gramophone", "Seaside_Gramophone", "small")
    objects: list[bpy.types.Object] = []
    mats = gramophone_materials()

    # The same shallow drift the mailbox and parasol use, so the cabinet reads
    # as set down on the beach instead of stabbed into the terrain.
    kit.add_cone("Gramophone_Sand", (0, 0, 0.012), 0.180, 0.138, 0.024, mats["sand"], root, objects, vertices=14)

    # Cabinet: a wide, low box on a slightly wider plinth. Keeping it squat
    # leaves the horn as the tallest thing in the silhouette.
    kit.add_box("Gramophone_Plinth", (0, 0, 0.034), (0.244, 0.212, 0.024), mats["wood_dark"], root, objects, bevel=0.008)
    kit.add_box("Gramophone_Body", (0, 0, 0.098), (0.220, 0.192, 0.104), mats["wood"], root, objects, bevel=0.012)
    # One seafoam pinstripe under the lid, the same trim trick as the mailbox
    # eave: without it the body and the top plate melt into one wooden block.
    kit.add_box("Gramophone_Pinstripe", (0, 0, 0.142), (0.226, 0.198, 0.010), mats["trim"], root, objects, bevel=0.003)
    kit.add_box("Gramophone_Top", (0, 0, 0.160), (0.238, 0.208, 0.020), mats["wood_dark"], root, objects, bevel=0.006)

    # Turntable. The cream platter is a touch wider than the record so a ring of
    # light stays visible around the dark disc from every angle.
    kit.add_cylinder("Gramophone_Platter", (0, 0, 0.177), 0.070, 0.014, mats["platter"], root, objects, vertices=18)
    kit.add_cylinder("Gramophone_Record", (0, 0, 0.187), 0.064, 0.006, mats["record"], root, objects, vertices=18)
    kit.add_cylinder("Gramophone_Label", (0, 0, 0.191), 0.021, 0.004, mats["horn"], root, objects, vertices=12)

    # Horn, rising from the back right corner and opening toward the front
    # (-Y), so the prop faces whoever placed it.
    kit.add_cylinder("Gramophone_Horn_Mount", (0.082, 0.062, 0.180), 0.022, 0.026, mats["wood_dark"], root, objects, vertices=10)
    kit.add_beam(
        "Gramophone_Horn_Neck",
        (0.082, 0.062, 0.190),
        (0.066, 0.040, 0.250),
        0.014,
        mats["wood_dark"],
        root,
        objects,
        vertices=8,
        end_radius=0.021,
    )

    bell_start = Vector((0.066, 0.040, 0.248))
    bell_end = Vector((0.006, -0.078, 0.344))
    bell_axis = (bell_end - bell_start).normalized()
    kit.add_beam(
        "Gramophone_Horn_Bell",
        tuple(bell_start),
        tuple(bell_end),
        0.026,
        mats["horn"],
        root,
        objects,
        vertices=16,
        end_radius=0.100,
    )
    # The cone is capped, so the mouth would otherwise be a flat coral disc. A
    # dark disc set just proud of that cap turns it back into an opening, and a
    # thin torus gives the rim the thickness a bell needs.
    mouth = kit.add_cylinder(
        "Gramophone_Horn_Mouth",
        tuple(bell_end + bell_axis * 0.007),
        0.092,
        0.005,
        mats["record"],
        root,
        objects,
        vertices=16,
    )
    orient(mouth, bell_axis)
    rim = kit.add_torus(
        "Gramophone_Horn_Rim",
        tuple(bell_end),
        0.100,
        0.008,
        mats["horn"],
        root,
        objects,
        major_segments=16,
        minor_segments=4,
    )
    orient(rim, bell_axis)

    # Tonearm: pivots beside the horn mount and reaches the record's outer edge,
    # where a needle would actually sit at the start of a side.
    kit.add_cylinder("Gramophone_Arm_Pivot", (0.078, 0.042, 0.178), 0.013, 0.018, mats["wood_dark"], root, objects, vertices=10)
    kit.add_beam(
        "Gramophone_Arm",
        (0.078, 0.042, 0.186),
        (0.012, -0.012, 0.198),
        0.006,
        mats["wood_dark"],
        root,
        objects,
        vertices=6,
    )
    kit.add_box("Gramophone_Arm_Head", (0.008, -0.016, 0.194), (0.022, 0.018, 0.012), mats["horn"], root, objects, bevel=0.003)

    # Crank on the right cheek. Two beams and a knob is enough to say "wind me"
    # at this size; a real handle loop would just read as noise.
    kit.add_beam("Gramophone_Crank_Shaft", (0.112, 0.030, 0.104), (0.150, 0.030, 0.104), 0.008, mats["wood_dark"], root, objects, vertices=6)
    kit.add_beam("Gramophone_Crank_Arm", (0.150, 0.030, 0.104), (0.150, 0.030, 0.068), 0.007, mats["wood_dark"], root, objects, vertices=6)
    kit.add_ico("Gramophone_Crank_Knob", (0.150, 0.030, 0.060), (0.014, 0.014, 0.017), mats["wood"], root, objects, irregularity=0.06)

    # One spare record propped against the cabinet front — the same
    # one-detail rule as the mailbox's shell. Two would read as clutter. It sits
    # forward rather than beside the cabinet so it never reads as a shadow
    # leaking out from behind the box.
    spare_rotation = (math.radians(72), 0.0, 0.0)
    spare_location = Vector((-0.060, -0.118, 0.040))
    # It leans back onto the front panel, so its label rides on the face turned
    # toward the beach. Kept small on purpose: at the first size it matched the
    # cabinet's own width and read as a cart wheel rather than a record.
    spare_normal = Euler(spare_rotation, "XYZ").to_matrix() @ Vector((0, 0, 1))
    kit.add_cylinder(
        "Gramophone_Spare_Record",
        tuple(spare_location),
        0.040,
        0.007,
        mats["record"],
        root,
        objects,
        vertices=18,
        rotation=spare_rotation,
    )
    kit.add_cylinder(
        "Gramophone_Spare_Label",
        tuple(spare_location + spare_normal * 0.006),
        0.013,
        0.004,
        mats["horn"],
        root,
        objects,
        vertices=12,
        rotation=spare_rotation,
    )

    finish("seaside_gramophone", root, objects)


build_seaside_gramophone()
print("SEASIDE_GRAMOPHONE_COMPLETE=1")
