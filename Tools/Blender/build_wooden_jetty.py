"""Build Landfall's social harbor arrival jetty.

The jetty is deliberately shorter than the first long-pier revision and hands
arrivals to a low side float. Continuous double rope rails, a clearly framed
boarding gate, deep driven piles, and submerged cross-bracing make the harbor
safe without reading as a featureless bridge.

Everything here stays inside the island's flat-shaded, untextured vocabulary:
no image maps, no smooth normals, only solid colours and real geometry. Depth
comes from three deliberate choices instead. First, a palette built as a value
ladder, so the deck is the lightest wood in the model, the piles sit a clear
step below it, and the framing under the boards is nearly black. Second, a
banded waterline: every pile is driven as four stacked segments — bleached
above the splash line, dark and saturated through the tide band, a fouled
encrustation shelf, then near-black timber below. Third, joinery that casts its
own contact shadows: an edge fascia behind the plank ends, bolsters on the pile
heads, iron bands and bolts at the joints, and rope lashings at the rails.

One deterministic build emits the editable Blender source, runtime USDZ, and a
review render.

The deck span, deck height, rail line, boarding gate and footprint are consumed
verbatim by HomeIslandMetrics in Swift. Treat every number in this file's
"authored geometry" section as fixed.
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "Assets3D/source/wooden_jetty.blend"
USDZ_PATH = ROOT / "Landfall/Resources/wooden_jetty.usdz"
RENDER_PATH = ROOT / "marketing/3d/wooden-jetty.png"
RNG = random.Random(42173)


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float = 0.94,
    *,
    metallic: float = 0.0,
) -> bpy.types.Material:
    value = bpy.data.materials.new(name)
    value.diffuse_color = rgba(color)
    value.use_nodes = True
    shader = next(node for node in value.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = rgba(color)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    return value


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

# A value ladder, not five shades of tan. Reading top to bottom these run from
# the lightest thing in the model (rope and the walked centre boards) down to
# the framing, which is meant to read as shadow even when it is lit.
MATS = {
    # Deck: the walking plane is the brightest wood, so it separates from the
    # structure below it at a glance and carries the eye down the pier.
    "deck_worn": material("LF_JettyDeckWorn", "#A89479", 0.97),
    "deck": material("LF_JettyDeck", "#8E7550", 0.96),
    "deck_grey": material("LF_JettyDeckGrey", "#75613F", 0.98),
    "deck_new": material("LF_JettyDeckNew", "#8F6B3E", 0.93),
    # Piles: a cooler, clearly darker ladder that never merges with the deck.
    "pile_sun": material("LF_JettyPileSun", "#5E5648", 0.98),
    "pile_wet": material("LF_JettyPileWet", "#443023", 0.90),
    "pile_deep": material("LF_JettyPileDeep", "#2A2A21", 0.95),
    "weed": material("LF_JettyWeed", "#3A4A33", 1.0),
    "barnacle": material("LF_JettyBarnacle", "#8B8471", 0.99),
    # Framing: the darkest wood in the model. Everything the deck sits on.
    "frame": material("LF_JettyFrame", "#3A2A1E", 0.98),
    "frame_deep": material("LF_JettyFrameDeep", "#241A14", 0.99),
    # Cordage and ironwork.
    "rope": material("LF_JettyRope", "#C3AB7C", 0.99),
    "rope_dark": material("LF_JettyRopeDark", "#8A6F49", 0.99),
    "iron": material("LF_JettyIron", "#20272A", 0.72, metallic=0.35),
    "rust": material("LF_JettyRust", "#6E4028", 0.90, metallic=0.12),
    "moss": material("LF_JettyMoss", "#4A6144", 1.0),
}

root = bpy.data.objects.new("Wooden_Jetty", None)
bpy.context.collection.objects.link(root)
asset_objects: list[bpy.types.Object] = []


def keep(obj: bpy.types.Object, name: str, mat: bpy.types.Material) -> bpy.types.Object:
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    if not obj.data.materials:
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
    mesh.validate(clean_customdata=False)
    mesh.update()
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
    bevel: float = 0.012,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        modifier = obj.modifiers.new(name="Tide-worn edges", type="BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.rotation_euler = rotation
    return keep(obj, name, mat)


def add_cylinder(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    mat: bpy.types.Material,
    *,
    vertices: int = 8,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    return keep(bpy.context.object, name, mat)


def add_beam(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius: float,
    mat: bpy.types.Material,
    *,
    vertices: int = 7,
) -> bpy.types.Object:
    a = Vector(start)
    b = Vector(end)
    direction = b - a
    obj = add_cylinder(name, tuple((a + b) * 0.5), radius, direction.length, mat, vertices=vertices)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return obj


def add_torus(
    name: str,
    location: tuple[float, float, float],
    major_radius: float,
    minor_radius: float,
    mat: bpy.types.Material,
    *,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    major_segments: int = 10,
    minor_segments: int = 3,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=major_segments,
        minor_segments=minor_segments,
        location=location,
        rotation=rotation,
    )
    return keep(bpy.context.object, name, mat)


def add_rope(
    name: str,
    points: list[tuple[float, float, float]],
    radius: float,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(f"{name}_Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = radius
    curve.bevel_resolution = 0
    curve.resolution_u = 2
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, coordinate in zip(spline.bezier_points, points):
        point.co = coordinate
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    obj.data.name = f"{name}_Mesh"
    obj.parent = root
    asset_objects.append(obj)
    return obj


# ---------------------------------------------------------------------------
# Authored geometry. Swift's HomeIslandMetrics hardcodes every value below.
# Walking, boarding and placement all break if any of them move.
# ---------------------------------------------------------------------------
# Low shore ramp: local -Y is land, +Y points out toward the water. A little
# over twice the original span gives boats room to berth without separating
# the gathering place from the island.
deck_start = -1.75
legacy_deck_length = 3.90
deck_length = legacy_deck_length * 2.35
deck_end = deck_start + deck_length
deck_height = 0.39
# Roughly where the preview sea plane and the in-game water sit. Only used to
# place the pile banding; no Swift constant depends on it.
water_level = 0.0
plank_count = 50
spacing = (deck_end - deck_start) / plank_count

# The deck is laid as three courses across, so the most-walked centre band can
# be silvered while the outer boards stay darker. A handful of rows are single
# full-width replacement boards in fresher timber, which is also what breaks up
# the butt-joint grid.
replaced_rows = {12, 34}


def board_tone(y: float, jitter: float) -> bpy.types.Material:
    """Landward boards stay dry and warm; seaward boards silver off in spray."""
    reach = (y - deck_start) / deck_length + jitter
    if reach > 0.66:
        return MATS["deck_grey"]
    if reach > 0.27:
        return MATS["deck"]
    return MATS["deck_worn"]


for index in range(plank_count):
    y = deck_start + (index + 0.5) * spacing
    x_shift = RNG.uniform(-0.028, 0.028)
    z_shift = RNG.uniform(-0.009, 0.009)
    yaw = RNG.uniform(-0.018, 0.018)
    width = RNG.uniform(1.23, 1.36)
    if index in replaced_rows:
        # A board that was pulled and renewed: one piece, no butt joints, and
        # noticeably fresher than the timber either side of it.
        add_box(
            f"Deck_Replacement_{index + 1:02}",
            (x_shift, y, deck_height + z_shift),
            (width, spacing * 0.86, 0.105),
            MATS["deck_new"],
            (RNG.uniform(-0.006, 0.006), 0, yaw),
            0.016,
        )
        continue
    # Staggered butt joints. The seams wander so the deck never reads as a grid,
    # and the 12 mm gaps show the near-black framing underneath as shadow lines.
    left_seam = -RNG.uniform(0.20, 0.34)
    right_seam = RNG.uniform(0.20, 0.34)
    courses = (
        ("L", -width * 0.5, left_seam, board_tone(y, RNG.uniform(-0.14, 0.14))),
        (
            "C",
            left_seam,
            right_seam,
            MATS["deck_worn"] if RNG.random() < 0.74 else board_tone(y, 0.0),
        ),
        ("R", right_seam, width * 0.5, board_tone(y, RNG.uniform(-0.14, 0.14))),
    )
    for course, inner, outer, mat in courses:
        span = outer - inner - 0.012
        add_box(
            f"Deck_Board_{index + 1:02}_{course}",
            ((inner + outer) * 0.5 + x_shift, y, deck_height + z_shift + RNG.uniform(-0.005, 0.005)),
            (span, spacing * 0.84, 0.105),
            mat,
            (RNG.uniform(-0.008, 0.008), 0, yaw + RNG.uniform(-0.006, 0.006)),
            0.014,
        )

# A two-board approach slopes down to the island surface.
for index, (y, z, pitch) in enumerate(((-1.93, 0.30, -0.18), (-2.12, 0.19, -0.23))):
    add_box(
        f"Shore_Ramp_{index + 1:02}",
        (0, y, z),
        (1.30, 0.35, 0.105),
        MATS["deck"] if index == 0 else MATS["deck_grey"],
        (pitch, 0, RNG.uniform(-0.01, 0.01)),
        0.018,
    )

# Understructure stays visible between the piles and now runs the full span.
deck_center = (deck_start + deck_end) * 0.5
for x in (-0.47, 0.47):
    add_box(
        f"Long_Stringer_{'L' if x < 0 else 'R'}",
        (x, deck_center, 0.25),
        (0.13, deck_length + 0.15, 0.16),
        MATS["frame_deep"],
        bevel=0.014,
    )

# Edge fascia. It tucks just under the plank ends rather than covering them, so
# the deck reads as a rhythm of lit board ends sitting on one unbroken dark
# band. This is the cheapest contact shadow in the model.
for x in (-0.655, 0.655):
    add_box(
        f"Edge_Fascia_{'L' if x < 0 else 'R'}",
        (x, deck_center, 0.2625),
        (0.055, deck_length + 0.02, 0.145),
        MATS["frame"],
        bevel=0.012,
    )

post_spacing = 1.25
post_ys = tuple(
    deck_start + 0.25 + index * post_spacing
    for index in range(8)
)
for index, y in enumerate(post_ys):
    add_box(
        f"Cross_Beam_{index + 1:02}",
        (0, y, 0.21),
        (1.50, 0.14, 0.15),
        MATS["frame"],
        (0, 0, RNG.uniform(-0.015, 0.015)),
        0.014,
    )

# Piles are visibly driven well below the water line, and each one is built as
# four stacked segments so the sea leaves a mark on it: bleached timber above
# the splash line, a dark saturated tide band, a fouled shelf that steps proud
# of the shaft, then near-black wood the rest of the way down.
pile_top = 1.10
pile_bottom = -3.20
splash_top = water_level + 0.28
tide_bottom = water_level - 0.22
# The fouled shelf deliberately straddles the surface. Half of it shows above
# the water as a step proud of the shaft, which is the whole point: it is the
# one silhouette break that says this timber lives in the sea.
growth_top = water_level + 0.075
growth_bottom = water_level - 0.30
pile_heads: list[tuple[float, float, float]] = []
for row, y in enumerate(post_ys):
    for x in (-0.72, 0.72):
        side = "L" if x < 0 else "R"
        radius = 0.105 if row % 3 else 0.115
        # Each pile was driven a little off plumb. The head stays exactly on the
        # authored rail line; only the buried foot wanders.
        foot = Vector((x + RNG.uniform(-0.030, 0.030), y + RNG.uniform(-0.030, 0.030), pile_bottom))
        head = Vector((x, y, pile_top))

        def at(z: float, foot: Vector = foot, head: Vector = head) -> tuple[float, float, float]:
            t = (z - foot.z) / (head.z - foot.z)
            point = foot.lerp(head, t)
            return (point.x, point.y, point.z)

        add_beam(
            f"Pile_Sun_{row + 1:02}_{side}",
            at(splash_top),
            at(pile_top),
            radius,
            MATS["pile_sun"],
            vertices=9,
        )
        add_beam(
            f"Pile_Tide_{row + 1:02}_{side}",
            at(tide_bottom),
            at(splash_top),
            radius * 1.02,
            MATS["pile_wet"],
            vertices=9,
        )
        add_beam(
            f"Pile_Growth_{row + 1:02}_{side}",
            at(growth_bottom),
            at(growth_top),
            radius + 0.036,
            MATS["weed"],
            vertices=9,
        )
        add_beam(
            f"Pile_Deep_{row + 1:02}_{side}",
            at(pile_bottom),
            at(tide_bottom),
            radius * 1.04,
            MATS["pile_deep"],
            vertices=9,
        )
        pile_heads.append((x, y, radius))

        # Barnacle crust on the seaward faces of the outer piles only.
        if row % 2 == 0:
            for nub in range(2):
                angle = RNG.uniform(0.0, math.tau)
                z = RNG.uniform(growth_top - 0.06, growth_top + 0.14)
                shaft = at(z)
                inner = radius + 0.012
                outer = radius + 0.040
                add_beam(
                    f"Pile_Barnacle_{row + 1:02}_{side}_{nub + 1}",
                    (shaft[0] + math.cos(angle) * inner, shaft[1] + math.sin(angle) * inner, z),
                    (shaft[0] + math.cos(angle) * outer, shaft[1] + math.sin(angle) * outer, z + 0.018),
                    RNG.uniform(0.016, 0.026),
                    MATS["barnacle"],
                    vertices=5,
                )

# Joinery at the pile heads. A bolster under the deck, an iron band round the
# head and a bolt through the cross beam give every joint its own small forms
# to catch light against, which is what stops a flat-shaded pier reading as one
# extruded block.
for x, y, radius in pile_heads:
    side = "L" if x < 0 else "R"
    tag = f"{side}_{y:+.2f}".replace(".", "p").replace("+", "P").replace("-", "M")
    add_box(
        f"Pile_Bolster_{tag}",
        (x, y, 0.298),
        (0.21, 0.23, 0.095),
        MATS["frame"],
        (0, 0, RNG.uniform(-0.02, 0.02)),
        0.012,
    )
    # The strap sits at deck level, where it would actually pin the toe board
    # and the head of the bolster. Keeping it off the pile top leaves the posts
    # reading as driven timber rather than capped bollards.
    add_cylinder(
        f"Pile_Iron_Band_{tag}",
        (x, y, 0.470),
        radius + 0.019,
        0.040,
        MATS["iron"],
        vertices=9,
    )
    add_beam(
        f"Pile_Bolt_{tag}",
        (x * 1.02, y - 0.10, 0.245),
        (x * 1.02, y + 0.10, 0.245),
        0.024,
        MATS["iron"],
        vertices=6,
    )

# Alternating longitudinal braces are fully submerged but remain visible
# through clear water and in the low arrival camera.
for side, x in (("L", -0.72), ("R", 0.72)):
    for section, (start, end) in enumerate(zip(post_ys[:-1], post_ys[1:])):
        high, low = (-0.30, -1.82) if section % 2 == 0 else (-1.82, -0.30)
        add_beam(
            f"Submerged_Brace_{side}_{section + 1:02}",
            (x, start, high),
            (x, end, low),
            0.050,
            MATS["pile_deep"],
            vertices=7,
        )

for index, y in enumerate(post_ys[1:-1:3]):
    add_beam(
        f"Submerged_Cross_Tie_{index + 1:02}",
        (-0.72, y, -1.70),
        (0.72, y, -1.70),
        0.052,
        MATS["pile_deep"],
        vertices=7,
    )

# Low toe boards remove the ambiguous open strip beneath the rope railing. The
# starboard side has one intentional opening, aligned exactly with the authored
# stair connector to the low boarding float.
gate_start = post_ys[4]
gate_end = post_ys[5]
gate_posts = (gate_start, gate_end)
for side, x in (("L", -0.67), ("R", 0.67)):
    spans = ((deck_start + 0.06, deck_end - 0.06),)
    if side == "R":
        spans = ((deck_start + 0.06, gate_start), (gate_end, deck_end - 0.06))
    for span_index, (start, end) in enumerate(spans, 1):
        add_box(
            f"Toe_Board_{side}_{span_index}",
            (x, (start + end) * 0.5, 0.49),
            (0.085, end - start, 0.16),
            MATS["frame_deep"],
            bevel=0.016,
        )

# Each side is authored as two continuous ropes. Mid-span sag points are part
# of the same curve, so there are no floating endpoints or pass-through gaps.
for side, x in (("L", -0.72), ("R", 0.72)):
    post_spans = (post_ys,)
    if side == "R":
        post_spans = (post_ys[:5], post_ys[5:])
    for span_index, span in enumerate(post_spans, 1):
        upper_points: list[tuple[float, float, float]] = []
        lower_points: list[tuple[float, float, float]] = []
        for section, (start, end) in enumerate(zip(span[:-1], span[1:])):
            if section == 0:
                upper_points.append((x, start, 1.02))
                lower_points.append((x, start, 0.76))
            middle = (start + end) * 0.5
            upper_points.extend(((x, middle, 0.85), (x, end, 1.02)))
            lower_points.extend(((x, middle, 0.65), (x, end, 0.76)))
        if len(upper_points) >= 2:
            add_rope(
                f"Continuous_Upper_Rope_{side}_{span_index}",
                upper_points,
                0.026,
                MATS["rope"],
            )
            add_rope(
                f"Continuous_Lower_Rope_{side}_{span_index}",
                lower_points,
                0.023,
                MATS["rope_dark"],
            )

# Lashings sit where the rails actually meet the posts. The two gate posts get
# extra turns, which is both how a real gate post is served and a quiet way of
# pointing at the boarding opening.
for row, y in enumerate(post_ys):
    for x in (-0.72, 0.72):
        side = "L" if x < 0 else "R"
        radius = (0.105 if row % 3 else 0.115) + 0.014
        heights = [(0.742, MATS["rope_dark"]), (1.026, MATS["rope"])]
        if y in gate_posts:
            heights = [
                (0.712, MATS["rope_dark"]),
                (0.756, MATS["rope_dark"]),
                (0.996, MATS["rope"]),
                (1.040, MATS["rope"]),
            ]
        for wrap, (z, mat) in enumerate(heights):
            add_torus(
                f"Pile_Lashing_{row + 1:02}_{side}_{wrap + 1:02}",
                (x, y, z),
                radius,
                0.017,
                mat,
                rotation=(RNG.uniform(-0.05, 0.05), 0, RNG.uniform(-0.10, 0.10)),
            )

# Nail heads and shallow cracks sell the deck at close range. They sit over the
# outer courses, where the fixings would actually be driven.
for index in range(1, plank_count, 3):
    y = deck_start + (index + 0.5) * spacing
    for side, x in (("L", -0.52), ("R", 0.52)):
        add_cylinder(
            f"Deck_Nail_{index + 1:02}_{side}",
            (x, y, deck_height + 0.058),
            0.017,
            0.016,
            MATS["iron"],
            vertices=6,
        )
crack_specs = [
    (
        RNG.uniform(-0.34, 0.34),
        deck_start + 0.72 + index * (deck_length - 1.44) / 5,
        RNG.uniform(0.22, 0.34),
    )
    for index in range(6)
]
for index, (x, y, length) in enumerate(crack_specs):
    add_beam(
        f"Deck_Crack_{index + 1:02}",
        (x - length * 0.5, y, deck_height + 0.062),
        (x + length * 0.5, y + 0.02, deck_height + 0.062),
        0.009,
        MATS["frame_deep"],
        vertices=5,
    )

# Mooring cleats repeat at useful intervals along the extended berth.
for index, (x, y) in enumerate(((-0.45, 0.16), (0.45, 3.05), (-0.45, 6.65))):
    add_cylinder(f"Cleat_Pin_{index + 1:02}", (x, y, 0.52), 0.027, 0.16, MATS["iron"], vertices=7)
    add_beam(
        f"Cleat_Arm_{index + 1:02}",
        (x - 0.12, y, 0.59),
        (x + 0.12, y, 0.59),
        0.030,
        MATS["iron"],
        vertices=7,
    )

coil_y = 5.65
for index, radius in enumerate((0.12, 0.16, 0.20, 0.235)):
    add_torus(
        f"Rope_Coil_{index + 1:02}",
        (0.27 + index * 0.008, coil_y - index * 0.012, 0.468 + index * 0.004),
        radius,
        0.018,
        MATS["rope"] if index % 2 else MATS["rope_dark"],
        rotation=(0, 0, 0.15 + index * 0.08),
        major_segments=12,
    )

# One rope fender hung over the port side between piles. It stays well inside
# the authored footprint and gives the long rail run a single point of interest.
add_beam(
    "Fender_Lanyard",
    (-0.66, 1.62, 0.560),
    (-0.755, 1.62, 0.330),
    0.017,
    MATS["rope_dark"],
    vertices=5,
)
add_cylinder(
    "Fender_Body",
    (-0.755, 1.62, 0.185),
    0.072,
    0.290,
    MATS["rope_dark"],
    vertices=8,
)

# Seaward ladder reaches below deck height without increasing the placement footprint.
for x in (-0.25, 0.25):
    add_beam(
        f"Ladder_Rail_{'L' if x < 0 else 'R'}",
        (x, deck_end + 0.03, 0.52),
        (x, deck_end + 0.15, -0.30),
        0.032,
        MATS["rust"],
        vertices=7,
    )
for index, z in enumerate((0.12, 0.28, 0.44)):
    add_beam(
        f"Ladder_Rung_{index + 1:02}",
        (-0.25, deck_end + 0.125 - z * 0.12, z - 0.20),
        (0.25, deck_end + 0.125 - z * 0.12, z - 0.20),
        0.026,
        MATS["rust"],
        vertices=7,
    )

# Small moss straps around the landward piles blend the prop into grassy islands.
for index, (x, y) in enumerate(((-0.72, -1.50), (0.72, -1.50), (-0.72, -0.43))):
    add_torus(
        f"Pile_Moss_{index + 1:02}",
        (x, y, 0.12 + index * 0.018),
        0.108,
        0.026,
        MATS["moss"],
        rotation=(0.06 * (index - 1), 0, 0.10 * index),
    )


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_preview_stage() -> None:
    sea_mat = material("PREVIEW_Sea", "#225D53", 0.76)
    shore_mat = material("PREVIEW_Shore", "#788573", 1.0)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 5.5, -0.025))
    sea = bpy.context.object
    sea.name = "PREVIEW_Sea"
    sea.data.materials.append(sea_mat)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -2.80, -0.02))
    shore = bpy.context.object
    shore.name = "PREVIEW_Shore"
    shore.dimensions = (8.0, 2.0, 0.14)
    shore.data.materials.append(shore_mat)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#183F3A")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.20

    # Energies are tuned so the review render lands in the same exposure band as
    # the sibling harbor props (darks near 110, deck near 205 of 255). The old
    # values pushed the whole model into 165-225, which flattened every material
    # in the palette into the same near-white and made the asset unjudgeable.
    lights = (
        ("PREVIEW_Key", (-5.0, -5.5, 7.0), 330, 5.4, "#FFE4B8"),
        ("PREVIEW_Fill", (5.3, -1.8, 3.8), 150, 4.6, "#72B29C"),
        ("PREVIEW_Rim", (2.8, 5.2, 4.8), 250, 3.8, "#B9D6C6"),
    )
    for name, location, energy, size, color in lights:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = rgba(color)[:3]
        look_at(light, (0, 2.7, 0.15))

    bpy.ops.object.camera_add(location=(8.6, -7.8, 8.4))
    camera = bpy.context.object
    camera.name = "PREVIEW_Camera"
    camera.data.lens = 57
    look_at(camera, (0, 2.8, 0.18))
    bpy.context.scene.camera = camera


add_preview_stage()

BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
USDZ_PATH.parent.mkdir(parents=True, exist_ok=True)
RENDER_PATH.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

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
scene.render.image_settings.color_depth = "8"
scene.view_settings.look = "AgX - Medium High Contrast"
bpy.ops.render.render(write_still=True)

triangles = sum(
    len(polygon.vertices) - 2
    for obj in export_objects
    for polygon in obj.data.polygons
)
print(f"ASSET={root.name} MESHES={len(export_objects)} TRIANGLES={triangles}")
print(f"BLEND={BLEND_PATH}")
print(f"USDZ={USDZ_PATH}")
print(f"RENDER={RENDER_PATH}")
