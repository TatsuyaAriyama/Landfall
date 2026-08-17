"""Build Landfall's mossy stone well with a timber winding frame."""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/stone_well.blend"
USDZ_PATH = ROOT / "Landfall/Resources/stone_well.usdz"
RENDER_PATH = ROOT / "marketing/3d/stone-well.png"
RNG = random.Random(19037)


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float = 0.95,
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
    "stone_deep": material("LF_WellStoneDeep", "#384640", 1.0),
    "stone_shadow": material("LF_WellStoneShadow", "#536057", 0.99),
    "stone": material("LF_WellStone", "#73786A", 0.98),
    "stone_light": material("LF_WellStoneLight", "#98947E", 0.97),
    "mortar": material("LF_WellMortar", "#46514C", 1.0),
    "moss_deep": material("LF_WellMossDeep", "#3E573E", 1.0),
    "moss": material("LF_WellMoss", "#637654", 0.99),
    "wood_deep": material("LF_WellWoodDeep", "#362923", 0.98),
    "wood": material("LF_WellWood", "#5D4333", 0.96),
    "wood_light": material("LF_WellWoodLight", "#806048", 0.96),
    "roof": material("LF_WellRoof", "#4E3D34", 0.98),
    "roof_light": material("LF_WellRoofLight", "#715749", 0.97),
    "rope": material("LF_WellRope", "#9A7952", 0.99),
    "iron": material("LF_WellIron", "#293331", 0.84, metallic=0.23),
    "rust": material("LF_WellRust", "#724936", 0.91, metallic=0.10),
    "water": material(
        "LF_WellWater", "#255F5B", 0.34,
        emission="#1E5552", emission_strength=0.18,
    ),
}

root = bpy.data.objects.new("Stone_Well", None)
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
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
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
    thickness: float,
    mat: bpy.types.Material,
    *,
    square: bool = False,
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
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    major_segments: int = 18,
    minor_segments: int = 5,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=major_segments,
        minor_segments=minor_segments,
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


def ring_block(
    name: str,
    z: float,
    height: float,
    outer_radius: float,
    angle_start: float,
    angle_end: float,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    inner_radius = outer_radius - 0.24
    vertices: list[tuple[float, float, float]] = []
    for radius, level in ((outer_radius, z), (outer_radius, z + height), (inner_radius, z), (inner_radius, z + height)):
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


# Dark core and four offset courses of physical masonry.
add_cylinder("Well_Mortar_Core", (0, 0, 0.43), 0.72, 0.82, MATS["mortar"], vertices=24)
stone_mats = (MATS["stone_deep"], MATS["stone_shadow"], MATS["stone"], MATS["stone_light"])
for course in range(4):
    z = 0.08 + course * 0.205
    offset = (course % 2) * math.tau / 24
    for segment in range(12):
        angle = math.tau * segment / 12 + offset
        half = math.tau / 24 - 0.014
        ring_block(
            f"Well_Block_{course + 1:02}_{segment + 1:02}",
            z + RNG.uniform(-0.006, 0.006),
            0.18,
            0.78 * RNG.uniform(0.986, 1.014),
            angle - half,
            angle + half,
            stone_mats[(course * 3 + segment) % 4],
        )

# Cap stones flare slightly and frame a genuinely dark opening.
for segment in range(12):
    angle = math.tau * segment / 12
    half = math.tau / 24 - 0.014
    ring_block(
        f"Well_Cap_{segment + 1:02}",
        0.88 + RNG.uniform(-0.008, 0.008),
        0.16,
        0.86 * RNG.uniform(0.99, 1.015),
        angle - half,
        angle + half,
        stone_mats[(segment + 2) % 4],
    )
add_cylinder("Well_Dark_Opening", (0, 0, 0.885), 0.58, 0.025, MATS["stone_deep"], vertices=28)
add_cylinder("Well_Water", (0, 0, 0.835), 0.50, 0.018, MATS["water"], vertices=36)
for radius in (0.17, 0.31, 0.44):
    add_torus("Water_Ripple", (0, 0, 0.85), radius, 0.009, MATS["stone_light"], major_segments=24, minor_segments=4)

# Timber winding frame leans just enough to feel handmade.
for side, x in (("L", -0.94), ("R", 0.94)):
    add_beam(
        f"Frame_Post_{side}",
        (x, 0.02, 0.05),
        (x + (0.035 if x < 0 else -0.025), -0.015, 2.31),
        0.18,
        MATS["wood"] if side == "L" else MATS["wood_light"],
        square=True,
    )
    add_beam(
        f"Frame_Brace_{side}",
        (x, 0, 1.37),
        (x * 0.64, 0, 1.82),
        0.105,
        MATS["wood_deep"],
        square=True,
    )
add_beam("Frame_Top", (-1.05, 0, 2.22), (1.05, 0, 2.19), 0.16, MATS["wood_deep"], square=True)

# Horizontal axle, rope windings, crank, and a hanging bucket.
add_beam("Winding_Axle", (-1.04, 0, 1.56), (1.13, 0, 1.54), 0.16, MATS["wood"], square=False)
for index, x in enumerate((-0.16, -0.08, 0.00, 0.08, 0.16)):
    add_torus(
        f"Axle_Rope_{index + 1:02}",
        (x, 0, 1.55),
        0.095,
        0.020,
        MATS["rope"],
        rotation=(0, math.pi * 0.5, 0),
        major_segments=14,
        minor_segments=4,
    )
add_beam("Crank_Arm", (1.10, 0, 1.54), (1.28, 0, 1.22), 0.055, MATS["iron"], square=False)
add_beam("Crank_Handle", (1.28, -0.16, 1.22), (1.28, 0.16, 1.22), 0.065, MATS["wood_light"], square=False)
add_rope(
    "Hanging_Rope",
    [(0, -0.02, 1.48), (0.01, -0.015, 1.15), (-0.03, 0.02, 0.89)],
    0.025,
    MATS["rope"],
)

# Bucket sits just above the opening so it remains readable from all views.
bpy.ops.mesh.primitive_cone_add(vertices=14, radius1=0.18, radius2=0.23, depth=0.30, location=(-0.03, 0.02, 1.00))
keep(bpy.context.object, "Well_Bucket", MATS["wood"])
for z in (0.86, 1.13):
    add_torus("Bucket_Iron_Band", (-0.03, 0.02, z), 0.19 if z < 1 else 0.23, 0.018, MATS["rust"], major_segments=14, minor_segments=4)
add_torus(
    "Bucket_Handle",
    (-0.03, 0.02, 1.10),
    0.27,
    0.018,
    MATS["iron"],
    rotation=(math.pi * 0.5, 0, 0),
    major_segments=16,
    minor_segments=4,
)

# Crooked shingle roof protects the winding gear without hiding it.
roof_angle = math.radians(32)
for side in (-1, 1):
    for row in range(4):
        for column in range(7):
            x = -0.90 + column * 0.30 + RNG.uniform(-0.015, 0.015)
            y = side * (0.16 + row * 0.24)
            z = 2.34 - row * 0.15 + RNG.uniform(-0.008, 0.008)
            add_box(
                f"Roof_Shingle_{'Back' if side > 0 else 'Front'}_{row + 1:02}_{column + 1:02}",
                (x, y, z),
                (0.31, 0.29, 0.055),
                MATS["roof_light"] if (row + column) % 4 == 0 else MATS["roof"],
                ((-roof_angle if side > 0 else roof_angle), 0, RNG.uniform(-0.018, 0.018)),
                0.010,
            )
for index in range(7):
    add_box(
        f"Roof_Ridge_{index + 1:02}",
        (-0.90 + index * 0.30, 0, 2.40),
        (0.32, 0.18, 0.11),
        MATS["roof_light"] if index % 3 == 0 else MATS["roof"],
        (0, RNG.uniform(-0.05, 0.05), RNG.uniform(-0.015, 0.015)),
        0.016,
    )

# Moss clusters favor the damp rear and lower stone courses.
for index in range(18):
    angle = RNG.uniform(0.25, math.pi * 1.75)
    radius = RNG.uniform(0.76, 0.90)
    z = RNG.uniform(0.08, 0.93)
    add_box(
        f"Well_Moss_{index + 1:02}",
        (math.cos(angle) * radius, math.sin(angle) * radius, z),
        (RNG.uniform(0.10, 0.26), 0.026, RNG.uniform(0.05, 0.15)),
        MATS["moss"] if index % 3 else MATS["moss_deep"],
        (RNG.uniform(-0.12, 0.12), 0, angle + math.pi * 0.5),
        0.018,
    )


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_preview_stage() -> None:
    ground_mat = material("PREVIEW_Ground", "#416256", 1.0)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.02))
    ground = bpy.context.object
    ground.name = "PREVIEW_Ground"
    ground.data.materials.append(ground_mat)

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#163D38")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.23

    lights = (
        ("PREVIEW_Key", (-4.6, -5.6, 6.4), 760, 4.8, "#FFE3B5"),
        ("PREVIEW_Fill", (4.6, -2.0, 3.6), 390, 4.2, "#74B19A"),
        ("PREVIEW_Rim", (2.2, 4.5, 4.8), 550, 3.4, "#BDD6C7"),
    )
    for name, location, energy, size, color in lights:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = rgba(color)[:3]
        look_at(light, (0, 0, 1.25))

    bpy.ops.object.camera_add(location=(4.0, -5.8, 3.3))
    camera = bpy.context.object
    camera.name = "PREVIEW_Camera"
    camera.data.lens = 58
    look_at(camera, (0, 0, 1.23))
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
