"""Build Landfall's hero windswept tree as a detailed standalone 3D asset.

The model deliberately does not reuse the primitive-based world construction.  It
is authored as an organic hero prop: transported tube frames for curved wood,
physical bark plates and lichen, a connected fine-twig network, and individually
modeled folded leaves.  The editable Blender scene remains separated into semantic
parts; delivery meshes are merged by material for practical runtime draw counts.
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/windswept_tree.blend"
GLB_PATH = ROOT / "web/public/models/windswept_tree.glb"
USDZ_PATH = ROOT / "Landfall/Resources/windswept_tree.usdz"
RENDER_PATH = ROOT / "marketing/3d/windswept-tree.png"
SEED = 64291
RNG = random.Random(SEED)

COLORS = {
    "bark_deep": "#352820",
    "bark_shadow": "#473328",
    "bark": "#5E4332",
    "bark_sun": "#684D39",
    "deadwood": "#8B7359",
    "lichen_deep": "#607061",
    "lichen": "#82917A",
    "leaf_deep": "#173E34",
    "leaf_shadow": "#205244",
    "leaf": "#2E6C54",
    "leaf_light": "#4E8765",
    "leaf_sun": "#7EA477",
    "ground": "#8F9B92",
    "sky": "#AABCB2",
    "warm": "#FFF0CF",
    "cool": "#78A18C",
}


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float,
    *,
    double_sided: bool = False,
    sheen: float = 0.0,
) -> bpy.types.Material:
    value = bpy.data.materials.new(name)
    value.diffuse_color = rgba(color)
    value.use_nodes = True
    value.use_backface_culling = not double_sided
    bsdf = next(node for node in value.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = rgba(color)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = sheen
        bsdf.inputs["Coat Roughness"].default_value = 0.42
    return value


MATS = {
    "bark_deep": material("LF_TreeBarkDeep", COLORS["bark_deep"], 0.96),
    "bark_shadow": material("LF_TreeBarkShadow", COLORS["bark_shadow"], 0.94),
    "bark": material("LF_TreeBark", COLORS["bark"], 0.92),
    "bark_sun": material("LF_TreeBarkSun", COLORS["bark_sun"], 0.90),
    "twig": material("LF_TreeTwig", COLORS["bark_shadow"], 0.93),
    "deadwood": material("LF_TreeDeadwood", COLORS["deadwood"], 0.97),
    "lichen_deep": material("LF_TreeLichenDeep", COLORS["lichen_deep"], 1.0),
    "lichen": material("LF_TreeLichen", COLORS["lichen"], 1.0),
    "leaf_deep": material(
        "LF_TreeLeafDeep", COLORS["leaf_deep"], 0.79, double_sided=True, sheen=0.05
    ),
    "leaf_shadow": material(
        "LF_TreeLeafShadow", COLORS["leaf_shadow"], 0.76, double_sided=True, sheen=0.06
    ),
    "leaf": material(
        "LF_TreeLeaf", COLORS["leaf"], 0.73, double_sided=True, sheen=0.07
    ),
    "leaf_light": material(
        "LF_TreeLeafLight", COLORS["leaf_light"], 0.70, double_sided=True, sheen=0.08
    ),
    "leaf_sun": material(
        "LF_TreeLeafSun", COLORS["leaf_sun"], 0.68, double_sided=True, sheen=0.09
    ),
}


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

root = bpy.data.objects.new("Windswept_Tree", None)
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
    *,
    smooth: bool = False,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(mat)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = root
    asset_objects.append(obj)
    for polygon in mesh.polygons:
        polygon.use_smooth = smooth
    return obj


def transported_frames(points: list[Vector]) -> list[tuple[Vector, Vector, Vector]]:
    tangents: list[Vector] = []
    for index in range(len(points)):
        if index == 0:
            tangent = points[1] - points[0]
        elif index == len(points) - 1:
            tangent = points[-1] - points[-2]
        else:
            tangent = points[index + 1] - points[index - 1]
        tangents.append(tangent.normalized())

    reference = Vector((0, 0, 1))
    if abs(tangents[0].dot(reference)) > 0.88:
        reference = Vector((0, 1, 0))
    normal = tangents[0].cross(reference).normalized()
    frames: list[tuple[Vector, Vector, Vector]] = []
    for tangent in tangents:
        projected = normal - tangent * normal.dot(tangent)
        normal = projected.normalized() if projected.length > 1e-5 else tangent.orthogonal().normalized()
        binormal = tangent.cross(normal).normalized()
        frames.append((tangent, normal, binormal))
    return frames


def tube(
    name: str,
    coordinates: list[tuple[float, float, float]],
    radii: list[float],
    mat: bpy.types.Material,
    *,
    sides: int = 12,
    irregularity: float = 0.055,
    smooth: bool = True,
) -> bpy.types.Object:
    points = [Vector(value) for value in coordinates]
    frames = transported_frames(points)
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    phase = RNG.uniform(-math.pi, math.pi)
    for ring_index, (point, (_, normal, binormal), radius) in enumerate(zip(points, frames, radii)):
        for side in range(sides):
            angle = side / sides * math.tau
            ripple = 1 + irregularity * (
                math.sin(angle * 3 + phase + ring_index * 0.37) * 0.72
                + math.sin(angle * 5 - phase * 0.4 + ring_index * 0.81) * 0.28
            )
            offset = (normal * math.cos(angle) + binormal * math.sin(angle)) * radius * ripple
            vertices.append(tuple(point + offset))
    for ring in range(len(points) - 1):
        current = ring * sides
        following = (ring + 1) * sides
        for side in range(sides):
            nxt = (side + 1) % sides
            faces.append((current + side, current + nxt, following + nxt, following + side))

    start_center = len(vertices)
    vertices.append(tuple(points[0]))
    end_center = len(vertices)
    vertices.append(tuple(points[-1]))
    for side in range(sides):
        nxt = (side + 1) % sides
        faces.append((start_center, nxt, side))
        last = (len(points) - 1) * sides
        faces.append((end_center, last + side, last + nxt))
    return mesh_object(name, vertices, faces, mat, smooth=smooth)


def quadratic_point(a: Vector, b: Vector, c: Vector, t: float) -> Vector:
    one = 1 - t
    return a * (one * one) + b * (2 * one * t) + c * (t * t)


def quadratic_tangent(a: Vector, b: Vector, c: Vector, t: float) -> Vector:
    return ((b - a) * (2 * (1 - t)) + (c - b) * (2 * t)).normalized()


def bark_plate(
    name: str,
    center: Vector,
    normal: Vector,
    width: float,
    height: float,
    depth: float,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    normal = normal.normalized()
    vertical = Vector((0, 0, 1)) - normal * normal.z
    if vertical.length < 1e-4:
        vertical = Vector((1, 0, 0))
    vertical.normalize()
    horizontal = vertical.cross(normal).normalized()
    skew = RNG.uniform(-0.22, 0.22) * width
    base_center = center - normal * depth * 0.25
    front_center = center + normal * depth
    front = [
        front_center - vertical * height * 0.52 - horizontal * width * 0.18 + horizontal * skew,
        front_center - vertical * height * 0.34 + horizontal * width * 0.42,
        front_center + vertical * height * 0.18 + horizontal * width * 0.50,
        front_center + vertical * height * 0.52 + horizontal * width * 0.10 - horizontal * skew * 0.4,
        front_center + vertical * height * 0.37 - horizontal * width * 0.40,
        front_center - vertical * height * 0.10 - horizontal * width * 0.49,
    ]
    back = [point - normal * depth for point in front]
    vertices = [tuple(point) for point in front + back]
    faces = [tuple(range(6)), tuple(reversed(range(6, 12)))]
    for index in range(6):
        nxt = (index + 1) % 6
        faces.append((index, nxt, 6 + nxt, 6 + index))
    return mesh_object(name, vertices, faces, mat)


# Ground-gripping roots begin above the soil and disappear below it at their tips.
root_specs = [
    (0.18, 0.52, 0.055),
    (1.48, 0.42, 0.047),
    (2.76, 0.50, 0.054),
    (4.08, 0.46, 0.049),
    (5.34, 0.49, 0.052),
]
for index, (angle, length, radius) in enumerate(root_specs):
    direction = Vector((math.cos(angle), math.sin(angle), 0))
    side = Vector((-direction.y, direction.x, 0))
    bend = side * RNG.uniform(-0.18, 0.18)
    points = [
        direction * 0.045 + Vector((0, 0, 0.080)),
        direction * (length * 0.28) + bend * 0.28 + Vector((0, 0, 0.025)),
        direction * (length * 0.62) + bend + Vector((0, 0, -0.040)),
        direction * length + bend * 0.62 + Vector((0, 0, -0.095)),
    ]
    tube(
        f"Root_{index + 1:02}",
        [tuple(point) for point in points],
        [radius, radius * 0.58, radius * 0.16, 0.0025],
        MATS["bark_deep" if index % 3 == 0 else "bark_shadow"],
        sides=10,
        irregularity=0.09,
    )

# The trunk is a single transported surface, not a stack of cylinders.  The lower
# rings flare into the roots, while the upper line yields gradually to the sea wind.
trunk_points = [
    (0.00, 0.00, 0.02),
    (-0.030, 0.018, 0.17),
    (0.005, -0.024, 0.38),
    (0.070, 0.018, 0.65),
    (0.145, -0.018, 0.92),
    (0.235, 0.016, 1.19),
    (0.330, -0.014, 1.44),
    (0.430, 0.012, 1.66),
    (0.535, 0.000, 1.84),
]
trunk_radii = [0.185, 0.172, 0.150, 0.127, 0.105, 0.085, 0.065, 0.047, 0.029]
tube("Hero_Trunk", trunk_points, trunk_radii, MATS["bark"], sides=18, irregularity=0.105)

# Main scaffold branches establish a long leeward crown and a shorter, weathered
# windward side.  Every branch uses at least four centers so bends read organically.
branch_specs: list[tuple[str, list[tuple[float, float, float]], list[float], str]] = [
    ("Leeward_Low", [(0.13, 0.00, 0.88), (0.46, -0.04, 1.05), (0.86, -0.03, 1.22),
                      (1.23, 0.03, 1.35), (1.55, 0.02, 1.45)],
     [0.079, 0.062, 0.043, 0.027, 0.011], "bark_shadow"),
    ("Leeward_High", [(0.28, 0.00, 1.31), (0.58, 0.03, 1.55), (0.98, -0.04, 1.76),
                       (1.38, -0.05, 1.90), (1.72, 0.02, 1.96)],
     [0.068, 0.052, 0.036, 0.021, 0.008], "bark_sun"),
    ("Leeward_Back", [(0.20, 0.02, 1.16), (0.48, 0.30, 1.38), (0.82, 0.52, 1.56),
                       (1.16, 0.61, 1.67)],
     [0.060, 0.041, 0.024, 0.008], "bark"),
    ("Leeward_Front", [(0.34, -0.01, 1.47), (0.58, -0.28, 1.67), (0.92, -0.49, 1.82),
                        (1.26, -0.57, 1.86)],
     [0.052, 0.036, 0.020, 0.007], "bark_shadow"),
    ("Windward_Main", [(0.14, 0.00, 0.92), (-0.18, 0.03, 1.20), (-0.45, 0.08, 1.49),
                        (-0.72, 0.06, 1.70), (-0.92, 0.02, 1.79)],
     [0.071, 0.054, 0.036, 0.020, 0.008], "bark"),
    ("Windward_Back", [(0.21, 0.02, 1.20), (-0.02, 0.28, 1.44), (-0.24, 0.53, 1.67),
                        (-0.39, 0.68, 1.79)],
     [0.049, 0.033, 0.018, 0.007], "bark_sun"),
    ("Crown_Leader", [(0.40, 0.00, 1.60), (0.47, 0.04, 1.86), (0.53, 0.06, 2.09),
                       (0.55, 0.02, 2.29)],
     [0.052, 0.037, 0.022, 0.007], "bark_sun"),
    ("Crown_Back", [(0.38, 0.01, 1.54), (0.42, 0.36, 1.78), (0.48, 0.63, 1.98),
                     (0.51, 0.78, 2.08)],
     [0.045, 0.031, 0.017, 0.006], "bark"),
    ("Crown_Front", [(0.36, -0.01, 1.49), (0.36, -0.30, 1.73), (0.35, -0.59, 1.91),
                      (0.35, -0.77, 1.98)],
     [0.044, 0.029, 0.016, 0.006], "bark_shadow"),
]
for name, points, radii, mat_name in branch_specs:
    tube(name, points, radii, MATS[mat_name], sides=12, irregularity=0.075)

# A snapped limb on the windward face records years of storms.
tube(
    "Storm_Broken_Limb",
    [(0.08, 0.02, 0.70), (-0.04, -0.02, 0.78), (-0.14, -0.04, 0.81)],
    [0.034, 0.024, 0.014],
    MATS["deadwood"],
    sides=11,
    irregularity=0.12,
)

# Each crown unit is a branch endpoint with its own airy leaf volume.  The volumes
# overlap only at their edges, leaving deliberate windows through the canopy.
crown_units = [
    ((-0.92, 0.02, 1.79), (-0.78, 0.00, 1.92), (0.48, 0.42, 0.38), 11),
    ((-0.39, 0.68, 1.79), (-0.27, 0.67, 1.95), (0.52, 0.36, 0.38), 10),
    ((0.35, -0.77, 1.98), (0.38, -0.67, 2.08), (0.52, 0.38, 0.36), 11),
    ((0.51, 0.78, 2.08), (0.63, 0.68, 2.13), (0.56, 0.38, 0.38), 11),
    ((0.55, 0.02, 2.29), (0.68, 0.05, 2.25), (0.57, 0.46, 0.40), 12),
    ((1.16, 0.61, 1.67), (1.28, 0.58, 1.82), (0.62, 0.38, 0.38), 12),
    ((1.26, -0.57, 1.86), (1.39, -0.50, 1.88), (0.63, 0.40, 0.39), 12),
    ((1.55, 0.02, 1.45), (1.66, 0.02, 1.62), (0.60, 0.43, 0.42), 13),
    ((1.72, 0.02, 1.96), (1.80, 0.03, 2.01), (0.46, 0.36, 0.34), 10),
    ((0.86, -0.03, 1.22), (1.01, -0.02, 1.40), (0.45, 0.32, 0.30), 10),
    ((0.58, 0.03, 1.55), (0.72, 0.14, 1.72), (0.46, 0.34, 0.32), 10),
    ((-0.45, 0.08, 1.49), (-0.52, -0.18, 1.64), (0.40, 0.31, 0.30), 9),
]

leaf_batches: dict[str, tuple[list[tuple[float, float, float]], list[tuple[int, ...]]]] = {
    key: ([], [])
    for key in ("leaf_deep", "leaf_shadow", "leaf", "leaf_light", "leaf_sun")
}


def append_leaf(
    batch_name: str,
    center: Vector,
    direction: Vector,
    length: float,
    width: float,
    roll: float,
) -> None:
    direction = direction.normalized()
    reference = Vector((0, 0, 1)) if abs(direction.z) < 0.86 else Vector((0, 1, 0))
    side = direction.cross(reference).normalized()
    normal = side.cross(direction).normalized()
    side.rotate(Matrix.Rotation(roll, 3, direction))
    normal = side.cross(direction).normalized()
    base = center - direction * length * 0.50
    tip = center + direction * length * 0.50
    lower = center - direction * length * 0.17
    upper = center + direction * length * 0.14
    fold = width * 0.24
    vertices, faces = leaf_batches[batch_name]
    offset = len(vertices)
    vertices.extend(
        tuple(point)
        for point in (
            base,
            lower + side * width * 0.72,
            upper + side * width,
            tip,
            upper - side * width,
            lower - side * width * 0.72,
            center + normal * fold,
        )
    )
    faces.extend(
        (
            (offset, offset + 1, offset + 6),
            (offset + 1, offset + 2, offset + 6),
            (offset + 2, offset + 3, offset + 6),
            (offset, offset + 6, offset + 5),
            (offset + 5, offset + 6, offset + 4),
            (offset + 4, offset + 6, offset + 3),
        )
    )


for unit_index, (attachment_tuple, center_tuple, extents, spray_count) in enumerate(crown_units):
    attachment = Vector(attachment_tuple)
    center = Vector(center_tuple)
    extent = Vector(extents)
    connector_mid = attachment.lerp(center, 0.55) + Vector((0.02, RNG.uniform(-0.04, 0.04), 0.04))
    tube(
        f"Crown_Connector_{unit_index + 1:02}",
        [tuple(attachment), tuple(connector_mid), tuple(center)],
        [0.018, 0.011, 0.0045],
        MATS["twig"],
        sides=7,
        irregularity=0.06,
    )

    for spray_index in range(spray_count):
        azimuth = (spray_index / spray_count) * math.tau + RNG.uniform(-0.30, 0.30)
        elevation = RNG.uniform(-0.42, 0.72)
        radial = Vector((math.cos(azimuth), math.sin(azimuth), elevation)).normalized()
        # All sprays retain a subtle leeward bias without forming a comb.
        radial.x += 0.20
        radial.normalize()
        length_scale = RNG.uniform(0.62, 1.04)
        endpoint = center + Vector((
            radial.x * extent.x,
            radial.y * extent.y,
            radial.z * extent.z,
        )) * length_scale
        start = center + radial * RNG.uniform(0.015, 0.055)
        bend_axis = radial.cross(Vector((0, 0, 1)))
        if bend_axis.length < 1e-4:
            bend_axis = Vector((0, 1, 0))
        bend_axis.normalize()
        middle = start.lerp(endpoint, 0.52) + bend_axis * RNG.uniform(-0.055, 0.055)
        tube(
            f"Twig_{unit_index + 1:02}_{spray_index + 1:02}",
            [tuple(start), tuple(middle), tuple(endpoint)],
            [0.008, 0.0045, 0.0018],
            MATS["twig"],
            sides=6,
            irregularity=0.04,
        )

        leaves_on_spray = 22 if spray_index % 3 else 25
        for leaf_index in range(leaves_on_spray):
            t = 0.10 + 0.88 * (leaf_index + RNG.uniform(0.0, 0.65)) / leaves_on_spray
            twig_point = quadratic_point(start, middle, endpoint, t)
            tangent = quadratic_tangent(start, middle, endpoint, t)
            out = Vector((
                RNG.uniform(-1.0, 1.0),
                RNG.uniform(-1.0, 1.0),
                RNG.uniform(-0.55, 1.0),
            )).normalized()
            leaf_direction = (out * 0.82 + tangent * RNG.uniform(0.10, 0.42)).normalized()
            center_offset = out * RNG.uniform(0.012, 0.038)
            leaf_center = twig_point + center_offset
            size = RNG.uniform(0.084, 0.132) * (0.90 + 0.10 * t)
            width = size * RNG.uniform(0.28, 0.39)
            light_score = leaf_center.z * 0.9 - leaf_center.y * 0.32 + leaf_center.x * 0.10
            roll = RNG.uniform(-math.pi, math.pi)
            pick = RNG.random()
            if light_score > 2.15 and pick < 0.32:
                batch = "leaf_sun"
            elif light_score > 1.86 and pick < 0.55:
                batch = "leaf_light"
            elif leaf_center.y > 0.42 and pick < 0.62:
                batch = "leaf_deep"
            elif pick < 0.30:
                batch = "leaf_shadow"
            else:
                batch = "leaf"
            append_leaf(batch, leaf_center, leaf_direction, size, width, roll)

        # Terminal rosette hides the bare end of every twig and breaks the outline.
        for terminal in range(6):
            angle = terminal / 6 * math.tau + RNG.uniform(-0.22, 0.22)
            direction = (radial * 0.54 + Vector((math.cos(angle), math.sin(angle), 0.35)) * 0.68).normalized()
            append_leaf(
                "leaf_light" if terminal == 0 else "leaf",
                endpoint + direction * 0.025,
                direction,
                RNG.uniform(0.095, 0.132),
                RNG.uniform(0.030, 0.046),
                RNG.uniform(-math.pi, math.pi),
            )

for batch_name, (vertices, faces) in leaf_batches.items():
    mesh_object(
        f"Tree_Leaves_{batch_name.removeprefix('leaf_').title() or 'Mid'}",
        vertices,
        faces,
        MATS[batch_name],
    )


# Preview stage is deliberately excluded from all exported selections.
preview_ground_mat = material("PREVIEW_Ground", COLORS["ground"], 0.96)
bpy.ops.mesh.primitive_plane_add(size=200, location=(0.35, 0, -0.035))
ground = bpy.context.object
ground.name = "PREVIEW_Ground"
ground.data.materials.append(preview_ground_mat)

world = bpy.context.scene.world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba(COLORS["sky"])
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.32


def look_at(obj: bpy.types.Object, point: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.object.light_add(type="AREA", location=(-4.8, -5.2, 7.0))
key = bpy.context.object
key.name = "PREVIEW_Warm_Key"
key.data.energy = 520
key.data.shape = "DISK"
key.data.size = 5.0
key.data.color = rgba(COLORS["warm"])[:3]
look_at(key, (0.38, 0, 1.25))

bpy.ops.object.light_add(type="AREA", location=(5.5, 3.8, 4.0))
fill = bpy.context.object
fill.name = "PREVIEW_Cool_Fill"
fill.data.energy = 310
fill.data.size = 4.0
fill.data.color = rgba(COLORS["cool"])[:3]
look_at(fill, (0.55, 0, 1.35))

bpy.ops.object.light_add(type="AREA", location=(0.0, 4.0, 6.0))
rim = bpy.context.object
rim.name = "PREVIEW_Canopy_Rim"
rim.data.energy = 420
rim.data.size = 3.5
rim.data.color = rgba("#D6E8D5")[:3]
look_at(rim, (0.75, 0.1, 1.85))

bpy.ops.object.camera_add(location=(5.35, -7.35, 3.30))
camera = bpy.context.object
camera.name = "PREVIEW_Camera"
camera.data.lens = 61
look_at(camera, (0.42, 0.0, 1.25))

scene = bpy.context.scene
scene.camera = camera
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1700
scene.render.resolution_y = 1700
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.filepath = str(RENDER_PATH)
scene.render.film_transparent = False
scene.render.image_settings.color_depth = "8"
scene.view_settings.look = "AgX - Medium High Contrast"

BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
USDZ_PATH.parent.mkdir(parents=True, exist_ok=True)
RENDER_PATH.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

# Merge by PBR material for delivery while preserving the high-detail source scene.
groups: dict[str, list[bpy.types.Object]] = {}
for obj in asset_objects:
    if obj.type != "MESH":
        continue
    key_name = obj.data.materials[0].name if obj.data.materials else "Unmaterialed"
    groups.setdefault(key_name, []).append(obj)

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

bpy.ops.export_scene.gltf(
    filepath=str(GLB_PATH),
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_yup=True,
    export_animations=False,
)

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

mesh_count = len(export_objects)
triangle_count = sum(
    len(polygon.vertices) - 2
    for obj in export_objects
    if obj.type == "MESH"
    for polygon in obj.data.polygons
)
print(f"BLEND={BLEND_PATH}")
print(f"GLB={GLB_PATH}")
print(f"USDZ={USDZ_PATH}")
print(f"RENDER={RENDER_PATH}")
print(f"DELIVERY_MESHES={mesh_count}")
print(f"TRIANGLES={triangle_count}")
