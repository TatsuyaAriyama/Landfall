"""Build Landfall's weathered wooden crate as a standalone USDZ asset.

The crate uses the same hand-faceted, salt-worn language as the home island and
weathered cottage.  Individual warped planks, crooked braces, corroded nails,
broken top boards, and subtle moss make it readable from every camera angle.
The deterministic script emits editable Blender source, runtime USDZ, and a
review render from the same geometry.
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/weathered_crate.blend"
USDZ_PATH = ROOT / "Landfall/Resources/weathered_crate.usdz"
RENDER_PATH = ROOT / "marketing/3d/weathered-crate.png"
RNG = random.Random(77421)


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[index : index + 2], 16) / 255 for index in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float = 0.96,
    *,
    metallic: float = 0.0,
    double_sided: bool = False,
) -> bpy.types.Material:
    value = bpy.data.materials.new(name)
    value.diffuse_color = rgba(color)
    value.use_nodes = True
    value.use_backface_culling = not double_sided
    shader = next(node for node in value.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = rgba(color)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    return value


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

MATS = {
    "wood_deep": material("LF_CrateWoodDeep", "#332922", 0.99),
    "wood_shadow": material("LF_CrateWoodShadow", "#4A372B", 0.99),
    "wood": material("LF_CrateWood", "#674A36", 0.98),
    "wood_warm": material("LF_CrateWoodWarm", "#7D5C3F", 0.97),
    "wood_salt": material("LF_CrateWoodSalt", "#8C8067", 0.99),
    "iron": material("LF_CrateIron", "#29312E", 0.89, metallic=0.22),
    "rust": material("LF_CrateRust", "#784730", 0.96, metallic=0.08),
    "moss": material("LF_CrateMoss", "#53684D", 1.0, double_sided=True),
}

root = bpy.data.objects.new("Weathered_Crate", None)
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
    bevel: float = 0.010,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        modifier = obj.modifiers.new(name="Worn edges", type="BEVEL")
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
    width: float,
    depth: float,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    a = Vector(start)
    b = Vector(end)
    direction = b - a
    obj = add_box(
        name,
        tuple((a + b) * 0.5),
        (depth, width, direction.length),
        mat,
        bevel=min(width * 0.10, 0.010),
    )
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return obj


def add_nail(name: str, location: tuple[float, float, float], axis: str, mat: bpy.types.Material) -> None:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.030, location=location)
    nail = bpy.context.object
    if axis == "y":
        nail.scale = (1.0, 0.34, 1.0)
    elif axis == "x":
        nail.scale = (0.34, 1.0, 1.0)
    else:
        nail.scale = (1.0, 1.0, 0.34)
    keep(nail, name, mat)


# A dark inner shell prevents visible holes between deliberately uneven boards.
add_box("Crate_Inner", (0, 0, 0.52), (1.18, 0.88, 0.91), MATS["wood_deep"], bevel=0.025)

plank_materials = (
    MATS["wood"],
    MATS["wood_warm"],
    MATS["wood_shadow"],
    MATS["wood_salt"],
    MATS["wood"],
)

# Front and back boards vary subtly in height, lean, and depth.
for side in (-1, 1):
    for index in range(5):
        x = -0.49 + index * 0.245 + RNG.uniform(-0.010, 0.010)
        height = 0.76 + RNG.uniform(-0.035, 0.035)
        add_box(
            f"{'Back' if side > 0 else 'Front'}_Plank_{index + 1:02}",
            (x, side * (0.475 + RNG.uniform(0.0, 0.012)), 0.52 + RNG.uniform(-0.010, 0.010)),
            (0.232, 0.060, height),
            plank_materials[(index + (2 if side > 0 else 0)) % len(plank_materials)],
            (RNG.uniform(-0.010, 0.010), RNG.uniform(-0.016, 0.016), RNG.uniform(-0.018, 0.018)),
        )

# Side boards keep the crate authored from a full 360-degree orbit.
for side in (-1, 1):
    for index in range(4):
        y = -0.34 + index * 0.225 + RNG.uniform(-0.010, 0.010)
        add_box(
            f"{'Right' if side > 0 else 'Left'}_Plank_{index + 1:02}",
            (side * (0.625 + RNG.uniform(0.0, 0.010)), y, 0.52 + RNG.uniform(-0.012, 0.012)),
            (0.060, 0.214, 0.77 + RNG.uniform(-0.035, 0.025)),
            plank_materials[(index + (1 if side > 0 else 3)) % len(plank_materials)],
            (RNG.uniform(-0.012, 0.012), RNG.uniform(-0.012, 0.012), RNG.uniform(-0.016, 0.016)),
        )

# Salt-worn top slats. One shortened, lifted board gives the silhouette damage.
for index in range(5):
    x = -0.50 + index * 0.25
    broken = index == 4
    add_box(
        f"Top_Plank_{index + 1:02}",
        (x - (0.035 if broken else 0), -0.08 if broken else 0, 1.015 + (0.045 if broken else RNG.uniform(-0.008, 0.008))),
        (0.232 if not broken else 0.17, 0.92 if not broken else 0.70, 0.066),
        plank_materials[(index + 1) % len(plank_materials)],
        (0.0, RNG.uniform(-0.018, 0.018), RNG.uniform(-0.018, 0.018) + (0.075 if broken else 0)),
    )

# Two underside skids keep the asset grounded without a bulky pedestal.
for index, y in enumerate((-0.31, 0.31)):
    add_box(
        f"Bottom_Skid_{index + 1:02}",
        (0, y, 0.055),
        (1.08, 0.13, 0.11),
        MATS["wood_deep" if index else "wood_shadow"],
        (0, RNG.uniform(-0.012, 0.012), RNG.uniform(-0.012, 0.012)),
        0.014,
    )

# Crooked corner posts and perimeter rails visually bind the loose planks.
for index, (x, y) in enumerate(((-0.61, -0.48), (0.61, -0.48), (-0.61, 0.48), (0.61, 0.48))):
    add_box(
        f"Corner_Post_{index + 1:02}",
        (x, y, 0.52),
        (0.125, 0.125, 1.01),
        MATS["wood_deep" if index % 3 == 0 else "wood_shadow"],
        (RNG.uniform(-0.012, 0.012), RNG.uniform(-0.012, 0.012), RNG.uniform(-0.020, 0.020)),
        0.014,
    )

for side in (-1, 1):
    for index, z in enumerate((0.17, 0.88)):
        add_box(
            f"{'Back' if side > 0 else 'Front'}_Rail_{index + 1:02}",
            (0, side * 0.525, z),
            (1.22, 0.085, 0.115),
            MATS["wood_shadow" if index == 0 else "wood_deep"],
            (0, 0, RNG.uniform(-0.018, 0.018)),
            0.014,
        )
for side in (-1, 1):
    for index, z in enumerate((0.18, 0.87)):
        add_box(
            f"{'Right' if side > 0 else 'Left'}_Rail_{index + 1:02}",
            (side * 0.665, 0, z),
            (0.085, 0.95, 0.11),
            MATS["wood_deep" if index == 0 else "wood_shadow"],
            (0, 0, RNG.uniform(-0.014, 0.014)),
            0.012,
        )

# Signature crossed braces on front and back, intentionally not mirror-perfect.
for side in (-1, 1):
    plane = side * 0.572
    add_beam(
        f"{'Back' if side > 0 else 'Front'}_Brace_A",
        (-0.52, plane, 0.22),
        (0.49, plane, 0.84),
        0.105,
        0.070,
        MATS["wood_warm"],
    )
    add_beam(
        f"{'Back' if side > 0 else 'Front'}_Brace_B",
        (0.52, plane + side * 0.006, 0.23),
        (-0.47, plane + side * 0.006, 0.82),
        0.095,
        0.066,
        MATS["wood_salt" if side > 0 else "wood_shadow"],
    )

# Corroded fasteners remain legible at island-camera distance.
for side in (-1, 1):
    for row, z in enumerate((0.21, 0.84)):
        for column, x in enumerate((-0.50, 0.0, 0.50)):
            add_nail(
                f"Nail_FB_{'B' if side > 0 else 'F'}_{row}_{column}",
                (x, side * 0.615, z),
                "y",
                MATS["rust" if (row + column) % 3 == 0 else "iron"],
            )
for side in (-1, 1):
    for index, (y, z) in enumerate(((-0.34, 0.20), (0.34, 0.86))):
        add_nail(
            f"Nail_Side_{'R' if side > 0 else 'L'}_{index}",
            (side * 0.710, y, z),
            "x",
            MATS["rust" if index else "iron"],
        )

# A few physical grain scars and a snapped sliver prevent a toy-like clean read.
for index, (x, z, length) in enumerate(((-0.36, 0.43, 0.20), (0.18, 0.64, 0.16), (0.43, 0.36, 0.13))):
    add_box(
        f"Front_Grain_Scar_{index + 1:02}",
        (x, -0.618, z),
        (0.018, 0.010, length),
        MATS["wood_deep"],
        (0, 0, RNG.uniform(-0.55, 0.55)),
        0.003,
    )
add_beam(
    "Broken_Top_Splinter",
    (0.47, 0.27, 1.055),
    (0.62, 0.41, 1.22),
    0.035,
    0.024,
    MATS["wood_salt"],
)

# Small moss polygons hug the lower shaded faces rather than covering the crate.
mesh_object(
    "Moss_Front_Lower",
    [(-0.57, -0.621, 0.13), (-0.24, -0.621, 0.13), (-0.18, -0.621, 0.25), (-0.37, -0.621, 0.31), (-0.58, -0.621, 0.24)],
    [(0, 1, 2, 3, 4)],
    MATS["moss"],
)
mesh_object(
    "Moss_Left_Lower",
    [(-0.712, -0.38, 0.12), (-0.712, -0.08, 0.13), (-0.712, 0.04, 0.23), (-0.712, -0.17, 0.27), (-0.712, -0.40, 0.21)],
    [(0, 1, 2, 3, 4)],
    MATS["moss"],
)


def look_at(obj: bpy.types.Object, point: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()


# Preview-only stage; none of these objects enter the USDZ selection.
preview_ground = material("PREVIEW_Ground", "#244E47", 0.88)
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.01))
ground = bpy.context.object
ground.name = "PREVIEW_Ground"
ground.data.materials.append(preview_ground)

world = bpy.context.scene.world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#173F39")
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.32

for name, location, energy, size, color in (
    ("PREVIEW_Key", (-3.6, -4.2, 6.0), 720, 3.6, "#FFE6B7"),
    ("PREVIEW_Fill", (4.2, -1.5, 3.6), 430, 3.2, "#82BFA8"),
    ("PREVIEW_Rim", (1.0, 4.0, 4.5), 520, 2.8, "#C7DECB"),
):
    bpy.ops.object.light_add(type="AREA", location=location)
    light = bpy.context.object
    light.name = name
    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size
    light.data.color = rgba(color)[:3]
    look_at(light, (0, 0, 0.55))

bpy.ops.object.camera_add(location=(3.2, -4.2, 2.75))
camera = bpy.context.object
camera.name = "PREVIEW_Camera"
camera.data.lens = 62
look_at(camera, (0, 0, 0.52))
bpy.context.scene.camera = camera

BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
USDZ_PATH.parent.mkdir(parents=True, exist_ok=True)
RENDER_PATH.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

# Merge same-material parts to minimize SceneKit draw calls.
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
scene.view_settings.look = "AgX - Medium High Contrast"
bpy.ops.render.render(write_still=True)

triangles = sum(
    len(polygon.vertices) - 2
    for obj in export_objects
    for polygon in obj.data.polygons
)
print(f"ASSET={root.name} MESHES={len(export_objects)} TRIANGLES={triangles}")
print("FOOTPRINT=1.44x1.24 HEIGHT=1.24 ORIGIN_Y=0")
print(f"BLEND={BLEND_PATH}")
print(f"USDZ={USDZ_PATH}")
print(f"RENDER={RENDER_PATH}")
