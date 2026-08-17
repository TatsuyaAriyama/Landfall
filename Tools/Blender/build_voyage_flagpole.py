"""Build Landfall's voyage flagpole with a wind-shaped cloth flag."""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/voyage_flagpole.blend"
USDZ_PATH = ROOT / "Landfall/Resources/voyage_flagpole.usdz"
RENDER_PATH = ROOT / "marketing/3d/voyage-flagpole.png"
RNG = random.Random(61129)


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def material(name: str, color: str, roughness: float = 0.95, *, metallic: float = 0.0) -> bpy.types.Material:
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
    "stone_deep": material("LF_FlagpoleStoneDeep", "#3D4A45", 1.0),
    "stone": material("LF_FlagpoleStone", "#697169", 0.99),
    "stone_light": material("LF_FlagpoleStoneLight", "#918F7E", 0.98),
    "wood_deep": material("LF_FlagpoleWoodDeep", "#362A24", 0.98),
    "wood": material("LF_FlagpoleWood", "#644936", 0.96),
    "wood_light": material("LF_FlagpoleWoodLight", "#896A4C", 0.96),
    "rope": material("LF_FlagpoleRope", "#A18359", 0.99),
    "iron": material("LF_FlagpoleIron", "#293431", 0.84, metallic=0.24),
    "rust": material("LF_FlagpoleRust", "#704835", 0.92, metallic=0.10),
    "flag": material("LF_VoyageFlagCloth", "#D96847", 0.86),
    "flag_deep": material("LF_VoyageFlagDeep", "#A7453A", 0.90),
    "flag_mark": material("LF_VoyageFlagMark", "#EADBAF", 0.91),
    "moss": material("LF_FlagpoleMoss", "#52684C", 1.0),
}

root = bpy.data.objects.new("Voyage_Flagpole", None)
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
    *,
    location: tuple[float, float, float] = (0, 0, 0),
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(mat)
    mesh.validate(clean_customdata=False)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.parent = root
    asset_objects.append(obj)
    return obj


def add_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    mat: bpy.types.Material,
    rotation: tuple[float, float, float] = (0, 0, 0),
    bevel: float = 0.012,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        modifier = obj.modifiers.new(name="Weathered edges", type="BEVEL")
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
    vertices: int = 10,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location)
    return keep(bpy.context.object, name, mat)


def add_beam(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius: float,
    mat: bpy.types.Material,
    *,
    vertices: int = 9,
) -> bpy.types.Object:
    a = Vector(start)
    b = Vector(end)
    direction = b - a
    obj = add_cylinder(name, tuple((a + b) * 0.5), radius, direction.length, mat, vertices=vertices)
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
    major_segments: int = 16,
    minor_segments: int = 4,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=major_segments,
        minor_segments=minor_segments,
        location=location,
    )
    return keep(bpy.context.object, name, mat)


def add_rope(
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


# A compact cairn base gives the tall pole a believable placement contact.
stone_mats = (MATS["stone_deep"], MATS["stone"], MATS["stone_light"])
for index in range(13):
    angle = math.tau * index / 13 + RNG.uniform(-0.07, 0.07)
    radius = RNG.uniform(0.36, 0.50)
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=1,
        radius=1,
        location=(math.cos(angle) * radius, math.sin(angle) * radius, RNG.uniform(0.08, 0.13)),
    )
    stone = bpy.context.object
    stone.scale = (RNG.uniform(0.17, 0.24), RNG.uniform(0.13, 0.20), RNG.uniform(0.11, 0.17))
    stone.rotation_euler = (
        RNG.uniform(-0.18, 0.18), RNG.uniform(-0.18, 0.18), angle + RNG.uniform(-0.28, 0.28)
    )
    keep(stone, f"Base_Stone_{index + 1:02}", stone_mats[index % 3])

add_cylinder("Pole_Foot", (0, 0, 0.22), 0.18, 0.38, MATS["wood_deep"], vertices=12)
add_beam("Flagpole_Main", (0, 0, 0.22), (0.018, -0.012, 3.52), 0.10, MATS["wood"], vertices=12)
add_beam("Flagpole_Sun_Strip", (-0.055, -0.02, 0.38), (-0.038, -0.03, 3.36), 0.022, MATS["wood_light"], vertices=7)

# Iron collars, cap, and a practical halyard cleat.
for index, z in enumerate((0.30, 0.39, 2.75, 3.36)):
    add_torus(f"Pole_Collar_{index + 1:02}", (0, 0, z), 0.105, 0.018, MATS["rust"] if index < 2 else MATS["iron"])
add_cylinder("Pole_Cap", (0.018, -0.012, 3.59), 0.14, 0.14, MATS["iron"], vertices=10)
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.12, location=(0.018, -0.012, 3.71))
keep(bpy.context.object, "Pole_Finial", MATS["iron"])
add_beam("Halyard_Cleat_Pin", (0.13, -0.02, 1.01), (0.13, -0.02, 1.18), 0.025, MATS["iron"], vertices=7)
add_beam("Halyard_Cleat_Arm", (0.02, -0.02, 1.10), (0.24, -0.02, 1.10), 0.028, MATS["iron"], vertices=7)

# Halyard descends with a slight wind bow and wraps at the cleat.
add_rope(
    "Halyard_Long",
    [(0.09, -0.02, 3.39), (0.17, -0.04, 2.55), (0.13, -0.02, 1.12)],
    0.016,
    MATS["rope"],
)
for index, z in enumerate((1.03, 1.08, 1.13)):
    add_torus(f"Halyard_Wrap_{index + 1:02}", (0.13, -0.02, z), 0.060, 0.012, MATS["rope"], major_segments=12)

# Wind-shaped flag uses a local pole-top pivot for the SceneKit sway action.
flag_vertices: list[tuple[float, float, float]] = []
columns = (
    (0.00, 0.00, 0.00),
    (0.34, 0.06, 0.03),
    (0.70, -0.03, -0.02),
    (1.06, 0.09, 0.04),
    (1.40, 0.02, -0.05),
)
top = 0.0
bottom = -0.78
for x, y, z_offset in columns:
    flag_vertices.append((x, y, top + z_offset))
    flag_vertices.append((x, y + 0.018, bottom + z_offset + 0.06 * math.sin(x * 3.2)))
flag_faces: list[tuple[int, ...]] = []
for index in range(len(columns) - 1):
    a = index * 2
    # The final lower corner is omitted to create a small weather-torn swallow notch.
    if index == len(columns) - 2:
        flag_faces.append((a, a + 2, a + 3, a + 1))
    else:
        flag_faces.append((a, a + 2, a + 3, a + 1))
flag = mesh_object(
    "Voyage_Flag_Cloth",
    flag_vertices,
    flag_faces,
    MATS["flag"],
    location=(0.06, 0, 3.36),
)

# Dark hem and pale Landfall sail mark sit just in front of the cloth surface.
hem_points = [(x, y - 0.018, bottom + z_offset + 0.06 * math.sin(x * 3.2)) for x, y, z_offset in columns]
for index, (a, b) in enumerate(zip(hem_points, hem_points[1:])):
    add_beam(
        f"Flag_Hem_{index + 1:02}",
        tuple(Vector(a) + Vector((0.06, 0, 3.36))),
        tuple(Vector(b) + Vector((0.06, 0, 3.36))),
        0.022,
        MATS["flag_deep"],
        vertices=6,
    )

# The mark is a small sail-like triangle following the first cloth wave.
mesh_object(
    "Flag_Sail_Mark",
    [(0.36, -0.032, -0.18), (0.36, -0.032, -0.60), (0.78, -0.055, -0.46)],
    [(0, 1, 2)],
    MATS["flag_mark"],
    location=(0.06, 0, 3.36),
)

# Spare rope and moss keep the base from reading as a clean showroom prop.
for index, radius in enumerate((0.13, 0.18, 0.23)):
    add_torus(
        f"Spare_Rope_{index + 1:02}",
        (0.34 + index * 0.015, -0.20, 0.08 + index * 0.006),
        radius,
        0.016,
        MATS["rope"],
        major_segments=16,
    )
for index in range(8):
    angle = RNG.uniform(0, math.tau)
    radius = RNG.uniform(0.18, 0.55)
    add_box(
        f"Base_Moss_{index + 1:02}",
        (math.cos(angle) * radius, math.sin(angle) * radius, 0.018),
        (RNG.uniform(0.08, 0.20), RNG.uniform(0.05, 0.13), 0.025),
        MATS["moss"],
        (0, 0, RNG.uniform(0, math.tau)),
        0.016,
    )


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_preview_stage() -> None:
    ground_mat = material("PREVIEW_Ground", "#416458", 1.0)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.02))
    ground = bpy.context.object
    ground.name = "PREVIEW_Ground"
    ground.data.materials.append(ground_mat)

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#153C37")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.23

    lights = (
        ("PREVIEW_Key", (-4.8, -5.6, 7.2), 800, 5.0, "#FFE1B2"),
        ("PREVIEW_Fill", (4.5, -2.0, 4.1), 410, 4.2, "#74B39A"),
        ("PREVIEW_Rim", (2.4, 4.8, 5.6), 600, 3.6, "#BBD5C5"),
    )
    for name, location, energy, size, color in lights:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = rgba(color)[:3]
        look_at(light, (0.45, 0, 1.85))

    bpy.ops.object.camera_add(location=(5.0, -7.6, 4.25))
    camera = bpy.context.object
    camera.name = "PREVIEW_Camera"
    camera.data.lens = 64
    look_at(camera, (0.43, 0, 1.82))
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
