"""Build Landfall's compact cliff lookout with stairs and a brass spyglass."""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/cliff_lookout.blend"
USDZ_PATH = ROOT / "Landfall/Resources/cliff_lookout.usdz"
RENDER_PATH = ROOT / "marketing/3d/cliff-lookout.png"
RNG = random.Random(77143)


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def material(name: str, color: str, roughness: float = 0.95, *, metallic: float = 0.0) -> bpy.types.Material:
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
    "stone_deep": material("LF_LookoutStoneDeep", "#3B4843", 1.0),
    "stone": material("LF_LookoutStone", "#687068", 0.99),
    "stone_light": material("LF_LookoutStoneLight", "#918F7D", 0.98),
    "wood_deep": material("LF_LookoutWoodDeep", "#352923", 0.98),
    "wood_wet": material("LF_LookoutWoodWet", "#49362C", 0.97),
    "wood": material("LF_LookoutWood", "#654B39", 0.96),
    "wood_light": material("LF_LookoutWoodLight", "#8A6D51", 0.96),
    "rope": material("LF_LookoutRope", "#9B7B53", 0.99),
    "iron": material("LF_LookoutIron", "#293331", 0.84, metallic=0.24),
    "rust": material("LF_LookoutRust", "#714936", 0.91, metallic=0.10),
    "brass": material("LF_LookoutBrass", "#9A7740", 0.54, metallic=0.42),
    "glass": material("LF_LookoutGlass", "#33726B", 0.33, metallic=0.05),
    "moss": material("LF_LookoutMoss", "#53694C", 1.0),
}

root = bpy.data.objects.new("Cliff_Lookout", None)
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
    thickness: float,
    mat: bpy.types.Material,
    *,
    square: bool = True,
) -> bpy.types.Object:
    a = Vector(start)
    b = Vector(end)
    direction = b - a
    if square:
        obj = add_box(name, tuple((a + b) * 0.5), (thickness, thickness, direction.length), mat, bevel=thickness * 0.10)
    else:
        obj = add_cylinder(name, tuple((a + b) * 0.5), thickness * 0.5, direction.length, mat, vertices=9)
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
        major_segments=16,
        minor_segments=4,
        location=location,
        rotation=rotation,
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


# Four uneven stone pads and timber legs adapt the platform to rough terrain.
stone_mats = (MATS["stone_deep"], MATS["stone"], MATS["stone_light"])
leg_positions = ((-0.93, -0.58), (0.93, -0.58), (-0.93, 0.65), (0.93, 0.65))
for index, (x, y) in enumerate(leg_positions):
    for stone_index in range(3):
        angle = math.tau * stone_index / 3 + index * 0.4
        bpy.ops.mesh.primitive_ico_sphere_add(
            subdivisions=1,
            radius=1,
            location=(x + math.cos(angle) * 0.16, y + math.sin(angle) * 0.13, 0.08),
        )
        stone = bpy.context.object
        stone.scale = (0.21, 0.17, 0.13)
        stone.rotation_euler = (RNG.uniform(-0.2, 0.2), RNG.uniform(-0.2, 0.2), RNG.uniform(0, math.tau))
        keep(stone, f"Footing_{index + 1:02}_{stone_index + 1:02}", stone_mats[(index + stone_index) % 3])
    add_beam(
        f"Platform_Leg_{index + 1:02}",
        (x, y, 0.08),
        (x + RNG.uniform(-0.025, 0.025), y + RNG.uniform(-0.02, 0.02), 0.92),
        0.16,
        MATS["wood_wet"] if index < 2 else MATS["wood"],
    )

# Cross bracing makes the silhouette convincing from below.
for index, (start, end) in enumerate((
    ((-0.93, -0.58, 0.20), (0.93, -0.58, 0.78)),
    ((0.93, -0.58, 0.20), (-0.93, -0.58, 0.78)),
    ((-0.93, 0.65, 0.20), (0.93, 0.65, 0.78)),
    ((0.93, 0.65, 0.20), (-0.93, 0.65, 0.78)),
)):
    add_beam(f"Platform_Brace_{index + 1:02}", start, end, 0.09, MATS["wood_deep"])

add_box("Platform_Frame", (0, 0.02, 0.88), (2.20, 1.65, 0.18), MATS["wood_deep"], bevel=0.018)
for index in range(11):
    x = -0.99 + index * 0.198
    add_box(
        f"Deck_Plank_{index + 1:02}",
        (x + RNG.uniform(-0.012, 0.012), 0.02, 1.00 + RNG.uniform(-0.006, 0.006)),
        (0.18, 1.60 + RNG.uniform(-0.025, 0.025), 0.105),
        MATS["wood_light"] if index % 5 == 1 else MATS["wood"],
        (0, 0, RNG.uniform(-0.008, 0.008)),
        0.014,
    )

# Five broad steps lead up from local -Y, leaving the near rail open.
for index in range(5):
    y = -1.00 - index * 0.27
    z = 0.88 - index * 0.17
    add_box(
        f"Stair_Tread_{index + 1:02}",
        (0, y, z),
        (0.78, 0.34, 0.12),
        MATS["wood_light"] if index % 2 else MATS["wood"],
        bevel=0.018,
    )
for x in (-0.31, 0.31):
    add_beam("Stair_Stringer", (x, -0.89, 0.76), (x, -2.10, 0.04), 0.11, MATS["wood_deep"])

# Timber posts with rope spans keep the sea-facing side visually open.
rail_posts = ((-1.02, -0.72), (-1.02, 0.02), (-1.02, 0.76), (1.02, -0.72), (1.02, 0.02), (1.02, 0.76), (0, 0.78))
for index, (x, y) in enumerate(rail_posts):
    add_beam(f"Rail_Post_{index + 1:02}", (x, y, 0.92), (x, y, 1.75), 0.12, MATS["wood"])

for side, x in (("L", -1.02), ("R", 1.02)):
    for section, (start, end) in enumerate(((-0.72, 0.02), (0.02, 0.76))):
        add_rope(
            f"Rail_Rope_{side}_{section + 1:02}",
            [(x, start, 1.62), (x, (start + end) * 0.5, 1.48), (x, end, 1.62)],
            0.022,
            MATS["rope"],
        )
add_rope("Rear_Rail_Left", [(-1.02, 0.76, 1.62), (-0.52, 0.78, 1.48), (0, 0.78, 1.62)], 0.022, MATS["rope"])
add_rope("Rear_Rail_Right", [(0, 0.78, 1.62), (0.52, 0.78, 1.48), (1.02, 0.76, 1.62)], 0.022, MATS["rope"])

# Narrow bench occupies one edge without blocking the view.
add_box("Lookout_Bench", (-0.45, 0.48, 1.23), (0.92, 0.30, 0.14), MATS["wood_light"], bevel=0.025)
for x in (-0.75, -0.15):
    add_beam("Bench_Support", (x, 0.48, 1.02), (x, 0.48, 1.20), 0.10, MATS["wood_deep"])

# Brass spyglass on a three-legged iron tripod points toward local +Y.
tripod_center = Vector((0.42, 0.25, 1.05))
tripod_top = Vector((0.42, 0.25, 1.55))
for index, angle in enumerate((0.2, 2.3, 4.4)):
    foot = tripod_center + Vector((math.cos(angle) * 0.31, math.sin(angle) * 0.31, 0))
    add_beam(f"Spyglass_Tripod_{index + 1:02}", tuple(foot), tuple(tripod_top), 0.055, MATS["iron"], square=False)
add_cylinder("Spyglass_Pivot", tuple(tripod_top), 0.12, 0.16, MATS["rust"], vertices=10)
scope_start = Vector((0.42, 0.03, 1.60))
scope_end = Vector((0.42, 0.78, 1.74))
add_beam("Spyglass_Body", tuple(scope_start), tuple(scope_end), 0.16, MATS["brass"], square=False)
direction = (scope_end - scope_start).normalized()
add_beam("Spyglass_Eyepiece", tuple(scope_start - direction * 0.12), tuple(scope_start + direction * 0.03), 0.11, MATS["iron"], square=False)
add_beam("Spyglass_Lens_Rim", tuple(scope_end - direction * 0.02), tuple(scope_end + direction * 0.06), 0.20, MATS["brass"], square=False)
add_beam("Spyglass_Glass", tuple(scope_end + direction * 0.061), tuple(scope_end + direction * 0.075), 0.15, MATS["glass"], square=False)
for offset in (0.28, 0.50):
    point = scope_start + direction * offset
    ring = add_torus("Spyglass_Band", tuple(point), 0.17, 0.018, MATS["iron"], rotation=(math.pi * 0.5, 0, 0))
    ring.rotation_mode = "QUATERNION"
    ring.rotation_quaternion = direction.to_track_quat("Z", "Y")

# Nails, moss, and a small forgotten chart tube add close-range storytelling.
for index, (x, y) in enumerate(((-0.78, -0.50), (0.76, -0.46), (-0.80, 0.47), (0.76, 0.48))):
    add_cylinder(f"Deck_Nail_{index + 1:02}", (x, y, 1.065), 0.022, 0.018, MATS["iron"], vertices=8)
add_cylinder("Chart_Tube", (-0.62, 0.42, 1.39), 0.055, 0.50, MATS["rust"], vertices=10)
for index in range(10):
    angle = RNG.uniform(0, math.tau)
    radius = RNG.uniform(0.65, 1.35)
    add_box(
        f"Lookout_Moss_{index + 1:02}",
        (math.cos(angle) * radius, math.sin(angle) * radius, 0.025),
        (RNG.uniform(0.09, 0.24), RNG.uniform(0.05, 0.14), 0.03),
        MATS["moss"],
        (0, 0, RNG.uniform(0, math.tau)),
        0.018,
    )


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_preview_stage() -> None:
    ground_mat = material("PREVIEW_Ground", "#3F6255", 1.0)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.02))
    ground = bpy.context.object
    ground.name = "PREVIEW_Ground"
    ground.data.materials.append(ground_mat)
    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#143B36")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.23
    for name, location, energy, size, color in (
        ("PREVIEW_Key", (-5.0, -5.8, 7.0), 820, 5.2, "#FFE2B4"),
        ("PREVIEW_Fill", (4.8, -2.0, 4.0), 430, 4.4, "#75B29A"),
        ("PREVIEW_Rim", (2.5, 4.8, 5.2), 620, 3.6, "#BBD5C5"),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = rgba(color)[:3]
        look_at(light, (0, -0.10, 0.90))
    bpy.ops.object.camera_add(location=(5.0, -6.8, 3.8))
    camera = bpy.context.object
    camera.name = "PREVIEW_Camera"
    camera.data.lens = 58
    look_at(camera, (0, -0.10, 0.92))
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
