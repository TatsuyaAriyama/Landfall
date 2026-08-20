"""Build the drinks: three small things to stand on a desk.

A 500 ml bottle of water, a green glass bottle of sparkling water, and a short
can of coffee — the size Japanese vending machines sell. They are authored at
the same real-world scale as the desk they belong on (0.42 high), so the water
bottle's 0.190 comes up a little under half the desk's height, which is what a
bottle standing beside a laptop looks like.

All three wear the phoenix on their label instead of a brand: the same outline
the laptop's lid carries, read from `phoenix_emblem.py`. The mark is wrapped
around the label rather than laid flat against it, so it curves with the bottle
instead of floating off it at the edges, and it appears front and back so the
bird is in view from wherever the island's camera happens to be.

The water bottle is the one prop on the island meant to be seen through. Its
shell is exported as ordinary opaque plastic and made transparent at load time
by `AssetPlacementRuntime.makeAssetNode`, which is the only place that knows the
material names — USD's own opacity does not survive the trip into SceneKit's
sorting the way a material set in code does. The water inside is a solid body of
its own, so it is there to be seen once the shell goes clear.
"""

from __future__ import annotations

import math
import os
import shutil
import sys
from pathlib import Path

import bmesh
import bpy


os.environ["KEELMIRA_ASSET_IDS"] = "__drink_set_helpers_only__"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_home_island_asset_set_02 as kit  # noqa: E402
import phoenix_emblem  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "Landfall/Resources"

# Every round part is a 16-gon. Twelve reads as a nut at this size and twenty
# buys nothing a player can see from the island's camera.
SIDES = 16
# The emblem stands this far off the label it is wrapped around: far enough to
# clear the flats of a 16-gon, close enough to read as printed rather than bolted on.
BADGE_LIFT = 0.0012
BADGE_RELIEF = 0.0014


def finish(asset_id: str, root: bpy.types.Object, objects: list[bpy.types.Object]) -> None:
    root["integration_status"] = "home_island_placeable"
    kit.export_asset(asset_id, root, objects)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(kit.READY_DIR / f"{asset_id}.usdz", RUNTIME_DIR / f"{asset_id}.usdz")


def tube(name, bottom, top, radius, mat, root, objects, *, sides: int = SIDES):
    """A round section between two heights, which is how every part here is described."""
    return kit.add_cylinder(
        name,
        (0.0, 0.0, (bottom + top) * 0.5),
        radius,
        top - bottom,
        mat,
        root,
        objects,
        vertices=sides,
    )


def taper(name, bottom, top, radius_bottom, radius_top, mat, root, objects, *, sides: int = SIDES):
    return kit.add_cone(
        name,
        (0.0, 0.0, (bottom + top) * 0.5),
        radius_bottom,
        radius_top,
        top - bottom,
        mat,
        root,
        objects,
        vertices=sides,
    )


def wrapped_badge(
    name: str,
    outline: list[tuple[float, float]],
    centre_z: float,
    inner_radius: float,
    outer_radius: float,
    facing: float,
    mat,
    root,
    objects,
):
    """A flat emblem bent around a round label.

    The outline's x is walked around the label as an arc of the same length, so
    the bird keeps its proportions instead of being squashed by the curvature,
    and its own thickness runs outward along the radius.
    """
    def point(x: float, z: float, radius: float) -> tuple[float, float, float]:
        angle = facing + x / inner_radius
        return (
            math.sin(angle) * radius,
            -math.cos(angle) * radius,
            centre_z + z,
        )

    count = len(outline)
    vertices = [point(x, z, inner_radius) for x, z in outline]
    vertices += [point(x, z, outer_radius) for x, z in outline]

    faces: list[tuple[int, ...]] = [
        tuple(range(count)),
        tuple(range(2 * count - 1, count - 1, -1)),
    ]
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, nxt + count, index + count))

    obj = kit.mesh_object(name, vertices, faces, mat, root, objects)
    # The caps come from a screen-space path whose winding we do not want to
    # reason about; let bmesh point every normal outward instead.
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return obj


def stamp_phoenix(
    prefix: str,
    height: float,
    centre_z: float,
    label_radius: float,
    body_mat,
    eye_mat,
    root,
    objects,
) -> None:
    """The mark, on the front of the label and on the back of it."""
    outline = phoenix_emblem.outline(height)
    eye = phoenix_emblem.eye_circle(height)
    inner = label_radius + BADGE_LIFT
    for index, facing in enumerate((0.0, math.pi), 1):
        wrapped_badge(
            f"{prefix}_Phoenix_{index}",
            outline,
            centre_z,
            inner,
            inner + BADGE_RELIEF,
            facing,
            body_mat,
            root,
            objects,
        )
        wrapped_badge(
            f"{prefix}_Phoenix_Eye_{index}",
            eye,
            centre_z,
            inner + BADGE_RELIEF,
            inner + BADGE_RELIEF + 0.0007,
            facing,
            eye_mat,
            root,
            objects,
        )


def emblem_materials() -> tuple[bpy.types.Material, bpy.types.Material]:
    """Coral body, midnight eye — the bird's colours everywhere it appears."""
    return (
        kit.material("LF_DrinkEmblem", "#F0997B", 0.52),
        kit.material("LF_DrinkEmblemEye", "#1A1130", 0.58),
    )


def build_spring_water_bottle() -> None:
    """The clear 500 ml bottle: ribbed grip, blue cap, water up to the shoulder."""
    kit.reset_scene()
    root = kit.make_root("spring_water_bottle", "Spring_Water_Bottle", "small")
    objects: list[bpy.types.Object] = []

    # PET reads as almost colourless until it is seen against the sand; the
    # faint blue is what stops it looking like white plastic once it goes clear.
    shell = kit.material("LF_DrinkPetShell", "#DDEFF5", 0.16)
    shell_shade = kit.material("LF_DrinkPetShellShade", "#C4E1EB", 0.20)
    water = kit.material("LF_DrinkPetWater", "#A5D9EA", 0.24)
    label = kit.material("LF_DrinkPetLabel", "#F5F2EA", 0.74)
    stripe = kit.material("LF_DrinkPetStripe", "#E8853C", 0.66)
    cap = kit.material("LF_DrinkPetCap", "#E8853C", 0.52)
    emblem, emblem_eye = emblem_materials()

    radius = 0.033

    # The water first, so the shell is built around something rather than around
    # air. It stops just under the neck, the way a sealed bottle is filled.
    tube("Water_Bottle_Water_Body", 0.004, 0.115, radius - 0.0017, water, root, objects)
    taper(
        "Water_Bottle_Water_Shoulder",
        0.115,
        0.145,
        radius - 0.0017,
        0.0125,
        water,
        root,
        objects,
    )

    tube("Water_Bottle_Foot", 0.000, 0.010, 0.0305, shell_shade, root, objects)
    tube("Water_Bottle_Body", 0.008, 0.118, radius, shell, root, objects)
    # Three grip grooves below the label, which is what makes a smooth cylinder
    # read as a bottle somebody has already opened once.
    for index, z in enumerate((0.020, 0.032, 0.044), 1):
        tube(
            f"Water_Bottle_Rib_{index}",
            z - 0.0018,
            z + 0.0018,
            radius + 0.0009,
            shell_shade,
            root,
            objects,
        )
    taper("Water_Bottle_Shoulder", 0.118, 0.152, radius, 0.0145, shell, root, objects)
    tube("Water_Bottle_Neck", 0.150, 0.168, 0.0135, shell, root, objects)
    tube("Water_Bottle_Collar", 0.164, 0.170, 0.0156, shell_shade, root, objects)
    tube("Water_Bottle_Cap", 0.170, 0.190, 0.0166, cap, root, objects)
    tube("Water_Bottle_Cap_Top", 0.188, 0.190, 0.0150, cap, root, objects)

    label_radius = radius + 0.0006
    tube("Water_Bottle_Label", 0.052, 0.106, label_radius, label, root, objects)
    for index, z in enumerate((0.0535, 0.1045), 1):
        tube(
            f"Water_Bottle_Label_Stripe_{index}",
            z - 0.0015,
            z + 0.0015,
            label_radius + 0.0004,
            stripe,
            root,
            objects,
        )
    stamp_phoenix(
        "Water_Bottle",
        0.040,
        0.079,
        label_radius,
        emblem,
        emblem_eye,
        root,
        objects,
    )

    finish("spring_water_bottle", root, objects)


def build_sparkling_water_bottle() -> None:
    """The green glass one: a belly that tapers the whole way to a crown cap."""
    kit.reset_scene()
    root = kit.make_root("sparkling_water_bottle", "Sparkling_Water_Bottle", "small")
    objects: list[bpy.types.Object] = []

    glass = kit.material("LF_DrinkGlass", "#2E6B43", 0.22)
    glass_deep = kit.material("LF_DrinkGlassDeep", "#20512F", 0.26)
    # Glass thins as it is drawn up into a neck, and thin glass is paler. That
    # is the whole of the bottle's shading: no painted highlight, which on a
    # round bottle can only be a flat plate standing off the curve.
    glass_thin = kit.material("LF_DrinkGlassThin", "#3F8A57", 0.20)
    crown = kit.material("LF_DrinkCrownCap", "#C7D8CA", 0.34, metallic=0.62)
    label = kit.material("LF_DrinkGlassLabel", "#F2EADA", 0.74)
    emblem, emblem_eye = emblem_materials()

    belly = 0.036

    tube("Sparkling_Foot", 0.000, 0.009, 0.0300, glass_deep, root, objects)
    taper("Sparkling_Belly_Lower", 0.007, 0.040, 0.0305, belly, glass, root, objects)
    tube("Sparkling_Belly", 0.040, 0.062, belly, glass, root, objects)
    taper("Sparkling_Belly_Upper", 0.062, 0.112, belly, 0.0215, glass, root, objects)
    taper("Sparkling_Shoulder", 0.112, 0.140, 0.0215, 0.0125, glass_thin, root, objects)
    tube("Sparkling_Neck", 0.138, 0.162, 0.0125, glass_thin, root, objects)
    tube("Sparkling_Lip", 0.160, 0.167, 0.0146, glass_deep, root, objects)
    # A crown cap, skirt and all: the fluting is one wider ring, which is as
    # much of it as survives at this size anyway.
    tube("Sparkling_Cap_Skirt", 0.165, 0.173, 0.0160, crown, root, objects)
    tube("Sparkling_Cap_Crown", 0.172, 0.180, 0.0148, crown, root, objects)

    label_radius = belly + 0.0006
    tube("Sparkling_Label", 0.034, 0.074, label_radius, label, root, objects)
    stamp_phoenix(
        "Sparkling",
        0.030,
        0.054,
        label_radius,
        emblem,
        emblem_eye,
        root,
        objects,
    )

    finish("sparkling_water_bottle", root, objects)


def build_canned_coffee() -> None:
    """The short can: a vending-machine coffee, tab and all."""
    kit.reset_scene()
    root = kit.make_root("canned_coffee", "Canned_Coffee", "small")
    objects: list[bpy.types.Object] = []

    body = kit.material("LF_DrinkCanBody", "#3B2A21", 0.58)
    body_light = kit.material("LF_DrinkCanBodyLight", "#4C382C", 0.56)
    alloy = kit.material("LF_DrinkCanAlloy", "#C3C9CE", 0.34, metallic=0.58)
    alloy_shade = kit.material("LF_DrinkCanAlloyShade", "#98A0A6", 0.40, metallic=0.52)
    label = kit.material("LF_DrinkCanLabel", "#EFE3CE", 0.72)
    stripe = kit.material("LF_DrinkCanStripe", "#E8853C", 0.64)
    emblem, emblem_eye = emblem_materials()

    radius = 0.0285

    tube("Coffee_Can_Foot", 0.000, 0.006, 0.0262, alloy_shade, root, objects)
    tube("Coffee_Can_Body", 0.004, 0.066, radius, body, root, objects)
    tube("Coffee_Can_Body_Upper", 0.066, 0.092, radius, body_light, root, objects)
    taper("Coffee_Can_Neck", 0.092, 0.101, radius, 0.0243, alloy, root, objects)
    tube("Coffee_Can_Lid", 0.101, 0.104, 0.0246, alloy, root, objects)
    kit.add_torus(
        "Coffee_Can_Lid_Rim",
        (0.0, 0.0, 0.1035),
        0.0242,
        0.0022,
        alloy_shade,
        root,
        objects,
        major_segments=SIDES,
        minor_segments=4,
    )
    # The tab: a stamped ring with a rivet, sitting flat on the lid.
    kit.add_torus(
        "Coffee_Can_Tab",
        (0.0, 0.0065, 0.1052),
        0.0058,
        0.0013,
        alloy_shade,
        root,
        objects,
        major_segments=10,
        minor_segments=4,
    )
    kit.add_cylinder(
        "Coffee_Can_Rivet",
        (0.0, -0.0015, 0.1052),
        0.0022,
        0.0022,
        alloy_shade,
        root,
        objects,
        vertices=8,
    )

    label_radius = radius + 0.0006
    tube("Coffee_Can_Label", 0.024, 0.068, label_radius, label, root, objects)
    for index, z in enumerate((0.0255, 0.0665), 1):
        tube(
            f"Coffee_Can_Stripe_{index}",
            z - 0.0013,
            z + 0.0013,
            label_radius + 0.0004,
            stripe,
            root,
            objects,
        )
    stamp_phoenix(
        "Coffee_Can",
        0.032,
        0.046,
        label_radius,
        emblem,
        emblem_eye,
        root,
        objects,
    )

    finish("canned_coffee", root, objects)


BUILDERS = (
    build_spring_water_bottle,
    build_sparkling_water_bottle,
    build_canned_coffee,
)

for builder in BUILDERS:
    builder()

print(f"DRINK_SET_COMPLETE={len(BUILDERS)}")
