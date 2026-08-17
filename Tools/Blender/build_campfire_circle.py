"""Build Landfall's campfire circle with log seats as a reusable 3D asset."""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/campfire_circle.blend"
USDZ_PATH = ROOT / "Landfall/Resources/campfire_circle.usdz"
RENDER_PATH = ROOT / "marketing/3d/campfire-circle.png"
RNG = random.Random(53719)


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float = 0.94,
    *,
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
        emission_input = shader.inputs.get("Emission Color") or shader.inputs.get("Emission")
        if emission_input is not None:
            emission_input.default_value = rgba(emission)
        strength_input = shader.inputs.get("Emission Strength")
        if strength_input is not None:
            strength_input.default_value = emission_strength
    return value


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

MATS = {
    "stone_deep": material("LF_CampfireStoneDeep", "#3D4944", 1.0),
    "stone": material("LF_CampfireStone", "#687069", 0.99),
    "stone_light": material("LF_CampfireStoneLight", "#8A8878", 0.98),
    "ash": material("LF_CampfireAsh", "#423F3A", 1.0),
    "char": material("LF_CampfireChar", "#241F1C", 0.99),
    "ember": material(
        "LF_CampfireEmber", "#C75E2B", 0.82,
        emission="#F07835", emission_strength=2.8,
    ),
    "wood_deep": material("LF_CampfireWoodDeep", "#3B2D25", 0.98),
    "wood": material("LF_CampfireWood", "#624734", 0.96),
    "wood_light": material("LF_CampfireWoodLight", "#87684A", 0.96),
    "cut": material("LF_CampfireCutWood", "#B2966D", 0.97),
    "moss": material("LF_CampfireMoss", "#53684D", 1.0),
    "iron": material("LF_CampfireIron", "#293331", 0.84, metallic=0.22),
    "flame_outer": material(
        "LF_CampfireFlameOuter", "#D95726", 0.42,
        emission="#E5672B", emission_strength=0.45,
    ),
    "flame_mid": material(
        "LF_CampfireFlameMid", "#F39832", 0.38,
        emission="#F6A13A", emission_strength=0.75,
    ),
    "flame_core": material(
        "LF_CampfireFlameCore", "#FFD276", 0.34,
        emission="#FFC95F", emission_strength=1.15,
    ),
}

root = bpy.data.objects.new("Campfire_Circle", None)
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
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel: float = 0.012,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        modifier = obj.modifiers.new(name="Fire-worn edges", type="BEVEL")
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
    major_segments: int = 18,
    minor_segments: int = 5,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=major_segments,
        minor_segments=minor_segments,
        location=location,
    )
    return keep(bpy.context.object, name, mat)


def flame_mesh(
    name: str,
    radius: float,
    height: float,
    z: float,
    mat: bpy.types.Material,
    *,
    phase: float,
    center_x: float = 0.0,
    center_y: float = 0.0,
) -> bpy.types.Object:
    sides = 8
    rings = (
        (0.00, radius * 0.60, 0.00, 0.00),
        (0.24, radius, 0.02, -0.01),
        (0.56, radius * 0.67, -0.05, 0.035),
        (0.82, radius * 0.35, 0.06, -0.025),
        (1.00, 0.018, -0.02, 0.045),
    )
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for ring_index, (ratio, ring_radius, dx, dy) in enumerate(rings):
        for side in range(sides):
            angle = math.tau * side / sides + phase + ring_index * 0.13
            ripple = 1 + 0.10 * math.sin(angle * 3 + ring_index * 0.7)
            vertices.append(
                (
                    center_x + dx + math.cos(angle) * ring_radius * ripple,
                    center_y + dy + math.sin(angle) * ring_radius * ripple,
                    z + ratio * height,
                )
            )
    for ring in range(len(rings) - 1):
        for side in range(sides):
            nxt = (side + 1) % sides
            current = ring * sides
            following = (ring + 1) * sides
            faces.append((current + side, current + nxt, following + nxt, following + side))
    faces.append(tuple(reversed(range(sides))))
    return mesh_object(name, vertices, faces, mat)


# Ash bed and a ring of individually varied stones.
add_cylinder("Ash_Bed", (0, 0, 0.055), 0.62, 0.10, MATS["ash"], vertices=28)
stone_mats = (MATS["stone_deep"], MATS["stone"], MATS["stone_light"])
for index in range(14):
    angle = math.tau * index / 14 + RNG.uniform(-0.045, 0.045)
    radius = RNG.uniform(0.61, 0.68)
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=1,
        radius=1,
        location=(math.cos(angle) * radius, math.sin(angle) * radius, RNG.uniform(0.10, 0.14)),
    )
    stone = bpy.context.object
    stone.scale = (RNG.uniform(0.18, 0.24), RNG.uniform(0.13, 0.19), RNG.uniform(0.12, 0.17))
    stone.rotation_euler = (
        RNG.uniform(-0.20, 0.20), RNG.uniform(-0.16, 0.16), angle + RNG.uniform(-0.25, 0.25)
    )
    keep(stone, f"Fire_Ring_Stone_{index + 1:02}", stone_mats[index % 3])

# Crossed charred logs, glowing cracks, and cut ends.
log_specs = (
    ((-0.42, -0.25, 0.24), (0.42, 0.25, 0.31), 0.105),
    ((-0.40, 0.29, 0.29), (0.42, -0.27, 0.24), 0.105),
    ((-0.46, 0.02, 0.38), (0.44, -0.03, 0.39), 0.095),
    ((-0.02, -0.44, 0.37), (0.04, 0.43, 0.40), 0.090),
)
for index, (start, end, radius) in enumerate(log_specs):
    add_beam(f"Fire_Log_{index + 1:02}", start, end, radius, MATS["char"], vertices=10)
    direction = (Vector(end) - Vector(start)).normalized()
    cut_offset = direction * 0.007
    for side, point in (("A", Vector(start) - cut_offset), ("B", Vector(end) + cut_offset)):
        add_beam(
            f"Fire_Log_Cut_{index + 1:02}_{side}",
            tuple(point - direction * 0.006),
            tuple(point + direction * 0.006),
            radius * 0.78,
            MATS["wood_light"],
            vertices=10,
        )
    add_beam(
        f"Ember_Crack_{index + 1:02}",
        tuple(Vector(start) * 0.46 + Vector(end) * 0.54 + Vector((0, 0, radius * 0.72))),
        tuple(Vector(start) * 0.68 + Vector(end) * 0.32 + Vector((0, 0, radius * 0.72))),
        0.016,
        MATS["ember"],
        vertices=6,
    )

# Three nested faceted flames export as separately named nodes for runtime flicker.
flame_mesh("Flame_Outer", 0.39, 1.02, 0.30, MATS["flame_outer"], phase=0.15)
flame_mesh(
    "Flame_Outer_Lobe", 0.20, 0.63, 0.30, MATS["flame_outer"],
    phase=0.52, center_x=0.25, center_y=-0.03,
)
flame_mesh(
    "Flame_Mid", 0.26, 0.73, 0.30, MATS["flame_mid"],
    phase=0.78, center_x=-0.08, center_y=-0.23,
)
flame_mesh(
    "Flame_Core", 0.14, 0.46, 0.30, MATS["flame_core"],
    phase=1.22, center_x=-0.04, center_y=-0.40,
)

for index, (x, y, z, size) in enumerate(((-0.18, 0.02, 1.27, 0.035), (0.14, -0.05, 1.46, 0.028), (0.03, 0.10, 1.67, 0.022))):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=size, location=(x, y, z))
    keep(bpy.context.object, f"Rising_Spark_{index + 1:02}", MATS["flame_core"])

# Three log benches face the fire while keeping one side open as an entrance.
bench_specs = ((math.radians(28), 1.38), (math.radians(152), 1.38), (math.radians(270), 1.42))
for index, (angle, distance) in enumerate(bench_specs):
    center = Vector((math.cos(angle) * distance, math.sin(angle) * distance, 0.36))
    tangent = Vector((-math.sin(angle), math.cos(angle), 0))
    start = center - tangent * 0.58
    end = center + tangent * 0.58
    add_beam(
        f"Seat_Log_{index + 1:02}",
        tuple(start),
        tuple(end),
        0.19,
        MATS["wood"] if index != 1 else MATS["wood_light"],
        vertices=12,
    )
    direction = (end - start).normalized()
    for side, point in (("A", start - direction * 0.008), ("B", end + direction * 0.008)):
        add_beam(
            f"Seat_Cut_{index + 1:02}_{side}",
            tuple(point - direction * 0.006),
            tuple(point + direction * 0.006),
            0.155,
            MATS["cut"],
            vertices=12,
        )
    radial = Vector((math.cos(angle), math.sin(angle), 0))
    for support_index, along in enumerate((-0.34, 0.34)):
        support_center = center + tangent * along - Vector((0, 0, 0.22))
        add_beam(
            f"Seat_Support_{index + 1:02}_{support_index + 1:02}",
            tuple(support_center - radial * 0.16),
            tuple(support_center + radial * 0.16),
            0.105,
            MATS["wood_deep"],
            vertices=9,
        )

# Sparse moss and a forgotten enamel cup add quiet lived-in detail.
for index in range(9):
    angle = RNG.uniform(0, math.tau)
    radius = RNG.uniform(0.82, 1.80)
    add_box(
        f"Ground_Moss_{index + 1:02}",
        (math.cos(angle) * radius, math.sin(angle) * radius, 0.018),
        (RNG.uniform(0.10, 0.25), RNG.uniform(0.06, 0.15), 0.025),
        MATS["moss"],
        (0, 0, RNG.uniform(0, math.tau)),
        0.018,
    )

cup_angle = math.radians(152)
cup_center = (math.cos(cup_angle) * 1.38 + 0.22, math.sin(cup_angle) * 1.38, 0.61)
add_cylinder("Enamel_Cup", cup_center, 0.075, 0.14, MATS["stone_light"], vertices=12)
add_torus("Enamel_Cup_Rim", (cup_center[0], cup_center[1], cup_center[2] + 0.075), 0.073, 0.012, MATS["iron"], major_segments=12, minor_segments=4)
add_torus("Enamel_Cup_Handle", (cup_center[0] + 0.08, cup_center[1], cup_center[2]), 0.055, 0.012, MATS["iron"], major_segments=10, minor_segments=4)


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_preview_stage() -> None:
    ground_mat = material("PREVIEW_Ground", "#3E6254", 1.0)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.02))
    ground = bpy.context.object
    ground.name = "PREVIEW_Ground"
    ground.data.materials.append(ground_mat)

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#143A36")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.19

    lights = (
        ("PREVIEW_Key", (-4.8, -5.6, 6.2), 660, 4.8, "#FFDDB0"),
        ("PREVIEW_Fill", (4.2, -1.8, 3.5), 340, 4.0, "#71AF97"),
        ("PREVIEW_Rim", (2.4, 4.6, 4.3), 520, 3.4, "#B7D2C2"),
    )
    for name, location, energy, size, color in lights:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = rgba(color)[:3]
        look_at(light, (0, 0, 0.42))

    bpy.ops.object.light_add(type="POINT", location=(0, 0, 0.72))
    fire_light = bpy.context.object
    fire_light.name = "PREVIEW_FireLight"
    fire_light.data.energy = 95
    fire_light.data.color = rgba("#FF9B48")[:3]
    fire_light.data.shadow_soft_size = 1.0

    bpy.ops.object.camera_add(location=(4.2, -5.3, 3.7))
    camera = bpy.context.object
    camera.name = "PREVIEW_Camera"
    camera.data.lens = 57
    look_at(camera, (0, 0, 0.46))
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
