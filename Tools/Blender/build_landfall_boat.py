"""Build a higher-detail low-poly KeelMira boat and export a web-ready GLB.

The editable source keeps every semantic part separate. The delivery GLB is merged
by material, preserving stable material names for runtime color customization.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/landfall_boat.blend"
GLB_PATH = ROOT / "web/public/models/landfall_boat.glb"
USDZ_PATH = ROOT / "Landfall/Resources/landfall_boat.usdz"
RENDER_PATH = ROOT / "marketing/3d/landfall-boat.png"

COLORS = {
    "night": "#123830",
    "sea": "#1E5348",
    "sand": "#EADEBD",
    "coral": "#F0997B",
    "orange": "#F5822A",
    "wood": "#5A2A15",
    "wood_light": "#7A4528",
    "rust": "#7A3B22",
    "rust_deep": "#4A1B0C",
    "rope": "#B7A277",
    "midnight": "#1A1130",
    "ember": "#F3C065",
    "ripple": "#7FB8A6",
}


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float,
    emission: str | None = None,
    emission_strength: float = 0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = rgba(color)
    mat.use_nodes = True
    bsdf = next(node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = rgba(color)
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = rgba(emission)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


# Stable names are the runtime color contract.
MATS = {
    "hull": material("LF_BoatHull", COLORS["sand"], 0.84),
    "deck": material("LF_BoatDeck", COLORS["wood_light"], 0.9),
    "main_sail": material("LF_BoatMainSail", COLORS["coral"], 0.96),
    "jib": material("LF_BoatJib", COLORS["sand"], 0.96),
    "stripe": material("LF_BoatStripe", COLORS["orange"], 0.86),
    "flag": material("LF_BoatFlag", COLORS["orange"], 0.9),
    "wood": material("LF_BoatWood", COLORS["wood"], 0.82),
    "wood_dark": material("LF_BoatWoodDark", COLORS["rust_deep"], 0.88),
    "rope": material("LF_BoatRope", COLORS["rope"], 1.0),
    "metal": material("LF_BoatMetal", COLORS["rust"], 0.78),
    # 船上アクセントは帆色とは独立した KeelMira のコーラルで固定する。
    "cockpit": material("LF_BoatCockpit", COLORS["coral"], 0.9),
    "glow": material(
        "LF_BoatLanternGlow",
        COLORS["ember"],
        0.38,
        COLORS["ember"],
        4.5,
    ),
}


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
root = bpy.data.objects.new("Landfall_Boat", None)
bpy.context.collection.objects.link(root)
# Model coordinates intentionally match Three.js/SceneKit: X=forward, Y=up, Z=beam.
# Rotate that authored Y-up space into Blender's Z-up space for editing/rendering.
root.rotation_euler.x = math.pi / 2
asset_objects: list[bpy.types.Object] = []

# Runtime attachment point. The navigator is parented here instead of being
# positioned beside the imported boat with engine-specific world coordinates.
navigator_anchor = bpy.data.objects.new("Navigator_Anchor", None)
navigator_anchor.location = (0.74, 0.68, 0.18)
navigator_anchor.parent = root
bpy.context.collection.objects.link(navigator_anchor)


def keep(obj: bpy.types.Object, name: str, mat: bpy.types.Material) -> bpy.types.Object:
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    obj.data.materials.append(mat)
    obj.parent = root
    asset_objects.append(obj)
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
    obj = bpy.data.objects.new(name, mesh)
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
    bevel: float = 0,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = keep(bpy.context.object, name, mat)
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        modifier = obj.modifiers.new("Soft worn edge", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
    return obj


def cylinder(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    mat: bpy.types.Material,
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
    return keep(bpy.context.object, name, mat)


def cone(
    name: str,
    location: tuple[float, float, float],
    radius1: float,
    radius2: float,
    depth: float,
    mat: bpy.types.Material,
    vertices: int = 8,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius1,
        radius2=radius2,
        depth=depth,
        location=location,
    )
    return keep(bpy.context.object, name, mat)


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
    obj = cylinder(name, tuple((a + b) / 2), radius, delta.length, mat, vertices)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Z", "Y")
    return obj


def rope_curve(
    name: str,
    points: list[tuple[float, float, float]],
    radius: float = 0.012,
    mat: bpy.types.Material | None = None,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(f"{name}_Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = radius
    curve.bevel_resolution = 0
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for handle, coordinate in zip(spline.bezier_points, points):
        handle.co = coordinate
        handle.handle_left_type = "AUTO"
        handle.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat or MATS["rope"])
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


# Hull sections run stern (-X) to the high, narrow bow (+X).
sections = [
    (-1.08, 0.43, 0.31, 0.04),
    (-0.78, 0.45, 0.47, -0.16),
    (-0.18, 0.48, 0.57, -0.34),
    (0.45, 0.52, 0.53, -0.30),
    (0.92, 0.59, 0.39, -0.08),
    (1.22, 0.72, 0.22, 0.20),
    (1.40, 0.82, 0.035, 0.48),
]
hull_vertices: list[tuple[float, float, float]] = []
for x, top, width, keel in sections:
    hull_vertices.extend(
        [
            (x, top, -width),
            (x, keel + 0.13, -width * 0.72),
            (x, keel, 0),
            (x, keel + 0.13, width * 0.72),
            (x, top, width),
        ]
    )
hull_faces: list[tuple[int, ...]] = []
for section in range(len(sections) - 1):
    a = section * 5
    b = (section + 1) * 5
    for strip in range(4):
        hull_faces.append((a + strip, b + strip, b + strip + 1, a + strip + 1))
hull_faces += [(0, 1, 2, 3, 4), tuple(range((len(sections) - 1) * 5, len(sections) * 5))]
mesh_object("Hull", hull_vertices, hull_faces, MATS["hull"])

# Deck follows the upper hull profile but leaves a dark cockpit recess above it.
deck_vertices: list[tuple[float, float, float]] = []
for x, top, width, _ in sections[:-1]:
    deck_vertices += [(x, top + 0.015, -width * 0.91), (x, top + 0.015, width * 0.91)]
deck_faces = [
    (i * 2, (i + 1) * 2, (i + 1) * 2 + 1, i * 2 + 1)
    for i in range(len(sections) - 2)
]
mesh_object("Deck_Shell", deck_vertices, deck_faces, MATS["deck"])

# Curved gunwales give the hull a deliberate silhouette from all camera angles.
port_rail = [(x, top + 0.035, -width) for x, top, width, _ in sections]
starboard_rail = [(x, top + 0.035, width) for x, top, width, _ in sections]
rope_curve("Gunwale_Port", port_rail, 0.035, MATS["wood"])
rope_curve("Gunwale_Starboard", starboard_rail, 0.035, MATS["wood"])

# Existing return-orange stripe, now following both hull sides rather than a torus.
port_stripe = [
    (x, keel + (top - keel) * 0.48, -width * 0.96 - 0.008)
    for x, top, width, keel in sections[1:-1]
]
starboard_stripe = [
    (x, keel + (top - keel) * 0.48, width * 0.96 + 0.008)
    for x, top, width, keel in sections[1:-1]
]
rope_curve("Hull_Stripe_Port", port_stripe, 0.025, MATS["stripe"])
rope_curve("Hull_Stripe_Starboard", starboard_stripe, 0.025, MATS["stripe"])

# Cockpit, benches, rudder, and a small raised foredeck.
cube("Cockpit_Recess", (-0.43, 0.535, 0), (0.39, 0.025, 0.29), MATS["cockpit"], bevel=0.04)
for x in (-0.76, -0.30):
    cube(f"Cockpit_Bench_{x}", (x, 0.59, 0), (0.055, 0.035, 0.35), MATS["wood"], bevel=0.018)
cube("Foredeck", (0.74, 0.60, 0), (0.22, 0.055, 0.34), MATS["deck"], bevel=0.035)
beam("Tiller", (-0.98, 0.64, 0), (-0.54, 0.69, 0.08), 0.026, MATS["wood"], 7)
cube("Rudder", (-1.10, 0.12, 0), (0.18, 0.28, 0.035), MATS["wood_dark"], rotation=(0, 0, -0.12), bevel=0.025)

# Mast, boom, bowsprit, and metal collars.
beam("Mast", (0.08, 0.48, 0), (0.08, 2.58, 0), 0.036, MATS["wood"], 8)
beam("Boom", (0.04, 0.78, 0), (-0.95, 0.72, 0.10), 0.025, MATS["wood"], 7)
beam("Bowsprit", (0.91, 0.66, 0), (1.62, 0.91, 0), 0.026, MATS["wood"], 7)
for y in (0.54, 0.72):
    cylinder(f"Mast_Collar_{y}", (0.08, y, 0), 0.058, 0.035, MATS["metal"], 8)


def sail_mesh(
    name: str,
    anchor_x: float,
    base_y: float,
    height: float,
    width: float,
    direction: float,
    bulge: float,
    mat: bpy.types.Material,
    rows: int = 9,
    cols: int = 7,
) -> bpy.types.Object:
    vertices: list[tuple[float, float, float]] = []
    for row in range(rows + 1):
        v = row / rows
        row_width = width * (1 - v) * (1 + 0.12 * math.sin(math.pi * v))
        for col in range(cols + 1):
            u = col / cols
            x = anchor_x + direction * u * row_width
            y = base_y + v * height
            z = bulge * math.sin(math.pi * u) * math.sin(math.pi * min(v * 0.92 + 0.05, 1))
            vertices.append((x, y, z))
    faces: list[tuple[int, ...]] = []
    for row in range(rows):
        for col in range(cols):
            a = row * (cols + 1) + col
            b = a + 1
            d = a + cols + 1
            faces += [(a, d, b), (b, d, d + 1)]
    return mesh_object(name, vertices, faces, mat)


sail_mesh("Main_Sail", 0.03, 0.80, 1.70, 1.03, -1, 0.13, MATS["main_sail"])
sail_mesh("Jib", 0.16, 0.82, 1.54, 1.02, 1, 0.09, MATS["jib"], rows=8, cols=6)

# Rigging outlines the sail plan even when the sails are darkened by fog.
rope_curve("Main_Luff", [(0.04, 0.78, 0), (0.08, 2.52, 0)], 0.011)
rope_curve("Main_Leech", [(-1.00, 0.80, 0.01), (-0.63, 1.48, 0.08), (0.08, 2.52, 0)], 0.011)
rope_curve("Jib_Stay", [(0.08, 2.48, 0), (1.57, 0.91, 0)], 0.012)
rope_curve("Backstay", [(0.08, 2.48, 0), (-1.04, 0.50, -0.28)], 0.011)

# Pennant: current return-orange color, with a tiny split at the fly for motion.
flag_vertices = [
    (0.08, 2.51, 0),
    (0.08, 2.73, 0),
    (-0.50, 2.64, 0.015),
    (-0.32, 2.58, 0.02),
]
flag_faces = [(0, 1, 2, 3)]
mesh_object("Pennant", flag_vertices, flag_faces, MATS["flag"])

# A restrained stern lantern gives the model one warm focal point without replacing
# the HarborWorld's "today's light" gameplay lantern.
beam("Stern_Lantern_Post", (-0.92, 0.45, -0.28), (-0.92, 0.94, -0.28), 0.018, MATS["wood"], 6)
cylinder("Stern_Lantern_Base", (-0.92, 0.97, -0.28), 0.07, 0.035, MATS["metal"], 6)
cylinder("Stern_Lantern_Glow", (-0.92, 1.06, -0.28), 0.045, 0.14, MATS["glow"], 8)
cone("Stern_Lantern_Roof", (-0.92, 1.17, -0.28), 0.09, 0.018, 0.09, MATS["metal"], 6)

# Preview-only sea, ripples, camera, and moonlit studio lights.
sea_mat = material("PREVIEW_Sea", COLORS["sea"], 0.74)
bpy.ops.mesh.primitive_plane_add(size=24, location=(0, 0, -0.37))
sea = bpy.context.object
sea.name = "PREVIEW_Sea"
sea.data.materials.append(sea_mat)
for index, major in enumerate((1.1, 1.5, 1.95)):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major,
        minor_radius=0.012,
        major_segments=48,
        minor_segments=3,
        location=(0, 0, -0.34 + index * 0.002),
    )
    ripple = bpy.context.object
    ripple.name = f"PREVIEW_Ripple_{index + 1}"
    ripple.data.materials.append(material(f"PREVIEW_RippleMat_{index + 1}", COLORS["ripple"], 0.8))

world = bpy.context.scene.world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba(COLORS["night"])
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.19

bpy.ops.object.light_add(type="AREA", location=(-4.5, -5.2, 7.0))
key = bpy.context.object
key.name = "PREVIEW_MoonKey"
key.data.energy = 760
key.data.size = 5.0
key.data.color = rgba(COLORS["sand"])[:3]
look_at(key, (0.05, 0, 0.85))

bpy.ops.object.light_add(type="AREA", location=(4.8, 3.5, 3.2))
fill = bpy.context.object
fill.name = "PREVIEW_SeaFill"
fill.data.energy = 460
fill.data.size = 4.5
fill.data.color = rgba(COLORS["ripple"])[:3]
look_at(fill, (0.1, 0, 0.75))

bpy.ops.object.light_add(type="POINT", location=(-0.92, -0.28, 1.06))
lamp = bpy.context.object
lamp.name = "PREVIEW_LanternLight"
lamp.data.energy = 32
lamp.data.color = rgba(COLORS["ember"])[:3]
lamp.data.shadow_soft_size = 0.35

bpy.ops.object.camera_add(location=(5.2, -8.0, 3.75))
camera = bpy.context.object
camera.name = "PREVIEW_Camera"
camera.data.lens = 58
look_at(camera, (0.1, 0, 0.95))

scene = bpy.context.scene
scene.camera = camera
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1400
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.filepath = str(RENDER_PATH)
scene.view_settings.look = "AgX - Medium High Contrast"

BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
USDZ_PATH.parent.mkdir(parents=True, exist_ok=True)
RENDER_PATH.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

# Apply bevels and merge delivery geometry by stable material name.
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
    else:
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        bpy.ops.object.join()
        merged = bpy.context.object
    merged.name = material_name
    merged.data.name = f"{material_name}_Mesh"
    export_objects.append(merged)

bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
navigator_anchor.select_set(True)
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
# SceneKit receives the same authored X-forward/Y-up coordinate system as Web.
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
bpy.ops.render.render(write_still=True)

print(f"BLEND={BLEND_PATH}")
print(f"GLB={GLB_PATH}")
print(f"USDZ={USDZ_PATH}")
print(f"RENDER={RENDER_PATH}")
