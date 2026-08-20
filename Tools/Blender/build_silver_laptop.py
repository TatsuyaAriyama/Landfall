"""Build the silver laptop: an aluminium notebook, open on the sand.

Sized against the navigator like the rest of the small props — one navigator is
about 0.95 units, so a 0.33-wide machine standing 0.24 tall reads as a laptop
somebody carried down to the beach rather than as a desk. The stacked books are
0.25 across; this sits a little wider, which is the difference a player expects
between a book and the thing they work on.

The lid carries the phoenix instead of a maker's mark. It is the same silhouette
the app draws for the player's own icon — `PhoenixShape` in
`Views/Wrapped/ArchetypeSymbols.swift` — taken from `phoenix_emblem.py`, the one
transcription of those control points, so the emblem on the island and the
emblem on the player card are one shape, not two drawings that happen to
resemble each other. Coral body, midnight eye, as everywhere else the bird
appears.

The screen is not black. It holds the horizon: night sky above, harbour water
below, which is what the island itself looks like at the hour most of this app
gets used.
"""

from __future__ import annotations

import math
import os
import shutil
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


os.environ["KEELMIRA_ASSET_IDS"] = "__silver_laptop_helpers_only__"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_home_island_asset_set_02 as kit  # noqa: E402
import phoenix_emblem  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "Landfall/Resources"

# The authored envelope. Every other number below is derived from these, so the
# machine can be resized in one place without the keyboard drifting out of its
# well or the emblem sliding off the lid.
BASE_W = 0.330          # across, X
BASE_D = 0.230          # front to back, Y
BASE_H = 0.018
FOOT_H = 0.003
LID_LENGTH = 0.212
LID_T = 0.011
LID_GAP = 0.006         # hinge barrel to the bottom edge of the lid
LEAN = math.radians(13)  # past vertical, the angle a lid actually rests at

HINGE = Vector((0.0, BASE_D * 0.5 - 0.007, FOOT_H + BASE_H + 0.0065))
LID_CENTRE = HINGE + Vector((
    0.0,
    math.sin(LEAN) * (LID_GAP + LID_LENGTH * 0.5),
    math.cos(LEAN) * (LID_GAP + LID_LENGTH * 0.5),
))

PHOENIX_HEIGHT = 0.078       # head to tail on the lid


def finish(asset_id: str, root: bpy.types.Object, objects: list[bpy.types.Object]) -> None:
    root["integration_status"] = "home_island_placeable"
    kit.export_asset(asset_id, root, objects)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(kit.READY_DIR / f"{asset_id}.usdz", RUNTIME_DIR / f"{asset_id}.usdz")


def laptop_materials() -> dict[str, bpy.types.Material]:
    return {
        # Anodised aluminium: metallic enough to catch the key light, matte
        # enough that it never turns into chrome beside the island's flat props.
        "shell": kit.material("LF_LaptopShell", "#D2D6DA", 0.44, metallic=0.38),
        "shell_light": kit.material("LF_LaptopShellLight", "#E2E5E8", 0.40, metallic=0.34),
        "shell_shade": kit.material("LF_LaptopShellShade", "#AFB6BC", 0.48, metallic=0.36),
        "seam": kit.material("LF_LaptopSeam", "#8B939A", 0.55, metallic=0.30),
        "hinge": kit.material("LF_LaptopHinge", "#5C646B", 0.52, metallic=0.34),
        "bezel": kit.material("LF_LaptopBezel", "#23272B", 0.38),
        "screen_sky": kit.material("LF_LaptopScreenSky", "#1C3742", 0.30),
        "screen_sea": kit.material("LF_LaptopScreenSea", "#2F7075", 0.28),
        "screen_glow": kit.material("LF_LaptopScreenGlow", "#4E9AA0", 0.26),
        "key_well": kit.material("LF_LaptopKeyWell", "#1D2124", 0.62),
        "key": kit.material("LF_LaptopKey", "#343A3F", 0.66),
        "trackpad": kit.material("LF_LaptopTrackpad", "#C3C9CE", 0.36, metallic=0.26),
        "foot": kit.material("LF_LaptopFoot", "#2A2E32", 0.70),
        "emblem": kit.material("LF_LaptopEmblem", "#F0997B", 0.52),
        "emblem_eye": kit.material("LF_LaptopEmblemEye", "#1A1130", 0.58),
    }


def lid_point(lx: float, ly: float, lz: float) -> tuple[float, float, float]:
    """Lid-local coordinates to world.

    Local X runs across the lid, local Y is its thickness (+Y is the outer face
    the emblem sits on), local Z runs from the hinge to the top edge.
    """
    return (
        lx,
        LID_CENTRE.y + ly * math.cos(LEAN) + lz * math.sin(LEAN),
        LID_CENTRE.z - ly * math.sin(LEAN) + lz * math.cos(LEAN),
    )


def extruded_on_lid(
    name: str,
    outline: list[tuple[float, float]],
    inner_y: float,
    outer_y: float,
    mat: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
) -> bpy.types.Object:
    """A flat closed outline, given thickness and laid onto the tilted lid.

    Built in lid-local coordinates and then carried into place by the object's
    own transform, so the emblem is guaranteed to lie in the lid's plane rather
    than being fitted to it by hand.
    """
    count = len(outline)
    vertices: list[tuple[float, float, float]] = []
    for x, z in outline:
        vertices.append((x, inner_y, z))
    for x, z in outline:
        vertices.append((x, outer_y, z))

    faces: list[tuple[int, ...]] = [
        tuple(range(count)),                                  # inner cap
        tuple(range(2 * count - 1, count - 1, -1)),            # outer cap
    ]
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, nxt + count, index + count))

    obj = kit.mesh_object(name, vertices, faces, mat, root, objects)
    # The caps are authored from a screen-space path whose winding we do not
    # want to reason about; let bmesh point every normal outward instead.
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    obj.rotation_euler = (-LEAN, 0.0, 0.0)
    obj.location = LID_CENTRE
    return obj


def build_base(mats, root, objects) -> None:
    base_z = FOOT_H + BASE_H * 0.5

    # The two shells with a seam between them, which is what makes a slab of
    # aluminium read as a machine that opens.
    kit.add_box(
        "Laptop_Base_Body",
        (0.0, 0.0, base_z),
        (BASE_W, BASE_D, BASE_H),
        mats["shell"],
        root,
        objects,
        bevel=0.0055,
    )
    kit.add_box(
        "Laptop_Base_Seam",
        (0.0, 0.0, FOOT_H + BASE_H * 0.42),
        (BASE_W + 0.0015, BASE_D + 0.0015, 0.0022),
        mats["seam"],
        root,
        objects,
        bevel=0.0006,
    )
    kit.add_box(
        "Laptop_Base_Underside",
        (0.0, 0.0, FOOT_H + 0.0035),
        (BASE_W - 0.014, BASE_D - 0.014, 0.005),
        mats["shell_shade"],
        root,
        objects,
        bevel=0.0018,
    )
    deck_top = FOOT_H + BASE_H
    kit.add_box(
        "Laptop_Base_Deck",
        (0.0, 0.0, deck_top - 0.001),
        (BASE_W - 0.010, BASE_D - 0.010, 0.002),
        mats["shell_light"],
        root,
        objects,
        bevel=0.0012,
    )

    for index, (x, y) in enumerate(
        ((-0.138, -0.094), (0.138, -0.094), (-0.138, 0.094), (0.138, 0.094)), 1
    ):
        kit.add_cylinder(
            f"Laptop_Foot_{index}",
            (x, y, FOOT_H * 0.5),
            0.0105,
            FOOT_H,
            mats["foot"],
            root,
            objects,
            vertices=8,
        )

    # Keyboard well, then the keys standing in it. Individual keys cost a few
    # hundred triangles and are the only thing that tells a player, at the
    # island's low camera, that this is a laptop and not a closed case.
    well_top = deck_top + 0.0005
    kit.add_box(
        "Laptop_Key_Well",
        (0.0, 0.038, well_top - 0.00225),
        (0.278, 0.120, 0.0045),
        mats["key_well"],
        root,
        objects,
        bevel=0.0010,
    )
    key_z = well_top + 0.0012
    for row, y in enumerate((0.086, 0.062, 0.038, 0.014), 1):
        for column in range(11):
            kit.add_box(
                f"Laptop_Key_{row:02}_{column:02}",
                (-0.1276 + column * 0.02534, y, key_z),
                (0.0224, 0.0172, 0.0032),
                mats["key"],
                root,
                objects,
                bevel=0.0005,
            )
    kit.add_box(
        "Laptop_Key_Space",
        (0.0, -0.010, key_z),
        (0.132, 0.0172, 0.0032),
        mats["key"],
        root,
        objects,
        bevel=0.0005,
    )
    for index, x in enumerate((-0.1035, 0.1035), 1):
        kit.add_box(
            f"Laptop_Key_Space_Side_{index}",
            (x, -0.010, key_z),
            (0.0510, 0.0172, 0.0032),
            mats["key"],
            root,
            objects,
            bevel=0.0005,
        )

    kit.add_box(
        "Laptop_Trackpad_Groove",
        (0.0, -0.066, deck_top - 0.0004),
        (0.112, 0.076, 0.0016),
        mats["seam"],
        root,
        objects,
        bevel=0.0008,
    )
    kit.add_box(
        "Laptop_Trackpad",
        (0.0, -0.066, deck_top + 0.0004),
        (0.104, 0.068, 0.0018),
        mats["trackpad"],
        root,
        objects,
        bevel=0.0010,
    )

    kit.add_cylinder(
        "Laptop_Hinge_Barrel",
        tuple(HINGE),
        0.0072,
        0.288,
        mats["hinge"],
        root,
        objects,
        vertices=10,
        rotation=(0.0, math.pi * 0.5, 0.0),
    )


def build_lid(mats, root, objects) -> None:
    lid_rotation = (-LEAN, 0.0, 0.0)

    kit.add_box(
        "Laptop_Lid_Shell",
        tuple(LID_CENTRE),
        (BASE_W, LID_T, LID_LENGTH),
        mats["shell"],
        root,
        objects,
        rotation=lid_rotation,
        bevel=0.0045,
    )
    kit.add_box(
        "Laptop_Lid_Bezel",
        lid_point(0.0, -0.0072, 0.0),
        (0.316, 0.0032, 0.199),
        mats["bezel"],
        root,
        objects,
        rotation=lid_rotation,
        bevel=0.0016,
    )
    # The screen holds the island's own horizon rather than a dead black panel.
    kit.add_box(
        "Laptop_Screen_Sky",
        lid_point(0.0, -0.0091, 0.004),
        (0.296, 0.0018, 0.178),
        mats["screen_sky"],
        root,
        objects,
        rotation=lid_rotation,
        bevel=0.0007,
    )
    kit.add_box(
        "Laptop_Screen_Sea",
        lid_point(0.0, -0.0101, -0.043),
        (0.296, 0.0014, 0.076),
        mats["screen_sea"],
        root,
        objects,
        rotation=lid_rotation,
        bevel=0.0006,
    )
    kit.add_box(
        "Laptop_Screen_Glow",
        lid_point(0.0, -0.0104, -0.0035),
        (0.296, 0.0010, 0.0055),
        mats["screen_glow"],
        root,
        objects,
        rotation=lid_rotation,
        bevel=0.0004,
    )
    # A camera dot in the chin above the picture, and the lid's bottom lip.
    kit.add_cylinder(
        "Laptop_Lid_Camera",
        lid_point(0.0, -0.0101, 0.0935),
        0.0034,
        0.0016,
        mats["screen_glow"],
        root,
        objects,
        vertices=8,
        rotation=(math.pi * 0.5 - LEAN, 0.0, 0.0),
    )
    kit.add_box(
        "Laptop_Lid_Lip",
        lid_point(0.0, 0.0, -LID_LENGTH * 0.5 + 0.004),
        (BASE_W - 0.012, LID_T + 0.0018, 0.008),
        mats["shell_shade"],
        root,
        objects,
        rotation=lid_rotation,
        bevel=0.0018,
    )

    # The mark. Not an apple.
    outer = LID_T * 0.5
    extruded_on_lid(
        "Laptop_Lid_Phoenix",
        phoenix_emblem.outline(PHOENIX_HEIGHT),
        outer + 0.0002,
        outer + 0.0019,
        mats["emblem"],
        root,
        objects,
    )
    extruded_on_lid(
        "Laptop_Lid_Phoenix_Eye",
        phoenix_emblem.eye_circle(PHOENIX_HEIGHT),
        outer + 0.0019,
        outer + 0.0028,
        mats["emblem_eye"],
        root,
        objects,
    )


def build_silver_laptop() -> None:
    kit.reset_scene()
    root = kit.make_root("silver_laptop", "Silver_Laptop", "small")
    objects: list[bpy.types.Object] = []
    mats = laptop_materials()

    build_base(mats, root, objects)
    build_lid(mats, root, objects)

    finish("silver_laptop", root, objects)


build_silver_laptop()
print("SILVER_LAPTOP_COMPLETE=1")
