"""Build a detailed navigator's field tent for Landfall."""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/navigator_tent.blend"
USDZ_PATH = ROOT / "Landfall/Resources/navigator_tent.usdz"
RENDER_PATH = ROOT / "marketing/3d/navigator-tent.png"


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float = 0.92,
    metallic: float = 0.0,
    emission: str | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    value = bpy.data.materials.new(name)
    value.diffuse_color = rgba(color)
    value.use_nodes = True
    shader = next(node for node in value.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = rgba(color)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    if emission:
        shader.inputs["Emission Color"].default_value = rgba(emission)
        shader.inputs["Emission Strength"].default_value = emission_strength
    return value


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

MATS = {
    "canvas_shadow": material("LF_TentCanvasShadow", "#8B8069", 1.0),
    "canvas": material("LF_TentCanvas", "#B6A98A", 0.99),
    "canvas_light": material("LF_TentCanvasLight", "#D1C29C", 0.98),
    "canvas_patch": material("LF_TentCanvasPatch", "#71826A", 1.0),
    "wood_deep": material("LF_TentWoodDeep", "#3A2C22", 1.0),
    "wood": material("LF_TentWood", "#674B32", 0.98),
    "wood_light": material("LF_TentWoodLight", "#8A6640", 0.96),
    "rope": material("LF_TentRope", "#9B8764", 1.0),
    "parchment": material("LF_TentParchment", "#D7BF88", 0.94),
    "ink": material("LF_TentMapInk", "#315B59", 0.98),
    "brass": material("LF_TentBrass", "#9D7739", 0.5, 0.52),
    "bedroll": material("LF_TentBedroll", "#4E6B62", 1.0),
    "glow": material("LF_TentLanternGlow", "#E98B33", 0.28, 0.0, "#FF9A3C", 2.8),
}

asset_root = bpy.data.objects.new("Navigator_Tent", None)
bpy.context.collection.objects.link(asset_root)
asset_objects: list[bpy.types.Object] = []


def keep(obj: bpy.types.Object, name: str, mat: bpy.types.Material, smooth: bool = False) -> bpy.types.Object:
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    if not obj.data.materials:
        obj.data.materials.append(mat)
    obj.parent = asset_root
    asset_objects.append(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = smooth
    return obj


def add_mesh(
    name: str,
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    mat: bpy.types.Material,
    solidify: float = 0.025,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    keep(obj, name, mat)
    if solidify:
        modifier = obj.modifiers.new(name="Canvas thickness", type="SOLIDIFY")
        modifier.thickness = solidify
        modifier.offset = 0
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
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
    obj.rotation_euler = rotation
    if bevel:
        modifier = obj.modifiers.new(name="Worn edges", type="BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return keep(obj, name, mat)


def add_cylinder_between(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius: float,
    mat: bpy.types.Material,
    vertices: int = 10,
) -> bpy.types.Object:
    start_v = Vector(start)
    end_v = Vector(end)
    direction = end_v - start_v
    midpoint = (start_v + end_v) * 0.5
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=direction.length, location=midpoint)
    obj = bpy.context.object
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    obj.rotation_mode = "XYZ"
    return keep(obj, name, mat, smooth=False)


# Ground cloth and the three main tent walls.
add_box("Tent_Groundcloth", (0, 0.06, 0.055), (2.78, 2.25, 0.07), MATS["canvas_shadow"], bevel=0.035)
add_mesh(
    "Tent_Roof_Left",
    [(-1.45, -1.16, 0.27), (0, -1.16, 2.28), (0, 1.16, 2.28), (-1.45, 1.16, 0.27)],
    [(0, 1, 2, 3)], MATS["canvas"],
)
add_mesh(
    "Tent_Roof_Right",
    [(0, -1.16, 2.28), (1.45, -1.16, 0.27), (1.45, 1.16, 0.27), (0, 1.16, 2.28)],
    [(0, 1, 2, 3)], MATS["canvas_light"],
)
add_mesh(
    "Tent_Rear_Wall",
    [(-1.45, 1.17, 0.26), (1.45, 1.17, 0.26), (0, 1.17, 2.28)],
    [(0, 1, 2)], MATS["canvas_shadow"],
)

# Split front flaps leave a broad opening into the working interior.
add_mesh(
    "Tent_Front_Flap_Left",
    [(-1.45, -1.18, 0.26), (-0.78, -1.18, 0.26), (0, -1.18, 2.28)],
    [(0, 1, 2)], MATS["canvas"],
)
add_mesh(
    "Tent_Front_Flap_Right",
    [(0.78, -1.18, 0.26), (1.45, -1.18, 0.26), (0, -1.18, 2.28)],
    [(0, 1, 2)], MATS["canvas_light"],
)

# Canvas repair patches and reinforced corners.
add_box("Tent_Roof_Patch", (-0.77, 0.17, 1.40), (0.50, 0.035, 0.34), MATS["canvas_patch"], (0, math.radians(-36), 0.05), 0.012)
add_mesh(
    "Tent_Rear_Patch",
    [(0.53, 1.185, 0.35), (1.05, 1.185, 0.35), (0.80, 1.185, 0.72)],
    [(0, 1, 2)], MATS["canvas_patch"], 0.012,
)

# Ridge beam, uprights, guy ropes, and eight stakes.
add_cylinder_between("Tent_Ridge_Beam", (0, -1.31, 2.31), (0, 1.31, 2.31), 0.055, MATS["wood_deep"], 12)
add_cylinder_between("Tent_Front_Pole", (0, -1.27, 0.05), (0, -1.27, 2.39), 0.065, MATS["wood"], 12)
add_cylinder_between("Tent_Rear_Pole", (0, 1.27, 0.05), (0, 1.27, 2.39), 0.065, MATS["wood"], 12)

rope_specs = [
    ((0, -1.29, 2.35), (-1.78, -1.80, 0.10)), ((0, -1.29, 2.35), (1.78, -1.80, 0.10)),
    ((0, 1.29, 2.35), (-1.78, 1.72, 0.10)), ((0, 1.29, 2.35), (1.78, 1.72, 0.10)),
    ((-1.42, -1.10, 0.42), (-1.78, -1.36, 0.10)), ((1.42, -1.10, 0.42), (1.78, -1.36, 0.10)),
]
for index, (start, end) in enumerate(rope_specs, 1):
    add_cylinder_between(f"Tent_Guy_Rope_{index:02}", start, end, 0.014, MATS["rope"], 8)
    add_cylinder_between(f"Tent_Stake_{index:02}", (end[0], end[1], 0.03), (end[0], end[1], 0.25), 0.026, MATS["wood_deep"], 8)

# Navigator's map table remains visible through the open front.
add_box("Tent_Map_Tabletop", (0.35, -0.56, 0.77), (1.12, 0.68, 0.10), MATS["wood_light"], bevel=0.035)
for index, (x, y) in enumerate([(-0.13, -0.83), (0.83, -0.83), (-0.13, -0.29), (0.83, -0.29)], 1):
    add_box(f"Tent_Table_Leg_{index:02}", (x, y, 0.40), (0.09, 0.09, 0.70), MATS["wood"], bevel=0.012)
add_box("Tent_Open_Map", (0.29, -0.57, 0.837), (0.78, 0.48, 0.018), MATS["parchment"], (0, 0, -0.06), 0.008)

# Map route: a dark teal polyline made from three slim inlaid segments.
route_points = [(-0.01, -0.66, 0.852), (0.17, -0.52, 0.852), (0.38, -0.63, 0.852), (0.57, -0.48, 0.852)]
for index in range(len(route_points) - 1):
    add_cylinder_between(f"Tent_Map_Route_{index + 1:02}", route_points[index], route_points[index + 1], 0.014, MATS["ink"], 8)

# Compass, rolled chart, and dividers give the tabletop a readable purpose.
bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.105, depth=0.026, location=(0.63, -0.70, 0.861))
keep(bpy.context.object, "Tent_Compass", MATS["brass"])
add_box("Tent_Compass_Needle", (0.63, -0.70, 0.881), (0.025, 0.15, 0.018), MATS["ink"], (0, 0, 0.42), 0.004)
add_cylinder_between("Tent_Rolled_Chart", (-0.10, -0.31, 0.87), (0.45, -0.31, 0.87), 0.055, MATS["parchment"], 16)
add_cylinder_between("Tent_Divider_Left", (0.05, -0.77, 0.88), (0.23, -0.46, 0.88), 0.012, MATS["brass"], 8)
add_cylinder_between("Tent_Divider_Right", (0.05, -0.77, 0.88), (-0.03, -0.43, 0.88), 0.012, MATS["brass"], 8)

# Bedroll and supply chest fill the rear corners without obscuring the workspace.
bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.24, depth=0.86, location=(-0.88, 0.55, 0.28), rotation=(0, math.pi * 0.5, 0.05))
keep(bpy.context.object, "Tent_Bedroll", MATS["bedroll"])
for index, x in enumerate((-1.08, -0.68), 1):
    bpy.ops.mesh.primitive_torus_add(
        major_segments=12, minor_segments=6, major_radius=0.235, minor_radius=0.018,
        location=(x, 0.55, 0.28), rotation=(0, math.pi * 0.5, 0),
    )
    keep(bpy.context.object, f"Tent_Bedroll_Strap_{index:02}", MATS["rope"])
add_box("Tent_Supply_Chest", (0.82, 0.64, 0.30), (0.72, 0.52, 0.48), MATS["wood_deep"], bevel=0.035)
add_box("Tent_Chest_Lid", (0.82, 0.64, 0.57), (0.78, 0.56, 0.10), MATS["wood"], bevel=0.03)
add_box("Tent_Chest_Latch", (0.82, 0.345, 0.47), (0.13, 0.035, 0.18), MATS["brass"], bevel=0.01)

# Hanging lantern: warm emissive core, brass caps, cage, and suspension rope.
add_cylinder_between("Tent_Lantern_Cord", (-0.58, -0.43, 2.00), (-0.58, -0.43, 1.56), 0.012, MATS["rope"], 8)
bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=0.15, location=(-0.58, -0.43, 1.39))
lantern_glow = keep(bpy.context.object, "LF_NavigatorTentLanternGlow", MATS["glow"], smooth=True)
lantern_glow.scale = (0.80, 0.80, 1.10)
for z in (1.23, 1.56):
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.18, depth=0.07, location=(-0.58, -0.43, z))
    keep(bpy.context.object, f"Tent_Lantern_Cap_{'Low' if z < 1.4 else 'High'}", MATS["brass"])
for index, heading in enumerate((0, math.pi * 0.5, math.pi, math.pi * 1.5), 1):
    x = -0.58 + math.cos(heading) * 0.15
    y = -0.43 + math.sin(heading) * 0.15
    add_cylinder_between(f"Tent_Lantern_Cage_{index:02}", (x, y, 1.25), (x, y, 1.55), 0.012, MATS["brass"], 8)


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_preview_stage() -> None:
    ground_mat = material("PREVIEW_Ground", "#345B50", 1.0)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.015))
    ground = bpy.context.object
    ground.name = "PREVIEW_Ground"
    ground.data.materials.append(ground_mat)
    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#103835")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.22
    for name, location, energy, size, color in (
        ("PREVIEW_Key", (-4.8, -5.8, 7.2), 590, 5.6, "#FFD89C"),
        ("PREVIEW_Fill", (5.2, -2.4, 4.8), 285, 4.8, "#69AFA0"),
        ("PREVIEW_Rim", (1.8, 5.4, 6.4), 480, 4.2, "#B9D5C5"),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = rgba(color)[:3]
        look_at(light, (0, 0, 0.9))
    bpy.ops.object.light_add(type="POINT", location=(-0.58, -0.55, 1.40))
    lantern_light = bpy.context.object
    lantern_light.name = "PREVIEW_LanternLight"
    lantern_light.data.energy = 55
    lantern_light.data.color = rgba("#FF9A45")[:3]
    lantern_light.data.shadow_soft_size = 1.1
    bpy.ops.object.camera_add(location=(2.45, -8.35, 4.15))
    camera = bpy.context.object
    camera.name = "PREVIEW_Camera"
    camera.data.lens = 62
    look_at(camera, (0, -0.10, 1.04))
    bpy.context.scene.camera = camera


add_preview_stage()

BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
USDZ_PATH.parent.mkdir(parents=True, exist_ok=True)
RENDER_PATH.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

# Merge meshes per material before export to keep runtime scene traversal shallow.
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
scene.render.resolution_x = 1450
scene.render.resolution_y = 1150
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
