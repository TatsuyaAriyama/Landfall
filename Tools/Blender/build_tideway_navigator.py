"""Build the original Tideway Navigator character for KeelMira.

The file is deliberately deterministic and self-contained. Running it with
Blender creates an editable source file, a rigged GLB for the web build, an
animated USDZ for SceneKit, and production review renders. The visual design
is an original KeelMira character: a swept tide-wave bob, a softly tailored
harbor jacket, a short single-sail shoulder scarf, compass pouch, and a
belt-clipped navigation light.

Run from the repository root:

    /Applications/Blender.app/Contents/MacOS/Blender \
        --background --factory-startup \
        --python Tools/Blender/build_tideway_navigator.py

Coordinate contract:
* Blender +Z is up and -Y is the character's forward direction.
* The armature origin is the ground contact point.
* Locomotion clips are in-place; SceneKit owns world translation/collision.
"""

from __future__ import annotations

import math
import os
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/tideway_navigator.blend"
# This character is an archived prototype and must never be emitted into the
# app bundle or the public web model directory. Artist source and review images
# stay editable, while every runtime export is isolated below Assets3D/archive.
ARCHIVE_DIR = ROOT / "Assets3D/archive/tideway_navigator"
GLB_PATH = ARCHIVE_DIR / "tideway_navigator.glb"
USDZ_PATH = ARCHIVE_DIR / "tideway_navigator.usdz"
PREVIEW_DIR = ROOT / "marketing/3d"
PREVIEW_PATHS = {
    "idle": PREVIEW_DIR / "tideway-navigator-idle.png",
    "idle_b": PREVIEW_DIR / "tideway-navigator-idle-b.png",
    "front": PREVIEW_DIR / "tideway-navigator-front.png",
    "side": PREVIEW_DIR / "tideway-navigator-side.png",
    "back": PREVIEW_DIR / "tideway-navigator-back.png",
    "walk": PREVIEW_DIR / "tideway-navigator-walk.png",
    "run": PREVIEW_DIR / "tideway-navigator-run.png",
    "start": PREVIEW_DIR / "tideway-navigator-start.png",
    "stop": PREVIEW_DIR / "tideway-navigator-stop.png",
    "turn_l": PREVIEW_DIR / "tideway-navigator-turn-left.png",
    "turn_r": PREVIEW_DIR / "tideway-navigator-turn-right.png",
    "wave": PREVIEW_DIR / "tideway-navigator-wave.png",
    "sit": PREVIEW_DIR / "tideway-navigator-sit.png",
    "stand": PREVIEW_DIR / "tideway-navigator-stand.png",
    "inspect": PREVIEW_DIR / "tideway-navigator-inspect-compass.png",
}

FPS = 24
TRIANGLE_BUDGET = 20_000

PALETTE = {
    "skin": "#B98069",
    "skin_light": "#D9A98E",
    "hair": "#21454D",
    "hair_light": "#4C777A",
    "cream": "#EFE5CC",
    "navy": "#213A55",
    "seaglass": "#5E8F8D",
    "coral": "#D97860",
    "leather": "#6B412F",
    "brass": "#D4AE61",
    "glow": "#FFD889",
}


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    srgb = tuple(int(value[index : index + 2], 16) / 255 for index in (0, 2, 4))
    linear = tuple(
        channel / 12.92
        if channel <= 0.04045
        else ((channel + 0.055) / 1.055) ** 2.4
        for channel in srgb
    )
    return linear + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float,
    metallic: float = 0.0,
    emission: str | None = None,
    emission_strength: float = 0.0,
    sheen: float = 0.0,
    coat: float = 0.0,
    coat_roughness: float = 0.25,
    specular: float = 0.5,
) -> bpy.types.Material:
    result = bpy.data.materials.new(name)
    result.diffuse_color = rgba(color)
    result.use_nodes = True
    bsdf = next(node for node in result.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = rgba(color)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if bsdf.inputs.get("Sheen Weight"):
        bsdf.inputs["Sheen Weight"].default_value = sheen
    if bsdf.inputs.get("Coat Weight"):
        bsdf.inputs["Coat Weight"].default_value = coat
    if bsdf.inputs.get("Coat Roughness"):
        bsdf.inputs["Coat Roughness"].default_value = coat_roughness
    if bsdf.inputs.get("Specular IOR Level"):
        bsdf.inputs["Specular IOR Level"].default_value = specular
    if emission:
        bsdf.inputs["Emission Color"].default_value = rgba(emission)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return result


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.armatures,
        bpy.data.actions,
        bpy.data.materials,
    ):
        for block in list(collection):
            if block.users == 0:
                collection.remove(block)


reset_scene()

MATS = {
    "skin": material("Tideway_Skin", PALETTE["skin"], 0.78, specular=0.34),
    "skin_light": material("Tideway_SkinLight", PALETTE["skin_light"], 0.74, specular=0.36),
    "hair": material("Tideway_DeepTealHair", PALETTE["hair"], 0.62, sheen=0.20, specular=0.34),
    "hair_light": material("Tideway_SeaGlassHair", PALETTE["hair_light"], 0.58, sheen=0.22, specular=0.36),
    "cream": material("Tideway_UnbleachedKnit", PALETTE["cream"], 0.93, sheen=0.22, specular=0.24),
    "navy": material("Tideway_NightIndigo", PALETTE["navy"], 0.79, sheen=0.18, specular=0.29),
    "seaglass": material("Tideway_HarborSeaGlass", PALETTE["seaglass"], 0.83, sheen=0.24, specular=0.28),
    "coral": material("Tideway_HarborCoral", PALETTE["coral"], 0.74, sheen=0.18, specular=0.33),
    "leather": material("Tideway_WeatheredLeather", PALETTE["leather"], 0.66, coat=0.08, coat_roughness=0.48, specular=0.38),
    "brass": material("Tideway_CompassBrass", PALETTE["brass"], 0.50, metallic=0.68, coat=0.05, coat_roughness=0.45),
    "glow": material(
        "Tideway_NavigationGlow",
        PALETTE["glow"],
        0.42,
        emission=PALETTE["glow"],
        emission_strength=0.9,
    ),
}

asset_objects: list[bpy.types.Object] = []


def smooth(obj: bpy.types.Object) -> bpy.types.Object:
    if obj.type == "MESH":
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    return obj


def keep(obj: bpy.types.Object, name: str, mat: bpy.types.Material) -> bpy.types.Object:
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    obj.data.materials.append(mat)
    asset_objects.append(obj)
    return obj


def bevel(obj: bpy.types.Object, width: float, segments: int = 2) -> bpy.types.Object:
    modifier = obj.modifiers.new("Tideway soft edge", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    return obj


def uv_sphere(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    segments: int = 20,
    rings: int = 14,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        radius=1,
        location=location,
    )
    obj = keep(bpy.context.object, name, mat)
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return smooth(obj)


def ico_sphere(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    subdivisions: int = 2,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1, location=location)
    obj = keep(bpy.context.object, name, mat)
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return smooth(obj)


def cylinder(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    mat: bpy.types.Material,
    vertices: int = 14,
    rotation: tuple[float, float, float] = (0, 0, 0),
    scale: tuple[float, float, float] = (1, 1, 1),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = keep(bpy.context.object, name, mat)
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return smooth(obj)


def cone(
    name: str,
    location: tuple[float, float, float],
    top: float,
    bottom: float,
    depth: float,
    mat: bpy.types.Material,
    vertices: int = 14,
    rotation: tuple[float, float, float] = (0, 0, 0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=bottom,
        radius2=top,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    return smooth(keep(bpy.context.object, name, mat))


def torus(
    name: str,
    location: tuple[float, float, float],
    major_radius: float,
    minor_radius: float,
    mat: bpy.types.Material,
    major_segments: int = 18,
    minor_segments: int = 8,
    rotation: tuple[float, float, float] = (0, 0, 0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=major_segments,
        minor_segments=minor_segments,
        location=location,
        rotation=rotation,
    )
    return smooth(keep(bpy.context.object, name, mat))


def rounded_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    mat: bpy.types.Material,
    edge: float = 0.025,
    rotation: tuple[float, float, float] = (0, 0, 0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1, location=location, rotation=rotation)
    obj = keep(bpy.context.object, name, mat)
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    # Bevel must stay below half the thinnest dimension. Larger values collapse
    # opposite faces and create zero-area triangles after modifier application.
    safe_edge = min(edge, min(dimensions) * 0.45)
    bevel(obj, safe_edge, 3)
    return obj


def curve_tube(
    name: str,
    points: list[tuple[float, float, float]],
    radius: float,
    mat: bpy.types.Material,
    resolution: int = 2,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(f"{name}_Curve", "CURVE")
    curve.dimensions = "3D"
    curve.use_fill_caps = True
    curve.resolution_u = resolution
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    curve.resolution_u = 2
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for bezier, point in zip(spline.bezier_points, points):
        bezier.co = point
        bezier.handle_left_type = "AUTO"
        bezier.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    curve.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    asset_objects.append(obj)
    return smooth(obj)


def prism_xz(
    name: str,
    points: list[tuple[float, float]],
    y: float,
    depth: float,
    mat: bpy.types.Material,
    edge: float = 0.008,
) -> bpy.types.Object:
    vertices = [(x, y - depth / 2, z) for x, z in points]
    vertices += [(x, y + depth / 2, z) for x, z in points]
    count = len(points)
    faces: list[tuple[int, ...]] = [tuple(range(count)), tuple(reversed(range(count, count * 2)))]
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, count + nxt, count + index))
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(mat)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    asset_objects.append(obj)
    bevel(obj, edge, 2)
    return obj


def ribbon(
    name: str,
    centers: list[tuple[float, float, float]],
    widths: list[float],
    mat: bpy.types.Material,
    thickness: float = 0.009,
) -> bpy.types.Object:
    """Broad vertical ribbon used for the character's graphic wave-cut hair."""
    vertices: list[tuple[float, float, float]] = []
    for (x, y, z), width in zip(centers, widths):
        vertices.extend([(x - width, y, z), (x + width, y, z)])
    faces = [
        (row * 2, row * 2 + 1, row * 2 + 3, row * 2 + 2)
        for row in range(len(centers) - 1)
    ]
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(mat)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    asset_objects.append(obj)
    solidify = obj.modifiers.new("Tideway hair thickness", "SOLIDIFY")
    solidify.thickness = thickness
    bevel(obj, 0.003, 2)
    return smooth(obj)


def mesh_object(
    name: str,
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    mat: bpy.types.Material,
) -> bpy.types.Object:
    """Create one smooth authored mesh without primitive-object seams."""

    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(mat)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    asset_objects.append(obj)
    return smooth(obj)


def loft_path(
    name: str,
    centers: list[tuple[float, float, float]],
    widths: list[float],
    depths: list[float],
    mat: bpy.types.Material,
    ring_segments: int = 12,
    subdivisions: int = 1,
) -> tuple[bpy.types.Object, list[float]]:
    """Loft rounded cross-sections along a 3D path.

    This is used for limbs and hair. Unlike stacked spheres, the resulting
    topology is continuous through shoulders, elbows, knees and tapered tips,
    so gradient skinning bends a single silhouette rather than separate toys.
    """

    if not (len(centers) == len(widths) == len(depths)):
        raise ValueError(f"Loft arrays differ for {name}")
    path = [Vector(point) for point in centers]
    width_values = list(widths)
    depth_values = list(depths)
    if subdivisions > 1:
        source_path = path
        source_widths = width_values
        source_depths = depth_values
        path = []
        width_values = []
        depth_values = []

        def catmull(a, b, c, d, t):
            return 0.5 * (
                2 * b
                + (-a + c) * t
                + (2 * a - 5 * b + 4 * c - d) * t * t
                + (-a + 3 * b - 3 * c + d) * t * t * t
            )

        for index in range(len(source_path) - 1):
            a = source_path[max(0, index - 1)]
            b = source_path[index]
            c = source_path[index + 1]
            d = source_path[min(len(source_path) - 1, index + 2)]
            for sample in range(subdivisions):
                t = sample / subdivisions
                path.append(catmull(a, b, c, d, t))
                width_values.append(float(catmull(source_widths[max(0, index - 1)], source_widths[index], source_widths[index + 1], source_widths[min(len(source_widths) - 1, index + 2)], t)))
                depth_values.append(float(catmull(source_depths[max(0, index - 1)], source_depths[index], source_depths[index + 1], source_depths[min(len(source_depths) - 1, index + 2)], t)))
        path.append(source_path[-1])
        width_values.append(source_widths[-1])
        depth_values.append(source_depths[-1])
    vertices: list[tuple[float, float, float]] = []
    values: list[float] = []
    for index, (center, width, depth) in enumerate(zip(path, width_values, depth_values)):
        before = path[max(0, index - 1)]
        after = path[min(len(path) - 1, index + 1)]
        tangent = (after - before).normalized()
        reference = Vector((0, 1, 0))
        if abs(tangent.dot(reference)) > 0.94:
            reference = Vector((1, 0, 0))
        width_axis = reference.cross(tangent).normalized()
        depth_axis = tangent.cross(width_axis).normalized()
        value = index / (len(path) - 1)
        for segment in range(ring_segments):
            angle = segment * math.tau / ring_segments
            point = center + width_axis * (math.cos(angle) * width) + depth_axis * (math.sin(angle) * depth)
            vertices.append(tuple(point))
            values.append(value)
    faces: list[tuple[int, ...]] = []
    for ring in range(len(path) - 1):
        for segment in range(ring_segments):
            nxt = (segment + 1) % ring_segments
            a = ring * ring_segments + segment
            b = ring * ring_segments + nxt
            c = (ring + 1) * ring_segments + nxt
            d = (ring + 1) * ring_segments + segment
            faces.append((a, b, c, d))
    faces.append(tuple(reversed(range(ring_segments))))
    last = (len(path) - 1) * ring_segments
    faces.append(tuple(last + segment for segment in range(ring_segments)))
    return mesh_object(name, vertices, faces, mat), values


def sculpted_head(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    segments: int = 28,
    rings: int = 18,
) -> bpy.types.Object:
    """Soft pear-shaped face with cheek fullness, a narrower jaw and chin."""

    cx, cy, cz = location
    rx, ry, rz = scale
    vertices: list[tuple[float, float, float]] = [(cx, cy, cz - rz)]
    for ring in range(1, rings):
        latitude = -math.pi / 2 + math.pi * ring / rings
        vertical = math.sin(latitude)
        radial = math.cos(latitude)
        # Full cheeks at the lower-middle plane and a gently tapered chin.
        cheek = 1.0 + 0.075 * math.exp(-((vertical + 0.18) / 0.34) ** 2)
        jaw = 1.0 - 0.18 * max(0.0, -vertical - 0.42) / 0.58
        forehead = 1.0 - 0.035 * max(0.0, vertical - 0.55) / 0.45
        width_scale = cheek * jaw * forehead
        for segment in range(segments):
            angle = segment * math.tau / segments
            x = cx + math.cos(angle) * radial * rx * width_scale
            y_radius = ry * (1.0 + 0.035 * max(0.0, -vertical))
            y = cy + math.sin(angle) * radial * y_radius
            # The chin moves very slightly forward, avoiding a spherical mask.
            if math.sin(angle) < 0:
                y -= 0.012 * max(0.0, -vertical)
            z = cz + vertical * rz
            vertices.append((x, y, z))
    vertices.append((cx, cy, cz + rz))
    faces: list[tuple[int, ...]] = []
    # Single-vertex pole fans avoid the zero-area triangles produced by a UV
    # sphere's repeated coincident pole ring.
    for segment in range(segments):
        nxt = (segment + 1) % segments
        faces.append((0, 1 + nxt, 1 + segment))
    ring_count = rings - 1
    for ring in range(ring_count - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            a = 1 + ring * segments + segment
            b = 1 + ring * segments + nxt
            c = 1 + (ring + 1) * segments + nxt
            d = 1 + (ring + 1) * segments + segment
            faces.append((a, b, c, d))
    top = len(vertices) - 1
    last = 1 + (ring_count - 1) * segments
    for segment in range(segments):
        nxt = (segment + 1) % segments
        faces.append((last + segment, last + nxt, top))
    return mesh_object(name, vertices, faces, mat)


def rounded_boot(
    name: str,
    x: float,
    mat: bpy.types.Material,
    side: str,
) -> bpy.types.Object:
    """One-piece deck boot with a short heel, soft instep and lifted toe."""

    y_values = (0.050, 0.012, -0.064, -0.137, -0.198, -0.225)
    z_values = (0.150, 0.120, 0.090, 0.082, 0.092, 0.100)
    widths = (0.058, 0.068, 0.074, 0.069, 0.041, 0.008)
    heights = (0.095, 0.105, 0.080, 0.068, 0.040, 0.010)
    segments = 12
    vertices: list[tuple[float, float, float]] = []
    for y, z, width, height in zip(y_values, z_values, widths, heights):
        for segment in range(segments):
            angle = segment * math.tau / segments
            point_z = max(0.012, z + math.sin(angle) * height)
            vertices.append((x + math.cos(angle) * width, y, point_z))
    faces: list[tuple[int, ...]] = []
    for ring in range(len(y_values) - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            a = ring * segments + segment
            b = ring * segments + nxt
            c = (ring + 1) * segments + nxt
            d = (ring + 1) * segments + segment
            faces.append((a, b, c, d))
    faces.append(tuple(reversed(range(segments))))
    last = (len(y_values) - 1) * segments
    faces.append(tuple(last + segment for segment in range(segments)))
    return mesh_object(name, vertices, faces, mat)


def sail_panel(
    name: str,
    mat: bpy.types.Material,
    y: float,
    y_offset: float = 0,
) -> tuple[bpy.types.Object, list[tuple[float, float]]]:
    rows = 8
    columns = 8
    vertices: list[tuple[float, float, float]] = []
    cloth_values: list[tuple[float, float]] = []
    faces: list[tuple[int, ...]] = []
    for row in range(rows):
        v = row / (rows - 1)
        z = 1.185 - v * 0.330
        center = 0.045 + v * 0.070
        # A compact shoulder sail, not a hero cloak. It opens outward for a
        # readable asymmetry but ends above the knees so the run stays free.
        half_width = (0.055 + math.sqrt(v) * 0.185) * (1.0 - 0.10 * v * v)
        for column in range(columns):
            u = column / (columns - 1)
            across = u * 2 - 1
            x = center + across * half_width
            lower_scallop = math.sin(u * math.pi) * 0.022 * v
            # Double curvature and diagonal fold phase keep the cloth from
            # reading as one extruded triangle.
            billow = math.sin(u * math.pi) * (0.012 + 0.032 * v)
            folds = math.sin(u * math.pi * 2.5 + v * 1.7) * 0.006 * (0.25 + v)
            edge_curl = across * across * 0.008 * v
            trailing = max(0.0, across) * 0.085 * v
            vertices.append((x, y + y_offset + billow + folds - edge_curl + trailing, z - lower_scallop))
            cloth_values.append((v, u))
    for row in range(rows - 1):
        for column in range(columns - 1):
            a = row * columns + column
            b = a + 1
            d = a + columns
            c = d + 1
            faces.append((a, b, c, d))
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(mat)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    asset_objects.append(obj)
    solidify = obj.modifiers.new("Tideway sail thickness", "SOLIDIFY")
    solidify.thickness = 0.0015
    bevel(obj, 0.002, 2)
    return smooth(obj), cloth_values


# MARK: - Armature


def build_armature() -> bpy.types.Object:
    data = bpy.data.armatures.new("TidewayNavigator_Skeleton")
    armature = bpy.data.objects.new("TidewayNavigator_Rig", data)
    bpy.context.collection.objects.link(armature)
    armature.show_in_front = True
    asset_objects.append(armature)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    def bone(
        name: str,
        head: tuple[float, float, float],
        tail: tuple[float, float, float],
        parent: str | None = None,
        connected: bool = False,
        deform: bool = True,
    ) -> None:
        result = data.edit_bones.new(name)
        result.head = head
        result.tail = tail
        result.use_deform = deform
        if parent:
            result.parent = data.edit_bones[parent]
            result.use_connect = connected

    bone("root", (0, 0, 0), (0, 0, 0.10), deform=False)
    bone("contact", (0, 0, 0.02), (0, 0, 0.16), "root", deform=False)
    bone("core", (0, 0, 0.72), (0, 0, 0.93), "contact")
    bone("spine", (0, 0, 0.91), (0, 0, 1.10), "core", True)
    bone("chest", (0, 0, 1.08), (0, 0, 1.23), "spine", True)
    bone("neck", (0, 0, 1.20), (0, 0, 1.30), "chest", True)
    bone("head", (0, 0, 1.28), (0, 0, 1.60), "neck", True)

    for side, x in (("L", 0.18), ("R", -0.18)):
        bone(f"clavicle{side}", (0, 0, 1.17), (x, 0, 1.16), "chest")
        bone(f"arm{side}", (x, 0, 1.16), (x * 1.42, 0, 0.93), f"clavicle{side}")
        bone(
            f"forearm{side}",
            (x * 1.42, 0, 0.93),
            (x * 1.55, -0.01, 0.73),
            f"arm{side}",
            True,
        )
        bone(
            f"hand{side}",
            (x * 1.55, -0.01, 0.73),
            (x * 1.57, -0.02, 0.62),
            f"forearm{side}",
            True,
        )

    for side, x in (("L", 0.115), ("R", -0.115)):
        bone(f"leg{side}", (x, 0, 0.80), (x, 0, 0.52), "core")
        bone(f"knee{side}", (x, 0, 0.52), (x, 0, 0.27), f"leg{side}", True)
        bone(f"ankle{side}", (x, 0, 0.27), (x, -0.01, 0.14), f"knee{side}", True)
        bone(f"foot{side}", (x, -0.01, 0.14), (x, -0.17, 0.08), f"ankle{side}")
        bone(f"toe{side}", (x, -0.12, 0.08), (x, -0.24, 0.07), f"foot{side}")

    bone("cape", (0.03, 0.10, 1.18), (0.07, 0.15, 1.04), "chest")
    bone("capeMid", (0.07, 0.15, 1.04), (0.12, 0.18, 0.88), "cape", True)
    bone("capeTip", (0.12, 0.18, 0.88), (0.17, 0.20, 0.72), "capeMid", True)
    bone("capeOuter", (0.04, 0.14, 1.15), (0.31, 0.20, 0.78), "cape")

    bone("hairL1", (0.13, 0.02, 1.57), (0.24, 0.02, 1.38), "head")
    bone("hairL2", (0.24, 0.02, 1.38), (0.27, 0.04, 1.20), "hairL1")
    bone("hairR1", (-0.13, 0.02, 1.57), (-0.24, 0.02, 1.40), "head")
    bone("hairR2", (-0.24, 0.02, 1.40), (-0.22, 0.04, 1.25), "hairR1")
    bone("hairBack", (0, 0.10, 1.55), (0, 0.16, 1.24), "head")
    bone("pouch", (0.15, -0.02, 0.92), (0.28, -0.08, 0.74), "core")
    bone("lantern", (-0.285, 0.025, 0.88), (-0.335, 0.035, 0.68), "core")

    # Small facial controls are bones rather than shape keys because the same
    # rig must animate reliably through GLB and SceneKit's USD skeleton path.
    for side, x in (("L", 0.072), ("R", -0.072)):
        bone(f"eye{side}", (x, -0.205, 1.47), (x, -0.205, 1.495), "head")
        bone(f"lid{side}", (x, -0.215, 1.505), (x, -0.215, 1.530), "head")
        bone(f"brow{side}", (x, -0.210, 1.535), (x, -0.210, 1.558), "head")
        bone(f"mouth{side}", (x * 0.44, -0.215, 1.390), (x * 0.44, -0.215, 1.412), "head")

    bpy.ops.object.mode_set(mode="POSE")
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "XYZ"
    bpy.ops.object.mode_set(mode="OBJECT")

    armature["asset_role"] = "playable_character"
    armature["design"] = "Tideway Navigator / 潮路の案内人"
    armature["version"] = 3
    armature["original_design"] = True
    armature["front_axis_blender"] = "-Y"
    armature["front_axis_runtime"] = "+Z"
    armature["locomotion"] = "in_place"
    armature["runtime_pivots"] = (
        "root,contact,core,head,armL,armR,forearmL,forearmR,"
        "legL,legR,kneeL,kneeR,cape,lantern,eyeL,eyeR,lidL,lidR"
    )
    return armature


ARMATURE = build_armature()


def bind_rigid(obj: bpy.types.Object, bone_name: str) -> bpy.types.Object:
    if obj.type != "MESH":
        return obj
    group = obj.vertex_groups.new(name=bone_name)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    modifier = obj.modifiers.new("Tideway armature", "ARMATURE")
    modifier.object = ARMATURE
    obj.parent = ARMATURE
    obj.matrix_parent_inverse = ARMATURE.matrix_world.inverted()
    return obj


def bind_gradient(
    obj: bpy.types.Object,
    values: list[float],
    ranges: list[tuple[str, float]],
) -> bpy.types.Object:
    groups = {name: obj.vertex_groups.new(name=name) for name, _ in ranges}
    centers = [center for _, center in ranges]
    for vertex, value in enumerate(values):
        distances = [abs(value - center) for center in centers]
        nearest = sorted(range(len(distances)), key=distances.__getitem__)[:2]
        if len(nearest) == 1 or distances[nearest[0]] < 1e-6:
            weights = [(nearest[0], 1.0)]
        else:
            d0, d1 = distances[nearest[0]], distances[nearest[1]]
            total = d0 + d1
            weights = [(nearest[0], d1 / total), (nearest[1], d0 / total)]
        for index, weight in weights:
            groups[ranges[index][0]].add([vertex], weight, "REPLACE")
    modifier = obj.modifiers.new("Tideway armature", "ARMATURE")
    modifier.object = ARMATURE
    obj.parent = ARMATURE
    obj.matrix_parent_inverse = ARMATURE.matrix_world.inverted()
    return obj


def bind_spatial_gradient(
    obj: bpy.types.Object,
    ranges: list[tuple[str, float]],
) -> bpy.types.Object:
    """Blend an overlapping limb capsule along world Z in the bind pose."""

    groups = {name: obj.vertex_groups.new(name=name) for name, _ in ranges}
    centers = [center for _, center in ranges]
    for vertex in obj.data.vertices:
        value = (obj.matrix_world @ vertex.co).z
        distances = [abs(value - center) for center in centers]
        nearest = sorted(range(len(distances)), key=distances.__getitem__)[:2]
        if len(nearest) == 1 or distances[nearest[0]] < 1e-6:
            weights = [(nearest[0], 1.0)]
        else:
            d0, d1 = distances[nearest[0]], distances[nearest[1]]
            total = d0 + d1
            weights = [(nearest[0], d1 / total), (nearest[1], d0 / total)]
        for index, weight in weights:
            groups[ranges[index][0]].add([vertex.index], weight, "REPLACE")
    modifier = obj.modifiers.new("Tideway armature", "ARMATURE")
    modifier.object = ARMATURE
    obj.parent = ARMATURE
    obj.matrix_parent_inverse = ARMATURE.matrix_world.inverted()
    return obj


def bind_cape(obj: bpy.types.Object, values: list[tuple[float, float]]) -> bpy.types.Object:
    """Blend the cape vertically and let its free outer edge lag sideways.

    The two closest chain bones plus the outer-edge bone keep each vertex at a
    maximum of three influences while producing cloth twist instead of a board
    rotating around a single centre line.
    """

    vertical = (("cape", 0.08), ("capeMid", 0.52), ("capeTip", 0.94))
    groups = {name: obj.vertex_groups.new(name=name) for name, _ in vertical}
    groups["capeOuter"] = obj.vertex_groups.new(name="capeOuter")
    centers = [center for _, center in vertical]
    for vertex, (v, u) in enumerate(values):
        distances = [abs(v - center) for center in centers]
        nearest = sorted(range(len(distances)), key=distances.__getitem__)[:2]
        if distances[nearest[0]] < 1e-6:
            chain_weights = [(nearest[0], 1.0)]
        else:
            d0, d1 = distances[nearest[0]], distances[nearest[1]]
            total = d0 + d1
            chain_weights = [(nearest[0], d1 / total), (nearest[1], d0 / total)]
        outer = max(0.0, (u - 0.50) / 0.50) * v * 0.34
        for index, weight in chain_weights:
            groups[vertical[index][0]].add([vertex], weight * (1.0 - outer), "REPLACE")
        if outer > 0.0001:
            groups["capeOuter"].add([vertex], outer, "REPLACE")
    modifier = obj.modifiers.new("Tideway armature", "ARMATURE")
    modifier.object = ARMATURE
    obj.parent = ARMATURE
    obj.matrix_parent_inverse = ARMATURE.matrix_world.inverted()
    return obj


def consolidate_runtime_meshes() -> None:
    """Bake visual modifiers and merge the skinned character by material.

    SceneKit submits one draw for each mesh/material primitive. The authored
    character is intentionally assembled from many editable pieces, but keeping
    every piece as a runtime primitive would cost roughly eighty submissions.
    Baking transforms to the common armature origin also guarantees that rigid
    details such as thumbs retain their exact relationship to the mitten while
    the hand bone rotates.
    """

    meshes = [obj for obj in asset_objects if obj.type == "MESH"]
    for obj in meshes:
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = world

        # Armature deformation must remain live; bevel/solidify are authoring
        # modifiers and can be baked before meshes are combined.
        for modifier in list(obj.modifiers):
            if modifier.type == "ARMATURE":
                obj.modifiers.remove(modifier)

        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        for modifier in list(obj.modifiers):
            bpy.context.view_layer.objects.active = obj
            try:
                bpy.ops.object.modifier_apply(modifier=modifier.name)
            except RuntimeError as error:
                raise RuntimeError(f"Could not apply {modifier.name} on {obj.name}") from error
        obj.select_set(False)

    by_material: dict[bpy.types.Material, list[bpy.types.Object]] = {}
    for obj in meshes:
        if len(obj.data.materials) != 1 or obj.data.materials[0] is None:
            raise RuntimeError(f"Runtime mesh must have exactly one material: {obj.name}")
        by_material.setdefault(obj.data.materials[0], []).append(obj)

    merged: list[bpy.types.Object] = []
    for mat, members in sorted(by_material.items(), key=lambda item: item[0].name):
        bpy.ops.object.select_all(action="DESELECT")
        target = members[0]
        for obj in members:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = target
        if len(members) > 1:
            bpy.ops.object.join()
        target.name = f"TidewayMesh_{mat.name.removeprefix('Tideway_')}"
        target.data.name = f"{target.name}_Geometry"
        target["runtime_material"] = mat.name
        modifier = target.modifiers.new("Tideway armature", "ARMATURE")
        modifier.object = ARMATURE
        target.parent = ARMATURE
        target.matrix_parent_inverse = ARMATURE.matrix_world.inverted()
        merged.append(target)

    asset_objects[:] = [ARMATURE, *merged]
    ARMATURE["runtime_primitives"] = len(merged)
    ARMATURE["runtime_materials"] = ",".join(obj.data.materials[0].name for obj in merged)


# MARK: - Character geometry

# v3 proportion target is about 3.15 heads. Limbs, sleeves and boots use
# continuous loft topology, with the body narrowing at waist, knee and ankle.
for side, x in (("L", 0.108), ("R", -0.108)):
    leg, leg_values = loft_path(
        f"ContinuousTrouserLeg_{side}",
        [(x * 1.02, 0.010, 0.815), (x * 1.08, 0.006, 0.720),
         (x * 0.92, 0.000, 0.585), (x * 1.04, 0.000, 0.455),
         (x * 1.01, 0.000, 0.315), (x * 0.98, 0.000, 0.205)],
        [0.092, 0.098, 0.078, 0.082, 0.070, 0.061],
        [0.080, 0.084, 0.070, 0.072, 0.063, 0.056],
        MATS["seaglass"],
        12,
    )
    bind_gradient(
        leg,
        leg_values,
        [("core", 0.00), (f"leg{side}", 0.24), (f"knee{side}", 0.62), (f"ankle{side}", 1.00)],
    )
    boot = rounded_boot(f"OnePieceDeckBoot_{side}", x, MATS["leather"], side)
    bind_rigid(boot, f"foot{side}")
    sole = rounded_box(
        f"DeckBootSole_{side}",
        (x, -0.088, 0.008),
        (0.146, 0.242, 0.016),
        MATS["navy"],
        0.009,
    )
    bind_rigid(sole, f"foot{side}")
    boot_cuff = torus(
        f"DeckBootCuff_{side}", (x, 0.028, 0.187), 0.066, 0.011,
        MATS["coral"], 16, 6,
    )
    bind_rigid(boot_cuff, f"ankle{side}")

hips, hip_values = loft_path(
    "TailoredTrouserSeat",
    [(0, 0.010, 0.740), (0, 0.014, 0.795), (0, 0.010, 0.855), (0, 0.005, 0.895)],
    [0.145, 0.188, 0.185, 0.155],
    [0.112, 0.137, 0.132, 0.105],
    MATS["seaglass"],
    14,
)
seat_surface_group = hips.vertex_groups.new(name="sitSurface")
seat_surface_group.add(list(range(len(hips.data.vertices))), 1.0, "REPLACE")
bind_rigid(hips, "core")

# Sea-glass harbor jacket is one rounded shell. The cream knit insert creates a
# light vertical channel that remains distinct at 100 px without dark blocks.
jacket, jacket_values = loft_path(
    "HarborJacketShell",
    [(0, 0.025, 0.820), (0, 0.020, 0.900), (0, 0.012, 1.020),
     (0, 0.015, 1.125), (0, 0.010, 1.190)],
    [0.176, 0.208, 0.224, 0.205, 0.145],
    [0.112, 0.140, 0.150, 0.138, 0.100],
    MATS["seaglass"],
    14,
)
bind_gradient(jacket, jacket_values, [("core", 0.00), ("spine", 0.48), ("chest", 1.00)])
knit, knit_values = loft_path(
    "UnbleachedKnitFront",
    [(0, -0.112, 0.855), (0, -0.128, 0.930), (0, -0.138, 1.050), (0, -0.124, 1.170)],
    [0.095, 0.112, 0.110, 0.072],
    [0.010, 0.012, 0.012, 0.009],
    MATS["cream"],
    12,
)
bind_gradient(knit, knit_values, [("spine", 0.05), ("chest", 0.92)])
for index, x in enumerate((-0.052, 0, 0.052), 1):
    rib = curve_tube(
        f"FineKnitRib_{index}",
        [(x, -0.139, 0.885), (x * 0.96, -0.153, 1.025), (x * 0.82, -0.145, 1.145)],
        0.0032,
        MATS["cream"],
    )
    bind_rigid(rib, "spine")
neck = cylinder("Neck", (0, 0, 1.230), 0.058, 0.110, MATS["skin"], 16)
bind_rigid(neck, "neck")
collar = torus("RolledKnitCollar", (0, 0, 1.195), 0.068, 0.015, MATS["cream"], 20, 7)
bind_rigid(collar, "chest")
hem = curve_tube(
    "CoralJacketHem",
    [(-0.155, -0.132, 0.835), (-0.080, -0.158, 0.810),
     (0, -0.166, 0.805), (0.080, -0.158, 0.810), (0.155, -0.132, 0.835)],
    0.0055,
    MATS["coral"],
)
bind_rigid(hem, "core")

# One continuous sleeve per arm removes the shoulder/elbow capsule seams.
for side, sign in (("L", 1), ("R", -1)):
    sleeve, sleeve_values = loft_path(
        f"ContinuousHarborSleeve_{side}",
        [(sign * 0.142, 0.010, 1.120), (sign * 0.182, 0.006, 1.080),
         (sign * 0.225, 0.000, 1.000), (sign * 0.252, -0.002, 0.885),
         (sign * 0.266, -0.006, 0.760), (sign * 0.268, -0.008, 0.720)],
        [0.055, 0.064, 0.068, 0.064, 0.055, 0.050],
        [0.051, 0.059, 0.063, 0.059, 0.051, 0.047],
        MATS["seaglass"],
        12,
    )
    bind_gradient(
        sleeve,
        sleeve_values,
        [(f"clavicle{side}", 0.02), (f"arm{side}", 0.34), (f"forearm{side}", 0.76), (f"hand{side}", 1.00)],
    )
    cuff = torus(
        f"FineKnitCuff_{side}", (sign * 0.268, -0.006, 0.710), 0.046, 0.010,
        MATS["cream"], 16, 6,
    )
    bind_rigid(cuff, f"forearm{side}")
    hand = sculpted_head(
        f"SoftHand_{side}", (sign * 0.274, -0.010, 0.646),
        (0.061, 0.054, 0.072), MATS["skin_light"], 16, 10,
    )
    bind_gradient(hand, [0.80] * len(hand.data.vertices), [(f"forearm{side}", 0.70), (f"hand{side}", 0.82)])
    thumb = uv_sphere(
        f"SoftThumb_{side}",
        (sign * 0.315, -0.028, 0.650),
        (0.022, 0.022, 0.034), MATS["skin"], 12, 8,
    )
    bind_rigid(thumb, f"hand{side}")

# The shoulder sail is short enough for free arm silhouettes while preserving
# the navigation identity. Its coral lining only flashes during turns/runs.
cape_under, cape_values = sail_panel("ShortSailScarf_CoralLining", MATS["coral"], 0.146, 0.002)
bind_cape(cape_under, cape_values)
cape_top, cape_values_top = sail_panel("ShortSailScarf_SeaGlassFace", MATS["seaglass"], 0.144, 0)
bind_cape(cape_top, cape_values_top)
cape_rope = curve_tube(
    "ShortSailScarf_Piping",
    [(0.025, 0.145, 1.180), (0.215, 0.190, 1.000), (0.315, 0.230, 0.840)],
    0.0045,
    MATS["coral"],
)
bind_rigid(cape_rope, "capeMid")

# A pear-shaped face and flowing, rounded clumps replace the spherical mask and
# flat fringe cards. The side-swept part is an original tide motif with no
# sprout, stem, leaf, long ear or antenna silhouette.
face = sculpted_head("SculptedFace", (0, -0.028, 1.455), (0.222, 0.187, 0.252), MATS["skin_light"], 28, 18)
bind_rigid(face, "head")
hair_mass = sculpted_head("SweptBob_CohesiveShell", (0, 0.035, 1.475), (0.250, 0.205, 0.267), MATS["hair"], 26, 17)
bind_rigid(hair_mass, "hairBack")
hair_specs = [
    ("PartSweep", [(-0.075, -0.120, 1.690), (-0.015, -0.194, 1.674),
                   (0.060, -0.214, 1.620), (0.115, -0.214, 1.555)],
     [0.046, 0.055, 0.044, 0.005], [0.018, 0.021, 0.017, 0.004], "hairR1", "seaglass"),
    ("PortFringe", [(-0.105, -0.125, 1.675), (-0.160, -0.190, 1.605),
                    (-0.205, -0.196, 1.500), (-0.220, -0.155, 1.355)],
     [0.044, 0.052, 0.043, 0.005], [0.018, 0.021, 0.017, 0.004], "hairR2", "hair"),
    ("StarboardFringe", [(0.060, -0.130, 1.685), (0.145, -0.186, 1.615),
                         (0.205, -0.190, 1.505), (0.228, -0.145, 1.335)],
     [0.043, 0.053, 0.044, 0.005], [0.018, 0.021, 0.017, 0.004], "hairL2", "seaglass"),
    ("PortNape", [(-0.175, 0.005, 1.600), (-0.225, -0.012, 1.515),
                  (-0.242, 0.010, 1.405), (-0.225, 0.055, 1.310)],
     [0.039, 0.045, 0.035, 0.005], [0.020, 0.023, 0.018, 0.004], "hairR2", "hair"),
    ("StarboardNape", [(0.175, 0.005, 1.605), (0.225, -0.012, 1.520),
                       (0.242, 0.012, 1.410), (0.225, 0.058, 1.315)],
     [0.039, 0.045, 0.035, 0.005], [0.020, 0.023, 0.018, 0.004], "hairL2", "hair"),
]
for name, centers, widths, depths, bone_name, mat_name in hair_specs:
    lock, _ = loft_path(f"SweptBob_{name}", centers, widths, depths, MATS[mat_name], 10, 3)
    bind_rigid(lock, bone_name)

# Layered eyes: white, iris, pupil and highlight remain readable at iPhone size.
for side, x in (("L", 0.073), ("R", -0.073)):
    white = uv_sphere(f"EyeWhite_{side}", (x, -0.214, 1.478), (0.036, 0.009, 0.034), MATS["cream"], 16, 10)
    bind_rigid(white, "head")
    iris = uv_sphere(f"SeaGlassIris_{side}", (x, -0.225, 1.477), (0.032, 0.006, 0.032), MATS["seaglass"], 14, 9)
    bind_rigid(iris, f"eye{side}")
    pupil = uv_sphere(f"Pupil_{side}", (x, -0.232, 1.476), (0.012, 0.004, 0.016), MATS["hair"], 12, 8)
    bind_rigid(pupil, f"eye{side}")
    highlight = uv_sphere(f"EyeHighlight_{side}", (x - 0.007, -0.237, 1.488), (0.005, 0.0025, 0.006), MATS["cream"], 8, 5)
    bind_rigid(highlight, f"eye{side}")
    lid = curve_tube(
        f"UpperLid_{side}",
        [(x - 0.033, -0.232, 1.507), (x, -0.238, 1.518), (x + 0.033, -0.232, 1.507)],
        0.0025, MATS["skin"],
    )
    bind_rigid(lid, f"lid{side}")
    brow = curve_tube(
        f"ExpressiveBrow_{side}",
        [(x - 0.031, -0.225, 1.535), (x, -0.231, 1.545), (x + 0.031, -0.225, 1.538)],
        0.0042, MATS["hair"],
    )
    bind_rigid(brow, f"brow{side}")
nose = uv_sphere("SoftNose", (0, -0.222, 1.435), (0.008, 0.005, 0.012), MATS["skin"], 10, 6)
bind_rigid(nose, "head")
for side, x in (("L", 0.115), ("R", -0.115)):
    cheek = uv_sphere(f"CoralCheek_{side}", (x, -0.216, 1.410), (0.014, 0.0025, 0.006), MATS["coral"], 12, 7)
    bind_rigid(cheek, "head")
mouth_left = curve_tube("MouthCorner_L", [(-0.055, -0.225, 1.393), (-0.025, -0.231, 1.382), (0, -0.232, 1.381)], 0.0045, MATS["hair"])
bind_rigid(mouth_left, "mouthR")
mouth_right = curve_tube("MouthCorner_R", [(0, -0.232, 1.381), (0.025, -0.231, 1.382), (0.055, -0.225, 1.393)], 0.0045, MATS["hair"])
bind_rigid(mouth_right, "mouthL")

# Compact compass pouch; four bold cardinal spokes survive downsampling better
# than eight hairline spokes.
strap = curve_tube(
    "CompassPouch_Sling",
    [(-0.120, -0.125, 1.155), (0.010, -0.164, 1.020), (0.195, -0.142, 0.850)],
    0.006, MATS["leather"],
)
bind_rigid(strap, "chest")
pouch = rounded_box("CompassPouch", (0.198, -0.119, 0.835), (0.115, 0.062, 0.098), MATS["leather"], 0.020, (0, 0, -0.07))
bind_rigid(pouch, "pouch")
rose_face = cylinder("CompassPouch_Face", (0.198, -0.159, 0.835), 0.035, 0.008, MATS["navy"], 18, rotation=(math.pi / 2, 0, 0))
bind_rigid(rose_face, "pouch")
rose_rim = torus("CompassPouch_Rim", (0.198, -0.166, 0.835), 0.038, 0.0050, MATS["brass"], 18, 6, rotation=(math.pi / 2, 0, 0))
bind_rigid(rose_rim, "pouch")
for index in range(4):
    angle = index * math.pi / 2
    spoke = rounded_box(
        f"CompassCardinal_{index + 1}",
        (0.198 + math.sin(angle) * 0.017, -0.171, 0.835 + math.cos(angle) * 0.017),
        (0.008, 0.004, 0.031), MATS["brass"], 0.0025, (0, angle, 0),
    )
    bind_rigid(spoke, "pouch")

# Belt-clipped navigation lamp keeps both arms free. It sits behind the left
# hip while its warm core remains a 6–8 px nighttime signature.
lamp_x, lamp_y = -0.350, 0.010
clip = curve_tube(
    "NavigationLamp_BeltClip",
    [(-0.205, 0.020, 0.875), (-0.285, 0.030, 0.895), (lamp_x, lamp_y, 0.855)],
    0.008, MATS["brass"],
)
bind_rigid(clip, "lantern")
lamp_top = cone("NavigationLamp_Top", (lamp_x, lamp_y, 0.812), 0.029, 0.066, 0.049, MATS["brass"], 10)
bind_rigid(lamp_top, "lantern")
lamp_glow = uv_sphere("NavigationLamp_Glow", (lamp_x, lamp_y, 0.748), (0.061, 0.055, 0.070), MATS["glow"], 14, 9)
bind_rigid(lamp_glow, "lantern")
lamp_cage_top = torus("NavigationLamp_CageTop", (lamp_x, lamp_y, 0.801), 0.059, 0.0060, MATS["brass"], 14, 6)
bind_rigid(lamp_cage_top, "lantern")
lamp_cage_bottom = torus("NavigationLamp_CageBottom", (lamp_x, lamp_y, 0.693), 0.059, 0.0060, MATS["brass"], 14, 6)
bind_rigid(lamp_cage_bottom, "lantern")
for index, angle in enumerate((0, math.pi / 2, math.pi, math.pi * 1.5), 1):
    bar = cylinder(
        f"NavigationLamp_Bar_{index}",
        (lamp_x + math.cos(angle) * 0.056, lamp_y + math.sin(angle) * 0.056, 0.747),
        0.0052, 0.108, MATS["brass"], 8,
    )
    bind_rigid(bar, "lantern")
lamp_base = cone("NavigationLamp_Base", (lamp_x, lamp_y, 0.674), 0.060, 0.071, 0.040, MATS["brass"], 10)
bind_rigid(lamp_base, "lantern")

# Collapse the authored pieces into ten material batches before any animation
# is evaluated. This is the representation saved and exported for production.
consolidate_runtime_meshes()


# MARK: - Animation clips


def rad(value: float) -> float:
    return math.radians(value)


PoseKey = tuple[
    int,
    dict[str, tuple[float, float, float]],
    dict[str, tuple[float, float, float]],
]


def clear_pose() -> None:
    for pose_bone in ARMATURE.pose.bones:
        pose_bone.location = (0, 0, 0)
        pose_bone.rotation_euler = (0, 0, 0)
        pose_bone.scale = (1, 1, 1)


def key_pose(
    frame: int,
    rotations: dict[str, tuple[float, float, float]],
    locations: dict[str, tuple[float, float, float]],
) -> None:
    clear_pose()
    for name, value in rotations.items():
        ARMATURE.pose.bones[name].rotation_euler = value
    for name, value in locations.items():
        ARMATURE.pose.bones[name].location = value
    for pose_bone in ARMATURE.pose.bones:
        pose_bone.keyframe_insert(data_path="rotation_euler", frame=frame, group=pose_bone.name)
        pose_bone.keyframe_insert(data_path="location", frame=frame, group=pose_bone.name)


def create_action(name: str, end_frame: int, keys: list[PoseKey], loop: bool) -> bpy.types.Action:
    if ARMATURE.animation_data is None:
        ARMATURE.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    action["fps"] = FPS
    action["end_frame"] = end_frame
    action["loop"] = loop
    action["in_place"] = True
    ARMATURE.animation_data.action = action
    for frame, rotations, locations in keys:
        key_pose(frame, rotations, locations)
    # Blender 5's layered Action API: clamp handles so vertical support-foot
    # corrections never overshoot the floor between authored gait poses.
    for layer in action.layers:
        for strip in layer.strips:
            for channelbag in strip.channelbags:
                for fcurve in channelbag.fcurves:
                    for keyframe in fcurve.keyframe_points:
                        keyframe.interpolation = "BEZIER"
                        keyframe.handle_left_type = "AUTO_CLAMPED"
                        keyframe.handle_right_type = "AUTO_CLAMPED"
    ARMATURE.animation_data.action = None
    return action


IDLE_KEYS: list[PoseKey] = [
    (1, {"head": (rad(-1), 0, rad(-1)), "capeMid": (rad(1), 0, 0),
         "capeOuter": (rad(0.5), 0, rad(0.5)),
         "capeTip": (rad(2), 0, 0), "hairL2": (rad(1), 0, 0),
         "hairR2": (rad(-0.5), 0, 0)}, {}),
    (24, {"core": (0, 0, rad(0.5)), "chest": (rad(1), rad(-1), rad(0.5)),
          "head": (rad(0.5), rad(-3), rad(0.8)), "armL": (rad(-2), 0, rad(-1)),
          "armR": (rad(-1), 0, rad(1)), "cape": (rad(-1), 0, rad(0.5)),
          "capeMid": (rad(-4), rad(1), rad(1)), "capeTip": (rad(-7), rad(2), rad(1.5)),
          "capeOuter": (rad(-3), rad(1), rad(3)),
          "hairL1": (rad(-1), 0, rad(1)), "hairL2": (rad(-3), 0, rad(2)),
          "hairR1": (rad(-0.5), 0, rad(-0.5)), "hairR2": (rad(-2), 0, rad(-1)),
          "pouch": (rad(-1), 0, rad(-0.7)), "lantern": (rad(1), 0, rad(-1))},
     {"core": (0.005, 0.006, 0)}),
    (48, {"core": (0, 0, rad(-0.5)), "chest": (rad(-0.5), rad(1), rad(-0.5)),
          "head": (rad(-1), rad(4), rad(-0.8)), "capeMid": (rad(2), rad(-1), rad(-0.7)),
          "capeTip": (rad(4), rad(-2), rad(-1)), "capeOuter": (rad(2), rad(-1), rad(-2)),
          "hairL1": (rad(0.5), 0, rad(-0.5)),
          "hairL2": (rad(2), 0, rad(-1)), "hairR2": (rad(1), 0, rad(1)),
          "pouch": (rad(1), 0, rad(0.8)), "lantern": (rad(-1), 0, rad(1))},
     {"core": (-0.005, 0.001, 0)}),
    (72, {"core": (0, 0, rad(0.5)), "chest": (rad(1), rad(-1), rad(0.5)),
          "head": (rad(0.5), rad(-3), rad(0.8)), "armL": (rad(-2), 0, rad(-1)),
          "armR": (rad(-1), 0, rad(1)), "cape": (rad(-1), 0, rad(0.5)),
          "capeMid": (rad(-4), rad(1), rad(1)), "capeTip": (rad(-7), rad(2), rad(1.5)),
          "capeOuter": (rad(-3), rad(1), rad(3)),
          "hairL2": (rad(-3), 0, rad(2)), "hairR2": (rad(-2), 0, rad(-1)),
          "pouch": (rad(-1), 0, rad(-0.7)), "lantern": (rad(1), 0, rad(-1))},
     {"core": (0.005, 0.006, 0)}),
    (96, {"head": (rad(-1), 0, rad(-1)), "capeMid": (rad(1), 0, 0),
          "capeOuter": (rad(0.5), 0, rad(0.5)),
          "capeTip": (rad(2), 0, 0), "hairL2": (rad(1), 0, 0),
          "hairR2": (rad(-0.5), 0, 0)}, {}),
]


def locomotion_keys(run: bool) -> list[PoseKey]:
    # Nine poses expose the actual gait mechanics instead of interpolating from
    # neutral directly into maximum split.  Walk uses contact/down/passing/up;
    # run uses flight/descent/contact/compression around each support foot.
    frames = (1, 3, 5, 7, 9, 11, 13, 15, 17) if run else (1, 4, 7, 10, 13, 16, 19, 22, 25)
    # Values are solved against evaluated boot vertices: the support sole stays
    # within a few millimetres of Z=0 while flight frames remain airborne.
    walk_heights = (-0.047, -0.028, 0.002, -0.015, -0.047, -0.028, 0.002, -0.015, -0.047)
    run_heights = (0.026, 0.010, -0.158, -0.082, 0.026, 0.010, -0.158, -0.082, 0.026)
    swing_angle = 44 if run else 25
    arm_angle = 40 if run else 23
    knee_angle = 50 if run else 35
    keys: list[PoseKey] = []
    for index, frame in enumerate(frames):
        phase = index * math.pi / 4
        # Walk contacts at phase 0/pi; run contacts one quarter-cycle later so
        # frame 1/9/17 is a clear airborne passing silhouette.
        stride = math.sin(phase) if run else math.cos(phase)
        passing = math.cos(phase) if run else math.sin(phase)
        lag = math.sin(phase - 0.45) if run else math.cos(phase - 0.35)
        settle = math.sin(phase - 0.24) if run else math.cos(phase - 0.20)
        lean = -9 if run else -3
        if run:
            bend_l = max(0.0, passing)
            bend_r = max(0.0, -passing)
            vertical = run_heights[index]
        else:
            # From left contact to right contact the right leg is the swing leg.
            bend_l = max(0.0, -passing)
            bend_r = max(0.0, passing)
            vertical = walk_heights[index]
        leg_l_angle = -swing_angle * stride
        leg_r_angle = swing_angle * stride
        heel = 12 if run else 10
        toe_off = 20 if run else 18
        foot_l_angle = heel * max(0.0, stride) - toe_off * max(0.0, -stride)
        foot_r_angle = heel * max(0.0, -stride) - toe_off * max(0.0, stride)
        ankle_l_angle = -leg_l_angle - foot_l_angle
        ankle_r_angle = -leg_r_angle - foot_r_angle
        rear_knee = 65 if run else 42
        trailing_l = rear_knee * max(0.0, -stride)
        trailing_r = rear_knee * max(0.0, stride)
        rotations = {
            "core": (0, rad((4.0 if run else 3.0) * stride), rad((2.5 if run else 1.8) * stride)),
            "spine": (rad(lean), rad((2.0 if run else 1.0) * stride), 0),
            "chest": (rad(-4 if run else -1), rad((-5.0 if run else -4.0) * stride),
                      rad((-2.5 if run else -1.5) * stride)),
            "head": (rad(6 if run else 1), rad((1.5 if run else 0.8) * stride),
                     rad((1.5 if run else 1.0) * stride)),
            "legL": (rad(leg_l_angle), 0, rad(1.5 * stride)),
            "legR": (rad(leg_r_angle), 0, rad(1.5 * stride)),
            "kneeL": (rad(-(knee_angle * bend_l + trailing_l)), 0, 0),
            "kneeR": (rad(-(knee_angle * bend_r + trailing_r)), 0, 0),
            # Counter-rotation keeps the support sole close to horizontal.
            "ankleL": (rad(ankle_l_angle), 0, 0),
            "ankleR": (rad(ankle_r_angle), 0, 0),
            "footL": (rad(foot_l_angle), 0, 0),
            "footR": (rad(foot_r_angle), 0, 0),
            "toeL": (rad(10 * max(0.0, -stride)), 0, 0),
            "toeR": (rad(10 * max(0.0, stride)), 0, 0),
            "armL": (rad(arm_angle * stride), 0, 0),
            # The lamp hand has a shorter, steadier swing than the free hand.
            "armR": (rad(-arm_angle * 0.68 * stride), 0, rad(1.5 * stride)),
            "forearmL": (rad(-20 if run else -9), 0, rad(-2 * stride)),
            "forearmR": (rad(-24 if run else -12), 0, rad(2 * stride)),
            "cape": (rad((-12 if run else -5) + (3 if run else 1.5) * lag), 0,
                     rad((3.0 if run else 1.5) * lag)),
            "capeMid": (rad((-21 if run else -10) + (6 if run else 3) * lag), 0,
                        rad((6.0 if run else 3.0) * lag)),
            "capeTip": (rad((-31 if run else -16) + (9 if run else 5) * lag), 0,
                        rad((9.0 if run else 5.0) * lag)),
            "capeOuter": (rad((-14 if run else -7) + (5 if run else 2.5) * lag),
                          rad((3.0 if run else 1.5) * lag),
                          rad((11.0 if run else 5.5) * lag)),
            "hairL1": (rad((-3 if run else -1) + 2 * settle), 0,
                         rad((2.5 if run else 1.3) * settle)),
            "hairL2": (rad((-9 if run else -3) + 3 * lag), 0,
                         rad((4.0 if run else 2.0) * lag)),
            "hairR1": (rad((-2 if run else -1) + 1.5 * settle), 0,
                         rad((-2.0 if run else -1.0) * settle)),
            "hairR2": (rad((-8 if run else -3) + 2.5 * lag), 0,
                         rad((-4.0 if run else -2.0) * lag)),
            "pouch": (rad((-7 if run else -3) + 2 * settle), 0,
                      rad((-5.0 if run else -2.5) * settle)),
            "lantern": (rad((-9 if run else -4) + 3 * lag), 0,
                        rad((4.0 if run else 2.5) * lag)),
        }
        side_shift = (0.016 if run else 0.012) * stride
        # core's bone-local Y axis is Blender world vertical.
        keys.append((frame, rotations, {"core": (side_shift, vertical, 0)}))
    return keys


WALK_KEYS = locomotion_keys(False)
RUN_KEYS = locomotion_keys(True)

WAVE_KEYS: list[PoseKey] = [
    (1, {}, {}),
    (8, {"armL": (rad(4), 0, rad(12)), "forearmL": (rad(-8), 0, rad(6)),
         "head": (0, rad(2), rad(1)), "chest": (0, rad(1), rad(1)),
         "capeMid": (rad(2), 0, rad(-1)), "capeOuter": (rad(2), 0, rad(-2)),
         "hairL2": (rad(1), 0, rad(-1))},
     {"core": (-0.006, -0.003, 0)}),
    (16, {"armL": (rad(-8), 0, rad(-103)), "forearmL": (rad(-34), rad(-5), rad(-24)),
          "handL": (0, 0, rad(-5)), "head": (0, rad(-5), rad(-2)),
          "chest": (0, rad(-2), rad(-1)), "capeMid": (rad(-3), 0, rad(1)),
          "capeTip": (rad(-5), 0, rad(2)), "capeOuter": (rad(-3), 0, rad(3)),
          "hairL2": (rad(-2), 0, rad(1))},
     {"core": (-0.010, 0.003, 0)}),
    (26, {"armL": (rad(-8), 0, rad(-103)), "forearmL": (rad(-34), rad(-5), rad(-24)),
          "handL": (0, rad(-16), rad(20)), "head": (0, rad(-5), rad(-2)),
          "chest": (0, rad(-2), rad(-1)), "capeMid": (rad(-4), 0, rad(2)),
          "capeTip": (rad(-7), 0, rad(3)), "capeOuter": (rad(-4), 0, rad(4)),
          "hairL2": (rad(-3), 0, rad(2))},
     {"core": (-0.010, 0.003, 0)}),
    (36, {"armL": (rad(-8), 0, rad(-103)), "forearmL": (rad(-34), rad(-5), rad(-24)),
          "handL": (0, rad(16), rad(-20)), "head": (0, rad(-5), rad(-2)),
          "chest": (0, rad(-2), rad(-1)), "capeMid": (rad(1), 0, rad(-2)),
          "capeTip": (rad(3), 0, rad(-3)), "capeOuter": (rad(2), 0, rad(-4)),
          "hairL2": (rad(1), 0, rad(-2))},
     {"core": (-0.010, 0.003, 0)}),
    (46, {"armL": (rad(-8), 0, rad(-103)), "forearmL": (rad(-34), rad(-5), rad(-24)),
          "handL": (0, rad(-13), rad(17)), "head": (0, rad(-5), rad(-2)),
          "chest": (0, rad(-2), rad(-1)), "capeMid": (rad(-2), 0, rad(1)),
          "capeTip": (rad(-4), 0, rad(2)), "capeOuter": (rad(-2), 0, rad(3)),
          "hairL2": (rad(-2), 0, rad(1))},
     {"core": (-0.010, 0.003, 0)}),
    (54, {"armL": (rad(-3), 0, rad(-46)), "forearmL": (rad(-18), 0, rad(-12)),
          "handL": (0, rad(-4), rad(4)), "head": (0, rad(-2), rad(-1)),
          "capeMid": (rad(2), 0, rad(-1)), "capeOuter": (rad(2), 0, rad(-2)),
          "hairL2": (rad(1), 0, rad(-1))},
     {"core": (-0.004, 0, 0)}),
    (60, {}, {}),
]

SIT_KEYS: list[PoseKey] = [
    (1, {}, {}),
    (10, {"spine": (rad(-5), 0, 0), "chest": (rad(-3), 0, 0),
          "head": (rad(4), 0, 0), "legL": (rad(-18), 0, 0), "legR": (rad(-18), 0, 0),
          "kneeL": (rad(18), 0, 0), "kneeR": (rad(18), 0, 0),
          "armL": (rad(-12), 0, rad(-5)), "armR": (rad(-12), 0, rad(5)),
          "capeMid": (rad(-4), 0, 0), "hairL2": (rad(-2), 0, 0)},
     {"core": (0, -0.013, 0)}),
    (20, {"spine": (rad(5), 0, 0), "chest": (rad(3), 0, 0),
          "head": (rad(1), 0, 0), "legL": (rad(-48), 0, 0), "legR": (rad(-48), 0, 0),
          "kneeL": (rad(52), 0, 0), "kneeR": (rad(52), 0, 0),
          "ankleL": (rad(8), 0, 0), "ankleR": (rad(8), 0, 0),
          "armL": (rad(-28), 0, rad(-8)), "armR": (rad(-28), 0, rad(8)),
          "forearmL": (rad(-16), 0, 0), "forearmR": (rad(-16), 0, 0),
          "cape": (rad(5), 0, 0), "capeMid": (rad(10), 0, 0),
          "capeTip": (rad(15), 0, 0), "capeOuter": (rad(10), 0, rad(2)),
          "hairL2": (rad(2), 0, 0),
          "pouch": (rad(3), 0, 0), "lantern": (rad(4), 0, 0)},
     {"core": (0, -0.055, 0)}),
    (32, {"spine": (rad(2), 0, 0), "head": (rad(2), 0, 0),
          "legL": (rad(-72), 0, 0), "legR": (rad(-72), 0, 0),
          "kneeL": (rad(78), 0, 0), "kneeR": (rad(78), 0, 0),
          "ankleL": (rad(10), 0, 0), "ankleR": (rad(10), 0, 0),
          "armL": (rad(-38), 0, rad(-10)), "armR": (rad(-38), 0, rad(10)),
          "forearmL": (rad(-25), 0, 0), "forearmR": (rad(-25), 0, 0),
          "cape": (rad(10), 0, 0), "capeMid": (rad(19), 0, rad(1)),
          "capeTip": (rad(26), 0, rad(2)), "capeOuter": (rad(17), rad(-2), rad(4)),
          "hairL2": (rad(3), 0, rad(1)),
          "hairR2": (rad(2), 0, rad(-1)), "pouch": (rad(6), 0, rad(2)),
          "lantern": (rad(7), 0, rad(-1))},
     {"core": (0, -0.147, 0)}),
    (48, {"spine": (rad(1), 0, 0), "head": (rad(1), rad(3), 0),
          "legL": (rad(-72), 0, 0), "legR": (rad(-72), 0, 0),
          "kneeL": (rad(78), 0, 0), "kneeR": (rad(78), 0, 0),
          "ankleL": (rad(10), 0, 0), "ankleR": (rad(10), 0, 0),
          "armL": (rad(-38), 0, rad(-10)), "armR": (rad(-38), 0, rad(10)),
          "forearmL": (rad(-25), 0, 0), "forearmR": (rad(-25), 0, 0),
          "cape": (rad(9), 0, 0), "capeMid": (rad(17), 0, 0),
          "capeTip": (rad(23), 0, 0), "capeOuter": (rad(14), rad(-1), rad(2)),
          "hairL2": (rad(2), 0, 0),
          "hairR2": (rad(1), 0, 0), "pouch": (rad(4), 0, 0),
          "lantern": (rad(5), 0, 0)},
     {"core": (0, -0.145, 0)}),
]

ACTIONS = {
    "Idle": create_action("Idle", 96, IDLE_KEYS, True),
    "Walk": create_action("Walk", 25, WALK_KEYS, True),
    "Run": create_action("Run", 17, RUN_KEYS, True),
    "Wave": create_action("Wave", 60, WAVE_KEYS, False),
    "Sit": create_action("Sit", 48, SIT_KEYS, False),
}

# Keep every clip discoverable in Blender even when it is not the active Action.
for action in ACTIONS.values():
    track = ARMATURE.animation_data.nla_tracks.new()
    track.name = f"STASH_{action.name}"
    strip = track.strips.new(action.name, 1, action)
    strip.name = action.name
    track.mute = True


def offset_keys(keys: list[PoseKey], frame_offset: int) -> list[PoseKey]:
    return [(frame + frame_offset, rotations, locations) for frame, rotations, locations in keys]


SHOWCASE_RANGES = {
    "Idle": (1, 96),
    "Walk": (106, 130),
    "Run": (140, 156),
    "Wave": (166, 225),
    "Sit": (235, 282),
}
showcase_keys = []
showcase_keys += offset_keys(IDLE_KEYS, 0)
showcase_keys += offset_keys(WALK_KEYS, 105)
showcase_keys += offset_keys(RUN_KEYS, 139)
showcase_keys += offset_keys(WAVE_KEYS, 165)
showcase_keys += offset_keys(SIT_KEYS, 234)
SHOWCASE = create_action("Tideway_Showcase", 282, showcase_keys, False)
SHOWCASE["clip_ranges"] = ";".join(
    f"{name}:{start}-{end}" for name, (start, end) in SHOWCASE_RANGES.items()
)
ARMATURE["usd_clip_ranges"] = SHOWCASE["clip_ranges"]


# MARK: - Preview stage

bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=1.15, depth=0.10, location=(0, 0, -0.055))
preview_plinth = bpy.context.object
preview_plinth.name = "PREVIEW_HarborPlinth"
preview_plinth.data.materials.append(material("PREVIEW_Plaster", "#D9E1D8", 0.95))
bevel(preview_plinth, 0.035, 3)

bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.11))
preview_floor = bpy.context.object
preview_floor.name = "PREVIEW_Floor"
preview_floor.data.materials.append(material("PREVIEW_Background", "#C9DDD5", 1.0))

for name, location, energy, size, color in (
    ("PREVIEW_Key", (-3.8, -4.5, 5.5), 700, 4.5, "#FFE7C2"),
    ("PREVIEW_Fill", (4.0, -2.0, 3.6), 360, 3.4, "#B9DCE2"),
    ("PREVIEW_Rim", (0.5, 4.2, 4.8), 520, 3.2, "#FFC0A3"),
):
    bpy.ops.object.light_add(type="AREA", location=location)
    light = bpy.context.object
    light.name = name
    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size
    light.data.color = rgba(color)[:3]


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.object.camera_add(location=(2.65, -5.7, 2.05))
camera = bpy.context.object
camera.name = "PREVIEW_Camera"
camera.data.type = "ORTHO"
camera.data.ortho_scale = 2.12
look_at(camera, (0, 0, 0.88))

scene = bpy.context.scene
scene.camera = camera
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1100
scene.render.resolution_y = 1300
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.film_transparent = False
scene.render.fps = FPS
scene.world.color = rgba("#C9DDD5")[:3]
scene.view_settings.look = "AgX - Medium High Contrast"

for path in (BLEND_PATH, GLB_PATH, USDZ_PATH, *PREVIEW_PATHS.values()):
    path.parent.mkdir(parents=True, exist_ok=True)


def render_pose(
    action: bpy.types.Action,
    frame: int,
    path: Path,
    camera_location: tuple[float, float, float],
    target: tuple[float, float, float] = (0, 0, 0.88),
    character_yaw: float = 0,
) -> None:
    ARMATURE.animation_data.action = action
    scene.frame_start = 1
    scene.frame_end = int(action["end_frame"])
    scene.frame_set(frame)
    ARMATURE.rotation_euler.z = character_yaw
    camera.location = camera_location
    look_at(camera, target)
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    ARMATURE.rotation_euler.z = 0


if os.environ.get("TIDEWAY_SKIP_PREVIEWS") != "1":
    render_pose(ACTIONS["Idle"], 1, PREVIEW_PATHS["front"], (0, -6.0, 1.72))
    render_pose(ACTIONS["Idle"], 1, PREVIEW_PATHS["side"], (6.0, 0, 1.72))
    if os.environ.get("TIDEWAY_GEOMETRY_GATE") != "1":
        render_pose(ACTIONS["Idle"], 24, PREVIEW_PATHS["idle"], (2.65, -5.7, 2.05))
        render_pose(ACTIONS["Idle"], 1, PREVIEW_PATHS["back"], (0, -6.0, 1.72), character_yaw=math.pi)
        render_pose(ACTIONS["Walk"], 7, PREVIEW_PATHS["walk"], (2.5, -5.8, 1.95))
        render_pose(ACTIONS["Run"], 5, PREVIEW_PATHS["run"], (2.5, -5.8, 1.95))
        render_pose(ACTIONS["Wave"], 36, PREVIEW_PATHS["wave"], (2.5, -5.8, 1.95))
        render_pose(ACTIONS["Sit"], 32, PREVIEW_PATHS["sit"], (2.65, -5.7, 1.72), target=(0, 0, 0.68))


# MARK: - Validation and export


def evaluated_triangle_count() -> int:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    total = 0
    for obj in asset_objects:
        if obj.type != "MESH":
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        total += len(mesh.loop_triangles)
        evaluated.to_mesh_clear()
    return total


def maximum_vertex_influences() -> int:
    maximum = 0
    for obj in asset_objects:
        if obj.type != "MESH":
            continue
        for vertex in obj.data.vertices:
            influences = sum(1 for item in vertex.groups if item.weight > 0.0001)
            maximum = max(maximum, influences)
    return maximum


def evaluated_group_z_bounds(
    action: bpy.types.Action,
    frame: int,
    group_names: set[str] | None = None,
    minimum_weight: float = 0.45,
) -> tuple[float, float]:
    """Return evaluated world-Z bounds for selected authored vertex groups."""

    ARMATURE.animation_data.action = action
    scene.frame_set(frame)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    values: list[float] = []
    for obj in asset_objects:
        if obj.type != "MESH":
            continue
        group_indices = {
            group.index
            for group in obj.vertex_groups
            if group_names is None or group.name in group_names
        }
        if group_names is not None and not group_indices:
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        if len(mesh.vertices) != len(obj.data.vertices):
            evaluated.to_mesh_clear()
            raise RuntimeError(f"Vertex topology changed during metadata evaluation: {obj.name}")
        for source, result in zip(obj.data.vertices, mesh.vertices):
            if group_names is not None and not any(
                membership.group in group_indices and membership.weight >= minimum_weight
                for membership in source.groups
            ):
                continue
            values.append((evaluated.matrix_world @ result.co).z)
        evaluated.to_mesh_clear()
    if not values:
        raise RuntimeError(f"No vertices found for metadata groups: {group_names}")
    return min(values), max(values)


triangle_count = evaluated_triangle_count()
maximum_influences = maximum_vertex_influences()
bone_count = len(ARMATURE.data.bones)
if triangle_count > TRIANGLE_BUDGET:
    raise RuntimeError(f"Tideway Navigator exceeds triangle budget: {triangle_count}")
if maximum_influences > 4:
    raise RuntimeError(f"Tideway Navigator exceeds four weights per vertex: {maximum_influences}")
if not 32 <= bone_count <= 48:
    raise RuntimeError(f"Tideway Navigator bone count outside target: {bone_count}")

# Author the actual seating contract from the final evaluated Sit pose. Runtime
# can align this surface with a stump/bench without reusing Phoenix dimensions.
sit_ground_min, _ = evaluated_group_z_bounds(ACTIONS["Sit"], 48, {"footL", "footR"})
sit_surface_height, sit_surface_top = evaluated_group_z_bounds(ACTIONS["Sit"], 48, {"sitSurface"})
walk_contact_bounds = [
    (
        frame,
        evaluated_group_z_bounds(ACTIONS["Walk"], frame, {"footL"})[0],
        evaluated_group_z_bounds(ACTIONS["Walk"], frame, {"footR"})[0],
    )
    for frame in (1, 13, 25)
]
run_contact_bounds = [
    (
        frame,
        evaluated_group_z_bounds(ACTIONS["Run"], frame, {"footL"})[0],
        evaluated_group_z_bounds(ACTIONS["Run"], frame, {"footR"})[0],
    )
    for frame in (5, 13)
]
walk_all_bounds = [
    (
        frame,
        evaluated_group_z_bounds(ACTIONS["Walk"], frame, {"footL"})[0],
        evaluated_group_z_bounds(ACTIONS["Walk"], frame, {"footR"})[0],
    )
    for frame in (1, 4, 7, 10, 13, 16, 19, 22, 25)
]
run_all_bounds = [
    (
        frame,
        evaluated_group_z_bounds(ACTIONS["Run"], frame, {"footL"})[0],
        evaluated_group_z_bounds(ACTIONS["Run"], frame, {"footR"})[0],
    )
    for frame in (1, 3, 5, 7, 9, 11, 13, 15, 17)
]
sit_all_bounds = [
    (
        frame,
        evaluated_group_z_bounds(ACTIONS["Sit"], frame)[0],
    )
    for frame in (1, 8, 10, 14, 18, 20, 22, 25, 28, 32, 36, 40, 44, 48)
]
walk_floor_series = [
    evaluated_group_z_bounds(ACTIONS["Walk"], frame, {"footL", "footR"})[0]
    for frame in range(1, 26)
]
run_floor_series = [
    evaluated_group_z_bounds(ACTIONS["Run"], frame, {"footL", "footR"})[0]
    for frame in range(1, 18)
]
sit_floor_series = [
    evaluated_group_z_bounds(ACTIONS["Sit"], frame)[0]
    for frame in range(1, 49)
]
if min(walk_floor_series) < -0.005:
    raise RuntimeError(f"Walk penetrates authored floor: {min(walk_floor_series):.6f}")
if min(run_floor_series) < -0.005:
    raise RuntimeError(f"Run penetrates authored floor: {min(run_floor_series):.6f}")
if min(sit_floor_series) < -0.010:
    raise RuntimeError(f"Sit transition penetrates authored floor: {min(sit_floor_series):.6f}")
if abs(sit_ground_min) > 0.010:
    raise RuntimeError(f"Sit final foot contact outside tolerance: {sit_ground_min:.6f}")
for owner in (ARMATURE, SHOWCASE):
    owner["sitSurfaceHeight"] = round(sit_surface_height, 6)
    owner["sitSurfaceTop"] = round(sit_surface_top, 6)
    owner["sitGroundMin"] = round(sit_ground_min, 6)
    owner["sit_surface_height"] = round(sit_surface_height, 6)

# Save an artist-friendly file with Idle active and every clip stashed/fake-user protected.
ARMATURE.animation_data.action = ACTIONS["Idle"]
scene.frame_start = 1
scene.frame_end = 96
scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

# Export the character hierarchy only. Preview lights/floor/camera never enter runtime assets.
bpy.ops.object.select_all(action="DESELECT")
for obj in asset_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = ARMATURE
bpy.ops.export_scene.gltf(
    filepath=str(GLB_PATH),
    export_format="GLB",
    use_selection=True,
    export_yup=True,
    export_materials="EXPORT",
    export_cameras=False,
    export_lights=False,
    export_extras=True,
    export_apply=False,
    export_skins=True,
    export_animations=True,
    export_animation_mode="ACTIONS",
    export_extra_animations=True,
    export_force_sampling=True,
    export_optimize_animation_size=True,
    export_optimize_animation_keep_anim_armature=True,
)

# Blender USD exports the evaluated scene timeline. A concatenated action keeps
# every required motion in one SceneKit-readable SkelAnimation; clip ranges are
# stored as custom metadata on both the rig and the Action.
ARMATURE.animation_data.action = SHOWCASE
scene.frame_start = 1
scene.frame_end = 282
scene.frame_set(1)
bpy.ops.wm.usd_export(
    filepath=str(USDZ_PATH),
    root_prim_path="/TidewayAsset",
    selected_objects_only=True,
    export_animation=True,
    export_materials=True,
    export_normals=True,
    export_uvmaps=True,
    export_armatures=True,
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

print(f"TIDEWAY_BLEND={BLEND_PATH}")
print(f"TIDEWAY_GLB={GLB_PATH}")
print(f"TIDEWAY_USDZ={USDZ_PATH}")
print(f"TIDEWAY_PREVIEWS={','.join(str(path) for path in PREVIEW_PATHS.values())}")
print(f"TIDEWAY_TRIANGLES={triangle_count}")
print(f"TIDEWAY_BONES={bone_count}")
print(f"TIDEWAY_MAX_INFLUENCES={maximum_influences}")
print(f"TIDEWAY_ACTIONS={','.join(action.name for action in ACTIONS.values())}")
print(f"TIDEWAY_USD_CLIP_RANGES={SHOWCASE['clip_ranges']}")
print(f"TIDEWAY_SIT_SURFACE_HEIGHT={sit_surface_height:.6f}")
print(f"TIDEWAY_SIT_GROUND_MIN={sit_ground_min:.6f}")
print(
    "TIDEWAY_WALK_CONTACT_Z="
    + ";".join(f"{frame}:{left:.5f},{right:.5f}" for frame, left, right in walk_contact_bounds)
)
print(
    "TIDEWAY_RUN_CONTACT_Z="
    + ";".join(f"{frame}:{left:.5f},{right:.5f}" for frame, left, right in run_contact_bounds)
)
print(
    "TIDEWAY_WALK_ALL_Z="
    + ";".join(f"{frame}:{left:.5f},{right:.5f}" for frame, left, right in walk_all_bounds)
)
print(
    "TIDEWAY_RUN_ALL_Z="
    + ";".join(f"{frame}:{left:.5f},{right:.5f}" for frame, left, right in run_all_bounds)
)
print(
    "TIDEWAY_SIT_ALL_Z="
    + ";".join(f"{frame}:{minimum:.5f}" for frame, minimum in sit_all_bounds)
)
print(f"TIDEWAY_WALK_FLOOR_RANGE={min(walk_floor_series):.6f},{max(walk_floor_series):.6f}")
print(f"TIDEWAY_RUN_FLOOR_RANGE={min(run_floor_series):.6f},{max(run_floor_series):.6f}")
print(f"TIDEWAY_SIT_FLOOR_RANGE={min(sit_floor_series):.6f},{max(sit_floor_series):.6f}")
