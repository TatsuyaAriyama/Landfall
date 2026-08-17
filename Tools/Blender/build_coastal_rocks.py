"""Build a weathered coastal-rock cluster for Landfall."""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/coastal_rocks.blend"
USDZ_PATH = ROOT / "Landfall/Resources/coastal_rocks.usdz"
RENDER_PATH = ROOT / "marketing/3d/coastal-rocks.png"
RNG = random.Random(79421)


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float = 0.95,
    metallic: float = 0.0,
) -> bpy.types.Material:
    value = bpy.data.materials.new(name)
    value.diffuse_color = rgba(color)
    value.use_nodes = True
    shader = next(node for node in value.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = rgba(color)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    return value


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

MATS = {
    "rock_deep": material("LF_CoastRockDeep", "#293A3D", 1.0),
    "rock_shadow": material("LF_CoastRockShadow", "#405152", 1.0),
    "rock": material("LF_CoastRock", "#5A6765", 0.99),
    "rock_light": material("LF_CoastRockLight", "#75817B", 0.98),
    "wet": material("LF_CoastRockWet", "#19383D", 0.58),
    "crack": material("LF_CoastRockCrack", "#202E30", 1.0),
    "moss_deep": material("LF_CoastMossDeep", "#344C3D", 1.0),
    "moss": material("LF_CoastMoss", "#567052", 0.99),
    "pool": material("LF_TidePool", "#176E7C", 0.18, 0.08),
    "shell": material("LF_BarnacleShell", "#C5BEA4", 0.9),
}

asset_root = bpy.data.objects.new("Coastal_Rocks", None)
bpy.context.collection.objects.link(asset_root)
asset_objects: list[bpy.types.Object] = []


def keep(obj: bpy.types.Object, name: str, mat: bpy.types.Material) -> bpy.types.Object:
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    if not obj.data.materials:
        obj.data.materials.append(mat)
    obj.parent = asset_root
    asset_objects.append(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def add_rock(
    index: int,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat_key: str,
    rotation: float,
    subdivisions: int = 2,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1, location=location)
    rock = bpy.context.object
    # Distort individual vertices so repeated primitives read as hand-weathered stones.
    for vertex in rock.data.vertices:
        direction = vertex.co.normalized()
        latitude = abs(direction.z)
        noise = RNG.uniform(0.88, 1.13) * (0.95 + latitude * 0.08)
        vertex.co *= noise
    rock.scale = scale
    rock.rotation_euler = (RNG.uniform(-0.10, 0.10), RNG.uniform(-0.10, 0.10), rotation)
    bpy.context.view_layer.objects.active = rock
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return keep(rock, f"Coastal_Rock_{index:02}", MATS[mat_key])


def add_flat_patch(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    rotation: tuple[float, float, float] = (0, 0, 0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1, location=location)
    patch = bpy.context.object
    patch.scale = scale
    patch.rotation_euler = rotation
    bpy.context.view_layer.objects.active = patch
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return keep(patch, name, mat)


# A broad tide pool anchors the cluster and gives the piece its coastal identity.
bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=1, depth=0.035, location=(0.08, -0.24, 0.035))
pool = bpy.context.object
pool.scale = (1.58, 0.98, 1)
bpy.context.view_layer.objects.active = pool
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
keep(pool, "LF_CoastalTidePool", MATS["pool"])

rock_specs = [
    ((-0.08, 0.24, 0.61), (1.12, 0.90, 0.82), "rock", 0.16),
    ((-0.98, 0.62, 0.37), (0.76, 0.58, 0.52), "rock_shadow", -0.32),
    ((0.96, 0.50, 0.40), (0.78, 0.62, 0.56), "rock_light", 0.42),
    ((-1.31, -0.20, 0.27), (0.62, 0.48, 0.39), "rock", 0.22),
    ((1.38, -0.18, 0.31), (0.69, 0.49, 0.44), "rock_shadow", -0.18),
    ((-0.66, -0.76, 0.24), (0.54, 0.43, 0.34), "rock_light", 0.63),
    ((0.66, -0.82, 0.22), (0.52, 0.42, 0.31), "rock", -0.48),
    ((-1.68, 0.45, 0.16), (0.39, 0.31, 0.25), "rock_deep", 0.11),
    ((1.72, 0.36, 0.18), (0.43, 0.32, 0.27), "rock_light", -0.24),
    ((-1.28, -0.83, 0.13), (0.35, 0.29, 0.22), "rock_shadow", 0.73),
    ((1.22, -0.91, 0.14), (0.36, 0.28, 0.23), "rock_deep", -0.58),
    ((0.03, -1.18, 0.13), (0.42, 0.31, 0.21), "rock_light", 0.07),
]
for index, (location, scale, mat_key, rotation) in enumerate(rock_specs, 1):
    add_rock(index, location, scale, mat_key, rotation, 2 if index <= 7 else 1)

# Dark wet bands sit low on the most exposed rocks.
for index, (x, y, z, sx, sy, heading) in enumerate(
    [(-1.03, 0.58, 0.25, 0.59, 0.45, -0.32), (1.01, 0.47, 0.27, 0.61, 0.48, 0.42),
     (-1.31, -0.18, 0.18, 0.48, 0.37, 0.22), (1.39, -0.17, 0.20, 0.52, 0.37, -0.18)],
    1,
):
    add_flat_patch(
        f"Coastal_Wet_Band_{index:02}", (x, y, z), (sx, sy, 0.09), MATS["wet"], (0, 0, heading)
    )

# Moss catches on upper ledges and breaks up the large central silhouette.
for index, (location, scale, rotation) in enumerate(
    [((-0.34, 0.10, 1.35), (0.42, 0.30, 0.055), (0.04, -0.11, 0.18)),
     ((0.41, 0.41, 1.27), (0.29, 0.21, 0.045), (-0.08, 0.16, -0.22)),
     ((-1.03, 0.66, 0.83), (0.27, 0.20, 0.04), (0.08, -0.12, 0.15)),
     ((1.04, 0.52, 0.90), (0.25, 0.19, 0.04), (-0.05, 0.14, -0.28))],
    1,
):
    add_flat_patch(f"Coastal_Moss_{index:02}", location, scale, MATS["moss" if index % 2 else "moss_deep"], rotation)

# Barnacles gather along the damp front edges in small readable clusters.
shell_index = 1
for base_x, base_y, base_z in [(-1.23, -0.48, 0.43), (1.27, -0.43, 0.46), (-0.53, -0.94, 0.35)]:
    for offset_x, offset_y, size in [(-0.09, 0.01, 0.075), (0.02, -0.03, 0.055), (0.10, 0.02, 0.068)]:
        bpy.ops.mesh.primitive_cone_add(
            vertices=8, radius1=size, radius2=size * 0.46, depth=size * 0.82,
            location=(base_x + offset_x, base_y + offset_y, base_z),
        )
        shell = bpy.context.object
        shell.rotation_euler = (math.radians(78), RNG.uniform(-0.22, 0.22), RNG.uniform(-0.35, 0.35))
        keep(shell, f"Coastal_Barnacle_{shell_index:02}", MATS["shell"])
        shell_index += 1


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_preview_stage() -> None:
    ground_mat = material("PREVIEW_Ground", "#31554F", 1.0)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.035))
    ground = bpy.context.object
    ground.name = "PREVIEW_Ground"
    ground.data.materials.append(ground_mat)
    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#0E3435")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.25
    for name, location, energy, size, color in (
        ("PREVIEW_Key", (-4.7, -5.6, 6.8), 520, 5.5, "#FFE1B0"),
        ("PREVIEW_Fill", (5.0, -1.8, 4.2), 260, 4.5, "#67AFA2"),
        ("PREVIEW_Rim", (1.8, 5.0, 5.8), 390, 4.0, "#B9D2C4"),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = rgba(color)[:3]
        look_at(light, (0, 0, 0.45))
    bpy.ops.object.camera_add(location=(4.9, -7.0, 6.2))
    camera = bpy.context.object
    camera.name = "PREVIEW_Camera"
    camera.data.lens = 58
    look_at(camera, (0, 0, 0.46))
    bpy.context.scene.camera = camera


add_preview_stage()

BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
USDZ_PATH.parent.mkdir(parents=True, exist_ok=True)
RENDER_PATH.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

# Keep one mesh per material in the shipped asset to reduce SceneKit traversal cost.
groups: dict[str, list[bpy.types.Object]] = {}
for obj in asset_objects:
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
asset_root.select_set(True)
for obj in export_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = asset_root
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
scene.render.resolution_x = 1400
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.color_depth = "8"
scene.render.filepath = str(RENDER_PATH)
scene.render.film_transparent = False
scene.view_settings.look = "AgX - Medium High Contrast"
bpy.ops.render.render(write_still=True)

triangles = sum(len(p.vertices) - 2 for obj in export_objects for p in obj.data.polygons)
print(f"MESHES={len(export_objects)} TRIANGLES={triangles}")
print(f"BLEND={BLEND_PATH}")
print(f"USDZ={USDZ_PATH}")
print(f"RENDER={RENDER_PATH}")
