"""Build separate weathered wooden desk and chair assets for Landfall."""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/wooden_furniture_set.blend"
RENDER_PATH = ROOT / "marketing/3d/wooden-furniture-set.png"
USDZ_PATHS = {
    "desk": ROOT / "Landfall/Resources/wooden_desk.usdz",
    "chair": ROOT / "Landfall/Resources/wooden_chair.usdz",
}


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float = 0.96,
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
    "wood_deep": material("LF_FurnitureWoodDeep", "#392B23", 1.0),
    "wood_shadow": material("LF_FurnitureWoodShadow", "#503A2B", 0.99),
    "wood": material("LF_FurnitureWood", "#705038", 0.98),
    "wood_warm": material("LF_FurnitureWoodWarm", "#8B6643", 0.97),
    "wood_pale": material("LF_FurnitureWoodPale", "#A58359", 0.98),
    "grain": material("LF_FurnitureWoodGrain", "#30251F", 1.0),
    "iron": material("LF_FurnitureIron", "#283432", 0.78, 0.28),
    "brass": material("LF_FurnitureBrass", "#A47A37", 0.52, 0.52),
    "repair": material("LF_FurnitureRepair", "#526851", 1.0),
}

piece_roots: dict[str, bpy.types.Object] = {}
piece_objects: dict[str, list[bpy.types.Object]] = {}
preview_offsets = {
    "desk": Vector((-1.65, 0.18, 0)),
    "chair": Vector((1.65, -0.10, 0)),
}
active_kind = "desk"

for kind, offset in preview_offsets.items():
    root = bpy.data.objects.new(f"Wooden_{kind.title()}", None)
    bpy.context.collection.objects.link(root)
    root.location = offset
    piece_roots[kind] = root
    piece_objects[kind] = []


def keep(obj: bpy.types.Object, name: str, mat: bpy.types.Material, smooth: bool = False) -> bpy.types.Object:
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    if not obj.data.materials:
        obj.data.materials.append(mat)
    obj.parent = piece_roots[active_kind]
    piece_objects[active_kind].append(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = smooth
    return obj


def add_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    mat: bpy.types.Material,
    rotation: tuple[float, float, float] = (0, 0, 0),
    bevel: float = 0.025,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.rotation_euler = rotation
    if bevel:
        modifier = obj.modifiers.new(name="Hand-worn edges", type="BEVEL")
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
    return keep(obj, name, mat)


# ---------------------------------------------------------------------------
# Desk — broad plank top, working drawer, pegged frame, and lower stretcher.
# ---------------------------------------------------------------------------
active_kind = "desk"
desk_planks = [
    (-0.78, MATS["wood_warm"], -0.008, 0.010),
    (0.00, MATS["wood_pale"], 0.006, -0.006),
    (0.78, MATS["wood"], -0.004, 0.008),
]
for index, (x, mat, y_shift, tilt) in enumerate(desk_planks, 1):
    add_box(
        f"Desk_Top_Plank_{index:02}", (x, y_shift, 1.18), (0.75, 1.17, 0.17), mat,
        (0, tilt, 0), 0.035,
    )

# Under-top frame and slightly splayed legs.
add_box("Desk_Apron_Front", (0, -0.51, 0.96), (2.15, 0.12, 0.32), MATS["wood_shadow"], bevel=0.022)
add_box("Desk_Apron_Back", (0, 0.51, 0.96), (2.15, 0.12, 0.32), MATS["wood_deep"], bevel=0.022)
add_box("Desk_Apron_Left", (-1.06, 0, 0.96), (0.12, 0.92, 0.28), MATS["wood_shadow"], bevel=0.020)
add_box("Desk_Apron_Right", (1.06, 0, 0.96), (0.12, 0.92, 0.28), MATS["wood"], bevel=0.020)

for index, (x, y, rx, ry, mat) in enumerate(
    [(-1.01, -0.43, -0.025, 0.028, MATS["wood"]),
     (1.01, -0.43, -0.025, -0.028, MATS["wood_warm"]),
     (-1.01, 0.43, 0.025, 0.028, MATS["wood_shadow"]),
     (1.01, 0.43, 0.025, -0.028, MATS["wood"])],
    1,
):
    add_box(f"Desk_Leg_{index:02}", (x, y, 0.49), (0.18, 0.18, 0.96), mat, (rx, ry, 0), 0.025)
    add_box(f"Desk_Foot_{index:02}", (x + ry * 0.5, y - rx * 0.5, 0.055), (0.23, 0.23, 0.10), MATS["wood_deep"], bevel=0.025)

add_box("Desk_Lower_Stretcher", (0, 0.38, 0.34), (1.88, 0.12, 0.15), MATS["wood_shadow"], bevel=0.028)
add_box("Desk_Left_Stretcher", (-1.01, 0, 0.34), (0.12, 0.78, 0.14), MATS["wood_deep"], bevel=0.022)
add_box("Desk_Right_Stretcher", (1.01, 0, 0.34), (0.12, 0.78, 0.14), MATS["wood"], bevel=0.022)

# A single centered drawer gives the object a clear "desk" silhouette.
add_box("Desk_Drawer_Front", (0, -0.585, 0.99), (0.88, 0.08, 0.27), MATS["wood_warm"], bevel=0.025)
add_box("Desk_Drawer_Inset", (0, -0.632, 0.99), (0.66, 0.018, 0.12), MATS["wood_shadow"], bevel=0.010)
bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=0.075, location=(0, -0.69, 0.99))
drawer_knob = bpy.context.object
drawer_knob.scale = (1, 0.72, 1)
keep(drawer_knob, "Desk_Drawer_Knob", MATS["brass"], smooth=True)

# Peg heads, corner brackets, and short grain marks reward close viewing.
for index, x in enumerate((-0.90, 0.90), 1):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=12, radius=0.045, depth=0.025, location=(x, -0.585, 0.94), rotation=(math.pi * 0.5, 0, 0)
    )
    keep(bpy.context.object, f"Desk_Frame_Peg_{index:02}", MATS["wood_pale"])
for index, (start, end) in enumerate(
    [((-0.98, -0.25, 1.276), (-0.48, -0.25, 1.276)),
     ((0.22, 0.18, 1.276), (0.71, 0.18, 1.276)),
     ((0.66, -0.36, 1.276), (0.95, -0.36, 1.276))],
    1,
):
    add_cylinder_between(f"Desk_Grain_Mark_{index:02}", start, end, 0.012, MATS["grain"], 8)
for index, x in enumerate((-1.08, 1.08), 1):
    add_box(f"Desk_Corner_Bracket_{index:02}", (x, -0.58, 1.10), (0.08, 0.025, 0.20), MATS["iron"], bevel=0.008)

# ---------------------------------------------------------------------------
# Chair — three-plank seat, tall ladder back, pegged rails, and foot stretchers.
# ---------------------------------------------------------------------------
active_kind = "chair"
for index, (x, mat, tilt) in enumerate(
    [(-0.36, MATS["wood_warm"], 0.012), (0, MATS["wood_pale"], -0.008), (0.36, MATS["wood"], 0.006)],
    1,
):
    add_box(f"Chair_Seat_Plank_{index:02}", (x, -0.02, 0.82), (0.34, 0.96, 0.14), mat, (0, tilt, 0), 0.032)

add_box("Chair_Apron_Front", (0, -0.43, 0.67), (0.92, 0.11, 0.24), MATS["wood_shadow"], bevel=0.022)
add_box("Chair_Apron_Back", (0, 0.41, 0.67), (0.92, 0.11, 0.24), MATS["wood_deep"], bevel=0.022)
add_box("Chair_Apron_Left", (-0.45, -0.01, 0.67), (0.11, 0.77, 0.21), MATS["wood_shadow"], bevel=0.020)
add_box("Chair_Apron_Right", (0.45, -0.01, 0.67), (0.11, 0.77, 0.21), MATS["wood"], bevel=0.020)

for index, (x, mat) in enumerate([(-0.42, MATS["wood"]), (0.42, MATS["wood_warm"])], 1):
    add_box(f"Chair_Front_Leg_{index:02}", (x, -0.38, 0.38), (0.14, 0.14, 0.76), mat, (-0.018, -0.022 if x < 0 else 0.022, 0), 0.023)
    add_box(f"Chair_Front_Foot_{index:02}", (x, -0.39, 0.045), (0.18, 0.18, 0.09), MATS["wood_deep"], bevel=0.022)

# Rear posts rise continuously into the ladder back and lean gently rearward.
for index, (x, mat) in enumerate([(-0.43, MATS["wood_shadow"]), (0.43, MATS["wood"])], 1):
    add_box(f"Chair_Back_Post_{index:02}", (x, 0.43, 0.99), (0.15, 0.15, 1.96), mat, (-0.055, 0, 0), 0.026)
    add_box(f"Chair_Back_Foot_{index:02}", (x, 0.38, 0.045), (0.19, 0.19, 0.09), MATS["wood_deep"], bevel=0.022)

add_box("Chair_Back_Rail_Low", (0, 0.49, 1.24), (0.86, 0.13, 0.18), MATS["wood_warm"], (-0.055, 0, 0), 0.030)
add_box("Chair_Back_Rail_Mid", (0, 0.53, 1.53), (0.86, 0.13, 0.17), MATS["wood_pale"], (-0.055, 0, -0.012), 0.030)
add_box("Chair_Back_Rail_Top", (0, 0.57, 1.86), (1.02, 0.17, 0.24), MATS["wood_warm"], (-0.055, 0, 0.015), 0.045)

# Low stretchers make the chair sturdy and visually grounded.
add_box("Chair_Stretcher_Front", (0, -0.39, 0.31), (0.74, 0.10, 0.12), MATS["wood_shadow"], bevel=0.025)
add_box("Chair_Stretcher_Back", (0, 0.39, 0.31), (0.74, 0.10, 0.12), MATS["wood_deep"], bevel=0.025)
add_box("Chair_Stretcher_Left", (-0.42, 0, 0.32), (0.10, 0.67, 0.11), MATS["wood_shadow"], bevel=0.022)
add_box("Chair_Stretcher_Right", (0.42, 0, 0.32), (0.10, 0.67, 0.11), MATS["wood"], bevel=0.022)

# A small green repair plate and wooden plugs imply years of continued use.
add_box("Chair_Back_Repair", (0.24, 0.615, 1.53), (0.24, 0.025, 0.095), MATS["repair"], (-0.055, 0, 0.04), 0.012)
for index, x in enumerate((-0.33, 0.33), 1):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=12, radius=0.040, depth=0.023, location=(x, -0.495, 0.67), rotation=(math.pi * 0.5, 0, 0)
    )
    keep(bpy.context.object, f"Chair_Apron_Peg_{index:02}", MATS["wood_pale"])


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_preview_stage() -> None:
    ground_mat = material("PREVIEW_Ground", "#365C51", 1.0)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.015))
    ground = bpy.context.object
    ground.name = "PREVIEW_Ground"
    ground.data.materials.append(ground_mat)
    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#103936")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.23
    for name, location, energy, size, color in (
        ("PREVIEW_Key", (-4.8, -5.6, 6.4), 630, 5.4, "#FFD8A0"),
        ("PREVIEW_Fill", (5.0, -2.0, 4.5), 300, 4.6, "#6BAA9A"),
        ("PREVIEW_Rim", (1.8, 5.0, 5.8), 480, 4.0, "#B9D1C2"),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = rgba(color)[:3]
        look_at(light, (0, 0, 0.8))
    bpy.ops.object.camera_add(location=(5.0, -7.2, 4.2))
    camera = bpy.context.object
    camera.name = "PREVIEW_Camera"
    camera.data.lens = 62
    look_at(camera, (0, 0, 0.82))
    bpy.context.scene.camera = camera


add_preview_stage()

BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
RENDER_PATH.parent.mkdir(parents=True, exist_ok=True)
for output_path in USDZ_PATHS.values():
    output_path.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

# Merge each asset independently by material, preserving reusable local origins.
piece_exports: dict[str, list[bpy.types.Object]] = {}
for kind in ("desk", "chair"):
    groups: dict[str, list[bpy.types.Object]] = {}
    for obj in piece_objects[kind]:
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

for kind in ("desk", "chair"):
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
scene.render.resolution_x = 1500
scene.render.resolution_y = 1150
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.color_depth = "8"
scene.render.filepath = str(RENDER_PATH)
scene.render.film_transparent = False
scene.view_settings.look = "AgX - Medium High Contrast"
bpy.ops.render.render(write_still=True)

for kind, export_objects in piece_exports.items():
    triangles = sum(len(p.vertices) - 2 for obj in export_objects for p in obj.data.polygons)
    print(f"PIECE={kind} MESHES={len(export_objects)} TRIANGLES={triangles} USDZ={USDZ_PATHS[kind]}")
print(f"BLEND={BLEND_PATH}")
print(f"RENDER={RENDER_PATH}")
