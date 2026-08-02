"""Build KeelMira's low-poly Wayfinder Buoy, render it, and export a GLB.

Run with:
  /Applications/Blender.app/Contents/MacOS/Blender \
    --background --factory-startup --python Tools/Blender/build_wayfinder_buoy.py
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/wayfinder_buoy.blend"
GLB_PATH = ROOT / "web/public/models/wayfinder_buoy.glb"
RENDER_PATH = ROOT / "marketing/3d/wayfinder-buoy.png"

PALETTE = {
    "night": "#123830",
    "sea": "#1E5348",
    "sand": "#EADEBD",
    "beach": "#DCCFA9",
    "wood": "#5A2A15",
    "rust": "#7A3B22",
    "rust_deep": "#4A1B0C",
    "ember": "#F3C065",
    "orange": "#F5822A",
    "coral": "#F0997B",
    "midnight": "#1A1130",
}


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float = 0.85,
    emission: str | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = rgba(color)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = rgba(color)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    if emission:
        bsdf.inputs["Emission Color"].default_value = rgba(emission)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


MATS = {
    "sand": material("LF_Sandstone", PALETTE["sand"], 0.92),
    "beach": material("LF_WeatheredStone", PALETTE["beach"], 0.96),
    "wood": material("LF_DarkWood", PALETTE["wood"], 0.82),
    "rust": material("LF_RustedIron", PALETTE["rust"], 0.78),
    "rust_deep": material("LF_DeepRust", PALETTE["rust_deep"], 0.86),
    "orange": material("LF_ReturnOrange", PALETTE["orange"], 0.8),
    "midnight": material("LF_Midnight", PALETTE["midnight"], 0.86),
    "glow": material(
        "LF_LanternGlow",
        PALETTE["ember"],
        0.38,
        emission=PALETTE["ember"],
        emission_strength=7.0,
    ),
}


def finish(obj: bpy.types.Object, name: str, mat: bpy.types.Material) -> bpy.types.Object:
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    obj.data.materials.append(mat)
    obj.parent = asset_root
    asset_objects.append(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def cylinder(
    name: str,
    radius: float,
    depth: float,
    z: float,
    mat: bpy.types.Material,
    vertices: int = 10,
    scale: tuple[float, float, float] = (1, 1, 1),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=(0, 0, z))
    obj = finish(bpy.context.object, name, mat)
    obj.scale = scale
    return obj


def cone(
    name: str,
    bottom: float,
    top: float,
    depth: float,
    z: float,
    mat: bpy.types.Material,
    vertices: int = 8,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=bottom,
        radius2=top,
        depth=depth,
        location=(0, 0, z),
    )
    return finish(bpy.context.object, name, mat)


def sphere(
    name: str,
    radius: float,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    segments: int = 12,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=max(6, segments // 2),
        radius=radius,
        location=location,
    )
    obj = finish(bpy.context.object, name, mat)
    obj.scale = scale
    return obj


def torus(
    name: str,
    major: float,
    minor: float,
    z: float,
    mat: bpy.types.Material,
    rotation: tuple[float, float, float] = (0, 0, 0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major,
        minor_radius=minor,
        major_segments=12,
        minor_segments=4,
        location=(0, 0, z),
        rotation=rotation,
    )
    return finish(bpy.context.object, name, mat)


def beam_between(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius: float,
    mat: bpy.types.Material,
    vertices: int = 6,
) -> bpy.types.Object:
    a, b = Vector(start), Vector(end)
    delta = b - a
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=delta.length,
        location=(a + b) / 2,
    )
    obj = finish(bpy.context.object, name, mat)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Z", "Y")
    return obj


def flat_shape(
    name: str,
    points: list[tuple[float, float]],
    location: tuple[float, float, float],
    mat: bpy.types.Material,
    thickness: float = 0.035,
) -> bpy.types.Object:
    # Shape lies in XZ so it reads clearly from the established three-quarter camera.
    verts = [(x, -thickness / 2, z) for x, z in points] + [
        (x, thickness / 2, z) for x, z in points
    ]
    n = len(points)
    faces = [tuple(range(n)), tuple(range(n, n * 2))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.parent = asset_root
    asset_objects.append(obj)
    return obj


def point_star(count: int, outer: float, inner: float) -> list[tuple[float, float]]:
    points = []
    for index in range(count * 2):
        angle = math.pi / 2 + index * math.pi / count
        radius = outer if index % 2 == 0 else inner
        points.append((math.cos(angle) * radius, math.sin(angle) * radius))
    return points


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


# Clean factory scene.
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

asset_objects: list[bpy.types.Object] = []
asset_root = bpy.data.objects.new("Wayfinder_Buoy", None)
bpy.context.collection.objects.link(asset_root)

# A broad, asymmetric stone float makes this feel found and weathered rather than manufactured.
sphere("Float_Stone", 0.62, (0, 0, 0.28), (1.0, 0.92, 0.38), MATS["sand"], 12)
cone("Float_Underside", 0.42, 0.53, 0.28, 0.12, MATS["beach"], 10)
torus("Float_RustBand", 0.49, 0.035, 0.31, MATS["rust_deep"])

# Barnacle-like stones break the perfect silhouette.
for index, (x, y, z, size) in enumerate(
    [(-0.42, 0.13, 0.36, 0.13), (0.28, -0.39, 0.32, 0.10), (0.43, 0.20, 0.29, 0.085)]
):
    sphere(
        f"Barnacle_{index + 1:02}",
        size,
        (x, y, z),
        (1.0, 0.78, 0.65),
        MATS["beach"],
        8,
    )

# Mast and rope collar.
cone("Mast", 0.105, 0.075, 1.42, 1.02, MATS["wood"], 8)
torus("Rope_Collar", 0.13, 0.032, 0.61, MATS["rust"])
torus("Rope_Loop", 0.29, 0.025, 0.43, MATS["rust"], rotation=(math.radians(72), 0, math.radians(18)))

# Hexagonal lantern with an exposed warm core and a small return-orange lower marker.
cylinder("Lantern_Base", 0.27, 0.09, 1.46, MATS["rust_deep"], 6)
cylinder("Lantern_Glow", 0.18, 0.43, 1.70, MATS["glow"], 8, scale=(0.88, 0.88, 1))
cylinder("Lantern_Top", 0.25, 0.08, 1.94, MATS["rust_deep"], 6)
cone("Lantern_Roof", 0.34, 0.06, 0.25, 2.105, MATS["rust"], 6)
cylinder("Return_Marker", 0.21, 0.045, 1.40, MATS["orange"], 6)

for index, angle in enumerate([0, math.pi / 3, 2 * math.pi / 3]):
    x, y = math.cos(angle) * 0.225, math.sin(angle) * 0.225
    beam_between(
        f"Lantern_Cage_{index + 1:02}",
        (x, y, 1.49),
        (x, y, 1.94),
        0.018,
        MATS["rust_deep"],
        5,
    )
    beam_between(
        f"Lantern_Cage_{index + 4:02}",
        (-x, -y, 1.49),
        (-x, -y, 1.94),
        0.018,
        MATS["rust_deep"],
        5,
    )

# A star vane is the recognizable KeelMira silhouette: navigation, not decoration.
beam_between("Vane_Stem", (0, 0, 2.18), (0, 0, 2.48), 0.025, MATS["rust_deep"], 6)
star = flat_shape("North_Star_Vane", point_star(4, 0.24, 0.075), (0, 0, 2.55), MATS["sand"], 0.045)
star.rotation_euler.z = math.radians(45)
sail = flat_shape(
    "Return_Sail_Vane",
    [(0.0, -0.12), (0.38, 0.02), (0.0, 0.15)],
    (0.08, 0.015, 2.28),
    MATS["orange"],
    0.025,
)

# Point light is preview-only; the exported glow is carried by the emissive material.
bpy.ops.object.light_add(type="POINT", location=(0, -0.02, 1.73))
lantern_light = bpy.context.object
lantern_light.name = "PREVIEW_LanternLight"
lantern_light.data.color = rgba(PALETTE["ember"])[:3]
lantern_light.data.energy = 75
lantern_light.data.shadow_soft_size = 0.55

# Preview world.
bpy.context.scene.world.color = rgba(PALETTE["night"])[:3]
bpy.context.scene.world.use_nodes = True
world_bg = bpy.context.scene.world.node_tree.nodes["Background"]
world_bg.inputs["Color"].default_value = rgba(PALETTE["night"])
world_bg.inputs["Strength"].default_value = 0.22

bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, -0.01))
sea = bpy.context.object
sea.name = "PREVIEW_Sea"
sea_mat = material("PREVIEW_SeaMaterial", PALETTE["sea"], 0.72)
sea.data.materials.append(sea_mat)

# A few flat ripple rings ground the object without turning the preview into a diorama.
for index, radius in enumerate((0.82, 1.12, 1.48)):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=radius,
        minor_radius=0.012,
        major_segments=48,
        minor_segments=3,
        location=(0, 0, 0.018 + index * 0.002),
    )
    ripple = bpy.context.object
    ripple.name = f"PREVIEW_Ripple_{index + 1}"
    ripple.data.materials.append(material(f"PREVIEW_RippleMat_{index + 1}", "#7FB8A6", 0.75))

# Studio lighting follows the moonlit palette already used by the app.
bpy.ops.object.light_add(type="AREA", location=(-3.7, -4.4, 6.2))
key = bpy.context.object
key.name = "PREVIEW_MoonKey"
key.data.energy = 560
key.data.shape = "DISK"
key.data.size = 4.5
key.data.color = rgba(PALETTE["sand"])[:3]
look_at(key, (0, 0, 1.0))

bpy.ops.object.light_add(type="AREA", location=(4.5, 1.5, 3.0))
fill = bpy.context.object
fill.name = "PREVIEW_SeaFill"
fill.data.energy = 360
fill.data.size = 5.0
fill.data.color = rgba("#7FB8A6")[:3]
look_at(fill, (0, 0, 1.1))

bpy.ops.object.camera_add(location=(4.4, -6.3, 3.35))
camera = bpy.context.object
camera.name = "PREVIEW_Camera"
camera.data.lens = 58
look_at(camera, (0, 0, 1.22))
bpy.context.scene.camera = camera

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1200
scene.render.resolution_y = 1200
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.film_transparent = False
scene.render.filepath = str(RENDER_PATH)
scene.render.image_settings.color_depth = "8"
scene.view_settings.look = "AgX - Medium High Contrast"

# Save the editable source with the preview rig, then export only the asset hierarchy.
BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
RENDER_PATH.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

bpy.ops.object.select_all(action="DESELECT")
asset_root.select_set(True)
for obj in asset_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = asset_root
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
