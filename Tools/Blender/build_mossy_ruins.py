"""Build Landfall's mossy coastal ruins with a broken arch and fallen column."""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/mossy_ruins.blend"
USDZ_PATH = ROOT / "Landfall/Resources/mossy_ruins.usdz"
RENDER_PATH = ROOT / "marketing/3d/mossy-ruins.png"
RNG = random.Random(88291)


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def material(name: str, color: str, roughness: float = 0.97, *, metallic: float = 0.0) -> bpy.types.Material:
    value = bpy.data.materials.new(name)
    value.diffuse_color = rgba(color)
    value.use_nodes = True
    value.use_backface_culling = False
    shader = next(node for node in value.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = rgba(color)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    return value


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

MATS = {
    "stone_deep": material("LF_RuinsStoneDeep", "#34433F", 1.0),
    "stone_shadow": material("LF_RuinsStoneShadow", "#4E5D56", 0.99),
    "stone": material("LF_RuinsStone", "#6F776B", 0.98),
    "stone_light": material("LF_RuinsStoneLight", "#969583", 0.97),
    "sandstone": material("LF_RuinsSandstone", "#A09578", 0.98),
    "moss_deep": material("LF_RuinsMossDeep", "#36523A", 1.0),
    "moss": material("LF_RuinsMoss", "#58734D", 0.99),
    "moss_light": material("LF_RuinsMossLight", "#7F8D64", 0.99),
    "vine": material("LF_RuinsVine", "#294B38", 0.99),
    "mark": material("LF_RuinsCarvedMark", "#C3B98F", 0.96),
}

root = bpy.data.objects.new("Mossy_Ruins", None)
bpy.context.collection.objects.link(root)
asset_objects: list[bpy.types.Object] = []


def keep(obj: bpy.types.Object, name: str, mat: bpy.types.Material) -> bpy.types.Object:
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    if not obj.data.materials:
        obj.data.materials.append(mat)
    obj.parent = root
    asset_objects.append(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
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
    rotation: tuple[float, float, float] = (0, 0, 0),
    bevel: float = 0.014,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        modifier = obj.modifiers.new(name="Ancient chips", type="BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.rotation_euler = rotation
    return keep(obj, name, mat)


def add_cylinder(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    mat: bpy.types.Material,
    *,
    vertices: int = 12,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location)
    return keep(bpy.context.object, name, mat)


def add_beam(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius: float,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    a = Vector(start)
    b = Vector(end)
    direction = b - a
    obj = add_cylinder(name, tuple((a + b) * 0.5), radius, direction.length, mat, vertices=10)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return obj


def add_torus(
    name: str,
    location: tuple[float, float, float],
    major_radius: float,
    minor_radius: float,
    mat: bpy.types.Material,
    *,
    rotation: tuple[float, float, float] = (0, 0, 0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=18,
        minor_segments=5,
        location=location,
        rotation=rotation,
    )
    return keep(bpy.context.object, name, mat)


def add_vine(
    name: str,
    points: list[tuple[float, float, float]],
    radius: float,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(f"{name}_Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = radius
    curve.bevel_resolution = 0
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, coordinate in zip(spline.bezier_points, points):
        point.co = coordinate
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    obj.data.name = f"{name}_Mesh"
    obj.parent = root
    asset_objects.append(obj)
    return obj


# Uneven flagstone floor extends through the arch and dissolves into the ground.
floor_specs = [
    (-0.78, -0.48, 0.58, 0.48), (-0.18, -0.50, 0.50, 0.45), (0.38, -0.50, 0.54, 0.46),
    (0.87, -0.47, 0.40, 0.40), (-0.66, 0.02, 0.48, 0.46), (-0.12, 0.02, 0.50, 0.44),
    (0.45, 0.02, 0.54, 0.46), (0.93, 0.06, 0.38, 0.39), (-0.50, 0.52, 0.44, 0.38),
    (0.02, 0.52, 0.48, 0.40), (0.57, 0.50, 0.46, 0.38),
]
stone_mats = (MATS["stone_deep"], MATS["stone_shadow"], MATS["stone"], MATS["stone_light"], MATS["sandstone"])
for index, (x, y, width, length) in enumerate(floor_specs):
    add_box(
        f"Floor_Stone_{index + 1:02}",
        (x + RNG.uniform(-0.025, 0.025), y + RNG.uniform(-0.025, 0.025), RNG.uniform(0.025, 0.055)),
        (width, length, RNG.uniform(0.08, 0.13)),
        stone_mats[(index * 2) % len(stone_mats)],
        (RNG.uniform(-0.04, 0.04), RNG.uniform(-0.04, 0.04), RNG.uniform(-0.10, 0.10)),
        0.025,
    )

# Two block piers preserve a walkable arch opening.
for side, x in (("L", -0.72), ("R", 0.72)):
    for course in range(6):
        z = 0.20 + course * 0.28
        x_shift = RNG.uniform(-0.025, 0.025)
        add_box(
            f"Arch_Pier_{side}_{course + 1:02}",
            (x + x_shift, 0.12 + RNG.uniform(-0.018, 0.018), z),
            (0.46 + RNG.uniform(-0.03, 0.03), 0.48, 0.25),
            stone_mats[(course + (0 if side == "L" else 2)) % len(stone_mats)],
            (RNG.uniform(-0.025, 0.025), RNG.uniform(-0.025, 0.025), RNG.uniform(-0.035, 0.035)),
            0.030,
        )

# Semicircular wedge blocks create the hero silhouette; one missing block exposes age.
arch_center_z = 1.62
arch_radius = 0.73
for index in range(11):
    if index == 8:
        continue
    angle = math.pi - math.pi * index / 10
    x = math.cos(angle) * arch_radius
    z = arch_center_z + math.sin(angle) * arch_radius
    add_box(
        f"Arch_Voussoir_{index + 1:02}",
        (x, 0.12, z),
        (0.34, 0.52, 0.28),
        MATS["sandstone"] if index in (4, 5, 6) else stone_mats[(index + 1) % 4],
        (0, angle - math.pi * 0.5, RNG.uniform(-0.022, 0.022)),
        0.035,
    )

# Broken side walls step down rather than ending in clean rectangles.
left_columns = ((-1.08, 4), (-1.38, 3), (-1.67, 2))
for column, (x, courses) in enumerate(left_columns):
    for course in range(courses):
        add_box(
            f"Left_Wall_{column + 1:02}_{course + 1:02}",
            (x, 0.14, 0.18 + course * 0.29),
            (0.34, 0.50, 0.26),
            stone_mats[(column + course + 1) % 5],
            (RNG.uniform(-0.02, 0.02), RNG.uniform(-0.02, 0.02), RNG.uniform(-0.04, 0.04)),
            0.028,
        )
right_columns = ((1.08, 2), (1.38, 1))
for column, (x, courses) in enumerate(right_columns):
    for course in range(courses):
        add_box(
            f"Right_Wall_{column + 1:02}_{course + 1:02}",
            (x, 0.14, 0.18 + course * 0.29),
            (0.34, 0.50, 0.26),
            stone_mats[(column + course + 3) % 5],
            (RNG.uniform(-0.03, 0.03), RNG.uniform(-0.02, 0.02), RNG.uniform(-0.06, 0.06)),
            0.028,
        )

# A carved Landfall sail on the keystone catches warm light.
mesh_object(
    "Keystone_Sail_Mark",
    [(-0.11, -0.151, 2.25), (-0.11, -0.151, 1.94), (0.15, -0.151, 2.02)],
    [(0, 1, 2)],
    MATS["mark"],
)

# Fallen column, broken capital, and scattered rubble tell how the right wall collapsed.
column_start = Vector((0.58, -0.70, 0.17))
column_end = Vector((1.72, -0.92, 0.28))
add_beam("Fallen_Column", tuple(column_start), tuple(column_end), 0.20, MATS["stone_light"])
direction = (column_end - column_start).normalized()
for ratio in (0.12, 0.45, 0.78):
    point = column_start.lerp(column_end, ratio)
    ring = add_torus("Column_Carved_Band", tuple(point), 0.22, 0.035, MATS["sandstone"], rotation=(math.pi * 0.5, 0, 0))
    ring.rotation_mode = "QUATERNION"
    ring.rotation_quaternion = direction.to_track_quat("Z", "Y")
add_box("Broken_Capital", (1.80, -0.92, 0.25), (0.48, 0.48, 0.30), MATS["sandstone"], (0.20, -0.12, 0.28), 0.045)
for index in range(18):
    angle = RNG.uniform(0, math.tau)
    radius = RNG.uniform(0.75, 2.05)
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=1,
        radius=1,
        location=(math.cos(angle) * radius, math.sin(angle) * radius * 0.66, RNG.uniform(0.07, 0.15)),
    )
    rubble = bpy.context.object
    rubble.scale = (RNG.uniform(0.12, 0.28), RNG.uniform(0.10, 0.24), RNG.uniform(0.08, 0.19))
    rubble.rotation_euler = (RNG.uniform(-0.3, 0.3), RNG.uniform(-0.3, 0.3), RNG.uniform(0, math.tau))
    keep(rubble, f"Rubble_{index + 1:02}", stone_mats[index % 5])

# Vines descend from the broken crown and curl around one pier.
add_vine("Arch_Vine_Left", [(-0.35, -0.17, 2.28), (-0.50, -0.20, 1.92), (-0.65, -0.18, 1.45), (-0.61, -0.20, 1.03)], 0.025, MATS["vine"])
add_vine("Arch_Vine_Right", [(0.48, -0.17, 2.18), (0.62, -0.20, 1.85), (0.66, -0.18, 1.43), (0.80, -0.20, 1.18)], 0.022, MATS["vine"])
moss_specs = (
    (-0.72, 0.34), (-0.72, 0.62), (-0.72, 0.92), (-0.72, 1.22), (-0.72, 1.48),
    (0.72, 0.28), (0.72, 0.58), (0.72, 0.88), (0.72, 1.18), (0.72, 1.46),
    (-1.08, 0.26), (-1.08, 0.55), (-1.08, 0.82),
    (-1.38, 0.24), (-1.38, 0.52), (-1.67, 0.25),
    (1.08, 0.28), (1.08, 0.56),
)
for index, (x, z) in enumerate(moss_specs):
    add_box(
        f"Wall_Moss_{index + 1:02}",
        (x + RNG.uniform(-0.06, 0.06), -0.125, z + RNG.uniform(-0.025, 0.025)),
        (RNG.uniform(0.10, 0.24), 0.022, RNG.uniform(0.06, 0.14)),
        (MATS["moss_deep"], MATS["moss"], MATS["moss_light"])[index % 3],
        (0, RNG.uniform(-0.05, 0.05), RNG.uniform(-0.16, 0.16)),
        0.018,
    )


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_preview_stage() -> None:
    ground_mat = material("PREVIEW_Ground", "#3C6253", 1.0)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.02))
    ground = bpy.context.object
    ground.name = "PREVIEW_Ground"
    ground.data.materials.append(ground_mat)
    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#133A35")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.23
    for name, location, energy, size, color in (
        ("PREVIEW_Key", (-5.2, -6.3, 7.2), 850, 5.3, "#FFE0B1"),
        ("PREVIEW_Fill", (5.0, -2.1, 4.1), 430, 4.5, "#72B198"),
        ("PREVIEW_Rim", (2.5, 5.0, 5.6), 640, 3.8, "#BBD5C5"),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = rgba(color)[:3]
        look_at(light, (0, 0, 1.1))
    bpy.ops.object.camera_add(location=(5.0, -7.2, 3.6))
    camera = bpy.context.object
    camera.name = "PREVIEW_Camera"
    camera.data.lens = 59
    look_at(camera, (0, 0, 1.05))
    bpy.context.scene.camera = camera


add_preview_stage()

BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
USDZ_PATH.parent.mkdir(parents=True, exist_ok=True)
RENDER_PATH.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

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
    filepath=str(USDZ_PATH), selected_objects_only=True, export_animation=False,
    export_materials=True, export_normals=True, export_uvmaps=False,
    export_armatures=False, export_shapekeys=False, export_lights=False,
    export_cameras=False, export_custom_properties=True,
    generate_preview_surface=True, triangulate_meshes=True, convert_orientation=True,
    export_global_forward_selection="NEGATIVE_Z", export_global_up_selection="Y",
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
triangles = sum(len(p.vertices) - 2 for obj in export_objects for p in obj.data.polygons)
print(f"ASSET={root.name} MESHES={len(export_objects)} TRIANGLES={triangles}")
print(f"BLEND={BLEND_PATH}")
print(f"USDZ={USDZ_PATH}")
print(f"RENDER={RENDER_PATH}")
