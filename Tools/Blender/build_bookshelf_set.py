"""Build the reading pair for Home Island: a bookshelf and a stack of books.

Both are authored at their final Home Island size and ship at scale 1.0, the
way the mailbox and the gramophone do. The navigator is about 0.95 units tall,
so the shelf tops out just under their eyeline at 0.93 and the floor stack
reaches an ankle. They share one book palette and one spine builder, so a
volume pulled off the shelf and left on the sand is recognisably the same book.
"""

from __future__ import annotations

import math
import os
import shutil
import sys
from pathlib import Path

import bpy
from mathutils import Vector


os.environ["KEELMIRA_ASSET_IDS"] = "__bookshelf_set_helpers_only__"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_home_island_asset_set_02 as kit  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "Landfall/Resources"

# Deterministic on its own seed: the shelf must not reshuffle its spines
# because some other builder drew from the shared kit RNG first.
RNG = __import__("random").Random(48213)


def finish(asset_id: str, root: bpy.types.Object, objects: list[bpy.types.Object]) -> None:
    root["integration_status"] = "home_island_placeable"
    kit.export_asset(asset_id, root, objects)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(kit.READY_DIR / f"{asset_id}.usdz", RUNTIME_DIR / f"{asset_id}.usdz")


def book_materials() -> dict[str, bpy.types.Material]:
    """One shared palette. The covers are the only saturated thing either prop
    owns, so the wood and the paper stay deliberately quiet around them."""
    return {
        "wood": kit.material("LF_BookshelfWood", "#9C7A54", 0.94),
        "wood_dark": kit.material("LF_BookshelfWoodDark", "#5E4630", 0.96),
        "wood_deep": kit.material("LF_BookshelfWoodDeep", "#3E2E20", 0.98),
        "trim": kit.material("LF_BookshelfTrim", "#5FAA9C", 0.90),
        "paper": kit.material("LF_BookPaper", "#EADFC4", 0.95),
        "cover_coral": kit.material("LF_BookCoverCoral", "#C05A44", 0.88),
        "cover_teal": kit.material("LF_BookCoverTeal", "#2F6B63", 0.88),
        "cover_ochre": kit.material("LF_BookCoverOchre", "#C08F42", 0.88),
        "cover_dusk": kit.material("LF_BookCoverDusk", "#4A5A7A", 0.88),
        "cover_moss": kit.material("LF_BookCoverMoss", "#5D7355", 0.88),
        "cover_leather": kit.material("LF_BookCoverLeather", "#7E5439", 0.90),
        "gilt": kit.material("LF_BookGilt", "#C9A85C", 0.62, metallic=0.34),
    }


COVER_KEYS = ("cover_coral", "cover_teal", "cover_ochre", "cover_dusk", "cover_moss", "cover_leather")


def shelve_books(
    name: str,
    mats: dict[str, bpy.types.Material],
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    *,
    left_x: float,
    right_x: float,
    floor_z: float,
    depth: float,
    y: float,
    lean_last: bool = False,
) -> None:
    """Fill one shelf with upright spines from left_x rightward.

    The row deliberately stops short of the right wall: a shelf packed wall to
    wall reads as a texture, while a gap with one leaning volume reads as a
    shelf somebody uses.
    """
    x = left_x
    index = 0
    stop = right_x - (0.075 if lean_last else 0.018)
    while x < stop:
        width = RNG.uniform(0.017, 0.032)
        if x + width > stop:
            break
        height = RNG.uniform(0.145, 0.205)
        cover = mats[COVER_KEYS[RNG.randrange(len(COVER_KEYS))]]
        index += 1
        kit.add_box(
            f"{name}_Spine_{index:02}",
            (x + width * 0.5, y, floor_z + height * 0.5),
            (width, depth, height),
            cover,
            root,
            objects,
            bevel=0.003,
        )
        # A pale block of pages behind each spine. Without it a row of covers
        # reads as a striped board rather than as books with paper in them.
        kit.add_box(
            f"{name}_Pages_{index:02}",
            (x + width * 0.5, y + depth * 0.30, floor_z + height * 0.5 - 0.004),
            (width - 0.006, depth * 0.34, height - 0.012),
            mats["paper"],
            root,
            objects,
            bevel=0.002,
        )
        if RNG.random() < 0.42:
            kit.add_box(
                f"{name}_Band_{index:02}",
                (x + width * 0.5, y - depth * 0.5 + 0.004, floor_z + height * 0.78),
                (width - 0.004, 0.006, 0.012),
                mats["gilt"],
                root,
                objects,
                bevel=0.001,
            )
        x += width + RNG.uniform(0.0005, 0.0035)

    if lean_last:
        # The leaning volume closes the row: it rests its spine on the last
        # upright book and its bottom edge on the shelf, so the gap reads as
        # somebody having taken a book out rather than as a modelling mistake.
        height = 0.185
        tilt = math.radians(24)
        width = 0.028
        centre_x = x + math.sin(tilt) * height * 0.5 + width * 0.5 + 0.004
        kit.add_box(
            f"{name}_Leaning_Spine",
            (centre_x, y, floor_z + math.cos(tilt) * height * 0.5),
            (width, depth, height),
            mats["cover_coral"],
            root,
            objects,
            rotation=(0, -tilt, 0),
            bevel=0.003,
        )
        kit.add_box(
            f"{name}_Leaning_Pages",
            (centre_x + 0.002, y + depth * 0.30, floor_z + math.cos(tilt) * height * 0.5),
            (width - 0.006, depth * 0.34, height - 0.012),
            mats["paper"],
            root,
            objects,
            rotation=(0, -tilt, 0),
            bevel=0.002,
        )


def flat_book(
    name: str,
    mats: dict[str, bpy.types.Material],
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    *,
    centre: Vector,
    length: float,
    width: float,
    thickness: float,
    yaw: float,
    cover_key: str,
    gilt: bool = False,
) -> None:
    """One closed book lying on its back cover."""
    cover = mats[cover_key]
    kit.add_box(
        f"{name}_Cover",
        tuple(centre),
        (length, width, thickness),
        cover,
        root,
        objects,
        rotation=(0, 0, yaw),
        bevel=0.004,
    )
    # Pages sit proud of the cover on three sides and stop short at the spine,
    # which is what tells the eye which edge is the binding.
    page_offset = Vector((math.sin(yaw) * 0.006, -math.cos(yaw) * 0.006, 0.0))
    kit.add_box(
        f"{name}_Pages",
        tuple(centre + page_offset),
        (length - 0.016, width - 0.010, thickness - 0.010),
        mats["paper"],
        root,
        objects,
        rotation=(0, 0, yaw),
        bevel=0.002,
    )
    if gilt:
        kit.add_box(
            f"{name}_Gilt",
            tuple(centre + Vector((0, 0, thickness * 0.5 - 0.001))),
            (length * 0.42, width * 0.12, 0.004),
            mats["gilt"],
            root,
            objects,
            rotation=(0, 0, yaw),
            bevel=0.001,
        )


def build_wooden_bookshelf() -> None:
    kit.reset_scene()
    root = kit.make_root("wooden_bookshelf", "Wooden_Bookshelf", "small")
    objects: list[bpy.types.Object] = []
    mats = book_materials()

    # Three compartments between a plinth and a cornice. The carcass is only
    # 0.26 deep so the shelf can stand against a cottage wall without its
    # footprint pushing the navigator's walking collider into the room.
    kit.add_box("Bookshelf_Plinth", (0, 0, 0.028), (0.660, 0.280, 0.056), mats["wood_dark"], root, objects, bevel=0.008)
    kit.add_box("Bookshelf_Side_L", (-0.285, 0, 0.442), (0.050, 0.260, 0.820), mats["wood"], root, objects, bevel=0.008)
    kit.add_box("Bookshelf_Side_R", (0.285, 0, 0.442), (0.050, 0.260, 0.820), mats["wood"], root, objects, bevel=0.008)
    kit.add_box("Bookshelf_Back", (0, 0.118, 0.452), (0.522, 0.022, 0.800), mats["wood_deep"], root, objects, bevel=0.004)
    # One seafoam pinstripe under the cornice, the same trim the mailbox eave
    # and the gramophone lid use, so the three props read as one family.
    kit.add_box("Bookshelf_Pinstripe", (0, 0, 0.862), (0.640, 0.272, 0.010), mats["trim"], root, objects, bevel=0.003)
    kit.add_box("Bookshelf_Cornice", (0, 0, 0.900), (0.700, 0.300, 0.050), mats["wood_dark"], root, objects, bevel=0.008)

    shelf_floors = []
    for index, z in enumerate((0.325, 0.595), 1):
        kit.add_box(f"Bookshelf_Shelf_{index}", (0, 0, z), (0.520, 0.250, 0.028), mats["wood"], root, objects, bevel=0.004)
        shelf_floors.append(z + 0.014)

    # Bottom compartment holds the tallest run, the middle one a shorter run
    # with the gap, and the top shelf carries a flat stack instead of a third
    # row — three identical rows would read as wallpaper.
    shelve_books("Bookshelf_Low", mats, root, objects, left_x=-0.252, right_x=0.252, floor_z=0.056, depth=0.190, y=0.006)
    shelve_books("Bookshelf_Mid", mats, root, objects, left_x=-0.252, right_x=0.252, floor_z=shelf_floors[0], depth=0.190, y=0.006, lean_last=True)

    top_floor = shelf_floors[1]
    for index, (dx, dy, yaw, key) in enumerate(
        (
            (-0.110, 0.004, math.radians(2), "cover_teal"),
            (-0.104, -0.002, math.radians(-4), "cover_ochre"),
            (-0.112, 0.006, math.radians(5), "cover_leather"),
        ),
        1,
    ):
        flat_book(
            f"Bookshelf_Top_Flat_{index}",
            mats,
            root,
            objects,
            centre=Vector((dx, dy, top_floor + 0.017 + (index - 1) * 0.030)),
            length=0.230,
            width=0.170,
            thickness=0.030,
            yaw=yaw,
            cover_key=key,
            gilt=index == 3,
        )
    shelve_books("Bookshelf_Top", mats, root, objects, left_x=0.030, right_x=0.252, floor_z=top_floor, depth=0.190, y=0.006)

    # A rolled chart laid across the cornice. One non-book object is what makes
    # the shelf belong to a navigator rather than to a library, and the cornice
    # is the one place on the carcass that stays visible from every angle the
    # island camera can reach — inside a compartment the near side panel hides
    # it whenever the player orbits round to that side.
    chart_yaw = math.radians(-7)
    kit.add_cylinder(
        "Bookshelf_Chart_Roll",
        (-0.148, 0.012, 0.949),
        0.024,
        0.250,
        mats["paper"],
        root,
        objects,
        vertices=10,
        rotation=(0, math.radians(90), chart_yaw),
    )
    kit.add_cylinder(
        "Bookshelf_Chart_Tie",
        (-0.148, 0.012, 0.949),
        0.027,
        0.014,
        mats["cover_teal"],
        root,
        objects,
        vertices=10,
        rotation=(0, math.radians(90), chart_yaw),
    )

    # Two books left on the cornice, because a used shelf overflows.
    flat_book(
        "Bookshelf_Crown_Flat_1",
        mats,
        root,
        objects,
        centre=Vector((0.085, -0.008, 0.940)),
        length=0.210,
        width=0.155,
        thickness=0.028,
        yaw=math.radians(-9),
        cover_key="cover_dusk",
    )
    flat_book(
        "Bookshelf_Crown_Flat_2",
        mats,
        root,
        objects,
        centre=Vector((0.079, 0.004, 0.967)),
        length=0.196,
        width=0.146,
        thickness=0.026,
        yaw=math.radians(4),
        cover_key="cover_moss",
        gilt=True,
    )

    finish("wooden_bookshelf", root, objects)


def build_stacked_books() -> None:
    kit.reset_scene()
    root = kit.make_root("stacked_books", "Stacked_Books", "small")
    objects: list[bpy.types.Object] = []
    mats = book_materials()

    # A pile somebody set down and stopped tidying: each volume a little
    # smaller and a little more turned than the one under it, so the stack
    # reads from directly above as well as from the island's usual low camera.
    stack = (
        (0.250, 0.185, 0.036, math.radians(0), "cover_leather", False),
        (0.232, 0.172, 0.032, math.radians(9), "cover_teal", False),
        (0.244, 0.178, 0.030, math.radians(-6), "cover_ochre", True),
        (0.214, 0.160, 0.028, math.radians(14), "cover_dusk", False),
        (0.198, 0.150, 0.026, math.radians(3), "cover_coral", True),
    )
    z = 0.0
    for index, (length, width, thickness, yaw, key, gilt) in enumerate(stack, 1):
        flat_book(
            f"StackedBooks_{index:02}",
            mats,
            root,
            objects,
            centre=Vector((
                RNG.uniform(-0.008, 0.008),
                RNG.uniform(-0.008, 0.008),
                z + thickness * 0.5,
            )),
            length=length,
            width=width,
            thickness=thickness,
            yaw=yaw,
            cover_key=key,
            gilt=gilt,
        )
        z += thickness

    # One volume propped against the pile: its foot on the ground and its top
    # corner resting on the stack. Rotating about Y stands the cover up, and the
    # yaw applied after it turns the whole book so it never sits square to the
    # island grid.
    lean = math.radians(-130)
    yaw = math.radians(30)
    length, width, thickness = 0.200, 0.156, 0.028
    axis = Vector((math.cos(lean), 0.0, -math.sin(lean)))
    foot = Vector((0.250, -0.030, 0.006))
    centre = foot + axis * (length * 0.5)
    spin = math.cos(yaw), math.sin(yaw)
    centre = Vector((centre.x * spin[0] - centre.y * spin[1], centre.x * spin[1] + centre.y * spin[0], centre.z))
    kit.add_box(
        "StackedBooks_Leaning_Cover",
        tuple(centre),
        (length, width, thickness),
        mats["cover_moss"],
        root,
        objects,
        rotation=(0, lean, yaw),
        bevel=0.004,
    )
    kit.add_box(
        "StackedBooks_Leaning_Pages",
        tuple(centre + Vector((0, 0, 0.006))),
        (length - 0.014, width - 0.012, thickness - 0.012),
        mats["paper"],
        root,
        objects,
        rotation=(0, lean, yaw),
        bevel=0.002,
    )
    # A bookmark left in the top volume, hanging over its fore edge. Teal
    # against the coral cover: a ribbon the same colour as the book it marks
    # would simply disappear.
    kit.add_box(
        "StackedBooks_Ribbon",
        (-0.028, -0.096, z - 0.010),
        (0.052, 0.086, 0.005),
        mats["cover_teal"],
        root,
        objects,
        rotation=(0, 0, math.radians(6)),
        bevel=0.002,
    )

    finish("stacked_books", root, objects)


build_wooden_bookshelf()
build_stacked_books()
print("BOOKSHELF_SET_COMPLETE=1")
