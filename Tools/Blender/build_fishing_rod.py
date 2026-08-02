"""Build a player-scale KeelMira fishing rod, preview it in-hand, and export GLB."""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/fishing_rod.blend"
GLB_PATH = ROOT / "web/public/models/fishing_rod.glb"
RENDER_PATH = ROOT / "marketing/3d/fishing-rod.png"

COLORS = {
    "night": "#123830",
    "sea": "#1E5348",
    "sand": "#EADEBD",
    "coral": "#F0997B",
    "orange": "#F5822A",
    "wood": "#5A2A15",
    "rust": "#7A3B22",
    "rust_deep": "#4A1B0C",
    "midnight": "#1A1130",
    "ember": "#F3C065",
    "rope": "#DCCFA9",
}


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float,
    emission: str | None = None,
    strength: float = 0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = rgba(color)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = rgba(color)
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = rgba(emission)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


MATS = {
    "shaft": material("LF_RodShaft", COLORS["wood"], 0.82),
    "grip": material("LF_RodGrip", COLORS["rust_deep"], 0.9),
    "wrap": material("LF_RodWrap", COLORS["coral"], 0.86),
    "metal": material("LF_RodMetal", COLORS["rust"], 0.76),
    "spool": material("LF_RodSpool", COLORS["midnight"], 0.72),
    "line": material("LF_RodLine", COLORS["rope"], 0.98),
    "accent": material("LF_RodAccent", COLORS["orange"], 0.84),
    "glow": material(
        "LF_RodBobberGlow",
        COLORS["ember"],
        0.42,
        COLORS["ember"],
        2.5,
    ),
}


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
root = bpy.data.objects.new("Fishing_Rod", None)
bpy.context.collection.objects.link(root)
# Author in the player's Y-up space: X=forward, Y=up, Z=right.
root.rotation_euler.x = math.pi / 2
asset_objects: list[bpy.types.Object] = []


def keep(obj: bpy.types.Object, name: str, mat: bpy.types.Material) -> bpy.types.Object:
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    obj.data.materials.append(mat)
    obj.parent = root
    asset_objects.append(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def beam(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius: float,
    mat: bpy.types.Material,
    vertices: int = 7,
) -> bpy.types.Object:
    a, b = Vector(start), Vector(end)
    delta = b - a
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=delta.length,
        location=tuple((a + b) / 2),
    )
    obj = keep(bpy.context.object, name, mat)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Z", "Y")
    return obj


def cylinder_z(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    mat: bpy.types.Material,
    vertices: int = 8,
) -> bpy.types.Object:
    # Default local Z is the authored lateral axis, ideal for a reel axle/spool.
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
    )
    return keep(bpy.context.object, name, mat)


def torus(
    name: str,
    location: tuple[float, float, float],
    major: float,
    minor: float,
    mat: bpy.types.Material,
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
    return keep(bpy.context.object, name, mat)


def ico(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=radius, location=location)
    obj = keep(bpy.context.object, name, mat)
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def rope_curve(
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


def guide_ring(
    name: str,
    position: tuple[float, float, float],
    normal: tuple[float, float, float],
    major: float,
) -> bpy.types.Object:
    obj = torus(name, position, major, 0.006, MATS["metal"])
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector(normal).normalized().to_track_quat("Z", "Y")
    return obj


def empty_socket(name: str, position: tuple[float, float, float]) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = position
    obj.parent = root
    asset_objects.append(obj)
    return obj


def look_at(obj: bpy.types.Object, point: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()


# Attachment contract. GripSocket is aligned to the player's hand; LineTip is where
# runtime fishing-line simulation begins.
empty_socket("GripSocket", (0, 0, 0))

# A slightly bowed six-piece blank: sturdy near the grip, fine at the tip.
rod_points = [
    (0.00, 0.10, 0),
    (0.015, 0.34, 0),
    (0.05, 0.58, 0),
    (0.11, 0.82, 0),
    (0.20, 1.04, 0),
    (0.32, 1.23, 0),
    (0.47, 1.39, 0),
]
rod_radii = [0.026, 0.023, 0.020, 0.017, 0.014, 0.010]
for index, (a, b, radius) in enumerate(zip(rod_points[:-1], rod_points[1:], rod_radii)):
    beam(f"Rod_Segment_{index + 1:02}", a, b, radius, MATS["shaft"], 7)

# One-handed grip centred on the origin, with coral wraps that remain readable on
# the dark player hand.
beam("Grip_Core", (0, -0.22, 0), (0, 0.14, 0), 0.052, MATS["grip"], 9)
beam("Butt_Cap", (0, -0.25, 0), (0, -0.20, 0), 0.064, MATS["metal"], 8)
for index, y in enumerate((-0.14, -0.08, -0.02, 0.04, 0.10)):
    torus(
        f"Grip_Wrap_{index + 1:02}",
        (0, y, 0),
        0.053,
        0.010,
        MATS["wrap"],
        rotation=(math.pi / 2, 0, 0),
    )

# Compact side-mounted reel. Its lateral offset leaves the palm and fingers clear.
cylinder_z("Reel_Spool", (0.02, 0.19, -0.105), 0.105, 0.12, MATS["spool"], 10)
cylinder_z("Reel_Rim_Inner", (0.02, 0.19, -0.17), 0.125, 0.025, MATS["metal"], 10)
cylinder_z("Reel_Rim_Outer", (0.02, 0.19, -0.04), 0.125, 0.025, MATS["metal"], 10)
beam("Reel_Foot", (0.0, 0.12, -0.02), (0.02, 0.19, -0.075), 0.018, MATS["metal"], 6)
beam("Reel_Crank_Axle", (0.02, 0.19, -0.18), (0.02, 0.19, -0.27), 0.014, MATS["metal"], 6)
beam("Reel_Crank_Arm", (0.02, 0.19, -0.27), (0.08, 0.10, -0.27), 0.014, MATS["metal"], 6)
ico("Reel_Crank_Knob", (0.09, 0.085, -0.27), 0.035, (0.8, 1.35, 0.8), MATS["grip"])

# Guide rings follow the bend. The line sits slightly camera-side of the blank.
guide_indices = (1, 3, 5, 6)
for guide_number, point_index in enumerate(guide_indices, start=1):
    point = Vector(rod_points[point_index])
    previous = Vector(rod_points[max(point_index - 1, 0)])
    following = Vector(rod_points[min(point_index + 1, len(rod_points) - 1)])
    tangent = following - previous
    size = 0.032 - guide_number * 0.004
    guide_ring(
        f"Line_Guide_{guide_number:02}",
        (point.x, point.y, -0.035),
        tuple(tangent),
        max(size, 0.014),
    )

line_points = [(0.02, 0.19, -0.19)]
line_points += [(rod_points[i][0], rod_points[i][1], -0.045) for i in guide_indices]
rope_curve("Stored_Line", line_points, 0.0035, MATS["line"])

tip = rod_points[-1]
empty_socket("LineTip", (tip[0], tip[1], -0.045))

# Stored hook and tiny return-orange float hang close to the reel so the equipment
# remains safe while walking. During fishing, runtime can hide these and spawn line.
rope_curve(
    "Hook_Shank",
    [(0.04, 0.26, -0.20), (0.09, 0.21, -0.22), (0.08, 0.15, -0.22), (0.04, 0.13, -0.21)],
    0.007,
    MATS["metal"],
)
ico("Stored_Bobber", (-0.055, 0.30, -0.205), 0.052, (0.75, 1.20, 0.75), MATS["accent"])
torus("Bobber_Band", (-0.055, 0.30, -0.205), 0.042, 0.008, MATS["glow"], rotation=(math.pi / 2, 0, 0))

# Preview-only coral sleeve and dark hand demonstrate actual held scale.
preview_coral = material("PREVIEW_CoralSleeve", COLORS["coral"], 0.86)
preview_hand = material("PREVIEW_Hand", COLORS["rust_deep"], 0.82)
bpy.ops.mesh.primitive_cone_add(
    vertices=10,
    radius1=0.16,
    radius2=0.105,
    depth=0.42,
    location=(0, 0, -0.43),
)
sleeve = bpy.context.object
sleeve.name = "PREVIEW_Sleeve"
sleeve.data.materials.append(preview_coral)
bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=0.115, location=(0, 0, -0.16))
hand = bpy.context.object
hand.name = "PREVIEW_Hand"
hand.scale = (0.8, 0.85, 1.25)
hand.data.materials.append(preview_hand)

# Preview backdrop and lighting.
world = bpy.context.scene.world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba(COLORS["night"])
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.18

bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 1.5, 0), rotation=(math.pi / 2, 0, 0))
backdrop = bpy.context.object
backdrop.name = "PREVIEW_Backdrop"
backdrop.data.materials.append(material("PREVIEW_Sea", COLORS["sea"], 0.9))

bpy.ops.object.light_add(type="AREA", location=(-3.2, -4.2, 5.0))
key = bpy.context.object
key.name = "PREVIEW_MoonKey"
key.data.energy = 700
key.data.size = 4.0
key.data.color = rgba(COLORS["sand"])[:3]
look_at(key, (0.15, 0, 0.55))

bpy.ops.object.light_add(type="AREA", location=(3.5, 2.5, 2.5))
fill = bpy.context.object
fill.name = "PREVIEW_SeaFill"
fill.data.energy = 380
fill.data.size = 4.0
fill.data.color = rgba("#7FB8A6")[:3]
look_at(fill, (0.15, 0, 0.55))

bpy.ops.object.camera_add(location=(2.65, -4.8, 2.3))
camera = bpy.context.object
camera.name = "PREVIEW_Camera"
camera.data.lens = 62
look_at(camera, (0.13, 0, 0.58))

scene = bpy.context.scene
scene.camera = camera
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1050
scene.render.resolution_y = 1400
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.filepath = str(RENDER_PATH)
scene.view_settings.look = "AgX - Medium High Contrast"

BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
RENDER_PATH.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

# Merge delivery meshes by material while retaining the socket empties.
groups: dict[str, list[bpy.types.Object]] = {}
socket_objects: list[bpy.types.Object] = []
for obj in asset_objects:
    if obj.type != "MESH":
        socket_objects.append(obj)
        continue
    key = obj.data.materials[0].name if obj.data.materials else "Unmaterialed"
    groups.setdefault(key, []).append(obj)

export_meshes: list[bpy.types.Object] = []
for material_name, objects in groups.items():
    if len(objects) == 1:
        merged = objects[0]
    else:
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        bpy.ops.object.join()
        merged = bpy.context.object
    merged.name = material_name
    merged.data.name = f"{material_name}_Mesh"
    export_meshes.append(merged)

bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
for obj in export_meshes + socket_objects:
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
