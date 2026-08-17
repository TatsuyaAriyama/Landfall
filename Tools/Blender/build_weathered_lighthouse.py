"""Build Landfall's weathered stone lighthouse as a standalone 3D asset.

The compact hero prop uses physical low-poly masonry, a chipped footing, an
iron balcony, a glazed lantern room, a rotating beacon assembly, and coastal
moss. One deterministic build produces the editable source, runtime USDZ, and
a square review render.
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/weathered_lighthouse.blend"
USDZ_PATH = ROOT / "Landfall/Resources/weathered_lighthouse.usdz"
RENDER_PATH = ROOT / "marketing/3d/weathered-lighthouse.png"
RNG = random.Random(82417)


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
    "stone_deep": material("LF_LighthouseStoneDeep", "#3B4946", 1.0),
    "stone_shadow": material("LF_LighthouseStoneShadow", "#53605A", 0.99),
    "stone": material("LF_LighthouseStone", "#747A6D", 0.98),
    "stone_light": material("LF_LighthouseStoneLight", "#989681", 0.97),
    "mortar": material("LF_LighthouseMortar", "#4A544F", 1.0),
    "moss_deep": material("LF_LighthouseMossDeep", "#40583E", 1.0),
    "moss": material("LF_LighthouseMoss", "#647658", 0.99),
    "wood": material("LF_LighthouseDoorWood", "#4C352C", 0.97),
    "wood_light": material("LF_LighthouseDoorWoodLight", "#71503C", 0.95),
    "iron": material("LF_LighthouseIron", "#273331", 0.84, metallic=0.24),
    "iron_rust": material("LF_LighthouseRust", "#704735", 0.91, metallic=0.10),
    "glass": material("LF_LighthouseGlass", "#326C68", 0.42, metallic=0.04),
    "glass_light": material("LF_LighthouseGlassLight", "#74A89A", 0.36),
    "beacon": material(
        "LF_LighthouseBeaconRotor",
        "#F4C76A",
        0.30,
        metallic=0.08,
        emission="#FFD98B",
        emission_strength=4.0,
    ),
    "roof": material("LF_LighthouseRoof", "#29443F", 0.82, metallic=0.18),
    "roof_light": material("LF_LighthouseRoofPatina", "#4F7163", 0.88, metallic=0.10),
}

root = bpy.data.objects.new("Weathered_Lighthouse", None)
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
        modifier = obj.modifiers.new(name="Sea-worn edges", type="BEVEL")
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
    *,
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
        bevel=min(0.012, thickness * 0.12),
    )
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return obj


def add_cylinder(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    mat: bpy.types.Material,
    *,
    vertices: int = 16,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location)
    return keep(bpy.context.object, name, mat)


def add_torus(
    name: str,
    location: tuple[float, float, float],
    major_radius: float,
    minor_radius: float,
    mat: bpy.types.Material,
    *,
    major_segments: int = 24,
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


def ring_block(
    name: str,
    z: float,
    height: float,
    lower_radius: float,
    upper_radius: float,
    angle_start: float,
    angle_end: float,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    inner_lower = max(0.24, lower_radius - 0.22)
    inner_upper = max(0.24, upper_radius - 0.22)
    vertices: list[tuple[float, float, float]] = []
    for radius, level in (
        (lower_radius, z),
        (upper_radius, z + height),
        (inner_lower, z),
        (inner_upper, z + height),
    ):
        vertices.extend(
            (
                (math.cos(angle_start) * radius, math.sin(angle_start) * radius, level),
                (math.cos(angle_end) * radius, math.sin(angle_end) * radius, level),
            )
        )
    faces = [
        (0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
        (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3),
    ]
    return mesh_object(name, vertices, faces, mat)


def radius_at(z: float) -> float:
    return 0.92 + (0.58 - 0.92) * min(max(z / 4.45, 0.0), 1.0)


# Irregular footing and mortar core keep course gaps dark and readable.
stone_mats = (MATS["stone_deep"], MATS["stone_shadow"], MATS["stone"], MATS["stone_light"])
for index in range(22):
    angle = math.tau * index / 22 + RNG.uniform(-0.06, 0.06)
    radius = RNG.uniform(0.82, 1.04)
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=1,
        radius=1.0,
        location=(math.cos(angle) * radius, math.sin(angle) * radius, RNG.uniform(0.06, 0.12)),
    )
    stone = bpy.context.object
    stone.scale = (RNG.uniform(0.19, 0.29), RNG.uniform(0.14, 0.23), RNG.uniform(0.11, 0.17))
    stone.rotation_euler = (
        RNG.uniform(-0.18, 0.18), RNG.uniform(-0.18, 0.18), angle + RNG.uniform(-0.22, 0.22)
    )
    keep(stone, f"Footing_Stone_{index + 1:02}", stone_mats[index % len(stone_mats)])

add_cylinder("Tower_Mortar_Core", (0, 0, 2.24), 0.79, 4.34, MATS["mortar"], vertices=24)

# Twelve offset blocks per course create masonry without bitmap textures.
for course in range(12):
    bottom = 0.18 + course * 0.355
    height = 0.330
    lower = radius_at(bottom) + RNG.uniform(-0.012, 0.012)
    upper = radius_at(bottom + height) + RNG.uniform(-0.012, 0.012)
    offset = (course % 2) * (math.tau / 24)
    for segment in range(12):
        angle = offset + math.tau * segment / 12
        half = math.tau / 24 - 0.012
        ring_block(
            f"Tower_Block_{course + 1:02}_{segment + 1:02}",
            bottom,
            height,
            lower * RNG.uniform(0.99, 1.012),
            upper * RNG.uniform(0.99, 1.012),
            angle - half,
            angle + half,
            stone_mats[(course * 5 + segment * 3) % len(stone_mats)],
        )

# South-facing plank door, stone arch, hardware, and two worn steps.
add_box("Door_Shadow", (0, -0.936, 0.86), (0.53, 0.055, 1.29), MATS["wood"], bevel=0.045)
for index in range(5):
    add_box(
        f"Door_Plank_{index + 1:02}",
        (-0.20 + index * 0.10, -0.972, 0.84 + RNG.uniform(-0.01, 0.01)),
        (0.088, 0.035, 1.18 + RNG.uniform(-0.035, 0.035)),
        MATS["wood_light"] if index % 2 else MATS["wood"],
        (0, 0, RNG.uniform(-0.012, 0.012)),
        0.008,
    )
for band_index, z in enumerate((0.40, 0.82, 1.20)):
    add_box(f"Door_Iron_Band_{band_index + 1:02}", (0, -0.997, z), (0.50, 0.025, 0.045), MATS["iron_rust"], bevel=0.006)
add_box("Door_Handle", (0.15, -1.016, 0.83), (0.035, 0.035, 0.13), MATS["iron"], bevel=0.008)
for index, angle in enumerate((math.pi, math.pi * 0.84, math.pi * 0.68, math.pi * 0.52, math.pi * 0.36, math.pi * 0.20, 0.0)):
    add_box(
        f"Door_Arch_Stone_{index + 1:02}",
        (math.cos(angle) * 0.34, -0.985, 1.32 + math.sin(angle) * 0.28),
        (0.16, 0.16, 0.22),
        stone_mats[(index + 1) % 4],
        (0, angle - math.pi * 0.5, 0),
        0.022,
    )
add_box("Door_Step_Lower", (0, -1.13, 0.09), (0.84, 0.45, 0.16), MATS["stone_shadow"], bevel=0.045)
add_box("Door_Step_Upper", (0, -1.01, 0.20), (0.68, 0.32, 0.16), MATS["stone"], bevel=0.035)


def add_window(name: str, angle: float, z: float) -> None:
    radius = radius_at(z) + 0.025
    center = Vector((math.cos(angle) * radius, math.sin(angle) * radius, z))
    tangent = Vector((-math.sin(angle), math.cos(angle), 0))
    normal = Vector((math.cos(angle), math.sin(angle), 0))
    for suffix, offset, dimensions in (
        ("Left", tangent * -0.18, (0.085, 0.10, 0.52)),
        ("Right", tangent * 0.18, (0.085, 0.10, 0.52)),
        ("Bottom", Vector((0, 0, -0.265)), (0.44, 0.11, 0.085)),
        ("Top", Vector((0, 0, 0.265)), (0.44, 0.11, 0.085)),
    ):
        add_box(
            f"{name}_Frame_{suffix}",
            tuple(center + offset + normal * 0.025),
            dimensions,
            MATS["stone_light"],
            (0, 0, angle + math.pi * 0.5),
            0.014,
        )
    add_box(
        f"{name}_Glass", tuple(center + normal * 0.036), (0.30, 0.035, 0.42), MATS["glass"],
        (0, 0, angle + math.pi * 0.5), 0.008,
    )
    add_beam(
        f"{name}_Glint",
        tuple(center - tangent * 0.10 + Vector((0, 0, -0.16)) + normal * 0.06),
        tuple(center + tangent * 0.09 + Vector((0, 0, 0.16)) + normal * 0.06),
        0.025, MATS["glass_light"], depth=0.018,
    )


add_window("Window_East", 0.0, 2.20)
add_window("Window_West", math.pi, 3.26)

# Cracks and lichen break up the regular stone courses.
for crack_index, (angle, z) in enumerate(((0.73, 1.52), (2.30, 2.68), (5.30, 3.60))):
    radius = radius_at(z) + 0.035
    normal = Vector((math.cos(angle), math.sin(angle), 0))
    tangent = Vector((-math.sin(angle), math.cos(angle), 0))
    center = normal * radius + Vector((0, 0, z))
    points = (
        center + tangent * -0.04 + Vector((0, 0, 0.19)),
        center + tangent * 0.05 + Vector((0, 0, 0.05)),
        center + tangent * -0.03 + Vector((0, 0, -0.12)),
        center + tangent * 0.08 + Vector((0, 0, -0.25)),
    )
    for part, (start, end) in enumerate(zip(points, points[1:])):
        add_beam(
            f"Tower_Crack_{crack_index + 1:02}_{part + 1:02}",
            tuple(start + normal * 0.008), tuple(end + normal * 0.008),
            0.018, MATS["stone_deep"], depth=0.012,
        )

for index in range(15):
    angle = RNG.uniform(0, math.tau)
    z = RNG.uniform(0.22, 2.3) if index < 11 else RNG.uniform(2.3, 4.1)
    radius = radius_at(z) + 0.045
    add_box(
        f"Moss_Patch_{index + 1:02}",
        (math.cos(angle) * radius, math.sin(angle) * radius, z),
        (RNG.uniform(0.12, 0.30), 0.025, RNG.uniform(0.07, 0.20)),
        MATS["moss"] if index % 3 else MATS["moss_deep"],
        (RNG.uniform(-0.14, 0.14), 0, angle + math.pi * 0.5),
        0.018,
    )

# Balcony slab, corbels, twin rail rings, and vertical posts.
add_cylinder("Balcony_Slab", (0, 0, 4.47), 0.82, 0.16, MATS["stone_deep"], vertices=24)
add_torus("Balcony_Edge", (0, 0, 4.55), 0.78, 0.055, MATS["stone_light"])
for index in range(12):
    angle = math.tau * index / 12
    x, y = math.cos(angle) * 0.72, math.sin(angle) * 0.72
    add_beam(
        f"Balcony_Post_{index + 1:02}", (x, y, 4.52), (x, y, 5.02), 0.035,
        MATS["iron"] if index % 4 else MATS["iron_rust"],
    )
add_torus("Balcony_Rail_Lower", (0, 0, 4.76), 0.72, 0.028, MATS["iron"], minor_segments=4)
add_torus("Balcony_Rail_Upper", (0, 0, 5.01), 0.72, 0.032, MATS["iron"], minor_segments=4)

# Octagonal lantern room with opaque teal glass for reliable SceneKit rendering.
add_cylinder("Lantern_Base", (0, 0, 4.63), 0.54, 0.18, MATS["iron"], vertices=16)
for index in range(8):
    angle = math.tau * index / 8
    radius = 0.48
    add_box(
        f"Lantern_Glass_{index + 1:02}",
        (math.cos(angle) * radius, math.sin(angle) * radius, 5.17),
        (0.36, 0.035, 0.72),
        MATS["glass_light"] if index in (5, 6) else MATS["glass"],
        (0, 0, angle + math.pi * 0.5), 0.012,
    )
    x, y = math.cos(angle) * 0.515, math.sin(angle) * 0.515
    add_beam(f"Lantern_Frame_{index + 1:02}", (x, y, 4.78), (x, y, 5.55), 0.04, MATS["iron"])
add_torus("Lantern_Frame_Lower", (0, 0, 4.80), 0.51, 0.035, MATS["iron"])
add_torus("Lantern_Frame_Upper", (0, 0, 5.55), 0.51, 0.035, MATS["iron"])

# Runtime finds this material/node name and rotates the compact lens assembly.
beacon_vertices = [
    (-0.44, -0.07, 5.13), (0.44, -0.07, 5.13), (0.44, 0.07, 5.13), (-0.44, 0.07, 5.13),
    (-0.44, -0.07, 5.31), (0.44, -0.07, 5.31), (0.44, 0.07, 5.31), (-0.44, 0.07, 5.31),
]
beacon_faces = [
    (0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1),
    (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0),
]
mesh_object("Lighthouse_Beacon_Rotor", beacon_vertices, beacon_faces, MATS["beacon"])
add_cylinder("Beacon_Pedestal", (0, 0, 5.09), 0.13, 0.48, MATS["iron"], vertices=12)

bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=0.67, radius2=0.08, depth=0.55, location=(0, 0, 5.84))
keep(bpy.context.object, "Lantern_Roof", MATS["roof"])
for index in range(5):
    angle = 0.45 + index * 1.12
    add_box(
        f"Roof_Patina_{index + 1:02}",
        (math.cos(angle) * 0.35, math.sin(angle) * 0.35, 5.88 + RNG.uniform(-0.04, 0.05)),
        (0.22, 0.05, 0.18), MATS["roof_light"],
        (RNG.uniform(-0.30, 0.30), 0, angle + math.pi * 0.5), 0.018,
    )

# Finial and simple weather vane finish the tall silhouette.
add_beam("Roof_Finial", (0, 0, 6.08), (0, 0, 6.45), 0.045, MATS["iron"])
add_beam("Weather_Vane_Arrow", (-0.30, 0, 6.34), (0.34, 0, 6.34), 0.035, MATS["iron"], depth=0.024)
mesh_object("Weather_Vane_Head", [(0.34, 0, 6.34), (0.17, 0, 6.45), (0.17, 0, 6.23)], [(0, 1, 2)], MATS["iron"])
mesh_object("Weather_Vane_Tail", [(-0.30, 0, 6.34), (-0.18, 0, 6.49), (-0.18, 0, 6.19)], [(0, 1, 2)], MATS["iron_rust"])


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_preview_stage() -> None:
    preview_ground = material("PREVIEW_Ground", "#385B52", 1.0)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.018))
    ground = bpy.context.object
    ground.name = "PREVIEW_Ground"
    ground.data.materials.append(preview_ground)

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#173D39")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.24

    lights = (
        ("PREVIEW_Key", (-5.2, -6.8, 9.0), 960, 5.5, "#FFE5B7"),
        ("PREVIEW_Fill", (5.5, -2.6, 5.4), 520, 4.2, "#73B59E"),
        ("PREVIEW_Rim", (3.3, 5.8, 8.0), 820, 4.0, "#B9D7C7"),
    )
    for name, location, energy, size, color in lights:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = rgba(color)[:3]
        look_at(light, (0, 0, 3.0))

    bpy.ops.object.camera_add(location=(8.2, -10.8, 6.1))
    camera = bpy.context.object
    camera.name = "PREVIEW_Camera"
    camera.data.lens = 64
    look_at(camera, (0, 0, 3.05))
    bpy.context.scene.camera = camera


add_preview_stage()

BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
USDZ_PATH.parent.mkdir(parents=True, exist_ok=True)
RENDER_PATH.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

# Merge by material for practical runtime draw calls; .blend retains semantic source objects.
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
