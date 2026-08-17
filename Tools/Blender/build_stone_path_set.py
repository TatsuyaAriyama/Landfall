"""Build three modular Landfall stone-path pieces from one editable scene."""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/stone_path_set.blend"
RENDER_PATH = ROOT / "marketing/3d/stone-path-set.png"
USDZ_PATHS = {
    "straight": ROOT / "Landfall/Resources/stone_path_straight.usdz",
    "curve": ROOT / "Landfall/Resources/stone_path_curve.usdz",
    "fork": ROOT / "Landfall/Resources/stone_path_fork.usdz",
}
RNG = random.Random(30817)


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def material(name: str, color: str, roughness: float = 0.98) -> bpy.types.Material:
    value = bpy.data.materials.new(name)
    value.diffuse_color = rgba(color)
    value.use_nodes = True
    shader = next(node for node in value.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = rgba(color)
    shader.inputs["Roughness"].default_value = roughness
    return value


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

MATS = {
    "stone_deep": material("LF_PathStoneDeep", "#40504A", 1.0),
    "stone_shadow": material("LF_PathStoneShadow", "#59665E", 0.99),
    "stone": material("LF_PathStone", "#788074", 0.98),
    "stone_light": material("LF_PathStoneLight", "#9B9A86", 0.97),
    "sandstone": material("LF_PathSandstone", "#A49A7B", 0.98),
    "moss_deep": material("LF_PathMossDeep", "#3D583F", 1.0),
    "moss": material("LF_PathMoss", "#627853", 0.99),
    "earth": material("LF_PathEarth", "#574C3B", 1.0),
}

piece_roots: dict[str, bpy.types.Object] = {}
piece_objects: dict[str, list[bpy.types.Object]] = {}
preview_offsets = {
    "straight": Vector((-3.25, 0, 0)),
    "curve": Vector((0, 0, 0)),
    "fork": Vector((3.25, 0, 0)),
}
active_kind = "straight"

for kind, offset in preview_offsets.items():
    root = bpy.data.objects.new(f"Stone_Path_{kind.title()}", None)
    bpy.context.collection.objects.link(root)
    root.location = offset
    piece_roots[kind] = root
    piece_objects[kind] = []


def keep(obj: bpy.types.Object, name: str, mat: bpy.types.Material) -> bpy.types.Object:
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    if not obj.data.materials:
        obj.data.materials.append(mat)
    obj.parent = piece_roots[active_kind]
    piece_objects[active_kind].append(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def add_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    mat: bpy.types.Material,
    rotation: tuple[float, float, float] = (0, 0, 0),
    bevel: float = 0.018,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        modifier = obj.modifiers.new(name="Footworn edges", type="BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.rotation_euler = rotation
    return keep(obj, name, mat)


def add_stone(index: int, x: float, y: float, heading: float, *, broad: bool = False) -> None:
    width = RNG.uniform(0.54, 0.72) * (1.16 if broad else 1.0)
    length = RNG.uniform(0.34, 0.48) * (1.10 if broad else 1.0)
    height = RNG.uniform(0.09, 0.15)
    palette = (MATS["stone_deep"], MATS["stone_shadow"], MATS["stone"], MATS["stone_light"], MATS["sandstone"])
    add_box(
        f"Path_Stone_{index + 1:02}",
        (x + RNG.uniform(-0.035, 0.035), y + RNG.uniform(-0.025, 0.025), height * 0.5 - 0.012),
        (width, length, height),
        palette[(index * 3 + len(active_kind)) % len(palette)],
        (RNG.uniform(-0.025, 0.025), RNG.uniform(-0.025, 0.025), heading + RNG.uniform(-0.08, 0.08)),
        0.025,
    )
    if index % 3 == 1:
        side = -1 if index % 2 else 1
        add_box(
            f"Stone_Moss_{index + 1:02}",
            (x + math.cos(heading) * side * width * 0.22, y + math.sin(heading) * side * width * 0.22, height + 0.006),
            (width * 0.34, length * 0.28, 0.022),
            MATS["moss"] if index % 4 else MATS["moss_deep"],
            (0, 0, heading + RNG.uniform(-0.12, 0.12)),
            0.014,
        )


def add_pebbles(seed_offset: int, positions: list[tuple[float, float]]) -> None:
    for index, (x, y) in enumerate(positions):
        bpy.ops.mesh.primitive_ico_sphere_add(
            subdivisions=1,
            radius=1,
            location=(x, y, RNG.uniform(0.025, 0.055)),
        )
        pebble = bpy.context.object
        pebble.scale = (RNG.uniform(0.08, 0.15), RNG.uniform(0.06, 0.12), RNG.uniform(0.04, 0.08))
        pebble.rotation_euler = (RNG.uniform(-0.2, 0.2), RNG.uniform(-0.2, 0.2), RNG.uniform(0, math.tau))
        keep(pebble, f"Path_Pebble_{seed_offset + index + 1:02}", MATS["stone_shadow"] if index % 2 else MATS["stone_deep"])


# Straight piece: centers align on the local Y axis with subtle hand-set drift.
active_kind = "straight"
for index in range(9):
    add_stone(index, (-0.08 if index % 2 else 0.08), -1.55 + index * 0.39, 0, broad=index in (0, 8))
add_pebbles(0, [(-0.43, -1.15), (0.45, -0.52), (-0.44, 0.25), (0.42, 0.92), (-0.38, 1.42)])

# Curve piece: a quarter-turn module whose ends remain tangent-compatible.
active_kind = "curve"
curve_radius = 1.45
for index in range(10):
    ratio = index / 9
    angle = math.radians(-92 + ratio * 92)
    x = -curve_radius + math.cos(angle) * curve_radius
    y = 1.45 + math.sin(angle) * curve_radius
    heading = angle + math.pi * 0.5
    add_stone(index, x, y, heading, broad=index in (0, 9))
add_pebbles(20, [(-1.20, 0.08), (-0.92, 0.38), (-0.62, 0.78), (-0.15, 1.12), (0.28, 1.38)])

# Fork piece: shared stem branches left and right with an enlarged junction stone.
active_kind = "fork"
index = 0
for y in (-1.48, -1.08, -0.68, -0.28):
    add_stone(index, 0, y, 0, broad=index == 0)
    index += 1
add_stone(index, 0, 0.12, 0, broad=True)
index += 1
for branch_side in (-1, 1):
    for step in range(1, 5):
        ratio = step / 4
        x = branch_side * 1.22 * ratio
        y = 0.12 + 1.22 * ratio
        heading = -branch_side * math.radians(42)
        add_stone(index, x, y, heading, broad=step == 4)
        index += 1
add_pebbles(40, [(-0.42, -0.92), (0.44, -0.52), (-0.55, 0.34), (0.58, 0.36), (-1.10, 1.02), (1.12, 1.04)])


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_preview_stage() -> None:
    ground_mat = material("PREVIEW_Ground", "#405F51", 1.0)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.03))
    ground = bpy.context.object
    ground.name = "PREVIEW_Ground"
    ground.data.materials.append(ground_mat)
    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#143B35")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.24
    for name, location, energy, size, color in (
        ("PREVIEW_Key", (-5.5, -6.5, 8.0), 880, 5.8, "#FFE1B0"),
        ("PREVIEW_Fill", (5.6, -2.0, 5.0), 450, 4.8, "#73B198"),
        ("PREVIEW_Rim", (2.8, 5.5, 6.5), 650, 4.0, "#BBD5C4"),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = rgba(color)[:3]
        look_at(light, (0, 0, 0))
    bpy.ops.object.camera_add(location=(6.4, -8.8, 8.2))
    camera = bpy.context.object
    camera.name = "PREVIEW_Camera"
    camera.data.lens = 58
    look_at(camera, (0, 0, 0))
    bpy.context.scene.camera = camera


add_preview_stage()

BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
RENDER_PATH.parent.mkdir(parents=True, exist_ok=True)
for output_path in USDZ_PATHS.values():
    output_path.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

# Merge each piece independently by material, preserving its own reusable origin.
piece_exports: dict[str, list[bpy.types.Object]] = {}
for kind in ("straight", "curve", "fork"):
    groups: dict[str, list[bpy.types.Object]] = {}
    for obj in piece_objects[kind]:
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
        merged.name = f"{material_name}_{kind.title()}"
        merged.data.name = f"{merged.name}_Mesh"
        merged.data.validate(clean_customdata=False)
        merged.data.update()
        export_objects.append(merged)
    piece_exports[kind] = export_objects

for kind in ("straight", "curve", "fork"):
    root = piece_roots[kind]
    saved_location = root.location.copy()
    root.location = Vector((0, 0, 0))
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for obj in piece_exports[kind]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.wm.usd_export(
        filepath=str(USDZ_PATHS[kind]), selected_objects_only=True, export_animation=False,
        export_materials=True, export_normals=True, export_uvmaps=False,
        export_armatures=False, export_shapekeys=False, export_lights=False,
        export_cameras=False, export_custom_properties=True,
        generate_preview_surface=True, triangulate_meshes=True, convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z", export_global_up_selection="Y",
    )
    root.location = saved_location
    bpy.context.view_layer.update()

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1600
scene.render.resolution_y = 1050
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.filepath = str(RENDER_PATH)
scene.render.film_transparent = False
scene.render.image_settings.color_depth = "8"
scene.view_settings.look = "AgX - Medium High Contrast"
bpy.ops.render.render(write_still=True)

for kind, export_objects in piece_exports.items():
    triangles = sum(len(p.vertices) - 2 for obj in export_objects for p in obj.data.polygons)
    print(f"PIECE={kind} MESHES={len(export_objects)} TRIANGLES={triangles} USDZ={USDZ_PATHS[kind]}")
print(f"BLEND={BLEND_PATH}")
print(f"RENDER={RENDER_PATH}")
