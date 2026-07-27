"""Build Landfall's small low-poly flying fish and export it for the sailing sea."""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/flying_fish.blend"
GLB_PATH = ROOT / "web/public/models/flying_fish.glb"
RENDER_PATH = ROOT / "marketing/3d/flying-fish.png"

COLORS = {
    "night": "#123830",
    "sea": "#1E5348",
    "sea_deep": "#0D2A24",
    "body": "#7FB8A6",
    "body_dark": "#184A40",
    "belly": "#EADEBD",
    "fin": "#5DCAA5",
    "fin_edge": "#123830",
    "coral": "#F0997B",
    "orange": "#F5822A",
    "eye": "#1A1130",
}


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float = 0.82,
    alpha: float = 1.0,
) -> bpy.types.Material:
    value = bpy.data.materials.new(name)
    value.diffuse_color = rgba(color, alpha)
    value.use_nodes = True
    # Blender 5 localizes/renames the node label; the stable node type is the
    # reliable contract across the existing Blender 4 assets and current 5.x.
    bsdf = next(node for node in value.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = rgba(color, alpha)
    bsdf.inputs["Roughness"].default_value = roughness
    if alpha < 1:
        bsdf.inputs["Alpha"].default_value = alpha
        value.surface_render_method = "DITHERED"
    return value


MATS = {
    "body": material("LF_FlyingFishBody", COLORS["body"], 0.68),
    "back": material("LF_FlyingFishBack", COLORS["body_dark"], 0.78),
    "belly": material("LF_FlyingFishBelly", COLORS["belly"], 0.9),
    "fin": material("LF_FlyingFishWingMembrane", COLORS["fin"], 0.74, 0.92),
    "fin_edge": material("LF_FlyingFishFinEdge", COLORS["fin_edge"], 0.82),
    "coral": material("LF_FlyingFishCoralMark", COLORS["coral"], 0.8),
    "eye": material("LF_FlyingFishEye", COLORS["eye"], 0.56),
    "orange": material("LF_FlyingFishAccent", COLORS["orange"], 0.76),
}


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

root = bpy.data.objects.new("FlyingFish", None)
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


def ico(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    subdivisions: int = 1,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=subdivisions,
        radius=1,
        location=location,
    )
    obj = keep(bpy.context.object, name, mat)
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def mesh_at_root(
    name: str,
    root_position: tuple[float, float, float],
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    mat: bpy.types.Material,
    thickness: float = 0.0,
) -> bpy.types.Object:
    data = bpy.data.meshes.new(f"{name}_Mesh")
    data.from_pydata(vertices, [], faces)
    data.materials.append(mat)
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = root_position
    obj.parent = root
    asset_objects.append(obj)
    if thickness > 0:
        modifier = obj.modifiers.new(name=f"{name}_Thickness", type="SOLIDIFY")
        modifier.thickness = thickness
        modifier.offset = 0
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)
    return obj


def beam(
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
        location=tuple((a + b) / 2),
    )
    obj = keep(bpy.context.object, name, mat)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Z", "Y")
    return obj


def parent_keep_world(child: bpy.types.Object, parent: bpy.types.Object) -> None:
    """Parent a detail to an animated part without changing its authored pose."""
    child.matrix_world = child.matrix_world
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()


# Blender coordinates: +X is forward, +Z is up, ±Y is lateral. glTF's Y-up
# conversion keeps +X forward and maps lateral width to ±Z at runtime.
ico("FlyingFish_Body", (0, 0, 0), (0.58, 0.145, 0.17), MATS["body"], 2)
ico("FlyingFish_Head", (0.42, 0, 0.015), (0.25, 0.15, 0.16), MATS["back"], 1)
ico("FlyingFish_Belly", (0.06, 0, -0.105), (0.42, 0.12, 0.06), MATS["belly"], 1)

# A small tapered snout and narrow caudal peduncle preserve the torpedo silhouette.
ico("FlyingFish_Snout", (0.62, 0, 0.01), (0.11, 0.105, 0.095), MATS["body"], 1)
beam("FlyingFish_TailPeduncle", (-0.42, 0, 0), (-0.66, 0, -0.005), 0.068, MATS["back"], 7)

# The caudal fin's lower lobe is deliberately longer. Flying fish keep this
# hypocaudal lobe in the water during taxiing to continue generating thrust.
tail = mesh_at_root(
    "FlyingFish_Tail",
    (-0.64, 0, 0),
    [
        (0.02, 0, 0.04),
        (-0.25, 0, 0.25),
        (-0.18, 0, 0.03),
        (-0.33, 0, -0.38),
        (0.03, 0, -0.06),
    ],
    [(0, 1, 2), (0, 2, 3, 4)],
    MATS["fin"],
    0.025,
)
tail_upper = beam(
    "FlyingFish_TailLeadingUpper",
    (-0.62, 0, 0.04),
    (-0.89, 0, 0.25),
    0.014,
    MATS["fin_edge"],
)
tail_lower = beam(
    "FlyingFish_TailLeadingLower",
    (-0.62, 0, -0.05),
    (-0.97, 0, -0.38),
    0.014,
    MATS["fin_edge"],
)
parent_keep_world(tail_upper, tail)
parent_keep_world(tail_lower, tail)


def wing(side: int) -> None:
    side_name = "L" if side > 0 else "R"
    root_position = (0.22, side * 0.105, 0.035)
    # Each wing is authored around its own shoulder pivot so the web app can fold
    # it backward for swimming and open it for a glide.
    pectoral = mesh_at_root(
        f"FlyingFish_Pectoral_{side_name}",
        root_position,
        [
            (0, 0, 0),
            (-0.12, side * 0.54, 0.015),
            (-0.48, side * 0.64, -0.005),
            (-0.36, side * 0.17, -0.035),
        ],
        [(0, 1, 2, 3)],
        MATS["fin"],
        0.012,
    )
    pectoral_edge = beam(
        f"FlyingFish_PectoralEdge_{side_name}",
        root_position,
        (-0.26, side * 0.745, 0.03),
        0.012,
        MATS["fin_edge"],
        5,
    )
    parent_keep_world(pectoral_edge, pectoral)
    # Four-winged flying-fish species also enlarge the pelvic fins. They stay
    # smaller than the pectorals, adding lift without turning the silhouette into a ray.
    mesh_at_root(
        f"FlyingFish_Pelvic_{side_name}",
        (-0.25, side * 0.09, -0.03),
        [
            (0, 0, 0),
            (-0.08, side * 0.26, -0.005),
            (-0.30, side * 0.31, -0.025),
            (-0.24, side * 0.07, -0.035),
        ],
        [(0, 1, 2, 3)],
        MATS["fin"],
        0.01,
    )


wing(1)
wing(-1)

# Low dorsal and anal stabilizers.
mesh_at_root(
    "FlyingFish_Dorsal",
    (-0.12, 0, 0.13),
    [(0, 0, 0), (-0.16, 0, 0.17), (-0.34, 0, 0)],
    [(0, 1, 2)],
    MATS["fin"],
    0.018,
)
mesh_at_root(
    "FlyingFish_Anal",
    (-0.16, 0, -0.13),
    [(0, 0, 0), (-0.13, 0, -0.13), (-0.28, 0, 0)],
    [(0, 1, 2)],
    MATS["fin"],
    0.018,
)

# Large, high-set eyes remain legible at the deliberately tiny runtime scale.
for side in (-1, 1):
    ico(
        f"FlyingFish_Eye_{'L' if side > 0 else 'R'}",
        (0.49, side * 0.124, 0.075),
        (0.042, 0.025, 0.042),
        MATS["eye"],
        1,
    )
    ico(
        f"FlyingFish_EyeGlint_{'L' if side > 0 else 'R'}",
        (0.51, side * 0.145, 0.09),
        (0.012, 0.008, 0.012),
        MATS["belly"],
        1,
    )

# A restrained return-orange mark ties the animal to Landfall's existing palette.
beam("FlyingFish_CoralStripe", (0.28, -0.151, -0.015), (0.28, -0.153, 0.08), 0.016, MATS["coral"], 5)
ico("FlyingFish_OrangeGill", (0.35, -0.143, -0.015), (0.03, 0.012, 0.06), MATS["orange"], 1)


def look_at(obj: bpy.types.Object, point: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()


# Preview scene: one open-wing fish and one folded-wing silhouette over the sea.
world = bpy.context.scene.world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba(COLORS["night"])
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.22

bpy.ops.mesh.primitive_plane_add(size=18, location=(0, 0, -0.75))
preview_sea = bpy.context.object
preview_sea.name = "PREVIEW_Sea"
preview_sea.data.materials.append(material("PREVIEW_SeaMaterial", COLORS["sea"], 0.68))

bpy.ops.object.light_add(type="AREA", location=(-3.5, -4.5, 5.5))
key = bpy.context.object
key.name = "PREVIEW_MoonKey"
key.data.energy = 720
key.data.size = 4.0
key.data.color = rgba(COLORS["belly"])[:3]
look_at(key, (0, 0, 0))

bpy.ops.object.light_add(type="AREA", location=(4.0, 3.0, 2.5))
fill = bpy.context.object
fill.name = "PREVIEW_SeaFill"
fill.data.energy = 420
fill.data.size = 4.0
fill.data.color = rgba(COLORS["fin"])[:3]
look_at(fill, (0, 0, 0))

bpy.ops.object.camera_add(location=(3.3, -4.8, 2.3))
camera = bpy.context.object
camera.name = "PREVIEW_Camera"
camera.data.lens = 62
look_at(camera, (0, 0, -0.02))

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
