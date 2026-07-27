"""Build the Polaris Wayfinder navigator and export game-ready assets.

The Blender file is the source of truth.  Named transform pivots are retained in
the GLB/USDZ so Three.js and SceneKit can keep the lightweight runtime poses.
The character deliberately has no lantern.
"""

from __future__ import annotations

import math
import shutil
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/navigator_main.blend"
GLB_PATH = ROOT / "web/public/models/navigator_main-v5.glb"
GLB_COMPAT_PATH = ROOT / "web/public/models/navigator_main.glb"
USDZ_PATH = ROOT / "Landfall/Resources/navigator_main.usdz"
RENDER_PATH = ROOT / "marketing/3d/navigator-main.png"
BACK_RENDER_PATH = ROOT / "marketing/3d/navigator-main-back.png"

PALETTE = {
    "terracotta": "#C47748",
    "terracotta_light": "#DC955C",
    "terracotta_shadow": "#91492D",
    "navy": "#111B31",
    "navy_light": "#1E2D4D",
    "coral": "#E66E51",
    "cream": "#E9DFC1",
    "gold": "#C9A45C",
    "gold_light": "#E4C77F",
    "brown": "#3A2118",
    "brown_light": "#613827",
    "face": "#111524",
    "eyes": "#F3E8C7",
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
    roughness: float = 0.82,
    metallic: float = 0.0,
    emission: str | None = None,
    emission_strength: float = 0.0,
    sheen: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = rgba(color)
    mat.use_nodes = True
    bsdf = next(
        node for node in mat.node_tree.nodes
        if node.type == "BSDF_PRINCIPLED"
    )
    bsdf.inputs["Base Color"].default_value = rgba(color)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if bsdf.inputs.get("Sheen Weight"):
        bsdf.inputs["Sheen Weight"].default_value = sheen
    if emission:
        bsdf.inputs["Emission Color"].default_value = rgba(emission)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


MATS = {
    "coat": material("LF_NavigatorTerracotta", PALETTE["terracotta"], 0.68, sheen=0.22),
    "coat_light": material("LF_NavigatorTerracottaLight", PALETTE["terracotta_light"], 0.64, sheen=0.24),
    "coat_shadow": material("LF_NavigatorTerracottaShadow", PALETTE["terracotta_shadow"], 0.76, sheen=0.16),
    "cape": material("LF_NavigatorCapeNavy", PALETTE["navy"], 0.74, sheen=0.34),
    "cape_light": material("LF_NavigatorCapeHighlight", PALETTE["navy_light"], 0.7, sheen=0.3),
    "coral": material("LF_NavigatorWindTail", PALETTE["coral"], 0.62, sheen=0.25),
    "cream": material("LF_NavigatorRope", PALETTE["cream"], 0.84, sheen=0.08),
    "gold": material("LF_NavigatorCompassGold", PALETTE["gold"], 0.28, 0.68),
    "gold_light": material("LF_NavigatorCompassHighlight", PALETTE["gold_light"], 0.24, 0.58),
    "brown": material("LF_NavigatorBoots", PALETTE["brown"], 0.58),
    "brown_light": material("LF_NavigatorLeather", PALETTE["brown_light"], 0.52),
    "face": material("LF_NavigatorFaceVoid", PALETTE["face"], 0.82),
    "eyes": material(
        "LF_NavigatorEyes",
        PALETTE["eyes"],
        0.78,
        emission=PALETTE["eyes"],
        emission_strength=0.16,
    ),
}


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.cameras, bpy.data.lights):
    for block in list(datablocks):
        if block.users == 0:
            datablocks.remove(block)

asset_objects: list[bpy.types.Object] = []


def empty(name: str, location=(0.0, 0.0, 0.0), parent=None) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.06
    obj.location = location
    obj.parent = parent
    asset_objects.append(obj)
    return obj


root = empty("Navigator_Main")
contact = empty("contact", parent=root)


def keep(
    obj: bpy.types.Object,
    name: str,
    mat: bpy.types.Material,
    parent: bpy.types.Object,
) -> bpy.types.Object:
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    obj.data.materials.append(mat)
    obj.parent = parent
    asset_objects.append(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def mesh_object(
    name: str,
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    mat: bpy.types.Material,
    parent: bpy.types.Object,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(mat)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    asset_objects.append(obj)
    return obj


def smooth(obj: bpy.types.Object) -> bpy.types.Object:
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def bevel(obj: bpy.types.Object, width: float = 0.012, segments: int = 4) -> bpy.types.Object:
    mod = obj.modifiers.new("Soft illustrated edges", "BEVEL")
    mod.width = width
    mod.segments = segments
    return obj


def uv_sphere(
    name: str,
    location,
    scale,
    mat,
    parent,
    segments=16,
    rings=10,
    smooth_shading=True,
):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        radius=1,
        location=location,
    )
    obj = keep(bpy.context.object, name, mat, parent)
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return smooth(obj) if smooth_shading else obj


def cylinder(
    name: str,
    location,
    radius: float,
    depth: float,
    mat,
    parent,
    vertices=16,
    rotation=(0.0, 0.0, 0.0),
    scale=(1.0, 1.0, 1.0),
    smooth_shading=True,
):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = keep(bpy.context.object, name, mat, parent)
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return smooth(obj) if smooth_shading else obj


def cone(
    name: str,
    location,
    radius1: float,
    radius2: float,
    depth: float,
    mat,
    parent,
    vertices=16,
    rotation=(0.0, 0.0, 0.0),
):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius1,
        radius2=radius2,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    return smooth(keep(bpy.context.object, name, mat, parent))


def torus(
    name: str,
    location,
    major_radius: float,
    minor_radius: float,
    mat,
    parent,
    rotation=(0.0, 0.0, 0.0),
    major_segments=24,
    minor_segments=8,
):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=major_segments,
        minor_segments=minor_segments,
        location=location,
        rotation=rotation,
    )
    return smooth(keep(bpy.context.object, name, mat, parent))


def lathe_z(
    name: str,
    profile: list[tuple[float, float]],
    mat,
    parent,
    segments=20,
    smooth_shading=True,
):
    verts: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for radius, z in profile:
        for index in range(segments):
            angle = index / segments * math.tau
            verts.append((math.cos(angle) * radius, math.sin(angle) * radius, z))
    for row in range(len(profile) - 1):
        for index in range(segments):
            nxt = (index + 1) % segments
            a = row * segments + index
            b = row * segments + nxt
            c = (row + 1) * segments + nxt
            d = (row + 1) * segments + index
            faces.append((a, b, c, d))
    faces.append(tuple(range(segments - 1, -1, -1)))
    top = (len(profile) - 1) * segments
    faces.append(tuple(top + i for i in range(segments)))
    obj = mesh_object(name, verts, faces, mat, parent)
    return smooth(obj) if smooth_shading else obj


def prism_xz(
    name: str,
    outline: list[tuple[float, float]],
    y: float,
    thickness: float,
    mat,
    parent,
    bevel_width=0.0,
):
    half = thickness / 2
    verts = [(x, y - half, z) for x, z in outline] + [(x, y + half, z) for x, z in outline]
    count = len(outline)
    faces: list[tuple[int, ...]] = [
        tuple(range(count - 1, -1, -1)),
        tuple(count + i for i in range(count)),
    ]
    for i in range(count):
        j = (i + 1) % count
        faces.append((i, j, count + j, count + i))
    obj = mesh_object(name, verts, faces, mat, parent)
    if bevel_width:
        bevel(obj, bevel_width, 4)
        smooth(obj)
    return obj


def star_prism(
    name: str,
    center: tuple[float, float],
    outer: float,
    inner: float,
    y: float,
    thickness: float,
    mat,
    parent,
    points=8,
):
    outline: list[tuple[float, float]] = []
    cx, cz = center
    for index in range(points * 2):
        angle = math.pi / 2 + index * math.pi / points
        radius = outer if index % 2 == 0 else inner
        outline.append((cx + math.cos(angle) * radius, cz + math.sin(angle) * radius))
    return prism_xz(name, outline, y, thickness, mat, parent, 0.004)


def curved_cape(
    name: str,
    outline: list[tuple[float, float]],
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    thickness: float = 0.024,
) -> bpy.types.Object:
    """Dense, softly bowed cloth grid for runtime wind deformation."""
    del outline
    rows = 21
    cols = 23
    verts: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for row in range(rows):
        v = row / (rows - 1)
        z = 0.15 - 0.89 * v
        if v < 0.12:
            width = 0.012 + (0.14 - 0.012) * (v / 0.12)
        elif v < 0.50:
            width = 0.14 + (0.54 - 0.14) * ((v - 0.12) / 0.38)
        else:
            width = 0.54 + (0.012 - 0.54) * ((v - 0.50) / 0.50)
        for col in range(cols):
            u = col / (cols - 1) * 2 - 1
            x = u * width
            shoulder_bow = 0.062 + 0.082 * max(0.0, 1.0 - abs(u))
            drape = 0.026 * v * v
            verts.append((x, shoulder_bow + drape, z))
    for row in range(rows - 1):
        for col in range(cols - 1):
            a = row * cols + col
            b = a + 1
            d = (row + 1) * cols + col
            e = d + 1
            faces.append((a, d, e, b))
    obj = mesh_object(name, verts, faces, mat, parent)
    smooth(obj)
    solidify = obj.modifiers.new("Fine cloth thickness", "SOLIDIFY")
    solidify.thickness = thickness
    solidify.offset = 0.0
    solidify.use_rim = True
    return obj


# Legs: the small offset and unequal foot angles preserve the relaxed,
# hand-drawn stance of the selected concept instead of a mirrored toy pose.
for side, x in (("L", -0.15), ("R", 0.135)):
    leg = empty(f"leg{side}", (x, 0.0, 0.46), contact)
    cone(
        f"Trouser_{side}",
        (0, 0.012, -0.12),
        0.17,
        0.118,
        0.30,
        MATS["brown"],
        leg,
        vertices=16,
    )
    cylinder(
        f"BootCuff_{side}",
        (0, -0.018, -0.31),
        0.10,
        0.10,
        MATS["brown_light"],
        leg,
        vertices=16,
    )
    boot = prism_xz(
        f"Boot_{side}",
        [(-0.115, -0.35), (0.105, -0.35), (0.13, -0.40), (0.11, -0.47), (-0.12, -0.47)],
        -0.075,
        0.30,
        MATS["brown"],
        leg,
        0.032,
    )
    boot.rotation_euler.z = 0.075 if side == "L" else -0.025


core = empty("core", parent=contact)

# The coat is a faceted A-line panel instead of a round body.
prism_xz(
    "Coat",
    [
        (-0.325, 0.35),
        (-0.35, 0.43),
        (-0.285, 0.65),
        (-0.215, 0.89),
        (0.195, 0.88),
        (0.275, 0.63),
        (0.32, 0.44),
        (0.275, 0.37),
    ],
    -0.015,
    0.43,
    MATS["coat"],
    core,
    0.035,
)
prism_xz(
    "CoatHem",
    [(-0.30, 0.365), (-0.335, 0.42), (0.335, 0.42), (0.30, 0.365)],
    -0.018,
    0.435,
    MATS["coat_shadow"],
    core,
    0.02,
)
prism_xz(
    "Belt",
    [(-0.285, 0.595), (0.285, 0.605), (0.282, 0.665), (-0.288, 0.655)],
    -0.225,
    0.035,
    MATS["brown"],
    core,
    0.012,
)

# Front coat overlap and center seam keep the broad volume readable.
prism_xz(
    "CoatFrontSeam",
    [(0.026, 0.38), (0.042, 0.38), (0.035, 0.61), (0.019, 0.61)],
    -0.239,
    0.008,
    MATS["coat_shadow"],
    core,
    0.002,
)

# Shoulder mantle under the rope collar.
prism_xz(
    "ShoulderMantle",
    [(-0.27, 0.77), (-0.205, 0.95), (0.19, 0.94), (0.245, 0.77), (-0.025, 0.715)],
    -0.01,
    0.40,
    MATS["coat_light"],
    core,
    0.026,
)

# Four-point navy cape, bowed around the back like cloth.
cape = empty("cape", (0, 0.22, 0.95), core)
cape_outline = [
    (-0.14, 0.06),
    (0.0, 0.15),
    (0.14, 0.06),
    (0.51, -0.27),
    (0.40, -0.37),
    (0.10, -0.52),
    (-0.025, -0.72),
    (-0.13, -0.54),
    (-0.44, -0.40),
    (-0.57, -0.32),
]
curved_cape("CompassCape", cape_outline, MATS["cape"], cape)
for suffix, outline in (
    ("Left", [(-0.52, -0.29), (-0.40, -0.31), (-0.43, -0.39)]),
    ("Right", [(0.52, -0.29), (0.40, -0.31), (0.43, -0.39)]),
    ("Bottom", [(0, -0.74), (-0.055, -0.61), (0.055, -0.61)]),
):
    prism_xz(f"CapeGoldTip_{suffix}", outline, 0.17, 0.025, MATS["gold"], cape, 0.003)
star_prism("CapeNorthStar", (0, -0.32), 0.11, 0.038, 0.18, 0.03, MATS["gold_light"], cape)

# A few large stitch marks communicate handmade cloth without visual noise.
for side in (-1, 1):
    for index in range(4):
        x = side * (0.18 + index * 0.075)
        z = -0.12 - index * 0.06
        prism_xz(
            f"CapeStitch_{'L' if side < 0 else 'R'}_{index + 1}",
            [(x - 0.026, z - 0.006), (x + 0.026, z - 0.006), (x + 0.026, z + 0.006), (x - 0.026, z + 0.006)],
        0.17,
        0.022,
        MATS["gold"],
        cape,
        )

for index in range(4):
    z = -0.43 - index * 0.067
    prism_xz(
        f"CapeStitch_C_{index + 1}",
        [(-0.006, z - 0.025), (0.006, z - 0.025), (0.006, z + 0.025), (-0.006, z + 0.025)],
        0.17,
        0.022,
        MATS["gold"],
        cape,
    )
star_prism("CapeTailCompass", (0, -0.625), 0.036, 0.012, 0.18, 0.022, MATS["gold_light"], cape, points=4)


# Hood/head pivot.  The long swept peak is the concept's defining asymmetry.
head = empty("head", (0, -0.005, 1.0), core)
hood_profile = [
    (0.22, -0.055, 0.0),
    (0.225, 0.04, -0.012),
    (0.198, 0.16, -0.055),
    (0.16, 0.28, -0.125),
    (0.105, 0.39, -0.215),
    (0.052, 0.49, -0.30),
    (0.008, 0.58, -0.355),
]
hood_verts: list[tuple[float, float, float]] = []
hood_faces: list[tuple[int, ...]] = []
hood_segments = 20
for radius, z, center_x in hood_profile:
    for index in range(hood_segments):
        angle = index / hood_segments * math.tau
        hood_verts.append((center_x + math.cos(angle) * radius, math.sin(angle) * radius, z))
for row in range(len(hood_profile) - 1):
    for index in range(hood_segments):
        nxt = (index + 1) % hood_segments
        a = row * hood_segments + index
        b = row * hood_segments + nxt
        c = (row + 1) * hood_segments + nxt
        d = (row + 1) * hood_segments + index
        hood_faces.append((a, b, c, d))
hood_obj = smooth(mesh_object("Hood_Peak", hood_verts, hood_faces, MATS["coat_light"], head))
bevel(hood_obj, 0.006, 2)

# A raised terracotta lip makes the black face read as an opening, not a plaque.
opening_outer = [
    (-0.155, 0.005),
    (-0.147, 0.19),
    (-0.105, 0.34),
    (-0.035, 0.425),
    (0.062, 0.355),
    (0.13, 0.205),
    (0.142, 0.005),
]
opening_inner = [
    (-0.126, 0.025),
    (-0.12, 0.18),
    (-0.08, 0.305),
    (-0.027, 0.365),
    (0.047, 0.31),
    (0.103, 0.18),
    (0.115, 0.025),
]
prism_xz("HoodOpeningRim", opening_outer, -0.236, 0.028, MATS["coat_shadow"], head, 0.014)
prism_xz("FaceVoid", opening_inner, -0.258, 0.025, MATS["face"], head, 0.014)
for side in (-1, 1):
    is_left = side < 0
    cylinder(
        f"Eye_{'L' if side < 0 else 'R'}",
        ((-0.057 if is_left else 0.042), -0.282, 0.205 if is_left else 0.212),
        0.019 if is_left else 0.022,
        0.007,
        MATS["eyes"],
        head,
        vertices=24,
        rotation=(math.pi / 2, 0, 0),
    )

# Rope collar: a visible braided arc across the chest, with side returns.
for index in range(13):
    t = index / 12
    x = -0.195 + t * 0.39
    y = -0.258 + abs(t - 0.5) * 0.035
    z = 0.985 + ((abs(t - 0.5) / 0.5) ** 1.7) * 0.045
    bead = uv_sphere(
        f"RopeSegment_{index + 1:02}",
        (x, y, z),
        (0.037, 0.025, 0.023),
        MATS["cream"],
        core,
        segments=10,
        rings=7,
        smooth_shading=True,
    )
    bead.rotation_euler.y = (t - 0.5) * 0.35
    bead.rotation_euler.z = (-1 if index % 2 else 1) * 0.42

# Chest compass clasp, facing the character's front (-Y).
cylinder(
    "CompassClaspRim",
    (0, -0.296, 0.89),
    0.078,
    0.024,
    MATS["gold"],
    core,
    24,
    rotation=(math.pi / 2, 0, 0),
)
cylinder(
    "CompassClaspFace",
    (0, -0.314, 0.89),
    0.058,
    0.014,
    MATS["cape"],
    core,
    24,
    rotation=(math.pi / 2, 0, 0),
)
star_prism("CompassClaspStar", (0, 0.89), 0.052, 0.016, -0.327, 0.014, MATS["gold_light"], core)

# Broad, slightly off-centre V-shaped pelerine from the concept.
prism_xz(
    "ChestPelerine",
    [(-0.27, 0.87), (-0.18, 0.98), (-0.025, 0.91), (0.16, 0.97), (0.25, 0.87), (-0.02, 0.74)],
    -0.235,
    0.024,
    MATS["coat_light"],
    core,
    0.018,
)

# Coral wind-direction tail.  It is a single strong shape with a diamond cutout
# suggested by a navy insert rather than a fragile boolean hole.
scarf = empty("scarfTail", (0.12, -0.015, 1.02), core)
prism_xz(
    "ScarfTail",
    [(0, 0.01), (0.17, 0.025), (0.39, -0.015), (0.34, -0.085), (0.14, -0.06)],
    -0.075,
    0.028,
    MATS["coral"],
    scarf,
    0.018,
)
prism_xz(
    "ScarfTailCutout",
    [(0.265, -0.025), (0.33, -0.041), (0.302, -0.069), (0.245, -0.054)],
    -0.094,
    0.032,
    MATS["cape"],
    scarf,
    0.003,
)


def make_arm(side: str, x: float) -> bpy.types.Object:
    arm = empty(f"arm{side}", (x, -0.04, 0.84), core)
    outward = -0.032 if side == "L" else 0.032
    prism_xz(
        f"SleeveUpper_{side}",
        [(-0.052, 0.0), (0.052, 0.0), (0.073, -0.22), (0.055, -0.265), (-0.055, -0.265), (-0.073, -0.22)],
        -0.04,
        0.15,
        MATS["coat"],
        arm,
        0.026,
    )
    prism_xz(
        f"SleeveCuff_{side}",
        [(-0.06, -0.245), (0.06, -0.245), (0.064, -0.32), (-0.064, -0.32)],
        -0.045,
        0.155,
        MATS["coat_shadow"],
        arm,
        0.018,
    )
    uv_sphere(
        f"Hand_{side}",
        (outward, -0.018, -0.345),
        (0.066, 0.055, 0.084),
        MATS["brown"],
        arm,
        segments=14,
        rings=9,
        smooth_shading=True,
    )
    thumb_x = outward + (0.047 if side == "L" else -0.047)
    uv_sphere(
        f"Thumb_{side}",
        (thumb_x, -0.033, -0.345),
        (0.026, 0.032, 0.043),
        MATS["brown"],
        arm,
        segments=12,
        rings=8,
        smooth_shading=True,
    )
    if side == "L":
        empty("GripSocket", (0, -0.012, -0.30), arm)
    return arm


arm_l = make_arm("L", -0.335)
arm_r = make_arm("R", 0.315)
arm_l.rotation_euler.z = 0.055
arm_r.rotation_euler.z = -0.135

# Authoring metadata travels with the Blender source and GLB extras.
root["asset_role"] = "main_navigator"
root["design"] = "Polaris Wayfinder"
root["version"] = 5
root["cape_motion"] = "dense_vertex_cloth"
root["has_lantern"] = False
root["front_axis_gltf"] = "+Z"
root["runtime_pivots"] = "core,head,armL,armR,legL,legR,cape,scarfTail,GripSocket"


# Preview stage.
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.005))
floor = bpy.context.object
floor.name = "PREVIEW_Floor"
floor_mat = material("PREVIEW_Background", "#EAE5DC", 1.0)
floor.data.materials.append(floor_mat)

bpy.ops.object.light_add(type="AREA", location=(-3.8, -4.5, 6.0))
key = bpy.context.object
key.name = "PREVIEW_Key"
key.data.energy = 480
key.data.shape = "DISK"
key.data.size = 4.0
key.data.color = rgba("#FFE5C4")[:3]

bpy.ops.object.light_add(type="AREA", location=(4.0, -1.0, 3.5))
fill = bpy.context.object
fill.name = "PREVIEW_Fill"
fill.data.energy = 220
fill.data.size = 3.0
fill.data.color = rgba("#A7C6D8")[:3]

bpy.ops.object.light_add(type="AREA", location=(0, 4.0, 4.5))
rim = bpy.context.object
rim.name = "PREVIEW_Rim"
rim.data.energy = 320
rim.data.size = 3.0
rim.data.color = rgba("#FFD1A3")[:3]


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.object.camera_add(location=(1.55, -6.2, 2.25))
camera = bpy.context.object
camera.name = "PREVIEW_Camera"
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.95
camera.data.lens = 55
look_at(camera, (0, 0, 0.76))

scene = bpy.context.scene
scene.camera = camera
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1200
scene.render.resolution_y = 1200
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.render.filepath = str(RENDER_PATH)
scene.world.color = rgba("#EAE5DC")[:3]
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "Medium High Contrast"

BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
USDZ_PATH.parent.mkdir(parents=True, exist_ok=True)
RENDER_PATH.parent.mkdir(parents=True, exist_ok=True)

bpy.ops.render.render(write_still=True)

# Back check: the cape emblem and compass silhouette are equally important.
root.rotation_euler.z = math.pi
scene.render.filepath = str(BACK_RENDER_PATH)
bpy.ops.render.render(write_still=True)
root.rotation_euler.z = 0
scene.render.filepath = str(RENDER_PATH)

# Save the neutral, game-facing transform after both visual checks.
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

# GLB: select the asset hierarchy only.  Exported empties are the animation rig.
bpy.ops.object.select_all(action="DESELECT")
for obj in asset_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = root
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
    export_animations=False,
)
# Preserve the canonical path for old builds while new builds use the
# versioned URL and therefore cannot receive a stale CDN/browser response.
shutil.copy2(GLB_PATH, GLB_COMPAT_PATH)

# SceneKit reads USDZ directly.  Preserve the same named transform hierarchy.
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

print(f"Saved Blender source: {BLEND_PATH}")
print(f"Exported GLB: {GLB_PATH}")
print(f"Updated compatibility GLB: {GLB_COMPAT_PATH}")
print(f"Exported USDZ: {USDZ_PATH}")
print(f"Rendered preview: {RENDER_PATH}")
print(f"Rendered back preview: {BACK_RENDER_PATH}")
