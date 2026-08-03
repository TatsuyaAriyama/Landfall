"""Build the empty sand-and-sandstone foundation for each player's home island.

The foundation is intentionally broad and calm: the centre is a nearly flat sand
field for player-owned props, while the irregular perimeter steps down through
hand-faceted sandstone strata into a thin beach.  Decorative rocks stay near the
edge so the initial island reads as authored without stealing buildable space.

Running this file in Blender produces the editable source, runtime USDZ, and a
review render from the same deterministic geometry.
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/home_island_foundation.blend"
USDZ_PATH = ROOT / "Landfall/Resources/home_island_foundation.usdz"
RENDER_PATH = ROOT / "marketing/3d/home-island-foundation.png"
RNG = random.Random(44103)
SEGMENTS = 48
TOP_HEIGHT = 0.62
ISLAND_RADIUS_X = 13.10
ISLAND_RADIUS_Y = 9.10


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[index : index + 2], 16) / 255 for index in (0, 2, 4)) + (alpha,)


def material(name: str, color: str, roughness: float = 0.96) -> bpy.types.Material:
    value = bpy.data.materials.new(name)
    value.diffuse_color = rgba(color)
    value.use_nodes = True
    value.use_backface_culling = False
    shader = next(node for node in value.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = rgba(color)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = 0.0
    return value


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

MATS = {
    "sand_light": material("LF_HomeSandLight", "#E9D19A", 0.99),
    "sand": material("LF_HomeSand", "#DAB878", 0.99),
    "sand_warm": material("LF_HomeSandWarm", "#CFA765", 0.99),
    "sand_shadow": material("LF_HomeSandShadow", "#B98B55", 1.0),
    "stone_light": material("LF_HomeSandstoneLight", "#C18B55", 0.98),
    "stone": material("LF_HomeSandstone", "#A96F42", 0.99),
    "stone_warm": material("LF_HomeSandstoneWarm", "#8D5537", 0.99),
    "stone_deep": material("LF_HomeSandstoneDeep", "#5B3C33", 1.0),
    "stone_cool": material("LF_HomeSandstoneCool", "#71604E", 1.0),
    "shell": material("LF_HomeShell", "#E9E0C4", 0.94),
}

root = bpy.data.objects.new("Home_Island_Foundation", None)
bpy.context.collection.objects.link(root)
asset_objects: list[bpy.types.Object] = []


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


def outline(angle: float, scale: float, layer: int = 0) -> tuple[float, float]:
    """Stable irregular ellipse shared by all cliff rings."""
    ripple = (
        math.sin(angle * 3.0 + 0.45) * 0.045
        + math.sin(angle * 7.0 - 0.82) * 0.026
        + math.sin(angle * 11.0 + 1.3) * 0.012
    )
    layer_shift = math.sin(angle * 5.0 + layer * 0.91) * 0.018
    radius = scale * (1.0 + ripple + layer_shift)
    return (
        math.cos(angle) * ISLAND_RADIUS_X * radius,
        math.sin(angle) * ISLAND_RADIUS_Y * radius,
    )


def ring(index: int, scale: float, height: float) -> list[tuple[float, float, float]]:
    points = []
    for step in range(SEGMENTS):
        angle = math.tau * step / SEGMENTS
        x, y = outline(angle, scale, index)
        # Only the perimeter undulates; the usable centre remains level.
        z = height + math.sin(angle * 6.0 + index) * 0.018
        points.append((x, y, z))
    return points


def add_ring_band(
    name: str,
    outer: list[tuple[float, float, float]],
    inner: list[tuple[float, float, float]],
    material_keys: tuple[str, ...],
) -> None:
    """Split a ring into material groups so the strata read as hand-faceted."""
    grouped: dict[str, tuple[list[tuple[float, float, float]], list[tuple[int, ...]]]] = {}
    for step in range(SEGMENTS):
        nxt = (step + 1) % SEGMENTS
        key = material_keys[(step * 5 + step // 3) % len(material_keys)]
        vertices, faces = grouped.setdefault(key, ([], []))
        base = len(vertices)
        vertices.extend((outer[step], outer[nxt], inner[nxt], inner[step]))
        faces.append((base, base + 1, base + 2, base + 3))
    for key, (vertices, faces) in grouped.items():
        mesh_object(f"{name}_{key}", vertices, faces, MATS[key])


# A wide, perfectly usable top.  Several short concentric bands avoid both a
# flat plastic-disc look and the visible starburst caused by long centre wedges.
top_ring = ring(0, 0.91, TOP_HEIGHT)
top_groups: dict[str, tuple[list[tuple[float, float, float]], list[tuple[int, ...]]]] = {}
top_rings = [
    [(math.cos(math.tau * step / SEGMENTS) * 1.12,
      math.sin(math.tau * step / SEGMENTS) * 0.76,
      TOP_HEIGHT) for step in range(SEGMENTS)],
    ring(30, 0.38, TOP_HEIGHT),
    ring(31, 0.66, TOP_HEIGHT),
    top_ring,
]
for ring_index in range(len(top_rings) - 1):
    inner = top_rings[ring_index]
    outer = top_rings[ring_index + 1]
    for step in range(SEGMENTS):
        nxt = (step + 1) % SEGMENTS
        key = "sand"
        vertices, faces = top_groups.setdefault(key, ([], []))
        base = len(vertices)
        vertices.extend((inner[step], inner[nxt], outer[nxt], outer[step]))
        faces.append((base, base + 1, base + 2, base + 3))

# The tiny centre cap keeps its triangles too short to form visible radial seams.
inner = top_rings[0]
for step in range(SEGMENTS):
    nxt = (step + 1) % SEGMENTS
    key = "sand"
    vertices, faces = top_groups.setdefault(key, ([], []))
    base = len(vertices)
    vertices.extend(((0.0, 0.0, TOP_HEIGHT), inner[step], inner[nxt]))
    faces.append((base, base + 1, base + 2))
for key, (vertices, faces) in top_groups.items():
    mesh_object(f"Buildable_Sand_{key}", vertices, faces, MATS[key])


def add_sand_patch(
    name: str,
    location: tuple[float, float],
    radii: tuple[float, float],
    mat_key: str,
    seed: int,
) -> None:
    """Add a low-contrast organic sand patch without dividing the whole plateau."""
    local = random.Random(seed)
    sides = 9
    vertices = [(location[0], location[1], TOP_HEIGHT + 0.004)]
    for step in range(sides):
        angle = math.tau * step / sides
        scale = local.uniform(0.82, 1.12)
        vertices.append((
            location[0] + math.cos(angle) * radii[0] * scale,
            location[1] + math.sin(angle) * radii[1] * scale,
            TOP_HEIGHT + 0.004,
        ))
    faces = [(0, step + 1, ((step + 1) % sides) + 1) for step in range(sides)]
    mesh_object(name, vertices, faces, MATS[mat_key])


for patch in (
    ("Pale_Sand_01", (-5.30, 2.50), (1.34, 0.80), "sand_light", 101),
    ("Pale_Sand_02", (4.40, -2.50), (1.68, 0.94), "sand_light", 102),
    ("Pale_Sand_03", (-0.60, 4.65), (1.22, 0.72), "sand_light", 106),
    ("Warm_Sand_01", (-2.50, -3.10), (1.24, 0.72), "sand_warm", 103),
    ("Warm_Sand_02", (5.30, 2.44), (1.18, 0.70), "sand_warm", 104),
    ("Warm_Sand_03", (0.30, 3.56), (0.92, 0.54), "sand_warm", 105),
    ("Warm_Sand_04", (6.90, -0.10), (1.04, 0.62), "sand_warm", 107),
):
    add_sand_patch(*patch)

# A pale apron makes the usable plateau visually obvious without drawing a hard
# editor grid into the world.
apron_outer = ring(1, 0.955, TOP_HEIGHT - 0.015)
add_ring_band(
    "Sand_Apron",
    apron_outer,
    top_ring,
    ("sand_light", "sand", "sand_warm"),
)

# Layered sandstone cliff.  The rings deliberately drift in and out so the side
# profile resembles weathered sediment instead of one thick cylinder.
cliff_rings = [
    apron_outer,
    ring(2, 0.985, 0.48),
    ring(3, 0.962, 0.20),
    ring(4, 0.925, -0.10),
    ring(5, 0.855, -0.43),
    ring(6, 0.765, -0.70),
]
bands = [
    (("stone_light", "sand_shadow", "stone"), "Upper_Strata"),
    (("stone", "stone_light", "stone_warm"), "Sunlit_Cliff"),
    (("stone_warm", "stone", "stone_deep"), "Middle_Strata"),
    (("stone_deep", "stone_warm", "stone_cool"), "Lower_Cliff"),
    (("stone_deep", "stone_cool"), "Undercut"),
]
for index, (keys, label) in enumerate(bands):
    add_ring_band(label, cliff_rings[index], cliff_rings[index + 1], keys)

# Close the underside so SceneKit can derive a stable collision hull.
bottom = cliff_rings[-1]
bottom_vertices = [(0.0, 0.0, -0.73), *bottom]
bottom_faces = []
for step in range(SEGMENTS):
    bottom_faces.append((0, step + 1, ((step + 1) % SEGMENTS) + 1))
mesh_object("Foundation_Underside", bottom_vertices, bottom_faces, MATS["stone_deep"])


def add_rock(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    mat_key: str,
    seed: int,
) -> None:
    local = random.Random(seed)
    rings = 3
    sides = 7
    vertices = [(0.0, 0.0, radius * 0.92)]
    for row in range(1, rings + 1):
        polar = math.pi * 0.5 * row / rings
        for side in range(sides):
            angle = math.tau * side / sides + row * 0.17
            r = radius * math.sin(polar) * local.uniform(0.80, 1.08)
            vertices.append((math.cos(angle) * r, math.sin(angle) * r, radius * math.cos(polar)))
    vertices.append((0.0, 0.0, -radius * 0.12))
    faces: list[tuple[int, ...]] = []
    for side in range(sides):
        faces.append((0, 1 + side, 1 + (side + 1) % sides))
    for row in range(rings - 1):
        start = 1 + row * sides
        next_start = start + sides
        for side in range(sides):
            faces.append((
                start + side,
                next_start + side,
                next_start + (side + 1) % sides,
                start + (side + 1) % sides,
            ))
    bottom_index = len(vertices) - 1
    last_start = 1 + (rings - 1) * sides
    for side in range(sides):
        faces.append((last_start + side, bottom_index, last_start + (side + 1) % sides))
    obj = mesh_object(name, vertices, faces, MATS[mat_key])
    obj.location = location
    obj.rotation_euler = (
        local.uniform(-0.18, 0.18),
        local.uniform(-0.18, 0.18),
        local.uniform(0.0, math.tau),
    )


# Sparse edge rocks preserve the broad empty centre.
for index, (angle, scale, radius, key) in enumerate((
    (-2.65, 0.78, 0.24, "stone_warm"),
    (-1.62, 0.84, 0.18, "stone_light"),
    (-0.28, 0.82, 0.28, "stone"),
    (0.72, 0.79, 0.20, "stone_cool"),
    (1.88, 0.80, 0.25, "stone_warm"),
    (2.72, 0.83, 0.17, "stone_light"),
)):
    x, y = outline(angle, scale, 10 + index)
    add_rock(
        f"Edge_Rock_{index + 1:02d}",
        (x, y, TOP_HEIGHT + radius * 0.32),
        radius,
        key,
        900 + index,
    )


def add_shell(name: str, angle: float, scale: float) -> None:
    x, y = outline(angle, scale, 20)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.075, location=(x, y, TOP_HEIGHT + 0.025))
    obj = bpy.context.object
    obj.name = name
    obj.scale = (1.25, 0.62, 0.24)
    obj.rotation_euler.z = angle * 1.7
    obj.data.materials.append(MATS["shell"])
    obj.parent = root
    asset_objects.append(obj)


for index, angle in enumerate((-2.22, -0.91, 0.28, 1.34, 2.47)):
    add_shell(f"Shell_{index + 1:02d}", angle, 0.88)


def look_at(obj: bpy.types.Object, point: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()


# Preview stage is intentionally excluded from the USDZ selection.
preview_ground = material("PREVIEW_Sea", "#24564C", 0.82)
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.76))
ground = bpy.context.object
ground.name = "PREVIEW_Sea"
ground.data.materials.append(preview_ground)

world = bpy.context.scene.world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#173F39")
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.28

for name, location, energy, size, color in (
    ("PREVIEW_Key", (-14.4, -16.0, 20.0), 1200, 11.0, "#FFE9BB"),
    ("PREVIEW_Fill", (16.0, -6.0, 12.4), 720, 10.0, "#8AC6AE"),
    ("PREVIEW_Rim", (4.0, 16.0, 16.0), 860, 9.0, "#D1E5CF"),
):
    bpy.ops.object.light_add(type="AREA", location=location)
    light = bpy.context.object
    light.name = name
    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size
    light.data.color = rgba(color)[:3]
    look_at(light, (0, 0, 0.1))

bpy.ops.object.camera_add(location=(21.6, -27.6, 18.0))
camera = bpy.context.object
camera.name = "PREVIEW_Camera"
camera.data.lens = 58
look_at(camera, (0, 0, 0.0))
bpy.context.scene.camera = camera


BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
USDZ_PATH.parent.mkdir(parents=True, exist_ok=True)
RENDER_PATH.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

# Merge same-material parts to keep runtime draw calls low.
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
scene.render.resolution_x = 1400
scene.render.resolution_y = 1100
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
print(f"BUILDABLE_WIDTH=23.6 BUILDABLE_DEPTH=16.4 SURFACE_Y={TOP_HEIGHT}")
print(f"BLEND={BLEND_PATH}")
print(f"USDZ={USDZ_PATH}")
print(f"RENDER={RENDER_PATH}")
