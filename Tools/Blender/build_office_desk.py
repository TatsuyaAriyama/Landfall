"""Build the desk: a black office desk for the Home Island.

Authored at the same scale as the rest of the small props — one navigator is
about 0.95 units, so a 0.42-high desk meets the navigator at hip height, which
is where a desk meets a person. The top is 1.06 across, three times the width of
the laptop that stands on it.

This is the first prop on the island with a working surface. `HomeIslandSurface`
in `HomeIslandModels.swift` holds the numbers the game needs — the top's height
and its usable rectangle — and they are copied from the constants below. Change
one, change the other.

Black laminate on a steel frame, with a two-drawer pedestal on the right. The
island is driftwood and rope everywhere else; this is deliberately the one thing
on it that came from a shop.
"""

from __future__ import annotations

import math
import os
import shutil
import sys
from pathlib import Path

import bpy


os.environ["KEELMIRA_ASSET_IDS"] = "__office_desk_helpers_only__"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_home_island_asset_set_02 as kit  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "Landfall/Resources"

# The authored envelope. HomeIslandSurface mirrors TOP_Z and the usable span.
TOP_W = 1.060           # across, X
TOP_D = 0.520           # front to back, Y
TOP_T = 0.030
TOP_Z = 0.420           # the working surface, and what a laptop stands on
LEG = 0.048
LEG_X = TOP_W * 0.5 - 0.076
LEG_Y = TOP_D * 0.5 - 0.068
FOOT_H = 0.008


def finish(asset_id: str, root: bpy.types.Object, objects: list[bpy.types.Object], sockets) -> None:
    root["integration_status"] = "home_island_placeable"
    root["surface_top_z"] = TOP_Z
    kit.export_asset(asset_id, root, objects, sockets)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(kit.READY_DIR / f"{asset_id}.usdz", RUNTIME_DIR / f"{asset_id}.usdz")


def desk_materials() -> dict[str, bpy.types.Material]:
    return {
        # Laminate, not lacquer: black that still shows its edge against the
        # island's pale sand instead of reading as a hole in the ground.
        "top": kit.material("LF_DeskTop", "#23272B", 0.52),
        "top_edge": kit.material("LF_DeskTopEdge", "#15181B", 0.58),
        "frame": kit.material("LF_DeskFrame", "#2E3339", 0.56, metallic=0.30),
        "frame_dark": kit.material("LF_DeskFrameDark", "#1B1F23", 0.60, metallic=0.26),
        "foot": kit.material("LF_DeskFoot", "#101315", 0.72),
        "panel": kit.material("LF_DeskPanel", "#20252A", 0.62),
        "drawer": kit.material("LF_DeskDrawer", "#262B31", 0.56),
        "handle": kit.material("LF_DeskHandle", "#98A0A7", 0.40, metallic=0.42),
        "grommet": kit.material("LF_DeskGrommet", "#0E1113", 0.66),
    }


def build_office_desk() -> None:
    kit.reset_scene()
    root = kit.make_root("office_desk", "Office_Desk", "medium")
    root["surface_schema"] = 1
    objects: list[bpy.types.Object] = []
    mats = desk_materials()

    # The top, with a darker band under its lip. One board reads as a slab; the
    # band is what makes it a laminated top with an edge.
    kit.add_box(
        "Desk_Top",
        (0.0, 0.0, TOP_Z - TOP_T * 0.5),
        (TOP_W, TOP_D, TOP_T),
        mats["top"],
        root,
        objects,
        bevel=0.008,
    )
    kit.add_box(
        "Desk_Top_Edge",
        (0.0, 0.0, TOP_Z - TOP_T - 0.006),
        (TOP_W - 0.012, TOP_D - 0.012, 0.012),
        mats["top_edge"],
        root,
        objects,
        bevel=0.004,
    )
    # A cable grommet at the back, so the top is not a blank rectangle from the
    # island's overhead-ish camera.
    kit.add_cylinder(
        "Desk_Grommet",
        (-0.300, TOP_D * 0.5 - 0.085, TOP_Z - 0.004),
        0.032,
        0.010,
        mats["grommet"],
        root,
        objects,
        vertices=12,
    )

    # Steel frame.
    leg_top = TOP_Z - TOP_T - 0.014
    leg_bottom = FOOT_H
    for index, (x, y) in enumerate(
        ((-LEG_X, -LEG_Y), (LEG_X, -LEG_Y), (-LEG_X, LEG_Y), (LEG_X, LEG_Y)), 1
    ):
        kit.add_box(
            f"Desk_Leg_{index}",
            (x, y, (leg_top + leg_bottom) * 0.5),
            (LEG, LEG, leg_top - leg_bottom),
            mats["frame"],
            root,
            objects,
            bevel=0.005,
        )
        kit.add_box(
            f"Desk_Foot_{index}",
            (x, y, FOOT_H * 0.5),
            (LEG + 0.012, LEG + 0.012, FOOT_H),
            mats["foot"],
            root,
            objects,
            bevel=0.003,
        )

    # Side rails and the back beam: the frame that stops four legs from reading
    # as four unrelated posts.
    for index, x in enumerate((-LEG_X, LEG_X), 1):
        kit.add_box(
            f"Desk_Side_Rail_{index}",
            (x, 0.0, leg_top - 0.036),
            (LEG - 0.008, LEG_Y * 2, 0.030),
            mats["frame_dark"],
            root,
            objects,
            bevel=0.004,
        )
    kit.add_box(
        "Desk_Back_Beam",
        (0.0, LEG_Y, leg_top - 0.036),
        (LEG_X * 2, LEG - 0.008, 0.030),
        mats["frame_dark"],
        root,
        objects,
        bevel=0.004,
    )
    # Modesty panel. It also gives the desk a solid read from behind, which is
    # the angle the island camera spends most of its time at.
    kit.add_box(
        "Desk_Modesty_Panel",
        (0.0, LEG_Y - 0.012, 0.268),
        (LEG_X * 2 - 0.030, 0.016, 0.150),
        mats["panel"],
        root,
        objects,
        bevel=0.004,
    )

    # Two-drawer pedestal on the right, clear of both right legs.
    pedestal_top = leg_top - 0.050
    pedestal_h = pedestal_top - 0.070
    kit.add_box(
        "Desk_Pedestal",
        (0.290, 0.0, pedestal_top - pedestal_h * 0.5),
        (0.262, TOP_D - 0.108, pedestal_h),
        mats["drawer"],
        root,
        objects,
        bevel=0.006,
    )
    for index, offset in enumerate((0.0, 1.0), 1):
        face_z = pedestal_top - 0.052 - offset * (pedestal_h * 0.48)
        kit.add_box(
            f"Desk_Drawer_Face_{index}",
            (0.290, -(TOP_D - 0.108) * 0.5 - 0.006, face_z),
            (0.240, 0.014, pedestal_h * 0.40),
            mats["frame_dark"],
            root,
            objects,
            bevel=0.005,
        )
        kit.add_box(
            f"Desk_Drawer_Handle_{index}",
            (0.290, -(TOP_D - 0.108) * 0.5 - 0.016, face_z + pedestal_h * 0.12),
            (0.120, 0.012, 0.011),
            mats["handle"],
            root,
            objects,
            bevel=0.004,
        )

    # The socket the game reads for anything standing on the desk. Its purpose
    # is "surface" rather than "seat": a navigator never sits here.
    top_socket = kit.add_socket(
        "SurfaceSocket_Top",
        (-0.150, 0.0, TOP_Z),
        root,
        slot_id="top",
        purpose="surface",
    )

    finish("office_desk", root, objects, (top_socket,))


build_office_desk()
print("OFFICE_DESK_COMPLETE=1")
