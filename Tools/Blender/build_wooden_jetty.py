"""Build Landfall's long wooden arrival jetty.

The rebuilt jetty keeps the original handcrafted width and shore ramp while
extending the deck to four times its former length. Continuous double rope
rails, toe boards, deep driven piles, and submerged cross-bracing make every
part read as one safe structure rather than a floating prop. One deterministic
build emits the editable Blender source, runtime USDZ, and a review render.
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/wooden_jetty.blend"
USDZ_PATH = ROOT / "Landfall/Resources/wooden_jetty.usdz"
RENDER_PATH = ROOT / "marketing/3d/wooden-jetty.png"
RNG = random.Random(42173)


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float = 0.94,
    *,
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
    "wood_deep": material("LF_JettyWoodDeep", "#342923", 0.99),
    "wood_wet": material("LF_JettyWoodWet", "#47352B", 0.97),
    "wood": material("LF_JettyWood", "#67503E", 0.95),
    "wood_sun": material("LF_JettyWoodSun", "#8A7358", 0.97),
    "wood_pale": material("LF_JettyWoodPale", "#A28C6B", 0.98),
    "rope": material("LF_JettyRope", "#9B7A51", 0.99),
    "rope_dark": material("LF_JettyRopeDark", "#634C35", 0.99),
    "iron": material("LF_JettyIron", "#293331", 0.83, metallic=0.24),
    "rust": material("LF_JettyRust", "#714A35", 0.92, metallic=0.10),
    "moss": material("LF_JettyMoss", "#52694D", 1.0),
}

root = bpy.data.objects.new("Wooden_Jetty", None)
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
        modifier = obj.modifiers.new(name="Tide-worn edges", type="BEVEL")
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
    vertices: int = 8,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    return keep(bpy.context.object, name, mat)


def add_beam(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius: float,
    mat: bpy.types.Material,
    *,
    vertices: int = 7,
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
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    major_segments: int = 16,
    minor_segments: int = 4,
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
    curve.resolution_u = 2
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


# Low shore ramp: local -Y is land, +Y points out toward the water. Preserve
# the old landward endpoint and extend its 3.9 m deck span by exactly 4×.
deck_start = -1.75
legacy_deck_length = 3.90
deck_length = legacy_deck_length * 4
deck_end = deck_start + deck_length
deck_height = 0.39
plank_count = 84
spacing = (deck_end - deck_start) / plank_count
plank_mats = (MATS["wood"], MATS["wood_sun"], MATS["wood_wet"], MATS["wood"], MATS["wood_pale"])

for index in range(plank_count):
    y = deck_start + (index + 0.5) * spacing
    x_shift = RNG.uniform(-0.028, 0.028)
    z_shift = RNG.uniform(-0.009, 0.009)
    yaw = RNG.uniform(-0.018, 0.018)
    width = RNG.uniform(1.23, 1.36)
    # Occasional repairs keep the much longer deck from becoming repetitive.
    if index in (16, 47, 73):
        for side, x in (("L", -0.34), ("R", 0.34)):
            add_box(
                f"Split_Plank_{side}",
                (x + x_shift, y, deck_height + z_shift),
                (0.62, spacing * 0.84, 0.105),
                MATS["wood_wet"] if side == "L" else MATS["wood_sun"],
                (RNG.uniform(-0.012, 0.012), 0, yaw + (0.018 if side == "R" else -0.012)),
                0.016,
            )
        continue
    add_box(
        f"Deck_Plank_{index + 1:02}",
        (x_shift, y, deck_height + z_shift),
        (width, spacing * 0.84, 0.105),
        plank_mats[(index * 3) % len(plank_mats)],
        (RNG.uniform(-0.008, 0.008), 0, yaw),
        0.016,
    )

# A two-board approach slopes down to the island surface.
for index, (y, z, pitch) in enumerate(((-1.93, 0.30, -0.18), (-2.12, 0.19, -0.23))):
    add_box(
        f"Shore_Ramp_{index + 1:02}",
        (0, y, z),
        (1.30, 0.35, 0.105),
        MATS["wood_sun"] if index == 0 else MATS["wood"],
        (pitch, 0, RNG.uniform(-0.01, 0.01)),
        0.018,
    )

# Understructure stays visible between the piles and now runs the full span.
deck_center = (deck_start + deck_end) * 0.5
for x in (-0.47, 0.47):
    add_box(
        f"Long_Stringer_{'L' if x < 0 else 'R'}",
        (x, deck_center, 0.25),
        (0.13, deck_length + 0.15, 0.16),
        MATS["wood_deep"],
        bevel=0.014,
    )

post_spacing = 1.25
post_ys = tuple(
    deck_start + 0.25 + index * post_spacing
    for index in range(13)
)
for index, y in enumerate(post_ys):
    add_box(
        f"Cross_Beam_{index + 1:02}",
        (0, y, 0.21),
        (1.50, 0.14, 0.15),
        MATS["wood_wet"],
        (0, 0, RNG.uniform(-0.015, 0.015)),
        0.014,
    )

# Piles are visibly driven well below the water line. Their 3.2 m submerged
# reach and alternating side braces keep the long pier from appearing to float.
pile_top = 1.10
pile_bottom = -3.20
pile_depth = pile_top - pile_bottom
pile_center = (pile_top + pile_bottom) * 0.5
for row, y in enumerate(post_ys):
    for x in (-0.72, 0.72):
        side = "L" if x < 0 else "R"
        lean_x = RNG.uniform(-0.025, 0.025)
        lean_y = RNG.uniform(-0.020, 0.020)
        add_cylinder(
            f"Pile_{row + 1:02}_{side}",
            (x, y, pile_center),
            0.105 if row % 3 else 0.115,
            pile_depth,
            MATS["wood_wet"],
            vertices=9,
            rotation=(lean_x, lean_y, RNG.uniform(-0.025, 0.025)),
        )
        for wrap, z in enumerate((0.54, 0.60, 0.66)):
            add_torus(
                f"Pile_Rope_{row + 1:02}_{side}_{wrap + 1:02}",
                (x, y, z),
                0.105,
                0.016,
                MATS["rope_dark"],
                rotation=(0, 0, RNG.uniform(-0.08, 0.08)),
            )

# Alternating longitudinal braces are fully submerged but remain visible
# through clear water and in the low arrival camera.
for side, x in (("L", -0.72), ("R", 0.72)):
    for section, (start, end) in enumerate(zip(post_ys[:-1], post_ys[1:])):
        high, low = (-0.30, -1.82) if section % 2 == 0 else (-1.82, -0.30)
        add_beam(
            f"Submerged_Brace_{side}_{section + 1:02}",
            (x, start, high),
            (x, end, low),
            0.050,
            MATS["wood_deep"],
            vertices=7,
        )

for index, y in enumerate(post_ys[1:-1:3]):
    add_beam(
        f"Submerged_Cross_Tie_{index + 1:02}",
        (-0.72, y, -1.70),
        (0.72, y, -1.70),
        0.052,
        MATS["wood_deep"],
        vertices=7,
    )

# Low toe boards remove the ambiguous open strip beneath the rope railing.
for side, x in (("L", -0.67), ("R", 0.67)):
    add_box(
        f"Toe_Board_{side}",
        (x, deck_center, 0.49),
        (0.085, deck_length - 0.12, 0.16),
        MATS["wood_deep"],
        bevel=0.016,
    )

# Each side is authored as two continuous ropes. Mid-span sag points are part
# of the same curve, so there are no floating endpoints or pass-through gaps.
for side, x in (("L", -0.72), ("R", 0.72)):
    upper_points: list[tuple[float, float, float]] = []
    lower_points: list[tuple[float, float, float]] = []
    for section, (start, end) in enumerate(zip(post_ys[:-1], post_ys[1:])):
        if section == 0:
            upper_points.append((x, start, 1.02))
            lower_points.append((x, start, 0.76))
        middle = (start + end) * 0.5
        upper_points.extend(((x, middle, 0.85), (x, end, 1.02)))
        lower_points.extend(((x, middle, 0.65), (x, end, 0.76)))
    add_rope(
        f"Continuous_Upper_Rope_{side}",
        upper_points,
        0.026,
        MATS["rope"],
    )
    add_rope(
        f"Continuous_Lower_Rope_{side}",
        lower_points,
        0.023,
        MATS["rope_dark"],
    )

# Nail heads and shallow cracks sell the deck at close range.
for index in range(1, plank_count, 3):
    y = deck_start + (index + 0.5) * spacing
    for side, x in (("L", -0.48), ("R", 0.48)):
        add_cylinder(
            f"Deck_Nail_{index + 1:02}_{side}",
            (x, y, deck_height + 0.060),
            0.018,
            0.018,
            MATS["iron"],
            vertices=8,
        )
crack_specs = [
    (
        RNG.uniform(-0.36, 0.36),
        deck_start + 0.72 + index * (deck_length - 1.44) / 11,
        RNG.uniform(0.22, 0.34),
    )
    for index in range(12)
]
for index, (x, y, length) in enumerate(crack_specs):
    add_beam(
        f"Deck_Crack_{index + 1:02}",
        (x - length * 0.5, y, deck_height + 0.064),
        (x + length * 0.5, y + 0.02, deck_height + 0.064),
        0.009,
        MATS["wood_deep"],
        vertices=5,
    )

# Mooring cleats repeat at useful intervals along the extended berth.
for index, (x, y) in enumerate(((-0.45, 0.16), (0.45, 4.60), (-0.45, 9.10), (0.45, 12.75))):
    add_cylinder(f"Cleat_Pin_{index + 1:02}", (x, y, 0.52), 0.027, 0.16, MATS["iron"], vertices=7)
    add_beam(
        f"Cleat_Arm_{index + 1:02}",
        (x - 0.12, y, 0.59),
        (x + 0.12, y, 0.59),
        0.030,
        MATS["iron"],
        vertices=7,
    )

coil_y = 10.65
for index, radius in enumerate((0.12, 0.16, 0.20, 0.235)):
    add_torus(
        f"Rope_Coil_{index + 1:02}",
        (0.27 + index * 0.008, coil_y - index * 0.012, 0.468 + index * 0.004),
        radius,
        0.018,
        MATS["rope"] if index % 2 else MATS["rope_dark"],
        rotation=(0, 0, 0.15 + index * 0.08),
        major_segments=18,
    )

# Seaward ladder reaches below deck height without increasing the placement footprint.
for x in (-0.25, 0.25):
    add_beam(
        f"Ladder_Rail_{'L' if x < 0 else 'R'}",
        (x, deck_end + 0.03, 0.52),
        (x, deck_end + 0.15, -0.30),
        0.032,
        MATS["rust"],
        vertices=7,
    )
for index, z in enumerate((0.12, 0.28, 0.44)):
    add_beam(
        f"Ladder_Rung_{index + 1:02}",
        (-0.25, deck_end + 0.125 - z * 0.12, z - 0.20),
        (0.25, deck_end + 0.125 - z * 0.12, z - 0.20),
        0.026,
        MATS["rust"],
        vertices=7,
    )

# Small moss straps around the landward piles blend the prop into grassy islands.
for index, (x, y) in enumerate(((-0.72, -1.50), (0.72, -1.50), (-0.72, -0.43))):
    add_torus(
        f"Pile_Moss_{index + 1:02}",
        (x, y, 0.12 + index * 0.018),
        0.108,
        0.026,
        MATS["moss"],
        rotation=(0.06 * (index - 1), 0, 0.10 * index),
    )


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_preview_stage() -> None:
    sea_mat = material("PREVIEW_Sea", "#225D53", 0.76)
    shore_mat = material("PREVIEW_Shore", "#788573", 1.0)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 5.5, -0.025))
    sea = bpy.context.object
    sea.name = "PREVIEW_Sea"
    sea.data.materials.append(sea_mat)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -2.80, -0.02))
    shore = bpy.context.object
    shore.name = "PREVIEW_Shore"
    shore.dimensions = (8.0, 2.0, 0.14)
    shore.data.materials.append(shore_mat)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#183F3A")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.25

    lights = (
        ("PREVIEW_Key", (-5.0, -5.5, 7.0), 820, 5.4, "#FFE4B8"),
        ("PREVIEW_Fill", (5.3, -1.8, 3.8), 440, 4.6, "#72B29C"),
        ("PREVIEW_Rim", (2.8, 5.2, 4.8), 650, 3.8, "#B9D6C6"),
    )
    for name, location, energy, size, color in lights:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = rgba(color)[:3]
        look_at(light, (0, 5.6, 0.15))

    bpy.ops.object.camera_add(location=(8.6, -7.8, 8.4))
    camera = bpy.context.object
    camera.name = "PREVIEW_Camera"
    camera.data.lens = 57
    look_at(camera, (0, 5.7, 0.18))
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
