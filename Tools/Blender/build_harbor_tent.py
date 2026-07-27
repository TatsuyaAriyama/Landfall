"""Build Landfall's small harbor rest tent, render it, and export a web GLB."""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/harbor_tent.blend"
GLB_PATH = ROOT / "web/public/models/harbor_tent.glb"
RENDER_PATH = ROOT / "marketing/3d/harbor-tent.png"

COLORS = {
    "night": "#123830",
    "sea": "#1E5348",
    "sand": "#EADEBD",
    "fly": "#3E756B",
    "fly_dark": "#244C46",
    "inner": "#D7C8A4",
    "floor": "#202A2D",
    "metal": "#A8B4B3",
    "rope": "#C8D5CF",
    "bed": "#1A1130",
    "ember": "#F3C065",
    "orange": "#F5822A",
}


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float = 0.9,
    emission: str | None = None,
    strength: float = 0,
    metallic: float = 0,
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
    "fly": material("LF_TentRipstopFly", COLORS["fly"], 0.62),
    "fly_dark": material("LF_TentReinforcedFly", COLORS["fly_dark"], 0.7),
    "inner": material("LF_TentBreathableInner", COLORS["inner"], 0.86),
    "floor": material("LF_TentWaterproofFloor", COLORS["floor"], 0.48),
    "metal": material("LF_TentAluminumPole", COLORS["metal"], 0.28, metallic=0.78),
    "rope": material("LF_TentReflectiveCord", COLORS["rope"], 0.72),
    "sand": material("PREVIEW_SandMaterial", COLORS["sand"], 0.98),
    "bed": material("LF_TentBedroll", COLORS["bed"], 0.96),
    "orange": material("LF_TentZipperPull", COLORS["orange"], 0.7),
    "glow": material("LF_TentGlow", COLORS["ember"], 0.4, COLORS["ember"], 4.5),
}

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
root = bpy.data.objects.new("Harbor_Tent", None)
bpy.context.collection.objects.link(root)
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


def mesh(
    name: str,
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    mat: bpy.types.Material,
) -> bpy.types.Object:
    data = bpy.data.meshes.new(f"{name}_Mesh")
    data.from_pydata(vertices, [], faces)
    data.materials.append(mat)
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.parent = root
    asset_objects.append(obj)
    return obj


def cube(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    rotation: tuple[float, float, float] = (0, 0, 0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = keep(bpy.context.object, name, mat)
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def beam(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius: float,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    a, b = Vector(start), Vector(end)
    delta = b - a
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=7,
        radius=radius,
        depth=delta.length,
        location=tuple((a + b) / 2),
    )
    obj = keep(bpy.context.object, name, mat)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Z", "Y")
    return obj


# The entrance is at local -Y, which becomes +Z in Three.js after Y-up export.
# A low, rounded tunnel silhouette and external aluminum arches keep it clearly
# contemporary camping equipment rather than an A-frame or shrine-like structure.
front, back = -0.86, 0.9
cross_section = [
    (-1.12, 0.08),
    (-0.94, 0.68),
    (-0.55, 1.12),
    (0.0, 1.32),
    (0.55, 1.12),
    (0.94, 0.68),
    (1.12, 0.08),
]
for index in range(len(cross_section) - 1):
    x0, z0 = cross_section[index]
    x1, z1 = cross_section[index + 1]
    mesh(
        f"Tent_RipstopPanel_{index + 1}",
        [(x0, front, z0), (x1, front, z1), (x1, back, z1), (x0, back, z0)],
        [(0, 1, 2, 3)],
        MATS["fly_dark" if index in (0, 5) else "fly"],
    )

# Closed rear inner wall; the front stays physically open so the navigator can enter.
rear_center = (0, back + 0.004, 0.12)
for index in range(len(cross_section) - 1):
    x0, z0 = cross_section[index]
    x1, z1 = cross_section[index + 1]
    mesh(
        f"Tent_RearInner_{index + 1}",
        [rear_center, (x0, back + 0.004, z0), (x1, back + 0.004, z1)],
        [(0, 1, 2)],
        MATS["inner"],
    )

# Rolled breathable inner doors frame a broad rounded opening.
beam("Tent_LeftDoorRoll", (-0.58, front - 0.02, 0.12), (-0.25, front - 0.02, 0.94), 0.045, MATS["inner"])
beam("Tent_RightDoorRoll", (0.58, front - 0.02, 0.12), (0.25, front - 0.02, 0.94), 0.045, MATS["inner"])
beam("Tent_DoorCanopy", (-0.25, front - 0.02, 0.94), (0.25, front - 0.02, 0.94), 0.035, MATS["fly_dark"])

# Two segmented aluminum arches show a different material and construction system.
for arch_name, y in (("Front", front - 0.035), ("Rear", back + 0.035)):
    for index in range(len(cross_section) - 1):
        x0, z0 = cross_section[index]
        x1, z1 = cross_section[index + 1]
        beam(
            f"Tent_{arch_name}Aluminum_{index + 1}",
            (x0, y, z0),
            (x1, y, z1),
            0.025,
            MATS["metal"],
        )
beam("Tent_RoofSpreader", (0, front - 0.05, 1.34), (0, back + 0.06, 1.34), 0.022, MATS["metal"])

# Reflective guy cords and metal pegs replace wooden ropes and stakes.
for index, (a, b) in enumerate(
    [
        ((-0.94, front, 0.56), (-1.42, front - 0.42, 0.04)),
        ((0.94, front, 0.56), (1.42, front - 0.42, 0.04)),
        ((-0.94, back, 0.56), (-1.42, back + 0.42, 0.04)),
        ((0.94, back, 0.56), (1.42, back + 0.42, 0.04)),
    ]
):
    beam(f"Tent_GuyRope_{index + 1}", a, b, 0.009, MATS["rope"])
    beam(f"Tent_Stake_{index + 1}", (b[0], b[1], 0), (b[0], b[1], 0.15), 0.02, MATS["metal"])

# Bathtub floor, inner groundsheet, and bedroll remain visibly separate materials.
cube("Tent_WaterproofFloor", (0, 0.06, 0.04), (0.88, 0.72, 0.04), MATS["floor"])
cube("Tent_InnerGroundsheet", (0, 0.09, 0.085), (0.73, 0.62, 0.018), MATS["inner"])
cube("Tent_Bedroll", (0.34, 0.18, 0.14), (0.3, 0.49, 0.11), MATS["bed"], (0, 0, 0.04))
beam("Tent_BedrollTie", (0.02, 0.18, 0.26), (0.66, 0.18, 0.26), 0.018, MATS["rope"])

# A clipped camp lantern and orange zipper pulls add function without any flags.
beam("Tent_LanternClip", (-0.38, front - 0.04, 0.84), (-0.38, front - 0.04, 1.02), 0.014, MATS["metal"])
cube("Tent_LanternBody", (-0.38, front - 0.05, 0.72), (0.08, 0.065, 0.1), MATS["glow"])
beam("Tent_LeftZipperPull", (-0.25, front - 0.035, 0.43), (-0.31, front - 0.035, 0.35), 0.012, MATS["orange"])
beam("Tent_RightZipperPull", (0.25, front - 0.035, 0.43), (0.31, front - 0.035, 0.35), 0.012, MATS["orange"])


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


# Preview-only ground, lights and camera.
bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, -0.02))
preview_ground = bpy.context.object
preview_ground.name = "PREVIEW_Sand"
preview_ground.data.materials.append(MATS["sand"])

world = bpy.context.scene.world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba(COLORS["night"])
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.22

bpy.ops.object.light_add(type="AREA", location=(-3.6, -4.5, 5.5))
key = bpy.context.object
key.data.energy = 660
key.data.size = 4.5
key.data.color = rgba(COLORS["sand"])[:3]
look_at(key, (0, 0, 0.65))

bpy.ops.object.light_add(type="AREA", location=(4.2, 2.8, 3))
fill = bpy.context.object
fill.data.energy = 360
fill.data.size = 4
fill.data.color = rgba(COLORS["sea"])[:3]
look_at(fill, (0, 0, 0.65))

bpy.ops.object.light_add(type="POINT", location=(-0.42, front - 0.34, 0.68))
lamp = bpy.context.object
lamp.data.energy = 52
lamp.data.color = rgba(COLORS["ember"])[:3]
lamp.data.shadow_soft_size = 0.5

bpy.ops.object.camera_add(location=(4.0, -5.5, 2.9))
camera = bpy.context.object
camera.data.lens = 58
look_at(camera, (0, 0, 0.65))

scene = bpy.context.scene
scene.camera = camera
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1400
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(RENDER_PATH)
scene.view_settings.look = "AgX - Medium High Contrast"

BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
RENDER_PATH.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

# Export only gameplay pieces; preview ground/lights/camera stay out of the GLB.
bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
for obj in asset_objects:
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
