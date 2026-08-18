"""Build the seaside mailbox: a small letter post for the Home Island.

Sized against the navigator like the beach set: one navigator is about 0.95
units, so the mailbox tops out just under chest height and reads as a friendly
waist-high prop rather than street furniture. Shipped at a default scale of 1.0.

The palette is the coast rather than the postal service: a seafoam body, a
cream barrel roof, a driftwood post, and one coral flag for the whole accent
budget.
"""

from __future__ import annotations

import math
import os
import shutil
import sys
from pathlib import Path

import bpy


os.environ["KEELMIRA_ASSET_IDS"] = "__seaside_mailbox_helpers_only__"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_home_island_asset_set_02 as kit  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "Landfall/Resources"


def finish(asset_id: str, root: bpy.types.Object, objects: list[bpy.types.Object]) -> None:
    root["integration_status"] = "home_island_placeable"
    kit.export_asset(asset_id, root, objects)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(kit.READY_DIR / f"{asset_id}.usdz", RUNTIME_DIR / f"{asset_id}.usdz")


def mailbox_materials() -> dict[str, bpy.types.Material]:
    return {
        "body": kit.material("LF_MailboxBody", "#5FAA9C", 0.90),
        "body_shade": kit.material("LF_MailboxBodyShade", "#46867E", 0.92),
        "roof": kit.material("LF_MailboxRoof", "#F2E8D2", 0.88),
        "post": kit.material("LF_MailboxPost", "#8A6A47", 0.94),
        "post_dark": kit.material("LF_MailboxPostDark", "#5E4630", 0.96),
        "slot": kit.material("LF_MailboxSlot", "#2C4A46", 0.86),
        "flag": kit.material("LF_MailboxFlag", "#E2795C", 0.90, double_sided=True),
        "trim": kit.material("LF_MailboxTrim", "#E2795C", 0.90),
        "letter": kit.material("LF_MailboxLetter", "#F8F1E2", 0.92),
        "sand": kit.material("LF_MailboxSand", "#C9B489", 0.98),
        "shell": kit.material("LF_MailboxShell", "#F1E4CC", 0.88),
    }


def build_seaside_mailbox() -> None:
    kit.reset_scene()
    root = kit.make_root("seaside_mailbox", "Seaside_Mailbox", "small")
    objects: list[bpy.types.Object] = []
    mats = mailbox_materials()

    # Chunky on purpose: a short, thick post under a tall box keeps the prop
    # cute rather than leggy, and leaves the seafoam body — not the cream cap —
    # holding most of the silhouette.
    half_width = 0.115
    depth = 0.196
    box_bottom = 0.372
    box_height = 0.208
    box_top = box_bottom + box_height

    # A shallow drift of sand hides the joint between post and ground, the same
    # trick the parasol uses so the prop never looks stabbed into the terrain.
    kit.add_cone("Mailbox_Sand", (0, 0, 0.013), 0.150, 0.118, 0.026, mats["sand"], root, objects, vertices=14)

    kit.add_beam("Mailbox_Post", (0, 0, 0.008), (0, 0, box_bottom + 0.02), 0.052, mats["post"], root, objects, vertices=8, end_radius=0.046)
    kit.add_cylinder("Mailbox_Post_Collar", (0, 0, 0.112), 0.060, 0.030, mats["post_dark"], root, objects, vertices=8)

    # Cap over the post, so the body reads as set down on it rather than fused.
    kit.add_box("Mailbox_Base_Plate", (0, 0, box_bottom - 0.014), (0.262, 0.234, 0.028), mats["post_dark"], root, objects, bevel=0.008)

    kit.add_box("Mailbox_Body", (0, 0, box_bottom + box_height / 2), (half_width * 2, depth, box_height), mats["body"], root, objects, bevel=0.014)
    # The cream barrel is centred on the box's top face, so exactly its upper
    # half shows: the round cap that makes the prop read as a mailbox. The
    # cylinder is already capped at both ends, so no end discs are needed.
    roof = kit.add_cylinder(
        "Mailbox_Roof",
        (0, 0, box_top),
        half_width,
        depth,
        mats["roof"],
        root,
        objects,
        vertices=20,
        rotation=(math.radians(90), 0, 0),
    )
    # Keep only the half above the roofline. Left whole, the barrel's lower half
    # lies flat against the box front as a cream disc, which reads as a porthole
    # rather than as a lid.
    for vertex in roof.data.vertices:
        vertex.co.y = max(vertex.co.y, 0.0)
    roof.data.update()

    # A slim coral eave separates cream roof from seafoam body — without it the
    # round cap and the box front melt into one shape from the front.
    kit.add_box("Mailbox_Eave", (0, 0, box_top), (half_width * 2 + 0.016, depth + 0.012, 0.014), mats["trim"], root, objects, bevel=0.004)

    front = -depth / 2 - 0.005
    kit.add_box("Mailbox_Slot", (0, front, box_top + 0.036), (0.130, 0.014, 0.024), mats["slot"], root, objects, bevel=0.004)
    letter = kit.add_box("Mailbox_Letter", (0, front - 0.022, box_top + 0.066), (0.096, 0.008, 0.052), mats["letter"], root, objects, bevel=0.004)
    letter.rotation_euler = (math.radians(-16), 0, 0)
    kit.add_box("Mailbox_Door_Line", (0, front + 0.003, box_bottom + 0.058), (0.150, 0.008, 0.012), mats["body_shade"], root, objects, bevel=0.003)

    # Raised flag: the island's one signal that a letter is waiting.
    staff_x = half_width + 0.022
    kit.add_beam(
        "Mailbox_Flag_Staff",
        (staff_x, 0.028, box_bottom + 0.036),
        (staff_x, 0.028, box_top + 0.106),
        0.009,
        mats["post_dark"],
        root,
        objects,
        vertices=6,
    )
    kit.mesh_object(
        "Mailbox_Flag",
        [
            (staff_x + 0.006, 0.028, box_top + 0.098),
            (staff_x + 0.006, 0.028, box_top + 0.026),
            (staff_x + 0.086, 0.022, box_top + 0.062),
        ],
        [(0, 1, 2)],
        mats["flag"],
        root,
        objects,
    )

    # One small shell on the sand. Two read as litter; none leaves the foot of
    # the post looking like a fence post dropped on the beach.
    kit.add_ico(
        "Mailbox_Shell",
        (0.104, -0.082, 0.026),
        (0.038, 0.030, 0.016),
        mats["shell"],
        root,
        objects,
        irregularity=0.12,
    )

    finish("seaside_mailbox", root, objects)


build_seaside_mailbox()
print("SEASIDE_MAILBOX_COMPLETE=1")
