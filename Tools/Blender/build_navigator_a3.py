"""Build the first game-ready prototype of the black-haired A3 navigator.

The asset is intentionally separate from the shipping navigator.  It creates:

* a Blender source file with a compact humanoid armature,
* a skinned GLB with in-place animation clips,
* neutral, walk and wave preview renders.

The character faces Blender -Y. glTF export converts the scene to Y-up.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/navigator_a3_black.blend"
GLB_PATH = ROOT / "web/public/models/navigator_a3_black.glb"
PREVIEW_PATH = ROOT / "marketing/3d/navigator-a3-black.png"
WALK_PREVIEW_PATH = ROOT / "marketing/3d/navigator-a3-black-walk.png"
WAVE_PREVIEW_PATH = ROOT / "marketing/3d/navigator-a3-black-wave.png"

FPS = 24

PALETTE = {
    "skin": "#C7A28D",
    "skin_shadow": "#A87E6B",
    "sclera": "#DDD8CC",
    "iris": "#687B75",
    "pupil": "#181816",
    "hair": "#171817",
    "hair_light": "#282A28",
    "brow": "#242320",
    "mouth": "#704F49",
    "coat": "#303637",
    "coat_edge": "#414A49",
    "undershirt": "#9ABAB3",
    "trouser": "#3A4142",
    "shoe": "#282E2E",
    "sole": "#111414",
    "copper": "#856954",
    "paper": "#E8E1D3",
}


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    srgb = tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4))
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
    roughness: float = 0.78,
    metallic: float = 0.0,
    sheen: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = rgba(color)
    mat.use_nodes = True
    bsdf = next(node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = rgba(color)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if bsdf.inputs.get("Sheen Weight"):
        bsdf.inputs["Sheen Weight"].default_value = sheen
    return mat


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
    ):
        for block in list(collection):
            if block.users == 0:
                collection.remove(block)


reset_scene()

MATS = {
    key: material(
        f"A3_{key.title()}",
        value,
        roughness=0.65 if key in {"hair", "hair_light"} else 0.8,
        metallic=0.18 if key == "copper" else 0.0,
        sheen=0.18 if key in {"coat", "trouser"} else 0.0,
    )
    for key, value in PALETTE.items()
}

asset_objects: list[bpy.types.Object] = []


def smooth(obj: bpy.types.Object) -> bpy.types.Object:
    if obj.type == "MESH":
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    return obj


def bevel(obj: bpy.types.Object, width: float = 0.006, segments: int = 3) -> bpy.types.Object:
    modifier = obj.modifiers.new("A3 soft edge", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    return obj


def keep(obj: bpy.types.Object, name: str, mat: bpy.types.Material) -> bpy.types.Object:
    obj.name = name
    if obj.data:
        obj.data.name = f"{name}_Mesh"
        obj.data.materials.append(mat)
    asset_objects.append(obj)
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
        radius=1.0,
        location=location,
    )
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
    scale: tuple[float, float, float] = (1.0, 1.0, 1.0),
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    vertices: int = 16,
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


def rounded_box(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    bevel_width: float = 0.02,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = keep(bpy.context.object, name, mat)
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bevel(obj, bevel_width, 4)
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
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    asset_objects.append(obj)
    return obj


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
    n = len(points)
    faces: list[tuple[int, ...]] = [
        tuple(range(n)),
        tuple(range(n, n * 2)),
    ]
    for index in range(n):
        next_index = (index + 1) % n
        faces.append((index, next_index, n + next_index, n + index))
    obj = mesh_object(name, vertices, faces, mat)
    bevel(obj, edge, 3)
    return obj


def curve_mesh(
    name: str,
    points: list[tuple[float, float, float]],
    bevel_depth: float,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(f"{name}_Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = bevel_depth
    curve.bevel_resolution = 3
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, co in zip(spline.bezier_points, points):
        point.co = co
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
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


def hair_ribbon(
    name: str,
    points: list[tuple[float, float, float]],
    widths: list[float],
    mat: bpy.types.Material,
) -> bpy.types.Object:
    """A tapered, slightly curved hair card with real thickness.

    A few broad cards read as intentionally modelled locks. Round curve tubes
    read as cords when seen at gameplay distance, so the face fringe avoids
    them entirely.
    """
    vertices: list[tuple[float, float, float]] = []
    for point, width in zip(points, widths):
        x, y, z = point
        vertices.extend([(x - width, y, z), (x + width, y, z)])
    faces = [(i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2) for i in range(len(points) - 1)]
    obj = smooth(mesh_object(name, vertices, faces, mat))
    solidify = obj.modifiers.new("Hair card thickness", "SOLIDIFY")
    solidify.thickness = 0.004
    bevel(obj, 0.0025, 2)
    return obj


def make_hair_cap() -> bpy.types.Object:
    center = Vector((0.0, 0.002, 1.625))
    rings = 8
    segments = 22
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    # A slightly asymmetric cap. It stops above the lower face; individual
    # clumps form the jaw-length fringe.
    for ring in range(rings + 1):
        theta = (ring / rings) * 2.04
        for segment in range(segments):
            phi = segment / segments * math.tau
            asym = 1.0 + 0.035 * math.sin(phi + 0.7)
            x = math.sin(theta) * math.cos(phi) * 0.116 * asym
            y = math.sin(theta) * math.sin(phi) * 0.096
            z = math.cos(theta) * 0.148
            vertices.append(tuple(center + Vector((x, y, z))))
    for ring in range(rings):
        for segment in range(segments):
            a = ring * segments + segment
            b = ring * segments + (segment + 1) % segments
            c = (ring + 1) * segments + (segment + 1) % segments
            d = (ring + 1) * segments + segment
            faces.append((a, b, c, d))
    return smooth(mesh_object("Hair_Cap", vertices, faces, MATS["hair"]))


def build_armature() -> bpy.types.Object:
    arm_data = bpy.data.armatures.new("Navigator_A3_Rig")
    armature = bpy.data.objects.new("Navigator_A3_Rig", arm_data)
    bpy.context.collection.objects.link(armature)
    asset_objects.append(armature)
    armature.show_in_front = True
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
        edit_bone = arm_data.edit_bones.new(name)
        edit_bone.head = head
        edit_bone.tail = tail
        edit_bone.use_deform = deform
        if parent:
            edit_bone.parent = arm_data.edit_bones[parent]
            edit_bone.use_connect = connected

    bone("Root", (0, 0, 0), (0, 0, 0.12), deform=False)
    bone("Pelvis", (0, 0, 0.84), (0, 0, 1.00), "Root")
    bone("Spine", (0, 0, 1.00), (0, 0, 1.22), "Pelvis", True)
    bone("Chest", (0, 0, 1.22), (0, 0, 1.42), "Spine", True)
    bone("Neck", (0, 0, 1.42), (0, 0, 1.52), "Chest", True)
    bone("Head", (0, 0, 1.52), (0, 0, 1.73), "Neck", True)

    for side, x in (("L", 0.255), ("R", -0.255)):
        bone(f"UpperArm.{side}", (x, 0, 1.37), (x, 0, 1.13), "Chest")
        bone(f"Forearm.{side}", (x, 0, 1.13), (x, 0, 0.93), f"UpperArm.{side}", True)
        bone(f"Hand.{side}", (x, 0, 0.93), (x, -0.005, 0.83), f"Forearm.{side}", True)

    for side, x in (("L", 0.115), ("R", -0.115)):
        bone(f"Thigh.{side}", (x, 0, 0.91), (x, 0, 0.55), "Pelvis")
        bone(f"Shin.{side}", (x, 0, 0.55), (x, 0, 0.18), f"Thigh.{side}", True)
        bone(f"Foot.{side}", (x, 0, 0.18), (x, -0.17, 0.10), f"Shin.{side}", True)

    bone("Cape.01", (-0.06, 0.10, 1.38), (-0.07, 0.12, 1.13), "Chest")
    bone("Cape.02", (-0.07, 0.12, 1.13), (-0.08, 0.14, 0.86), "Cape.01", True)
    bone("Cape.03", (-0.08, 0.14, 0.86), (-0.09, 0.16, 0.52), "Cape.02", True)

    bpy.ops.object.mode_set(mode="POSE")
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "XYZ"
    bpy.ops.object.mode_set(mode="OBJECT")
    armature["asset_role"] = "navigator_prototype"
    armature["design"] = "A3 black-haired navigator"
    armature["version"] = 1
    armature["front_axis_blender"] = "-Y"
    armature["animations"] = "Idle,Walk,Run,Wave,Read"
    return armature


ARMATURE = build_armature()


def bind_rigid(obj: bpy.types.Object, bone_name: str) -> None:
    if obj.type != "MESH":
        return
    group = obj.vertex_groups.new(name=bone_name)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    modifier = obj.modifiers.new("Navigator A3 armature", "ARMATURE")
    modifier.object = ARMATURE
    obj.parent = ARMATURE
    obj.matrix_parent_inverse = ARMATURE.matrix_world.inverted()


def bind_cape(obj: bpy.types.Object, rows: int, columns: int) -> None:
    groups = {
        name: obj.vertex_groups.new(name=name)
        for name in ("Cape.01", "Cape.02", "Cape.03")
    }
    for row in range(rows):
        v = row / max(1, rows - 1)
        if v < 0.38:
            weights = {"Cape.01": 1.0 - v / 0.38 * 0.45, "Cape.02": v / 0.38 * 0.45}
        elif v < 0.72:
            t = (v - 0.38) / 0.34
            weights = {"Cape.01": 0.55 * (1 - t), "Cape.02": 0.45 + 0.4 * t, "Cape.03": 0.15 * t}
        else:
            t = (v - 0.72) / 0.28
            weights = {"Cape.02": 0.85 * (1 - t), "Cape.03": 0.15 + 0.85 * t}
        total = sum(weights.values())
        for column in range(columns):
            vertex = row * columns + column
            for name, weight in weights.items():
                groups[name].add([vertex], weight / total, "REPLACE")
    modifier = obj.modifiers.new("Navigator A3 cape armature", "ARMATURE")
    modifier.object = ARMATURE
    obj.parent = ARMATURE
    obj.matrix_parent_inverse = ARMATURE.matrix_world.inverted()


# --- Human face and hair ----------------------------------------------------

face = uv_sphere("Face", (0, -0.018, 1.625), (0.108, 0.086, 0.139), MATS["skin"], 28, 20)
bind_rigid(face, "Head")

# A soft jaw/chin volume keeps the face from reading as a perfect doll sphere.
chin = uv_sphere("Chin", (0, -0.086, 1.565), (0.060, 0.016, 0.034), MATS["skin"], 18, 12)
bind_rigid(chin, "Head")

neck = cylinder("Neck", (0, 0.0, 1.475), 0.051, 0.13, MATS["skin"], scale=(0.92, 0.86, 1.0))
bind_rigid(neck, "Neck")

for side, x in (("L", 0.108), ("R", -0.108)):
    ear = uv_sphere(f"Ear.{side}", (x, -0.002, 1.625), (0.019, 0.012, 0.039), MATS["skin"], 14, 10)
    bind_rigid(ear, "Head")

nose = uv_sphere("Nose", (0.002, -0.101, 1.614), (0.011, 0.014, 0.020), MATS["skin"], 14, 10)
bind_rigid(nose, "Head")

for side, x in (("L", 0.038), ("R", -0.040)):
    white = uv_sphere(
        f"EyeWhite.{side}",
        (x, -0.099, 1.648),
        (0.020, 0.0038, 0.0072),
        MATS["sclera"],
        18,
        10,
    )
    bind_rigid(white, "Head")
    iris = uv_sphere(
        f"Iris.{side}",
        (x + (0.001 if side == "L" else -0.001), -0.106, 1.648),
        (0.0057, 0.0019, 0.0057),
        MATS["iris"],
        16,
        10,
    )
    bind_rigid(iris, "Head")
    pupil = uv_sphere(
        f"Pupil.{side}",
        (x + (0.001 if side == "L" else -0.001), -0.110, 1.648),
        (0.0027, 0.0014, 0.0027),
        MATS["pupil"],
        12,
        8,
    )
    bind_rigid(pupil, "Head")

for side, x0, x1, z0, z1 in (
    ("L", 0.014, 0.066, 1.678, 1.681),
    ("R", -0.067, -0.015, 1.682, 1.676),
):
    brow = curve_mesh(
        f"Brow.{side}",
        [(x0, -0.105, z0), ((x0 + x1) / 2, -0.108, max(z0, z1) + 0.003), (x1, -0.105, z1)],
        0.0033,
        MATS["brow"],
    )
    bind_rigid(brow, "Head")

mouth = curve_mesh(
    "Mouth",
    [(-0.029, -0.105, 1.568), (0.001, -0.109, 1.565), (0.031, -0.104, 1.570)],
    0.0027,
    MATS["mouth"],
)
bind_rigid(mouth, "Head")

hair_cap = make_hair_cap()
bind_rigid(hair_cap, "Head")

# A3's defining asymmetric jaw-length black fringe.
hair_paths = [
    ([(-0.082, -0.099, 1.742), (-0.062, -0.112, 1.685), (-0.048, -0.109, 1.612)], [0.019, 0.016, 0.004]),
    ([(-0.045, -0.105, 1.758), (-0.026, -0.117, 1.703), (-0.012, -0.114, 1.638)], [0.020, 0.016, 0.004]),
    ([(0.000, -0.108, 1.763), (0.010, -0.119, 1.710), (0.020, -0.115, 1.655)], [0.021, 0.016, 0.004]),
    ([(0.045, -0.102, 1.752), (0.060, -0.115, 1.699), (0.071, -0.107, 1.635)], [0.020, 0.015, 0.004]),
    ([(-0.097, -0.058, 1.714), (-0.111, -0.074, 1.657), (-0.105, -0.062, 1.595)], [0.018, 0.014, 0.004]),
    ([(0.092, -0.054, 1.707), (0.108, -0.070, 1.650), (0.100, -0.053, 1.588)], [0.018, 0.014, 0.004]),
]
for index, (points, widths) in enumerate(hair_paths, 1):
    strand = hair_ribbon(f"Hair_Fringe_{index:02}", points, widths, MATS["hair"])
    bind_rigid(strand, "Head")

# Small broken layers along the crown avoid a perfect salon silhouette.
for index, (x, y, z, sx, sy, sz, tilt) in enumerate(
    [
        (-0.075, 0.005, 1.742, 0.055, 0.035, 0.018, -0.35),
        (-0.028, -0.006, 1.770, 0.065, 0.038, 0.018, -0.12),
        (0.035, -0.004, 1.765, 0.072, 0.038, 0.018, 0.18),
        (0.083, 0.008, 1.730, 0.055, 0.035, 0.018, 0.36),
    ],
    1,
):
    clump = uv_sphere(f"Hair_Crown_{index:02}", (x, y, z), (sx, sy, sz), MATS["hair_light"], 14, 8)
    clump.rotation_euler.y = tilt
    bind_rigid(clump, "Head")


# --- Simplified A silhouette ------------------------------------------------

undershirt = uv_sphere("Undershirt", (0, 0.006, 1.225), (0.152, 0.084, 0.222), MATS["undershirt"], 24, 16)
bind_rigid(undershirt, "Spine")

chest_back = uv_sphere("Jacket_Back", (0, 0.050, 1.285), (0.188, 0.093, 0.192), MATS["coat"], 24, 16)
bind_rigid(chest_back, "Chest")

left_panel = prism_xz(
    "Jacket_Front_L",
    [(-0.188, 1.395), (-0.026, 1.402), (-0.015, 1.215), (-0.084, 1.075), (-0.188, 1.128)],
    -0.092,
    0.026,
    MATS["coat"],
    0.008,
)
bind_rigid(left_panel, "Chest")

right_panel = prism_xz(
    "Jacket_Front_R",
    [(0.026, 1.402), (0.188, 1.395), (0.188, 1.128), (0.082, 1.085), (0.015, 1.215)],
    -0.092,
    0.026,
    MATS["coat_edge"],
    0.008,
)
bind_rigid(right_panel, "Chest")

# Low open collar. It frames the human face without becoming a fantasy costume.
for side, points in (
    ("L", [(-0.18, 1.398), (-0.052, 1.448), (-0.016, 1.390), (-0.145, 1.342)]),
    ("R", [(0.052, 1.448), (0.18, 1.398), (0.145, 1.342), (0.016, 1.390)]),
):
    collar = prism_xz(f"Collar_{side}", points, -0.083, 0.018, MATS["coat_edge"], 0.006)
    bind_rigid(collar, "Chest")

# One tiny practical clasp is the only visible hardware.
clasp = uv_sphere("Jacket_Clasp", (0.012, -0.115, 1.305), (0.018, 0.008, 0.018), MATS["copper"], 14, 8)
bind_rigid(clasp, "Chest")

pelvis = uv_sphere("Trouser_Hips", (0, 0.008, 0.925), (0.146, 0.092, 0.112), MATS["trouser"], 22, 14)
bind_rigid(pelvis, "Pelvis")

for side, x in (("L", 0.225), ("R", -0.225)):
    upper_sleeve = uv_sphere(
        f"UpperSleeve.{side}",
        (x, 0.005, 1.245),
        (0.052, 0.044, 0.127),
        MATS["coat"],
        18,
        12,
    )
    bind_rigid(upper_sleeve, f"UpperArm.{side}")
    elbow = uv_sphere(
        f"Elbow.{side}",
        (x, 0.002, 1.120),
        (0.050, 0.043, 0.057),
        MATS["coat_edge"],
        16,
        10,
    )
    bind_rigid(elbow, f"Forearm.{side}")
    fore_sleeve = uv_sphere(
        f"ForeSleeve.{side}",
        (x, 0.0, 1.025),
        (0.047, 0.040, 0.112),
        MATS["coat_edge"],
        18,
        12,
    )
    bind_rigid(fore_sleeve, f"Forearm.{side}")
    hand = uv_sphere(f"Hand.{side}", (x, -0.006, 0.858), (0.047, 0.038, 0.067), MATS["skin"], 18, 12)
    bind_rigid(hand, f"Hand.{side}")
    thumb_x = x + (0.039 if side == "L" else -0.039)
    thumb = uv_sphere(f"Thumb.{side}", (thumb_x, -0.025, 0.865), (0.019, 0.019, 0.034), MATS["skin_shadow"], 12, 8)
    bind_rigid(thumb, f"Hand.{side}")

for side, x in (("L", 0.105), ("R", -0.105)):
    thigh = uv_sphere(
        f"Thigh.{side}",
        (x, 0.008, 0.710),
        (0.070, 0.060, 0.193),
        MATS["trouser"],
        20,
        14,
    )
    bind_rigid(thigh, f"Thigh.{side}")
    knee = uv_sphere(f"Knee.{side}", (x, -0.004, 0.535), (0.068, 0.057, 0.074), MATS["trouser"], 18, 12)
    bind_rigid(knee, f"Shin.{side}")
    shin = uv_sphere(
        f"Shin.{side}",
        (x, 0.012, 0.352),
        (0.059, 0.050, 0.192),
        MATS["trouser"],
        20,
        14,
    )
    bind_rigid(shin, f"Shin.{side}")
    shoe = rounded_box(
        f"Shoe.{side}",
        (x, -0.070, 0.090),
        (0.128, 0.235, 0.100),
        MATS["shoe"],
        0.038,
    )
    bind_rigid(shoe, f"Foot.{side}")
    sole = rounded_box(
        f"Sole.{side}",
        (x, -0.074, 0.029),
        (0.138, 0.248, 0.025),
        MATS["sole"],
        0.010,
    )
    bind_rigid(sole, f"Foot.{side}")
    ankle = uv_sphere(
        f"Ankle.{side}",
        (x, -0.004, 0.175),
        (0.055, 0.050, 0.079),
        MATS["shoe"],
        18,
        12,
    )
    bind_rigid(ankle, f"Foot.{side}")


def make_asymmetric_panel() -> bpy.types.Object:
    rows = 7
    columns = 4
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for row in range(rows):
        v = row / (rows - 1)
        z = 1.39 - 0.92 * v
        center = -0.075 - 0.055 * v
        width = 0.20 + 0.10 * v
        y = 0.135 + 0.045 * v
        for column in range(columns):
            u = column / (columns - 1) - 0.5
            # The left edge is deliberately longer and broader than the right.
            edge_drop = 0.055 * v * max(0.0, -u * 2)
            wave = 0.012 * math.sin(v * math.pi * 1.3 + column * 0.9)
            vertices.append((center + u * width, y + wave, z - edge_drop))
    for row in range(rows - 1):
        for column in range(columns - 1):
            a = row * columns + column
            b = a + 1
            d = a + columns
            c = d + 1
            faces.append((a, b, c, d))
    obj = smooth(mesh_object("Asymmetric_Back_Panel", vertices, faces, MATS["coat"]))
    solidify = obj.modifiers.new("Panel thickness", "SOLIDIFY")
    solidify.thickness = 0.008
    bevel(obj, 0.004, 2)
    bind_cape(obj, rows, columns)
    return obj


make_asymmetric_panel()


# --- Animation clips --------------------------------------------------------

def clear_pose() -> None:
    for bone in ARMATURE.pose.bones:
        bone.location = (0.0, 0.0, 0.0)
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)


def key_pose(
    frame: int,
    rotations: dict[str, tuple[float, float, float]] | None = None,
    locations: dict[str, tuple[float, float, float]] | None = None,
) -> None:
    clear_pose()
    for name, value in (rotations or {}).items():
        ARMATURE.pose.bones[name].rotation_euler = value
    for name, value in (locations or {}).items():
        ARMATURE.pose.bones[name].location = value
    for bone in ARMATURE.pose.bones:
        bone.keyframe_insert(data_path="rotation_euler", frame=frame, group=bone.name)
        bone.keyframe_insert(data_path="location", frame=frame, group=bone.name)


def create_action(
    name: str,
    end_frame: int,
    keys: list[
        tuple[
            int,
            dict[str, tuple[float, float, float]],
            dict[str, tuple[float, float, float]],
        ]
    ],
) -> bpy.types.Action:
    if ARMATURE.animation_data is None:
        ARMATURE.animation_data_create()
    action = bpy.data.actions.new(name)
    ARMATURE.animation_data.action = action
    for frame, rotations, locations in keys:
        key_pose(frame, rotations, locations)
    action["loop"] = name in {"Idle", "Walk", "Run", "Read"}
    action["fps"] = FPS
    action["end_frame"] = end_frame
    ARMATURE.animation_data.action = None
    return action


def rad(value: float) -> float:
    return math.radians(value)


idle = create_action(
    "Idle",
    48,
    [
        (1, {"Head": (rad(-1), 0, rad(-1.2)), "Cape.02": (rad(1), 0, 0)}, {}),
        (
            24,
            {
                "Chest": (rad(1.4), 0, 0),
                "Head": (rad(0.8), 0, rad(1.0)),
                "UpperArm.L": (rad(-1.5), 0, 0),
                "UpperArm.R": (rad(-1.0), 0, 0),
                "Cape.01": (rad(-2), 0, 0),
                "Cape.02": (rad(-4), 0, rad(-1)),
                "Cape.03": (rad(-6), 0, rad(1)),
            },
            {"Pelvis": (0, 0, 0.006)},
        ),
        (48, {"Head": (rad(-1), 0, rad(-1.2)), "Cape.02": (rad(1), 0, 0)}, {}),
    ],
)

walk_keys = []
for frame, phase in ((1, 0), (7, 1), (13, 2), (19, 3), (25, 4)):
    swing = math.sin(phase * math.pi / 2)
    lift = abs(math.sin(phase * math.pi / 2))
    walk_keys.append(
        (
            frame,
            {
                "Chest": (rad(-2), 0, rad(-2.2 * swing)),
                "Head": (rad(1), 0, rad(1.2 * swing)),
                "Thigh.L": (rad(25 * swing), 0, 0),
                "Thigh.R": (rad(-25 * swing), 0, 0),
                "Shin.L": (rad(-18 * max(0, -swing)), 0, 0),
                "Shin.R": (rad(-18 * max(0, swing)), 0, 0),
                "Foot.L": (rad(-7 * swing), 0, 0),
                "Foot.R": (rad(7 * swing), 0, 0),
                "UpperArm.L": (rad(-20 * swing), 0, 0),
                "UpperArm.R": (rad(20 * swing), 0, 0),
                "Forearm.L": (rad(-8), 0, 0),
                "Forearm.R": (rad(-8), 0, 0),
                "Cape.01": (rad(-7), 0, rad(1.5 * swing)),
                "Cape.02": (rad(-12), 0, rad(2.5 * swing)),
                "Cape.03": (rad(-17), 0, rad(3.5 * swing)),
            },
            {"Pelvis": (0, 0, 0.012 * lift)},
        )
    )
walk = create_action("Walk", 25, walk_keys)

run_keys = []
for frame, phase in ((1, 0), (5, 1), (10, 2), (15, 3), (20, 4)):
    swing = math.sin(phase * math.pi / 2)
    lift = abs(math.sin(phase * math.pi / 2))
    run_keys.append(
        (
            frame,
            {
                "Spine": (rad(-10), 0, 0),
                "Chest": (rad(-6), 0, rad(-3.5 * swing)),
                "Head": (rad(8), 0, rad(1.5 * swing)),
                "Thigh.L": (rad(42 * swing), 0, 0),
                "Thigh.R": (rad(-42 * swing), 0, 0),
                "Shin.L": (rad(-36 * max(0, -swing)), 0, 0),
                "Shin.R": (rad(-36 * max(0, swing)), 0, 0),
                "Foot.L": (rad(-12 * swing), 0, 0),
                "Foot.R": (rad(12 * swing), 0, 0),
                "UpperArm.L": (rad(-35 * swing), 0, 0),
                "UpperArm.R": (rad(35 * swing), 0, 0),
                "Forearm.L": (rad(-24), 0, 0),
                "Forearm.R": (rad(-24), 0, 0),
                "Cape.01": (rad(-13), 0, rad(2 * swing)),
                "Cape.02": (rad(-22), 0, rad(4 * swing)),
                "Cape.03": (rad(-29), 0, rad(6 * swing)),
            },
            {"Pelvis": (0, 0, 0.025 * lift)},
        )
    )
run = create_action("Run", 20, run_keys)

wave = create_action(
    "Wave",
    56,
    [
        (1, {}, {}),
        (
            12,
            {
                "UpperArm.L": (rad(-8), 0, rad(-105)),
                "Forearm.L": (rad(-22), rad(-10), rad(-20)),
                "Hand.L": (0, 0, rad(-8)),
                "Head": (0, rad(-4), rad(-2)),
            },
            {},
        ),
        (
            22,
            {
                "UpperArm.L": (rad(-8), 0, rad(-105)),
                "Forearm.L": (rad(-22), rad(-10), rad(-20)),
                "Hand.L": (0, rad(-18), rad(17)),
                "Head": (0, rad(-4), rad(-2)),
            },
            {},
        ),
        (
            32,
            {
                "UpperArm.L": (rad(-8), 0, rad(-105)),
                "Forearm.L": (rad(-22), rad(-10), rad(-20)),
                "Hand.L": (0, rad(18), rad(-15)),
                "Head": (0, rad(-4), rad(-2)),
            },
            {},
        ),
        (
            42,
            {
                "UpperArm.L": (rad(-8), 0, rad(-105)),
                "Forearm.L": (rad(-22), rad(-10), rad(-20)),
                "Hand.L": (0, rad(-18), rad(17)),
                "Head": (0, rad(-4), rad(-2)),
            },
            {},
        ),
        (56, {}, {}),
    ],
)

read = create_action(
    "Read",
    72,
    [
        (
            1,
            {
                "Head": (rad(10), 0, 0),
                "UpperArm.L": (rad(-42), 0, rad(-18)),
                "UpperArm.R": (rad(-42), 0, rad(18)),
                "Forearm.L": (rad(-32), rad(-8), rad(9)),
                "Forearm.R": (rad(-32), rad(8), rad(-9)),
            },
            {},
        ),
        (
            36,
            {
                "Chest": (rad(1.5), 0, 0),
                "Head": (rad(12), 0, rad(1.5)),
                "UpperArm.L": (rad(-43), 0, rad(-18)),
                "UpperArm.R": (rad(-43), 0, rad(18)),
                "Forearm.L": (rad(-32), rad(-8), rad(9)),
                "Forearm.R": (rad(-32), rad(8), rad(-9)),
                "Cape.02": (rad(-3), 0, 0),
            },
            {"Pelvis": (0, 0, 0.004)},
        ),
        (
            72,
            {
                "Head": (rad(10), 0, 0),
                "UpperArm.L": (rad(-42), 0, rad(-18)),
                "UpperArm.R": (rad(-42), 0, rad(18)),
                "Forearm.L": (rad(-32), rad(-8), rad(9)),
                "Forearm.R": (rad(-32), rad(8), rad(-9)),
            },
            {},
        ),
    ],
)

# The book is a small prop weighted to the chest for now; hands frame it in the
# Read clip. A later pass can give it a dedicated prop bone and page animation.
book = rounded_box("Field_Book", (0, -0.245, 1.035), (0.090, 0.020, 0.115), MATS["paper"], 0.008)
book.hide_render = True
book.hide_viewport = True
bind_rigid(book, "Chest")

ARMATURE.animation_data.action = idle
bpy.context.scene.frame_start = 1
bpy.context.scene.frame_end = 48
bpy.context.scene.render.fps = FPS


# --- Preview and export -----------------------------------------------------

bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.005))
floor = bpy.context.object
floor.name = "PREVIEW_Floor"
floor.data.materials.append(material("PREVIEW_Paper", "#E6E0D4", 1.0))

bpy.ops.object.light_add(type="AREA", location=(-3.8, -4.8, 5.8))
key = bpy.context.object
key.name = "PREVIEW_Key"
key.data.energy = 560
key.data.shape = "DISK"
key.data.size = 4.5
key.data.color = rgba("#F7E6D4")[:3]

bpy.ops.object.light_add(type="AREA", location=(4.0, -1.5, 3.5))
fill = bpy.context.object
fill.name = "PREVIEW_Fill"
fill.data.energy = 260
fill.data.size = 3.2
fill.data.color = rgba("#A9C8C6")[:3]

bpy.ops.object.light_add(type="AREA", location=(-1.0, 4.0, 4.4))
rim = bpy.context.object
rim.name = "PREVIEW_Rim"
rim.data.energy = 380
rim.data.size = 3.0
rim.data.color = rgba("#D9E5DF")[:3]


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.object.camera_add(location=(2.35, -5.8, 2.18))
camera = bpy.context.object
camera.name = "PREVIEW_Camera"
camera.data.type = "ORTHO"
camera.data.ortho_scale = 2.05
look_at(camera, (0, 0, 0.90))

scene = bpy.context.scene
scene.camera = camera
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1200
scene.render.resolution_y = 1500
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.world.color = rgba("#E6E0D4")[:3]
scene.view_settings.look = "AgX - Medium High Contrast"

for path in (BLEND_PATH, GLB_PATH, PREVIEW_PATH, WALK_PREVIEW_PATH, WAVE_PREVIEW_PATH):
    path.parent.mkdir(parents=True, exist_ok=True)


def render_action(action: bpy.types.Action, frame: int, path: Path) -> None:
    ARMATURE.animation_data.action = action
    scene.frame_set(frame)
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


render_action(idle, 24, PREVIEW_PATH)
render_action(walk, 7, WALK_PREVIEW_PATH)
render_action(wave, 28, WAVE_PREVIEW_PATH)
ARMATURE.animation_data.action = idle
scene.frame_set(1)
scene.render.filepath = str(PREVIEW_PATH)

bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

bpy.ops.object.select_all(action="DESELECT")
for obj in asset_objects:
    obj.hide_viewport = False
    obj.hide_render = False
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

print(f"Saved Blender source: {BLEND_PATH}")
print(f"Exported rigged GLB: {GLB_PATH}")
print(f"Rendered neutral preview: {PREVIEW_PATH}")
print(f"Rendered walk preview: {WALK_PREVIEW_PATH}")
print(f"Rendered wave preview: {WAVE_PREVIEW_PATH}")
