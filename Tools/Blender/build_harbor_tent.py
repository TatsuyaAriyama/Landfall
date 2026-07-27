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
    "canvas": "#7A4528",
    "canvas_dark": "#4A1B0C",
    "canvas_light": "#A66A3F",
    "wood": "#5A2A15",
    "rope": "#DCCFA9",
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


MATS = {
    "canvas": material("LF_TentCanvas", COLORS["canvas"], 0.96),
    "canvas_dark": material("LF_TentCanvasDark", COLORS["canvas_dark"], 0.94),
    "canvas_light": material("LF_TentCanvasSunworn", COLORS["canvas_light"], 0.96),
    "wood": material("LF_TentWood", COLORS["wood"], 0.9),
    "rope": material("LF_TentRope", COLORS["rope"], 1),
    "sand": material("LF_TentGroundsheet", COLORS["sand"], 0.98),
    "bed": material("LF_TentBedroll", COLORS["bed"], 0.96),
    "orange": material("LF_TentOrange", COLORS["orange"], 0.88),
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
front, back, half_width, ridge = -0.82, 0.82, 1.02, 1.42
mesh(
    "Tent_LeftCanvas",
    [(-half_width, front, 0), (0, front, ridge), (0, back, ridge), (-half_width, back, 0)],
    [(0, 1, 2, 3)],
    MATS["canvas"],
)
mesh(
    "Tent_RightCanvas",
    [(0, front, ridge), (half_width, front, 0), (half_width, back, 0), (0, back, ridge)],
    [(0, 1, 2, 3)],
    MATS["canvas_light"],
)
mesh(
    "Tent_BackCanvas",
    [(-half_width, back, 0), (half_width, back, 0), (0, back, ridge)],
    [(0, 1, 2)],
    MATS["canvas_dark"],
)

# Rolled entrance flaps leave an unmistakable opening instead of a painted doorway.
beam("Tent_LeftFlap", (-0.92, front - 0.015, 0.04), (-0.08, front - 0.015, 1.33), 0.055, MATS["canvas_dark"])
beam("Tent_RightFlap", (0.92, front - 0.015, 0.04), (0.08, front - 0.015, 1.33), 0.055, MATS["canvas"])

# Ridge, A-frame poles, guy ropes, and stakes make the structure feel usable.
beam("Tent_RidgePole", (0, front - 0.14, ridge + 0.03), (0, back + 0.18, ridge + 0.03), 0.035, MATS["wood"])
for side, x in (("L", -half_width), ("R", half_width)):
    beam(f"Tent_FrontPole_{side}", (x, front - 0.03, 0), (0, front - 0.03, ridge + 0.03), 0.038, MATS["wood"])
    beam(f"Tent_BackPole_{side}", (x, back + 0.03, 0), (0, back + 0.03, ridge + 0.03), 0.038, MATS["wood"])
for index, (a, b) in enumerate(
    [
        ((-0.96, front, 0.52), (-1.42, front - 0.42, 0.04)),
        ((0.96, front, 0.52), (1.42, front - 0.42, 0.04)),
        ((-0.96, back, 0.52), (-1.42, back + 0.42, 0.04)),
        ((0.96, back, 0.52), (1.42, back + 0.42, 0.04)),
    ]
):
    beam(f"Tent_GuyRope_{index + 1}", a, b, 0.009, MATS["rope"])
    beam(f"Tent_Stake_{index + 1}", (b[0], b[1], 0), (b[0], b[1], 0.16), 0.025, MATS["wood"])

# A groundsheet and bedroll give entering the tent a purpose: this is a place to rest.
cube("Tent_Groundsheet", (0, 0.05, 0.025), (0.77, 0.7, 0.025), MATS["sand"])
cube("Tent_Bedroll", (0.34, 0.18, 0.14), (0.3, 0.49, 0.11), MATS["bed"], (0, 0, 0.04))
beam("Tent_BedrollTie", (0.02, 0.18, 0.26), (0.66, 0.18, 0.26), 0.018, MATS["rope"])

# Warm entrance lantern and a tiny return-orange pennant tie the tent to Landfall.
beam("Tent_LanternHook", (-0.42, front - 0.03, 0.74), (-0.42, front - 0.03, 1.08), 0.018, MATS["wood"])
cube("Tent_LanternBody", (-0.42, front - 0.05, 0.65), (0.09, 0.07, 0.12), MATS["glow"])
mesh(
    "Tent_Pennant",
    [(0.02, back, 1.44), (0.02, back, 1.7), (0.45, back, 1.56)],
    [(0, 1, 2)],
    MATS["orange"],
)


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
