"""Build Landfall's small weathered cottage as a standalone 3D Studio asset.

The cottage follows the world's hand-authored low-poly language without looking
like a primitive block: its frame leans, the roof sags, shingles are individually
warped, plaster has physical chips and cracks, and the stone footing stays thin
enough to sit naturally on sculpted terrain.  The script produces the editable
Blender source, a runtime USDZ, and a review render from one deterministic seed.
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/weathered_cottage.blend"
USDZ_PATH = ROOT / "Landfall/Resources/weathered_cottage.usdz"
RENDER_PATH = ROOT / "marketing/3d/weathered-cottage.png"
RNG = random.Random(31987)


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[index : index + 2], 16) / 255 for index in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float = 0.94,
    *,
    metallic: float = 0.0,
    double_sided: bool = False,
) -> bpy.types.Material:
    value = bpy.data.materials.new(name)
    value.diffuse_color = rgba(color)
    value.use_nodes = True
    value.use_backface_culling = not double_sided
    shader = next(node for node in value.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = rgba(color)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    return value


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

MATS = {
    "stone_deep": material("LF_CottageStoneDeep", "#3C4B45", 1.0),
    "stone": material("LF_CottageStone", "#596860", 0.99),
    "stone_light": material("LF_CottageStoneLight", "#788078", 0.98),
    "plaster_shadow": material("LF_CottagePlasterShadow", "#807E69", 0.99),
    "plaster": material("LF_CottagePlaster", "#AAA78A", 0.98),
    "plaster_light": material("LF_CottagePlasterLight", "#C0B99A", 0.97),
    "wood_deep": material("LF_CottageWoodDeep", "#352A25", 0.98),
    "wood": material("LF_CottageWood", "#594034", 0.96),
    "wood_light": material("LF_CottageWoodLight", "#745746", 0.94),
    "deadwood": material("LF_CottageDeadwood", "#8A745A", 0.98),
    "roof_deep": material("LF_CottageRoofDeep", "#3B3530", 0.99),
    "roof_shadow": material("LF_CottageRoofShadow", "#51433A", 0.98),
    "roof": material("LF_CottageRoof", "#665044", 0.97),
    "roof_light": material("LF_CottageRoofLight", "#7A6150", 0.96),
    "moss_deep": material("LF_CottageMossDeep", "#405742", 1.0, double_sided=True),
    "moss": material("LF_CottageMoss", "#61785A", 0.99, double_sided=True),
    "moss_light": material("LF_CottageMossLight", "#7D8E68", 0.98, double_sided=True),
    "glass": material("LF_CottageGlass", "#193E3A", 0.74),
    "glass_glint": material("LF_CottageGlassGlint", "#6F9D8B", 0.66),
    "rust": material("LF_CottageRust", "#704632", 0.95, metallic=0.08),
    "iron": material("LF_CottageIron", "#2A3230", 0.88, metallic=0.15),
}

root = bpy.data.objects.new("Weathered_Cottage", None)
bpy.context.collection.objects.link(root)
asset_objects: list[bpy.types.Object] = []


def keep(obj: bpy.types.Object, name: str, mat: bpy.types.Material) -> bpy.types.Object:
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    if not obj.data.materials:
        obj.data.materials.append(mat)
    obj.parent = root
    asset_objects.append(obj)
    return obj


def mesh_object(
    name: str,
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    mat: bpy.types.Material,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(mat)
    mesh.validate(clean_customdata=False)
    mesh.update()
    for polygon in mesh.polygons:
        polygon.use_smooth = False
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = root
    asset_objects.append(obj)
    return obj


def add_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    mat: bpy.types.Material,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel: float = 0.012,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        modifier = obj.modifiers.new(name="Handworn edges", type="BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.rotation_euler = rotation
    return keep(obj, name, mat)


def add_beam(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    thickness: float,
    mat: bpy.types.Material,
    depth: float | None = None,
) -> bpy.types.Object:
    a = Vector(start)
    b = Vector(end)
    direction = b - a
    obj = add_box(
        name,
        tuple((a + b) * 0.5),
        (depth or thickness, thickness, direction.length),
        mat,
        bevel=min(thickness * 0.12, 0.014),
    )
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return obj


def add_stone(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    rotation: tuple[float, float, float],
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1.0, location=location)
    stone = bpy.context.object
    stone.scale = scale
    stone.rotation_euler = rotation
    return keep(stone, name, mat)


def wall_patch_front(
    name: str,
    points: list[tuple[float, float]],
    y: float,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    vertices = [(x, y, z) for x, z in points]
    return mesh_object(name, vertices, [tuple(range(len(vertices)))], mat)


def wall_patch_side(
    name: str,
    points: list[tuple[float, float]],
    x: float,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    vertices = [(x, y, z) for y, z in points]
    return mesh_object(name, vertices, [tuple(range(len(vertices)))], mat)


def crack_front(name: str, points: list[tuple[float, float]], y: float) -> None:
    for index, ((x1, z1), (x2, z2)) in enumerate(zip(points, points[1:])):
        add_beam(
            f"{name}_{index + 1:02}",
            (x1, y, z1),
            (x2, y, z2),
            0.012,
            MATS["wood_deep"],
            depth=0.009,
        )


# Thin, irregular foundation: it grounds the cottage without reading as a bulky pedestal.
foundation_specs: list[tuple[float, float, float, float, float]] = []
for side in (-1, 1):
    for index in range(7):
        foundation_specs.append((-1.03 + index * 0.34, side * 0.83, 0.09, 0.19, 0.13))
for side in (-1, 1):
    for index in range(4):
        foundation_specs.append((side * 1.17, -0.58 + index * 0.38, 0.09, 0.16, 0.13))
for index, (x, y, z, sx, sz) in enumerate(foundation_specs):
    add_stone(
        f"Foundation_Stone_{index + 1:02}",
        (x + RNG.uniform(-0.035, 0.035), y + RNG.uniform(-0.025, 0.025), z),
        (sx * RNG.uniform(0.88, 1.12), 0.16 * RNG.uniform(0.85, 1.14), sz),
        (MATS["stone_deep"], MATS["stone"], MATS["stone_light"])[index % 3],
        (RNG.uniform(-0.15, 0.15), RNG.uniform(-0.16, 0.16), RNG.uniform(-0.28, 0.28)),
    )

add_box("Cottage_Floor", (0, 0, 0.205), (2.22, 1.55, 0.14), MATS["wood_deep"], bevel=0.018)

# Crooked plaster shell. Frame pieces cover the seams and make the deformation intentional.
add_box("Wall_Front", (0.015, -0.785, 1.02), (2.18, 0.13, 1.64), MATS["plaster"], (0.0, -0.018, 0.008), 0.018)
add_box("Wall_Back", (-0.025, 0.785, 1.01), (2.18, 0.13, 1.62), MATS["plaster_shadow"], (0.0, 0.014, -0.012), 0.018)
add_box("Wall_Left", (-1.055, 0.0, 1.01), (0.13, 1.54, 1.63), MATS["plaster_light"], (0.012, 0.0, 0.006), 0.018)
add_box("Wall_Right", (1.055, 0.0, 1.00), (0.13, 1.54, 1.60), MATS["plaster"], (-0.015, 0.0, -0.008), 0.018)

# Close the gable ends so roof damage reads as intentional rather than unfinished geometry.
mesh_object(
    "Wall_Gable_Right",
    [(1.124, -0.78, 1.75), (1.124, 0.78, 1.78), (1.124, 0.0, 2.38)],
    [(0, 1, 2)],
    MATS["plaster_shadow"],
)
mesh_object(
    "Wall_Gable_Left",
    [(-1.124, -0.78, 1.77), (-1.124, 0.0, 2.39), (-1.124, 0.78, 1.76)],
    [(0, 1, 2)],
    MATS["plaster"],
)

# Timber frame, deliberately not perfectly parallel.
corner_posts = (
    ((-1.08, -0.82, 0.20), (-1.04, -0.81, 1.85)),
    ((1.08, -0.82, 0.20), (1.02, -0.80, 1.81)),
    ((-1.08, 0.82, 0.20), (-1.11, 0.80, 1.80)),
    ((1.08, 0.82, 0.20), (1.04, 0.80, 1.84)),
)
for index, (start, end) in enumerate(corner_posts):
    add_beam(f"Frame_Corner_{index + 1:02}", start, end, 0.135, MATS["wood"])

for name, start, end in (
    ("Frame_Front_Sill", (-1.10, -0.855, 0.27), (1.10, -0.855, 0.25)),
    ("Frame_Front_Top", (-1.08, -0.855, 1.79), (1.04, -0.855, 1.76)),
    ("Frame_Back_Sill", (-1.10, 0.855, 0.26), (1.10, 0.855, 0.28)),
    ("Frame_Back_Top", (-1.09, 0.855, 1.76), (1.06, 0.855, 1.80)),
    ("Frame_Left_Sill", (-1.115, -0.80, 0.27), (-1.115, 0.80, 0.25)),
    ("Frame_Right_Sill", (1.115, -0.80, 0.26), (1.115, 0.80, 0.28)),
    ("Frame_Left_Top", (-1.115, -0.80, 1.78), (-1.115, 0.80, 1.76)),
    ("Frame_Right_Top", (1.115, -0.80, 1.77), (1.115, 0.80, 1.80)),
):
    add_beam(name, start, end, 0.105, MATS["wood_deep"], depth=0.105)

for index, (start, end) in enumerate((
    ((-1.00, -0.865, 0.34), (-0.47, -0.865, 1.70)),
    ((0.98, -0.865, 0.32), (0.61, -0.865, 1.69)),
    ((-1.125, -0.68, 0.34), (-1.125, -0.08, 1.69)),
    ((1.125, 0.70, 0.35), (1.125, 0.15, 1.70)),
    ((-0.96, 0.865, 0.34), (-0.34, 0.865, 1.69)),
)):
    add_beam(f"Frame_Diagonal_{index + 1:02}", start, end, 0.082, MATS["wood"])

for side_index, x in enumerate((-1.148, 1.148)):
    add_beam(
        f"Frame_Gable_Post_{side_index + 1:02}",
        (x, 0.0, 1.76),
        (x, 0.0, 2.34),
        0.072,
        MATS["wood_deep"],
        depth=0.055,
    )
    add_beam(
        f"Frame_Gable_Brace_{side_index + 1:02}_A",
        (x, -0.73, 1.78),
        (x, 0.0, 2.34),
        0.060,
        MATS["wood"],
        depth=0.050,
    )
    add_beam(
        f"Frame_Gable_Brace_{side_index + 1:02}_B",
        (x, 0.73, 1.78),
        (x, 0.0, 2.34),
        0.060,
        MATS["wood"],
        depth=0.050,
    )

# Front door: individual boards, warped brace, corroded hinges, and a worn stone step.
add_box("Door_Shadow", (0.33, -0.864, 0.91), (0.72, 0.026, 1.30), MATS["wood_deep"], (0, 0, -0.028), 0.006)
door_colors = (MATS["wood"], MATS["wood_light"], MATS["deadwood"], MATS["wood"])
for index in range(4):
    add_box(
        f"Door_Plank_{index + 1:02}",
        (0.075 + index * 0.17, -0.892 - (index % 2) * 0.006, 0.90 + (index - 1.5) * 0.008),
        (0.165, 0.055, 1.28 - (index % 3) * 0.035),
        door_colors[index],
        (0.0, 0.0, -0.035 + index * 0.012),
        0.012,
    )
add_beam("Door_Brace", (0.06, -0.93, 0.55), (0.66, -0.93, 1.10), 0.075, MATS["deadwood"], depth=0.055)
for index, z in enumerate((0.58, 1.18)):
    add_box(f"Door_Hinge_{index + 1:02}", (0.03, -0.962, z), (0.27, 0.025, 0.045), MATS["rust"], (0, 0, 0.015), 0.006)
add_stone("Door_Knob", (0.62, -0.978, 0.91), (0.035, 0.022, 0.035), MATS["iron"], (0, 0, 0))
for index, x in enumerate((0.18, 0.50)):
    add_stone(
        f"Door_Step_{index + 1:02}",
        (x, -1.00 - index * 0.08, 0.10 - index * 0.018),
        (0.33, 0.22, 0.09),
        MATS["stone_light"] if index == 0 else MATS["stone"],
        (0.02, -0.04, (-0.04 if index else 0.03)),
    )

# A dark, salt-clouded window and rough emergency boarding tell the house's history.
add_box("Window_Front_Glass", (-0.57, -0.868, 1.18), (0.52, 0.025, 0.48), MATS["glass"], (0, 0, 0.012), 0.004)
for index, (location, dimensions) in enumerate((
    ((-0.57, -0.899, 0.92), (0.62, 0.052, 0.065)),
    ((-0.57, -0.899, 1.44), (0.62, 0.052, 0.065)),
    ((-0.86, -0.899, 1.18), (0.065, 0.052, 0.55)),
    ((-0.28, -0.899, 1.18), (0.065, 0.052, 0.55)),
)):
    add_box(f"Window_Front_Frame_{index + 1:02}", location, dimensions, MATS["wood_deep"], bevel=0.008)
add_box("Window_Front_Glint", (-0.69, -0.902, 1.30), (0.035, 0.012, 0.21), MATS["glass_glint"], (0, 0, -0.52), 0.003)
add_box("Window_Board_A", (-0.57, -0.936, 1.17), (0.72, 0.065, 0.12), MATS["deadwood"], (0, 0, 0.24), 0.012)
add_box("Window_Board_B", (-0.55, -0.941, 1.20), (0.68, 0.065, 0.10), MATS["wood_light"], (0, 0, -0.33), 0.012)

# Side window remains readable when the asset is rotated in the studio.
add_box("Window_Side_Glass", (1.126, 0.22, 1.16), (0.024, 0.52, 0.46), MATS["glass"], (0.0, 0.0, -0.015), 0.004)
for index, (location, dimensions) in enumerate((
    ((1.146, -0.07, 1.16), (0.05, 0.065, 0.54)),
    ((1.146, 0.51, 1.16), (0.05, 0.065, 0.54)),
    ((1.146, 0.22, 0.90), (0.05, 0.62, 0.065)),
    ((1.146, 0.22, 1.42), (0.05, 0.62, 0.065)),
)):
    add_box(f"Window_Side_Frame_{index + 1:02}", location, dimensions, MATS["wood_deep"], bevel=0.008)

# Physical plaster loss and hairline cracks remain visible at game-camera distance.
wall_patch_front("Plaster_Chip_Front_A", [(-1.01, 0.38), (-0.78, 0.35), (-0.69, 0.51), (-0.82, 0.67), (-1.03, 0.61)], -0.864, MATS["stone"])
wall_patch_front("Plaster_Chip_Front_B", [(0.72, 1.40), (0.94, 1.36), (1.02, 1.52), (0.89, 1.66), (0.70, 1.59)], -0.864, MATS["plaster_shadow"])
wall_patch_side("Plaster_Chip_Side", [(-0.65, 0.44), (-0.35, 0.38), (-0.18, 0.55), (-0.28, 0.73), (-0.58, 0.68)], 1.124, MATS["stone_light"])
crack_front("Wall_Crack_A", [(-0.13, 1.64), (-0.18, 1.51), (-0.12, 1.41), (-0.20, 1.27)], -0.879)
crack_front("Wall_Crack_B", [(0.91, 0.91), (0.83, 0.82), (0.88, 0.72), (0.77, 0.60)], -0.879)


def roof_sag(x: float) -> float:
    return -0.075 * (1.0 - min(1.0, abs(x) / 1.42)) + 0.018 * math.sin(x * 3.2)


def roof_shell(name: str, side: int) -> bpy.types.Object:
    xs = (-1.42, -0.80, -0.15, 0.52, 1.42)
    eave_y = side * 1.06
    vertices: list[tuple[float, float, float]] = []
    for x in xs:
        sag = roof_sag(x)
        vertices.extend(((x, eave_y, 1.74 + sag), (x, 0.0, 2.43 + sag)))
    thickness = 0.085
    vertices.extend((x, y, z - thickness) for x, y, z in list(vertices))
    faces: list[tuple[int, ...]] = []
    count = len(xs) * 2
    for index in range(len(xs) - 1):
        a = index * 2
        b = (index + 1) * 2
        faces.extend(((a, b, b + 1, a + 1), (a + count, a + 1 + count, b + 1 + count, b + count)))
    for edge in (0, len(xs) * 2 - 2):
        faces.append((edge, edge + count, edge + 1 + count, edge + 1))
    if side < 0:
        faces.append(tuple(range(0, count, 2)) + tuple(reversed(range(count - 1, 0, -2))))
    return mesh_object(name, vertices, faces, MATS["roof_deep"])


roof_shell("Roof_Underlay_Front", -1)
roof_shell("Roof_Underlay_Back", 1)

roof_materials = (MATS["roof_shadow"], MATS["roof"], MATS["roof_light"], MATS["deadwood"])
roof_rise = 2.43 - 1.74
roof_run = 1.06
roof_angle = math.atan2(roof_rise, roof_run)
columns = 10
rows = 6
missing = {(6, 2), (7, 2), (7, 3), (8, 3)}
for side in (-1, 1):
    normal = Vector((0.0, side * roof_rise / roof_run, 1.0)).normalized()
    for row in range(rows):
        t = (row + 0.46) / rows
        for column in range(columns):
            if side < 0 and (column, row) in missing:
                continue
            x = -1.35 + (column + 0.5) * 2.70 / columns
            x += RNG.uniform(-0.018, 0.018)
            y = side * roof_run * (1.0 - t)
            z = 1.74 + roof_rise * t + roof_sag(x)
            offset = normal * (0.052 + (row % 2) * 0.005)
            add_box(
                f"Roof_Shingle_{'Back' if side > 0 else 'Front'}_{row + 1:02}_{column + 1:02}",
                tuple(Vector((x, y, z)) + offset),
                (0.31 + RNG.uniform(-0.025, 0.025), 0.235, 0.035),
                roof_materials[(column * 3 + row + (1 if side > 0 else 0)) % len(roof_materials)],
                ((-roof_angle if side > 0 else roof_angle) + RNG.uniform(-0.014, 0.014), 0.0, RNG.uniform(-0.018, 0.018)),
                0.009,
            )

# Exposed rafters inside the missing front-roof patch.
for index, x in enumerate((0.43, 0.70, 0.97)):
    add_beam(
        f"Exposed_Rafter_{index + 1:02}",
        (x, -1.02, 1.76 + roof_sag(x)),
        (x, -0.22, 2.29 + roof_sag(x)),
        0.055,
        MATS["wood_deep"],
        depth=0.07,
    )

# Uneven ridge caps hide the seam while preserving the sagging silhouette.
for index in range(9):
    x = -1.27 + index * 0.315
    add_box(
        f"Roof_Ridge_{index + 1:02}",
        (x, 0.0, 2.45 + roof_sag(x)),
        (0.34, 0.20, 0.12),
        roof_materials[index % 3],
        (0.0, RNG.uniform(-0.08, 0.08), RNG.uniform(-0.025, 0.025)),
        0.018,
    )


def roof_patch(name: str, side: int, points: list[tuple[float, float]], mat: bpy.types.Material) -> None:
    normal = Vector((0.0, side * roof_rise / roof_run, 1.0)).normalized()
    vertices: list[tuple[float, float, float]] = []
    for x, t in points:
        position = Vector((x, side * roof_run * (1 - t), 1.74 + roof_rise * t + roof_sag(x)))
        vertices.append(tuple(position + normal * 0.083))
    mesh_object(name, vertices, [tuple(range(len(vertices)))], mat)


roof_patch("Roof_Moss_Front_A", -1, [(-1.20, 0.12), (-0.64, 0.08), (-0.45, 0.32), (-0.80, 0.48), (-1.22, 0.36)], MATS["moss"])
roof_patch("Roof_Moss_Front_B", -1, [(0.08, 0.64), (0.55, 0.57), (0.72, 0.79), (0.35, 0.93), (-0.02, 0.83)], MATS["moss_deep"])
roof_patch("Roof_Moss_Back", 1, [(-0.18, 0.18), (0.47, 0.10), (0.71, 0.32), (0.28, 0.51), (-0.12, 0.43)], MATS["moss_light"])

# Broken stone chimney. Individual blocks make the top silhouette visibly incomplete.
chimney_x = -0.63
chimney_y = 0.28
for layer in range(5):
    z = 2.08 + layer * 0.16
    for side in (-1, 1):
        if layer == 4 and side > 0:
            continue
        add_box(
            f"Chimney_Block_{layer + 1:02}_{'L' if side < 0 else 'R'}",
            (chimney_x + side * 0.12 + RNG.uniform(-0.015, 0.015), chimney_y, z),
            (0.22, 0.32, 0.145),
            (MATS["stone_deep"], MATS["stone"], MATS["stone_light"])[(layer + (1 if side > 0 else 0)) % 3],
            (RNG.uniform(-0.04, 0.04), RNG.uniform(-0.05, 0.05), RNG.uniform(-0.055, 0.055)),
            0.025,
        )
add_box("Chimney_Soot", (chimney_x, chimney_y, 2.49), (0.19, 0.18, 0.025), MATS["iron"], bevel=0.006)

# Sparse weeds and a snapped rain barrel enrich the base without hiding placement contact.
for index in range(14):
    angle = RNG.uniform(0, math.tau)
    radius = RNG.uniform(1.00, 1.36)
    x = math.cos(angle) * radius
    y = math.sin(angle) * radius * 0.74
    height = RNG.uniform(0.11, 0.24)
    add_beam(
        f"Weed_Stem_{index + 1:02}",
        (x, y, 0.015),
        (x + RNG.uniform(-0.045, 0.045), y + RNG.uniform(-0.045, 0.045), height),
        0.014,
        MATS["moss_deep"] if index % 3 else MATS["moss_light"],
        depth=0.011,
    )

barrel_center = Vector((-1.28, -0.52, 0.30))
for index in range(7):
    angle = math.tau * index / 7
    add_box(
        f"Broken_Barrel_Stave_{index + 1:02}",
        tuple(barrel_center + Vector((math.cos(angle) * 0.18, math.sin(angle) * 0.18, 0))),
        (0.095, 0.055, 0.52 - (0.12 if index in (1, 2) else 0.0)),
        MATS["wood"] if index % 2 else MATS["deadwood"],
        (math.sin(angle) * 0.10, -math.cos(angle) * 0.10, angle),
        0.010,
    )
for index, z in enumerate((0.12, 0.43)):
    bpy.ops.mesh.primitive_torus_add(major_radius=0.19, minor_radius=0.014, major_segments=12, minor_segments=4, location=(barrel_center.x, barrel_center.y, z))
    keep(bpy.context.object, f"Broken_Barrel_Hoop_{index + 1:02}", MATS["rust"])


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_preview_stage() -> None:
    preview_ground = material("PREVIEW_Ground", "#446258", 1.0)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.012))
    ground = bpy.context.object
    ground.name = "PREVIEW_Ground"
    ground.data.materials.append(preview_ground)

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#1F4840")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.26

    lights = (
        ("PREVIEW_Key", (-4.8, -5.8, 6.4), 720, 4.6, "#FFE8C2"),
        ("PREVIEW_Fill", (5.0, -2.2, 4.1), 420, 4.2, "#83C3AA"),
        ("PREVIEW_Rim", (2.2, 5.0, 5.4), 560, 3.2, "#C5E1CD"),
    )
    for name, location, energy, size, color in lights:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = rgba(color)[:3]
        look_at(light, (0, 0, 1.15))

    bpy.ops.object.camera_add(location=(4.5, -6.2, 3.25))
    camera = bpy.context.object
    camera.name = "PREVIEW_Camera"
    camera.data.lens = 56
    look_at(camera, (0, 0, 1.15))
    bpy.context.scene.camera = camera


add_preview_stage()

BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
USDZ_PATH.parent.mkdir(parents=True, exist_ok=True)
RENDER_PATH.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

# Merge by material for low runtime draw-call count while retaining semantic source objects in .blend.
groups: dict[str, list[bpy.types.Object]] = {}
for obj in asset_objects:
    if obj.type != "MESH":
        continue
    material_name = obj.data.materials[0].name if obj.data.materials else "Unmaterialed"
    groups.setdefault(material_name, []).append(obj)

export_objects: list[bpy.types.Object] = []
for material_name, objects in groups.items():
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    merged = bpy.context.object
    merged.name = material_name
    merged.data.name = f"{material_name}_Mesh"
    merged.data.validate(clean_customdata=False)
    merged.data.update()
    export_objects.append(merged)

bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
for obj in export_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = root

bpy.ops.wm.usd_export(
    filepath=str(USDZ_PATH),
    selected_objects_only=True,
    export_animation=False,
    export_materials=True,
    export_normals=True,
    export_uvmaps=False,
    export_armatures=False,
    export_shapekeys=False,
    export_lights=False,
    export_cameras=False,
    export_custom_properties=True,
    generate_preview_surface=True,
    triangulate_meshes=True,
    convert_orientation=True,
    export_global_forward_selection="NEGATIVE_Z",
    export_global_up_selection="Y",
)

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1200
scene.render.resolution_y = 1200
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.filepath = str(RENDER_PATH)
scene.render.film_transparent = False
scene.render.image_settings.color_depth = "8"
scene.view_settings.look = "AgX - Medium High Contrast"
bpy.ops.render.render(write_still=True)

triangles = sum(
    len(polygon.vertices) - 2
    for obj in export_objects
    for polygon in obj.data.polygons
)
print(f"ASSET={root.name} MESHES={len(export_objects)} TRIANGLES={triangles}")
print(f"BLEND={BLEND_PATH}")
print(f"USDZ={USDZ_PATH}")
print(f"RENDER={RENDER_PATH}")
