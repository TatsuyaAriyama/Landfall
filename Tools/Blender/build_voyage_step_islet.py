"""Build the simple sand islet used for voyage steps.

The midway island is intentionally quiet: one low sandbar, one soft dune, and
a broken line of foam. Completion is communicated by SceneKit's flag and glow,
not by extra architecture on the island itself.

Run with:
  /Applications/Blender.app/Contents/MacOS/Blender \
    --background --factory-startup --python Tools/Blender/build_voyage_step_islet.py
"""

from __future__ import annotations

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/voyage_step_islet.blend"
USDZ_PATH = ROOT / "Landfall/Resources/voyage_step_islet.usdz"
RENDER_PATH = ROOT / "marketing/3d/voyage-step-islet.png"


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float = 0.98,
    *,
    alpha: float = 1.0,
) -> bpy.types.Material:
    value = bpy.data.materials.new(name)
    value.diffuse_color = rgba(color, alpha)
    value.use_nodes = True
    value.use_backface_culling = False
    shader = next(node for node in value.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = rgba(color, alpha)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Alpha"].default_value = alpha
    if alpha < 1:
        value.surface_render_method = "DITHERED"
    return value


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

MATS = {
    "shadow": material("LF_StepShadow", "#123B37", 1.0, alpha=0.42),
    "foam": material("LF_StepFoam", "#E4EFE3", 0.72, alpha=0.84),
    "wet": material("LF_StepWetSand", "#B5A36F", 0.9),
    "beach": material("LF_StepBeach", "#DDCC97", 0.98),
    "dune": material("LF_StepDune", "#D5BE82", 1.0),
    "dune_light": material("LF_StepDuneLight", "#E7D7A7", 0.98),
}

root = bpy.data.objects.new("Voyage_Step_Islet", None)
bpy.context.collection.objects.link(root)
asset_objects: list[bpy.types.Object] = []


def keep(obj: bpy.types.Object, name: str, mat: bpy.types.Material) -> bpy.types.Object:
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    if not obj.data.materials:
        obj.data.materials.append(mat)
    obj.parent = root
    asset_objects.append(obj)
    if hasattr(obj.data, "polygons"):
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


COAST = [
    (-1.22, -0.18),
    (-0.92, -0.50),
    (-0.42, -0.66),
    (0.10, -0.64),
    (0.66, -0.52),
    (1.13, -0.23),
    (1.26, 0.10),
    (1.02, 0.42),
    (0.54, 0.60),
    (0.02, 0.65),
    (-0.54, 0.56),
    (-1.00, 0.35),
    (-1.26, 0.08),
]


def ring(
    scale_x: float,
    scale_y: float,
    z: float,
    offset_x: float = 0.0,
    offset_y: float = 0.0,
) -> list[tuple[float, float, float]]:
    return [(x * scale_x + offset_x, y * scale_y + offset_y, z) for x, y in COAST]


def band(
    name: str,
    lower: list[tuple[float, float, float]],
    upper: list[tuple[float, float, float]],
    mat: bpy.types.Material,
    *,
    cap_top: bool = False,
) -> bpy.types.Object:
    count = len(lower)
    vertices = lower + upper
    faces: list[tuple[int, ...]] = []
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, count + nxt, count + index))
    if cap_top:
        center = len(vertices)
        vertices.append(
            (
                sum(point[0] for point in upper) / count,
                sum(point[1] for point in upper) / count,
                sum(point[2] for point in upper) / count,
            )
        )
        for index in range(count):
            nxt = (index + 1) % count
            faces.append((center, count + index, count + nxt))
    return mesh_object(name, vertices, faces, mat)


# A faint submerged shadow anchors the otherwise very light island to the sea.
bpy.ops.mesh.primitive_cylinder_add(vertices=13, radius=1, depth=0.016, location=(0, 0, 0.0))
shadow = keep(bpy.context.object, "LF_StepShadow", MATS["shadow"])
shadow.scale = (1.42, 0.82, 1)

# Broken foam keeps the silhouette natural and avoids a bright perfect ring.
foam_outer = ring(1.09, 1.10, 0.025)
foam_inner = ring(1.01, 1.01, 0.029)
foam_vertices = foam_outer + foam_inner
foam_faces: list[tuple[int, ...]] = []
for index in range(len(COAST)):
    if index in {2, 6, 10}:
        continue
    nxt = (index + 1) % len(COAST)
    foam_faces.append((index, nxt, len(COAST) + nxt, len(COAST) + index))
mesh_object("LF_StepFoam", foam_vertices, foam_faces, MATS["foam"])

# Two shallow shelves: darker wet sand at the waterline and dry sand above it.
wet_lower = ring(1.00, 1.00, 0.035)
wet_upper = ring(0.94, 0.92, 0.080, -0.015, 0.005)
band("LF_StepWetSand", wet_lower, wet_upper, MATS["wet"])

beach_lower = ring(0.94, 0.92, 0.080, -0.015, 0.005)
beach_upper = ring(0.78, 0.73, 0.145, -0.055, 0.015)
band("LF_StepBeach", beach_lower, beach_upper, MATS["beach"], cap_top=True)

# One low dune supplies just enough height for the completion flag. It stays
# broad and rounded in plan, with no rocks, buildings, paths, or props.
dune_lower = ring(0.73, 0.66, 0.135, -0.06, 0.035)
dune_mid = ring(0.52, 0.46, 0.285, -0.10, 0.055)
dune_top = ring(0.25, 0.20, 0.450, -0.07, 0.025)
band("LF_StepDune", dune_lower, dune_mid, MATS["dune"])
band("LF_StepDuneLight", dune_mid, dune_top, MATS["dune_light"], cap_top=True)


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_preview_stage() -> None:
    sea = material("PREVIEW_Sea", "#1E554E", 0.38)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.015))
    bpy.context.object.name = "PREVIEW_Sea"
    bpy.context.object.data.materials.append(sea)

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#153E3A")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.28

    for name, location, energy, size, color in (
        ("PREVIEW_Key", (-4.5, -5.5, 7.4), 650, 5.0, "#F4E4BD"),
        ("PREVIEW_Fill", (5.0, -1.8, 4.2), 300, 4.2, "#78BFAE"),
        ("PREVIEW_Rim", (1.5, 4.8, 5.2), 360, 3.2, "#EE9875"),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = rgba(color)[:3]
        look_at(light, (0, 0, 0.16))

    bpy.ops.object.camera_add(location=(3.0, -4.8, 2.8))
    camera = bpy.context.object
    camera.name = "PREVIEW_Camera"
    camera.data.lens = 66
    look_at(camera, (0, 0, 0.14))
    bpy.context.scene.camera = camera


add_preview_stage()

BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
USDZ_PATH.parent.mkdir(parents=True, exist_ok=True)
RENDER_PATH.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

# Merge by material so cloning up to three islands remains trivial for SceneKit.
groups: dict[str, list[bpy.types.Object]] = {}
for obj in asset_objects:
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
scene.render.resolution_x = 1400
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.color_depth = "8"
scene.render.filepath = str(RENDER_PATH)
scene.render.film_transparent = False
scene.view_settings.look = "AgX - Medium High Contrast"
bpy.ops.render.render(write_still=True)

triangles = sum(len(p.vertices) - 2 for obj in export_objects for p in obj.data.polygons)
print(f"MESHES={len(export_objects)} TRIANGLES={triangles}")
print(f"BLEND={BLEND_PATH}")
print(f"USDZ={USDZ_PATH}")
print(f"RENDER={RENDER_PATH}")
