"""Build Landfall's harbor pier, render a preview, and export a web GLB."""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/harbor_pier.blend"
GLB_PATH = ROOT / "web/public/models/harbor_pier.glb"
RENDER_PATH = ROOT / "marketing/3d/harbor-pier.png"

COLORS = {
    "night": "#123830",
    "sea": "#1E5348",
    "sand": "#EADEBD",
    "wood": "#5A2A15",
    "wood_light": "#7A4528",
    "wood_dark": "#3D1D12",
    "rust": "#7A3B22",
    "deep_rust": "#4A1B0C",
    "ember": "#F3C065",
    "orange": "#F5822A",
    "ripple": "#7FB8A6",
}


def rgba(hex_value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = hex_value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def mat(
    name: str,
    color: str,
    roughness: float = 0.88,
    emission: str | None = None,
    strength: float = 0.0,
) -> bpy.types.Material:
    value = bpy.data.materials.new(name)
    value.diffuse_color = rgba(color)
    value.use_nodes = True
    bsdf = value.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = rgba(color)
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = rgba(emission)
        bsdf.inputs["Emission Strength"].default_value = strength
    return value


MATERIALS = {
    "wood": mat("LF_PierWood", COLORS["wood"], 0.9),
    "wood_light": mat("LF_PierWoodSunworn", COLORS["wood_light"], 0.93),
    "wood_dark": mat("LF_PierWoodWet", COLORS["wood_dark"], 0.86),
    "rust": mat("LF_PierRust", COLORS["rust"], 0.82),
    "deep_rust": mat("LF_PierDeepRust", COLORS["deep_rust"], 0.88),
    "sand": mat("LF_PierSand", COLORS["sand"], 0.94),
    "orange": mat("LF_PierReturnOrange", COLORS["orange"], 0.82),
    "glow": mat("LF_PierLanternGlow", COLORS["ember"], 0.4, COLORS["ember"], 5.5),
}


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

root = bpy.data.objects.new("Harbor_Pier", None)
bpy.context.collection.objects.link(root)
asset_objects: list[bpy.types.Object] = []


def keep(obj: bpy.types.Object, name: str, material: bpy.types.Material) -> bpy.types.Object:
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    obj.data.materials.append(material)
    obj.parent = root
    asset_objects.append(obj)
    for face in obj.data.polygons:
        face.use_smooth = False
    return obj


def cube(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    material: bpy.types.Material,
    rotation: tuple[float, float, float] = (0, 0, 0),
    bevel: float = 0.0,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = keep(bpy.context.object, name, material)
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        modifier = obj.modifiers.new("Worn edges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
    return obj


def cylinder(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    material: bpy.types.Material,
    vertices: int = 8,
    rotation: tuple[float, float, float] = (0, 0, 0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    return keep(bpy.context.object, name, material)


def cone(
    name: str,
    location: tuple[float, float, float],
    radius1: float,
    radius2: float,
    depth: float,
    material: bpy.types.Material,
    vertices: int = 8,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius1,
        radius2=radius2,
        depth=depth,
        location=location,
    )
    return keep(bpy.context.object, name, material)


def torus(
    name: str,
    location: tuple[float, float, float],
    major: float,
    minor: float,
    material: bpy.types.Material,
    rotation: tuple[float, float, float] = (0, 0, 0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major,
        minor_radius=minor,
        major_segments=12,
        minor_segments=4,
        location=location,
        rotation=rotation,
    )
    return keep(bpy.context.object, name, material)


def beam(
    name: str,
    a: tuple[float, float, float],
    b: tuple[float, float, float],
    radius: float,
    material: bpy.types.Material,
    vertices: int = 6,
) -> bpy.types.Object:
    start, end = Vector(a), Vector(b)
    delta = end - start
    obj = cylinder(name, tuple((start + end) / 2), radius, delta.length, material, vertices)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Z", "Y")
    return obj


def rope_curve(
    name: str,
    points: list[tuple[float, float, float]],
    radius: float,
    material: bpy.types.Material,
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
    obj.data.materials.append(material)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    obj.data.name = f"{name}_Mesh"
    obj.parent = root
    asset_objects.append(obj)
    return obj


def look_at(obj: bpy.types.Object, point: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()


# Deck: local origin is the shore end; +Z in runtime is represented by +Y in Blender
# so glTF's Y-up conversion produces a pier that extends toward local +Z in Three.js.
deck_y0 = 0.25
deck_length = 3.45
deck_top = 0.63
plank_count = 18
plank_spacing = deck_length / plank_count
for index in range(plank_count):
    y = deck_y0 + (index + 0.5) * plank_spacing
    # Deterministic wear keeps the silhouette handmade without using noisy textures.
    yaw = math.radians(((index * 7) % 9) - 4) * 0.16
    dz = (((index * 13) % 7) - 3) * 0.004
    overhang = (((index * 11) % 5) - 2) * 0.012
    material = (
        MATERIALS["wood_light"]
        if index % 5 == 1
        else MATERIALS["wood_dark"]
        if index % 7 == 0
        else MATERIALS["wood"]
    )
    cube(
        f"Deck_Plank_{index + 1:02}",
        (overhang, y, deck_top + dz),
        (0.56, plank_spacing * 0.43, 0.055),
        material,
        rotation=(0, 0, yaw),
        bevel=0.018,
    )

# Understructure and cross braces.
for x in (-0.43, 0.43):
    cube(
        f"Long_Stringer_{'L' if x < 0 else 'R'}",
        (x, deck_y0 + deck_length / 2, 0.48),
        (0.07, deck_length / 2 + 0.08, 0.09),
        MATERIALS["wood_dark"],
        bevel=0.012,
    )
for index, y in enumerate((0.34, 1.22, 2.10, 2.98, 3.62)):
    cube(
        f"Cross_Beam_{index + 1:02}",
        (0, y, 0.43),
        (0.66, 0.07, 0.075),
        MATERIALS["wood_dark"],
        bevel=0.012,
    )

# Support piles rise above the deck and visibly enter the water.
post_ys = (0.48, 1.52, 2.56, 3.60)
for row, y in enumerate(post_ys):
    for x in (-0.67, 0.67):
        lean = math.radians((row * 3 + (1 if x > 0 else -1)) * 0.45)
        cylinder(
            f"Pile_{row + 1}_{'R' if x > 0 else 'L'}",
            (x, y, 0.34),
            0.09 if row < 3 else 0.105,
            1.38 if row == 3 else 1.18,
            MATERIALS["wood_dark"] if row < 2 else MATERIALS["wood"],
            8,
            rotation=(lean, 0, math.radians(2 if x > 0 else -2)),
        )
        torus(
            f"Pile_Rope_{row + 1}_{'R' if x > 0 else 'L'}",
            (x, y, 0.78),
            0.105,
            0.023,
            MATERIALS["rust"],
        )

# Sagging rope handrail. The lower center points make the span visibly weighted.
for side, x in (("L", -0.67), ("R", 0.67)):
    for section, (a, b) in enumerate(zip(post_ys[:-1], post_ys[1:])):
        middle = (a + b) / 2
        rope_curve(
            f"Hand_Rope_{side}_{section + 1}",
            [(x, a, 1.04), (x, middle, 0.90), (x, b, 1.04)],
            0.018,
            MATERIALS["rust"],
        )

# Two warm harbor lights mark the seaward end.
for side, x in (("L", -0.67), ("R", 0.67)):
    cylinder(f"Lantern_Base_{side}", (x, 3.60, 1.07), 0.16, 0.06, MATERIALS["deep_rust"], 6)
    cylinder(f"Lantern_Glow_{side}", (x, 3.60, 1.23), 0.105, 0.27, MATERIALS["glow"], 8)
    cone(f"Lantern_Roof_{side}", (x, 3.60, 1.42), 0.20, 0.035, 0.15, MATERIALS["rust"], 6)
    for angle in (0, math.pi / 2):
        dx, dy = math.cos(angle) * 0.13, math.sin(angle) * 0.13
        beam(
            f"Lantern_Cage_{side}_{round(angle * 10)}A",
            (x + dx, 3.60 + dy, 1.08),
            (x + dx, 3.60 + dy, 1.37),
            0.012,
            MATERIALS["deep_rust"],
            5,
        )
        beam(
            f"Lantern_Cage_{side}_{round(angle * 10)}B",
            (x - dx, 3.60 - dy, 1.08),
            (x - dx, 3.60 - dy, 1.37),
            0.012,
            MATERIALS["deep_rust"],
            5,
        )

# Mooring cleats and a coiled rope tell the story of boats actually using the pier.
for index, y in enumerate((1.02, 2.22)):
    for x in (-0.46, 0.46):
        cylinder(
            f"Cleat_Pin_{index}_{'L' if x < 0 else 'R'}",
            (x, y, 0.75),
            0.025,
            0.18,
            MATERIALS["deep_rust"],
            6,
        )
        beam(
            f"Cleat_Arm_{index}_{'L' if x < 0 else 'R'}",
            (x - 0.10, y, 0.83),
            (x + 0.10, y, 0.83),
            0.025,
            MATERIALS["deep_rust"],
            6,
        )
for radius in (0.11, 0.15, 0.19):
    torus(
        f"Rope_Coil_{round(radius * 100)}",
        (0.24, 2.86, 0.74 + (radius - 0.11) * 0.08),
        radius,
        0.017,
        MATERIALS["rust"],
    )

# Seaward ladder, tilted just enough to catch the three-quarter view.
for x in (-0.24, 0.24):
    beam(
        f"Ladder_Rail_{'L' if x < 0 else 'R'}",
        (x, 3.79, 0.72),
        (x, 3.91, 0.02),
        0.028,
        MATERIALS["deep_rust"],
        6,
    )
for index, height in enumerate((0.18, 0.37, 0.56)):
    beam(
        f"Ladder_Rung_{index + 1}",
        (-0.24, 3.88 - height * 0.15, height),
        (0.24, 3.88 - height * 0.15, height),
        0.022,
        MATERIALS["deep_rust"],
        6,
    )

# A small return-orange pennant at the shore end anchors it to Landfall's palette.
beam("Pennant_Mast", (-0.61, 0.27, 0.75), (-0.61, 0.27, 1.65), 0.025, MATERIALS["wood"], 6)
mesh = bpy.data.meshes.new("Pier_Pennant_Mesh")
mesh.from_pydata(
    [(-0.61, 0.27, 1.62), (-0.61, 0.27, 1.34), (-0.12, 0.27, 1.50)],
    [],
    [(0, 1, 2)],
)
mesh.materials.append(MATERIALS["orange"])
pennant = bpy.data.objects.new("Pier_Pennant", mesh)
bpy.context.collection.objects.link(pennant)
pennant.parent = root
asset_objects.append(pennant)

# Preview sea and shore rocks are deliberately not exported.
sea_material = mat("PREVIEW_Sea", COLORS["sea"], 0.72)
bpy.ops.mesh.primitive_plane_add(size=24, location=(0, 2.0, -0.01))
sea = bpy.context.object
sea.name = "PREVIEW_Sea"
sea.data.materials.append(sea_material)

for index, (x, y, s) in enumerate(((-0.55, -0.15, 0.65), (0.28, -0.18, 0.8), (0.83, 0.02, 0.52))):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=s, location=(x, y, 0.16))
    rock = bpy.context.object
    rock.name = f"PREVIEW_ShoreRock_{index + 1}"
    rock.scale = (1.3, 0.9, 0.55)
    rock.data.materials.append(MATERIALS["sand"])

world = bpy.context.scene.world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba(COLORS["night"])
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.2

bpy.ops.object.light_add(type="AREA", location=(-4.5, -4.0, 7.0))
key = bpy.context.object
key.name = "PREVIEW_MoonKey"
key.data.energy = 720
key.data.size = 5.0
key.data.color = rgba(COLORS["sand"])[:3]
look_at(key, (0, 2.0, 0.55))

bpy.ops.object.light_add(type="AREA", location=(4.0, 5.5, 3.0))
fill = bpy.context.object
fill.name = "PREVIEW_SeaFill"
fill.data.energy = 420
fill.data.size = 5.0
fill.data.color = rgba(COLORS["ripple"])[:3]
look_at(fill, (0, 2.0, 0.55))

for x in (-0.67, 0.67):
    bpy.ops.object.light_add(type="POINT", location=(x, 3.60, 1.25))
    lamp = bpy.context.object
    lamp.name = "PREVIEW_LanternLight"
    lamp.data.energy = 46
    lamp.data.color = rgba(COLORS["ember"])[:3]
    lamp.data.shadow_soft_size = 0.45

bpy.ops.object.camera_add(location=(5.3, -6.8, 4.55))
camera = bpy.context.object
camera.name = "PREVIEW_Camera"
camera.data.lens = 55
look_at(camera, (0, 2.0, 0.62))

scene = bpy.context.scene
scene.camera = camera
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1400
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.filepath = str(RENDER_PATH)
scene.view_settings.look = "AgX - Medium High Contrast"

BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
RENDER_PATH.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

# Keep the editable .blend separated into named parts, but merge the delivery GLB by
# material. This preserves the same image while cutting mobile draw calls sharply.
for obj in asset_objects:
    if obj.type != "MESH" or not obj.modifiers:
        continue
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")

groups: dict[str, list[bpy.types.Object]] = {}
for obj in asset_objects:
    if obj.type != "MESH":
        continue
    key = obj.data.materials[0].name if obj.data.materials else "Unmaterialed"
    groups.setdefault(key, []).append(obj)

export_objects: list[bpy.types.Object] = []
for material_name, objects in groups.items():
    if len(objects) == 1:
        merged = objects[0]
        merged.name = f"HarborPier_{material_name.removeprefix('LF_Pier')}"
        merged.data.name = f"{merged.name}_Mesh"
        export_objects.append(merged)
        continue
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    merged = bpy.context.object
    merged.name = f"HarborPier_{material_name.removeprefix('LF_Pier')}"
    merged.data.name = f"{merged.name}_Mesh"
    export_objects.append(merged)

bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
for obj in export_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(
    filepath=str(GLB_PATH),
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_yup=True,
    export_animations=False,
)
bpy.ops.render.render(write_still=True)

print(f"BLEND={BLEND_PATH}")
print(f"GLB={GLB_PATH}")
print(f"RENDER={RENDER_PATH}")
