"""Build Landfall's rig-ready navigator, render it, and export a web GLB."""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/navigator.blend"
GLB_PATH = ROOT / "web/public/models/navigator.glb"
RENDER_PATH = ROOT / "marketing/3d/navigator.png"

COLORS = {
    "night": "#123830",
    "sea": "#1E5348",
    "sand": "#EADEBD",
    "coral": "#F0997B",
    "rust": "#7A3B22",
    "rust_deep": "#4A1B0C",
    "midnight": "#1A1130",
    "lantern": "#F3C065",
    "eye": "#FFD890",
    "brass": "#D5B56D",
}


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float,
    *,
    metallic: float = 0,
    emission: str | None = None,
    strength: float = 0,
) -> bpy.types.Material:
    value = bpy.data.materials.new(name)
    value.diffuse_color = rgba(color)
    value.use_nodes = True
    bsdf = value.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = rgba(color)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission:
        bsdf.inputs["Emission Color"].default_value = rgba(emission)
        bsdf.inputs["Emission Strength"].default_value = strength
    return value


MATS = {
    "coral": material("LF_NavigatorCoralCloth", COLORS["coral"], 0.82),
    "rust": material("LF_NavigatorRustTrim", COLORS["rust"], 0.88),
    "rust_deep": material("LF_NavigatorBootLeather", COLORS["rust_deep"], 0.93),
    "sand": material("LF_NavigatorSandRope", COLORS["sand"], 0.96),
    "midnight": material("LF_NavigatorMidnight", COLORS["midnight"], 0.78),
    "cape": material("LF_NavigatorCapeCloth", COLORS["midnight"], 0.92),
    "brass": material("LF_NavigatorBrass", COLORS["brass"], 0.42, metallic=0.64),
    "eye": material(
        "LF_NavigatorEyeGlow",
        COLORS["eye"],
        0.62,
        emission=COLORS["eye"],
        strength=0.72,
    ),
    "lantern": material(
        "LF_NavigatorLanternGlow",
        COLORS["lantern"],
        0.48,
        emission=COLORS["lantern"],
        strength=3.2,
    ),
    "preview_sand": material("PREVIEW_NavigatorSand", COLORS["sand"], 0.98),
}

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

asset_root = bpy.data.objects.new("Navigator_Asset", None)
bpy.context.collection.objects.link(asset_root)
asset_root["forward_axis"] = "-Y"
asset_root["ground_origin"] = "Z=0"
asset_root["animation_contract"] = "Root, Spine, Head, Arm.L, Arm.R, Leg.L, Leg.R"
asset_objects: list[bpy.types.Object] = []


def keep(
    obj: bpy.types.Object,
    name: str,
    mat: bpy.types.Material | None = None,
    *,
    smooth: bool = True,
) -> bpy.types.Object:
    obj.name = name
    if obj.data:
        obj.data.name = f"{name}_Mesh"
        if mat:
            obj.data.materials.append(mat)
        if hasattr(obj.data, "polygons"):
            for polygon in obj.data.polygons:
                polygon.use_smooth = smooth
    obj.parent = asset_root
    asset_objects.append(obj)
    return obj


def apply_scale(obj: bpy.types.Object) -> bpy.types.Object:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)
    return obj


def bevel(obj: bpy.types.Object, width: float, segments: int = 3) -> bpy.types.Object:
    modifier = obj.modifiers.new(name=f"{obj.name}_SoftEdges", type="BEVEL")
    modifier.width = width
    modifier.segments = segments
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)
    return obj


def sphere(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    *,
    segments: int = 20,
    rings: int = 12,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        location=location,
    )
    obj = keep(bpy.context.object, name, mat)
    obj.scale = scale
    return apply_scale(obj)


def cone(
    name: str,
    location: tuple[float, float, float],
    radius_bottom: float,
    radius_top: float,
    depth: float,
    mat: bpy.types.Material,
    *,
    vertices: int = 24,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius_bottom,
        radius2=radius_top,
        depth=depth,
        location=location,
    )
    return keep(bpy.context.object, name, mat)


def cube(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    *,
    rotation: tuple[float, float, float] = (0, 0, 0),
    bevel_width: float = 0,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = keep(bpy.context.object, name, mat)
    obj.scale = scale
    apply_scale(obj)
    if bevel_width:
        bevel(obj, bevel_width)
    return obj


def beam(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius: float,
    mat: bpy.types.Material,
    *,
    vertices: int = 12,
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


def torus(
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
        major_segments=24,
        minor_segments=8,
        location=location,
        rotation=rotation,
    )
    return keep(bpy.context.object, name, mat)


def mesh(
    name: str,
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    mat: bpy.types.Material,
    *,
    smooth: bool = True,
) -> bpy.types.Object:
    data = bpy.data.meshes.new(f"{name}_Mesh")
    data.from_pydata(vertices, [], faces)
    data.materials.append(mat)
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.parent = asset_root
    asset_objects.append(obj)
    for polygon in data.polygons:
        polygon.use_smooth = smooth
    return obj


def open_hood(name: str, mat: bpy.types.Material) -> bpy.types.Object:
    """Create a tapered cloth hood with a real opening toward model front (-Y)."""
    profile = [
        (0.18, 0.935),
        (0.165, 0.995),
        (0.138, 1.065),
        (0.102, 1.145),
        (0.058, 1.22),
        (0.012, 1.285),
    ]
    segments = 22
    front = -math.pi / 2
    gap = 0.58
    start = front + gap / 2
    span = math.pi * 2 - gap
    vertices: list[tuple[float, float, float]] = []
    for radius, z in profile:
        for index in range(segments + 1):
            angle = start + span * index / segments
            # The peak leans gently toward the cape (+Y) instead of standing
            # like a rigid traffic cone.
            lean = ((z - profile[0][1]) / (profile[-1][1] - profile[0][1])) ** 2 * 0.045
            vertices.append(
                (
                    math.cos(angle) * radius,
                    math.sin(angle) * radius + lean,
                    z,
                )
            )
    faces: list[tuple[int, ...]] = []
    stride = segments + 1
    for ring in range(len(profile) - 1):
        for index in range(segments):
            a = ring * stride + index
            b = a + 1
            d = a + stride
            faces.append((a, d, d + 1, b))
    return mesh(name, vertices, faces, mat)


# ---- Rig ----

armature_data = bpy.data.armatures.new("Navigator_RigData")
rig = bpy.data.objects.new("Navigator_Rig", armature_data)
bpy.context.collection.objects.link(rig)
rig.parent = asset_root
rig.show_in_front = True
rig["rig_version"] = 1
rig["socket_left_hand"] = "GripSocket.L"
rig["socket_right_hand"] = "GripSocket.R"
rig["socket_back"] = "BackSocket"
asset_objects.append(rig)

bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")


def edit_bone(
    name: str,
    head: tuple[float, float, float],
    tail: tuple[float, float, float],
    parent: str | None = None,
) -> None:
    value = armature_data.edit_bones.new(name)
    value.head = head
    value.tail = tail
    if parent:
        value.parent = armature_data.edit_bones[parent]


edit_bone("Root", (0, 0, 0), (0, 0, 0.16))
edit_bone("Spine", (0, 0, 0.42), (0, 0, 0.94), "Root")
edit_bone("Head", (0, 0, 0.94), (0, 0, 1.25), "Spine")
edit_bone("Arm.L", (-0.16, 0, 0.83), (-0.16, 0, 0.48), "Spine")
edit_bone("Arm.R", (0.16, 0, 0.83), (0.16, 0, 0.48), "Spine")
edit_bone("Leg.L", (-0.085, 0, 0.44), (-0.085, -0.02, 0.05), "Root")
edit_bone("Leg.R", (0.085, 0, 0.44), (0.085, -0.02, 0.05), "Root")
bpy.ops.object.mode_set(mode="OBJECT")
rig.select_set(False)


def bone_parent(obj: bpy.types.Object, bone_name: str) -> None:
    world = obj.matrix_world.copy()
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    obj.matrix_world = world


def socket(name: str, location: tuple[float, float, float], bone_name: str) -> bpy.types.Object:
    value = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(value)
    value.empty_display_type = "PLAIN_AXES"
    value.empty_display_size = 0.055
    value.location = location
    asset_objects.append(value)
    bone_parent(value, bone_name)
    return value


# ---- Body and clothing ----

# Legs and boots. The boot toe projects toward -Y, the model's forward direction.
for side, x in (("L", -0.085), ("R", 0.085)):
    ankle = beam(
        f"Navigator_Ankle.{side}",
        (x, 0.01, 0.12),
        (x, 0.01, 0.34),
        0.043,
        MATS["rust_deep"],
    )
    cuff = cone(
        f"Navigator_BootCuff.{side}",
        (x, -0.015, 0.145),
        0.067,
        0.058,
        0.065,
        MATS["rust"],
        vertices=16,
    )
    boot = sphere(
        f"Navigator_Boot.{side}",
        (x, -0.065, 0.075),
        (0.073, 0.12, 0.06),
        MATS["rust_deep"],
        segments=16,
        rings=10,
    )
    sole = cube(
        f"Navigator_Sole.{side}",
        (x, -0.065, 0.025),
        (0.06, 0.13, 0.014),
        MATS["rust"],
        bevel_width=0.012,
    )
    for obj in (ankle, cuff, boot, sole):
        bone_parent(obj, f"Leg.{side}")

# Bell-shaped coat with a darker weighted hem and a waist belt.
coat = cone("Navigator_Coat", (0, 0, 0.61), 0.235, 0.12, 0.58, MATS["coral"], vertices=28)
hem = torus("Navigator_WeightedHem", (0, 0, 0.325), 0.205, 0.018, MATS["rust"])
belt = torus("Navigator_Belt", (0, 0, 0.61), 0.15, 0.018, MATS["rust_deep"])
buckle = cube(
    "Navigator_BeltBuckle",
    (0, -0.157, 0.61),
    (0.032, 0.012, 0.025),
    MATS["brass"],
    bevel_width=0.006,
)
mantle = cone(
    "Navigator_ShoulderMantle",
    (0, 0, 0.87),
    0.225,
    0.105,
    0.18,
    MATS["coral"],
    vertices=28,
)
for obj in (coat, hem, belt, buckle, mantle):
    bone_parent(obj, "Spine")

# Midnight swallow-tail cape: broad at the shoulders, split into two soft tails.
cape_front_y = 0.09
cape_back_y = 0.115
cape_vertices = [
    (-0.16, cape_front_y, 0.93),
    (0.16, cape_front_y, 0.93),
    (0.34, cape_front_y, 0.35),
    (0.055, cape_front_y, 0.47),
    (0, cape_front_y, 0.55),
    (-0.055, cape_front_y, 0.47),
    (-0.34, cape_front_y, 0.35),
    (-0.16, cape_back_y, 0.93),
    (0.16, cape_back_y, 0.93),
    (0.34, cape_back_y, 0.35),
    (0.055, cape_back_y, 0.47),
    (0, cape_back_y, 0.55),
    (-0.055, cape_back_y, 0.47),
    (-0.34, cape_back_y, 0.35),
]
cape_faces = [
    (0, 1, 2, 3, 4, 5, 6),
    (13, 12, 11, 10, 9, 8, 7),
    (0, 7, 8, 1),
    (1, 8, 9, 2),
    (2, 9, 10, 3),
    (3, 10, 11, 4),
    (4, 11, 12, 5),
    (5, 12, 13, 6),
    (6, 13, 7, 0),
]
cape = mesh("Navigator_SwallowCape", cape_vertices, cape_faces, MATS["cape"])
bevel(cape, 0.012, 2)
bone_parent(cape, "Spine")

# Arms are separate rigid pieces so the rig can drive walking, waving, and item use.
for side, x in (("L", -0.17), ("R", 0.17)):
    sleeve = beam(
        f"Navigator_Sleeve.{side}",
        (x, 0, 0.79),
        (x, -0.012, 0.57),
        0.045,
        MATS["coral"],
        vertices=14,
    )
    cuff = cone(
        f"Navigator_SleeveCuff.{side}",
        (x, -0.012, 0.525),
        0.064,
        0.047,
        0.1,
        MATS["rust"],
        vertices=14,
    )
    hand = sphere(
        f"Navigator_Hand.{side}",
        (x, -0.012, 0.45),
        (0.048, 0.044, 0.052),
        MATS["rust_deep"],
        segments=14,
        rings=9,
    )
    for obj in (sleeve, cuff, hand):
        bone_parent(obj, f"Arm.{side}")

# Hood, shadowed face, and gently glowing eyes.
hood = open_hood("Navigator_PeakedHood", MATS["coral"])
face = sphere(
    "Navigator_ShadowFace",
    (0, -0.005, 1.07),
    (0.086, 0.05, 0.095),
    MATS["midnight"],
    segments=18,
    rings=12,
)
for side, x in (("L", -0.032), ("R", 0.032)):
    eye = sphere(
        f"Navigator_Eye.{side}",
        (x * 0.88, -0.058, 1.086),
        (0.014, 0.007, 0.009),
        MATS["eye"],
        segments=12,
        rings=8,
    )
    bone_parent(eye, "Head")
for obj in (hood, face):
    bone_parent(obj, "Head")

# Rope collar and knot.
collar = torus("Navigator_RopeCollar", (0, 0, 0.945), 0.15, 0.012, MATS["sand"])
knot = sphere(
    "Navigator_RopeKnot",
    (0.055, -0.145, 0.935),
    (0.026, 0.018, 0.022),
    MATS["sand"],
    segments=12,
    rings=8,
)
tail_l = beam("Navigator_RopeTail.L", (0.045, -0.145, 0.92), (0.02, -0.15, 0.84), 0.008, MATS["sand"])
tail_r = beam("Navigator_RopeTail.R", (0.065, -0.145, 0.92), (0.09, -0.15, 0.85), 0.008, MATS["sand"])
for obj in (collar, knot, tail_l, tail_r):
    bone_parent(obj, "Spine")

# Chest compass rose: brass rim, midnight dial, and eight sand-colored needles.
rose_rim = torus(
    "Navigator_CompassRim",
    (0, -0.21, 0.82),
    0.047,
    0.009,
    MATS["brass"],
    rotation=(math.pi / 2, 0, 0),
)
bpy.ops.mesh.primitive_cylinder_add(
    vertices=24,
    radius=0.041,
    depth=0.009,
    location=(0, -0.205, 0.82),
    rotation=(math.pi / 2, 0, 0),
)
rose_face = keep(bpy.context.object, "Navigator_CompassFace", MATS["midnight"])
for index in range(8):
    angle = index * math.pi / 4
    length = 0.035 if index % 2 == 0 else 0.024
    x = math.cos(angle) * length * 0.48
    z = 0.82 + math.sin(angle) * length * 0.48
    needle = cube(
        f"Navigator_CompassNeedle_{index + 1}",
        (x, -0.217, z),
        (length * 0.5, 0.004, 0.006),
        MATS["sand"],
        rotation=(0, angle, 0),
        bevel_width=0.003,
    )
    bone_parent(needle, "Spine")
rose_hub = sphere(
    "Navigator_CompassHub",
    (0, -0.222, 0.82),
    (0.009, 0.006, 0.009),
    MATS["brass"],
    segments=12,
    rings=8,
)
for obj in (rose_rim, rose_face, rose_hub):
    bone_parent(obj, "Spine")

# Open lantern held by the right hand. It shares the warm light used on ships.
lantern_x = 0.17
handle = torus(
    "Navigator_LanternHandle",
    (lantern_x, -0.012, 0.35),
    0.052,
    0.007,
    MATS["rust"],
    rotation=(math.pi / 2, 0, 0),
)
lantern_cap = cone(
    "Navigator_LanternCap",
    (lantern_x, -0.012, 0.29),
    0.055,
    0.015,
    0.05,
    MATS["rust"],
    vertices=8,
)
lantern_glow = sphere(
    "Navigator_LanternGlow",
    (lantern_x, -0.012, 0.225),
    (0.043, 0.043, 0.05),
    MATS["lantern"],
    segments=14,
    rings=9,
)
lantern_base = cone(
    "Navigator_LanternBase",
    (lantern_x, -0.012, 0.17),
    0.05,
    0.043,
    0.025,
    MATS["rust"],
    vertices=8,
)
for obj in (handle, lantern_cap, lantern_glow, lantern_base):
    bone_parent(obj, "Arm.R")

# Named sockets let future items attach without guessing character coordinates.
socket("GripSocket.L", (-0.17, -0.012, 0.45), "Arm.L")
socket("GripSocket.R", (0.17, -0.012, 0.45), "Arm.R")
socket("BackSocket", (0, 0.14, 0.76), "Spine")
socket("HeadSocket", (0, 0, 1.27), "Head")

# Preview-only ground, lights, and camera.
bpy.ops.mesh.primitive_circle_add(vertices=48, radius=1.35, fill_type="NGON", location=(0, 0, -0.005))
preview_ground = bpy.context.object
preview_ground.name = "PREVIEW_NavigatorGround"
preview_ground.data.materials.append(MATS["preview_sand"])

world = bpy.context.scene.world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba(COLORS["night"])
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.2


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


bpy.ops.object.light_add(type="AREA", location=(-3.4, -4.0, 4.4))
key = bpy.context.object
key.data.energy = 430
key.data.size = 4
key.data.color = rgba(COLORS["sand"])[:3]
look_at(key, (0, 0, 0.65))

bpy.ops.object.light_add(type="AREA", location=(3.4, 1.8, 2.8))
fill = bpy.context.object
fill.data.energy = 230
fill.data.size = 3
fill.data.color = rgba(COLORS["sea"])[:3]
look_at(fill, (0, 0, 0.7))

bpy.ops.object.light_add(type="POINT", location=(0.17, -0.28, 0.26))
lamp = bpy.context.object
lamp.data.energy = 24
lamp.data.color = rgba(COLORS["lantern"])[:3]
lamp.data.shadow_soft_size = 0.4

bpy.ops.object.camera_add(location=(2.15, -3.6, 1.9))
camera = bpy.context.object
camera.data.lens = 72
look_at(camera, (0, 0, 0.68))

scene = bpy.context.scene
scene.camera = camera
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1200
scene.render.resolution_y = 1400
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(RENDER_PATH)
scene.view_settings.look = "AgX - Medium High Contrast"

BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
RENDER_PATH.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

# Export only gameplay pieces. Preview lighting and ground remain in the .blend.
bpy.ops.object.select_all(action="DESELECT")
asset_root.select_set(True)
for obj in asset_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(
    filepath=str(GLB_PATH),
    export_format="GLB",
    use_selection=True,
    export_yup=True,
    export_animations=False,
    export_cameras=False,
    export_lights=False,
)

bpy.ops.object.select_all(action="DESELECT")
bpy.ops.render.render(write_still=True)

print(f"BLEND={BLEND_PATH}")
print(f"GLB={GLB_PATH}")
print(f"RENDER={RENDER_PATH}")
