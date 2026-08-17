"""Build ten compact low-poly props for KeelMira's Home Island.

The script is deterministic and deliberately writes outside the runtime bundle:
editable Blender sources go to ``Assets3D/source``, integration-ready USDZ files
go to ``Assets3D/ready``, and square review renders go to ``marketing/3d``.
Nothing is copied into ``Landfall/Resources`` by this builder.
"""

from __future__ import annotations

import math
import os
import random
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "Assets3D/source"
READY_DIR = ROOT / "Assets3D/ready"
RENDER_DIR = ROOT / "marketing/3d"
RNG = random.Random(81026)


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[index:index + 2], 16) / 255 for index in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float = 0.96,
    *,
    metallic: float = 0.0,
    emission: str | None = None,
    emission_strength: float = 0.0,
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
    if emission:
        emission_input = shader.inputs.get("Emission Color") or shader.inputs.get("Emission")
        if emission_input is not None:
            emission_input.default_value = rgba(emission)
        strength_input = shader.inputs.get("Emission Strength")
        if strength_input is not None:
            strength_input.default_value = emission_strength
    return value


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.materials,
    ):
        for block in list(collection):
            collection.remove(block)


def make_root(asset_id: str, display_name: str, size_class: str = "small") -> bpy.types.Object:
    root = bpy.data.objects.new(display_name, None)
    root["asset_id"] = asset_id
    root["size_class"] = size_class
    root["integration_status"] = "not_integrated"
    root["ground_plane_z"] = 0.0
    bpy.context.collection.objects.link(root)
    return root


def add_socket(
    name: str,
    location: tuple[float, float, float],
    root: bpy.types.Object,
    *,
    slot_id: str,
    purpose: str,
) -> bpy.types.Object:
    socket = bpy.data.objects.new(name, None)
    socket.location = location
    socket.empty_display_type = "ARROWS"
    socket.empty_display_size = 0.16
    socket.parent = root
    socket["seat_slot_id"] = slot_id
    socket["seat_socket_purpose"] = purpose
    socket["seat_facing_axis"] = "-Y"
    bpy.context.collection.objects.link(socket)
    return socket


def keep(
    obj: bpy.types.Object,
    name: str,
    mat: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
) -> bpy.types.Object:
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    if not obj.data.materials:
        obj.data.materials.append(mat)
    obj.parent = root
    objects.append(obj)
    if obj.type == "MESH":
        for polygon in obj.data.polygons:
            polygon.use_smooth = False
    return obj


def mesh_object(
    name: str,
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    mat: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(mat)
    mesh.validate(clean_customdata=False)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return keep(obj, name, mat, root, objects)


def add_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    mat: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    *,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel: float = 0.014,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        modifier = obj.modifiers.new(name="Hand-worn edges", type="BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.rotation_euler = rotation
    return keep(obj, name, mat, root, objects)


def add_cylinder(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    mat: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    *,
    vertices: int = 10,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    return keep(bpy.context.object, name, mat, root, objects)


def add_cone(
    name: str,
    location: tuple[float, float, float],
    radius1: float,
    radius2: float,
    depth: float,
    mat: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    *,
    vertices: int = 10,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius1,
        radius2=radius2,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    return keep(bpy.context.object, name, mat, root, objects)


def add_torus(
    name: str,
    location: tuple[float, float, float],
    major_radius: float,
    minor_radius: float,
    mat: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    *,
    major_segments: int = 12,
    minor_segments: int = 4,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=major_segments,
        minor_segments=minor_segments,
        location=location,
        rotation=rotation,
    )
    return keep(bpy.context.object, name, mat, root, objects)


def add_ico(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    *,
    subdivisions: int = 1,
    irregularity: float = 0.08,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0, location=location)
    obj = bpy.context.object
    for vertex in obj.data.vertices:
        vertex.co *= RNG.uniform(1.0 - irregularity, 1.0 + irregularity)
    obj.scale = scale
    obj.rotation_euler = (
        RNG.uniform(-0.12, 0.12),
        RNG.uniform(-0.12, 0.12),
        RNG.uniform(-0.35, 0.35),
    )
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return keep(obj, name, mat, root, objects)


def add_beam(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius: float,
    mat: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    *,
    vertices: int = 7,
    end_radius: float | None = None,
) -> bpy.types.Object:
    start_value = Vector(start)
    end_value = Vector(end)
    direction = end_value - start_value
    obj = add_cone(
        name,
        tuple((start_value + end_value) * 0.5),
        radius,
        radius if end_radius is None else end_radius,
        direction.length,
        mat,
        root,
        objects,
        vertices=vertices,
    )
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return obj


def look_at(obj: bpy.types.Object, point: Vector) -> None:
    obj.rotation_euler = (point - obj.location).to_track_quat("-Z", "Y").to_euler()


def bounds_for(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    bpy.context.view_layer.update()
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return low, high


def add_preview_stage(objects: list[bpy.types.Object]) -> None:
    low, high = bounds_for(objects)
    center = (low + high) * 0.5
    dimensions = high - low
    ground_mat = material("PREVIEW_Ground", "#365A51", 1.0)
    bpy.ops.mesh.primitive_plane_add(size=100, location=(0, 0, min(-0.025, low.z - 0.015)))
    ground = bpy.context.object
    ground.name = "PREVIEW_Ground"
    ground.data.materials.append(ground_mat)

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#103A35")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.25

    span = max(dimensions.x, dimensions.y, dimensions.z, 1.0)
    # Lights sit at a multiple of the prop's own span, so their energy has to
    # follow the inverse-square law. Without this a small prop is lit from
    # centimetres away and blows out to white, which makes its colours
    # impossible to judge in review. 2.4 is the span the presets were tuned for.
    exposure = (span / 2.4) ** 2
    for name, offset, energy, size, color in (
        ("PREVIEW_Key", Vector((-1.7, -2.2, 2.5)), 560, 4.2, "#FFE8BB"),
        ("PREVIEW_Fill", Vector((2.0, -0.8, 1.5)), 310, 3.4, "#77C4A5"),
        ("PREVIEW_Rim", Vector((0.8, 2.0, 2.1)), 410, 3.0, "#C8DDD0"),
    ):
        bpy.ops.object.light_add(type="AREA", location=center + offset * span)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy * exposure
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = rgba(color)[:3]
        look_at(light, center)

    bpy.ops.object.camera_add(location=center + Vector((2.5, -3.8, 2.4)) * span)
    camera = bpy.context.object
    camera.name = "PREVIEW_Camera"
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = max(dimensions.x * 1.16, dimensions.y * 1.25, dimensions.z * 1.18, 1.3)
    look_at(camera, center)
    bpy.context.scene.camera = camera


def export_asset(
    asset_id: str,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    sockets: tuple[bpy.types.Object, ...] = (),
) -> None:
    blend_path = SOURCE_DIR / f"{asset_id}.blend"
    usdz_path = READY_DIR / f"{asset_id}.usdz"
    render_path = RENDER_DIR / f"{asset_id.replace('_', '-')}.png"
    for path in (blend_path, usdz_path, render_path):
        path.parent.mkdir(parents=True, exist_ok=True)

    add_preview_stage(objects)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    groups: dict[str, list[bpy.types.Object]] = {}
    for obj in objects:
        if obj.type != "MESH":
            continue
        material_name = obj.data.materials[0].name if obj.data.materials else "Unmaterialed"
        groups.setdefault(material_name, []).append(obj)

    export_objects: list[bpy.types.Object] = []
    for material_name, group in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in group:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = group[0]
        if len(group) > 1:
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
    for socket in sockets:
        socket.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.wm.usd_export(
        filepath=str(usdz_path),
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
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 1000
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.filepath = str(render_path)
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.render.render(write_still=True)

    low, high = bounds_for(export_objects)
    dimensions = high - low
    triangles = sum(len(polygon.vertices) - 2 for obj in export_objects for polygon in obj.data.polygons)
    print(
        f"ASSET={asset_id} MESHES={len(export_objects)} TRIANGLES={triangles} "
        f"DIMS={dimensions.x:.2f}x{dimensions.y:.2f}x{dimensions.z:.2f} "
        f"MIN_Z={low.z:.3f}"
    )
    print(f"BLEND={blend_path}")
    print(f"USDZ={usdz_path}")
    print(f"RENDER={render_path}")


def build_harbor_lantern_post() -> None:
    reset_scene()
    root = make_root("harbor_lantern_post", "Harbor_Lantern_Post")
    objects: list[bpy.types.Object] = []
    mats = {
        "wood_deep": material("LF_LanternPostWoodDeep", "#352923", 0.99),
        "wood": material("LF_LanternPostWood", "#674B35", 0.97),
        "iron": material("LF_LanternPostIron", "#293331", 0.84, metallic=0.22),
        "glass": material("LF_LanternPostGlass", "#6C9B8B", 0.38),
        "glow": material("LF_LanternPostGlow", "#F3C065", 0.28, emission="#FF9A3C", emission_strength=2.4),
        "stone": material("LF_LanternPostStone", "#6F776D", 0.99),
        "moss": material("LF_LanternPostMoss", "#587052", 1.0),
    }
    add_ico("Lantern_Base_Stone", (0, 0, 0.11), (0.47, 0.40, 0.17), mats["stone"], root, objects, irregularity=0.12)
    add_box("Lantern_Post", (0, 0, 1.05), (0.17, 0.17, 1.92), mats["wood"], root, objects, rotation=(0.0, math.radians(-2), math.radians(2)), bevel=0.025)
    add_box("Lantern_Crossarm", (0.27, -0.01, 1.90), (0.70, 0.14, 0.14), mats["wood_deep"], root, objects, rotation=(0, 0, math.radians(-4)), bevel=0.022)
    add_beam("Lantern_Brace", (0.04, 0, 1.64), (0.51, 0, 1.91), 0.045, mats["wood_deep"], root, objects, vertices=6)
    add_beam("Lantern_Hanger", (0.54, 0, 1.88), (0.54, 0, 1.66), 0.018, mats["iron"], root, objects, vertices=6)
    add_cylinder("Lantern_Base", (0.54, 0, 1.48), 0.18, 0.10, mats["iron"], root, objects, vertices=8)
    add_cone("Lantern_Glass", (0.54, 0, 1.59), 0.145, 0.12, 0.24, mats["glass"], root, objects, vertices=8)
    add_ico("Lantern_Glow", (0.54, -0.01, 1.58), (0.075, 0.075, 0.10), mats["glow"], root, objects, irregularity=0.03)
    add_cone("Lantern_Roof", (0.54, 0, 1.76), 0.22, 0.03, 0.18, mats["iron"], root, objects, vertices=8)
    for x, y in ((0.42, 0), (0.66, 0), (0.54, -0.12), (0.54, 0.12)):
        add_beam("Lantern_Cage", (x, y, 1.46), (x, y, 1.73), 0.012, mats["iron"], root, objects, vertices=5)
    add_ico("Lantern_Moss", (-0.12, -0.05, 0.22), (0.20, 0.12, 0.025), mats["moss"], root, objects, irregularity=0.16)
    export_asset("harbor_lantern_post", root, objects)


def build_driftwood_bench() -> None:
    reset_scene()
    root = make_root("driftwood_bench", "Driftwood_Bench")
    root["seat_capacity"] = 2
    root["seat_socket_schema"] = 1
    objects: list[bpy.types.Object] = []
    mats = {
        "deep": material("LF_BenchWoodDeep", "#372B25", 1.0),
        "wood": material("LF_BenchWood", "#6A513D", 0.98),
        "salt": material("LF_BenchSaltWood", "#9A8565", 0.99),
        "iron": material("LF_BenchIron", "#293331", 0.86, metallic=0.19),
        "moss": material("LF_BenchMoss", "#5D7355", 1.0),
    }
    # A true two-person silhouette: the raw model is deliberately long, then
    # placed at 62% in Home Island so it reads naturally beside the navigator.
    for index, (y, z, mat, tilt) in enumerate(((-0.19, 0.57, mats["wood"], 0.012), (0.01, 0.59, mats["salt"], -0.010), (0.21, 0.56, mats["wood"], 0.018)), 1):
        add_box(f"Bench_Seat_{index:02}", (0, y, z), (2.70, 0.18, 0.14), mat, root, objects, rotation=(tilt, 0, RNG.uniform(-0.018, 0.018)), bevel=0.038)
    for index, x in enumerate((-0.96, 0.96), 1):
        add_beam(f"Bench_Leg_Front_{index}", (x, -0.22, 0.04), (x - 0.04, -0.15, 0.53), 0.09, mats["deep"], root, objects, vertices=7)
        add_beam(f"Bench_Leg_Back_{index}", (x, 0.27, 0.04), (x + 0.04, 0.15, 0.53), 0.09, mats["wood"], root, objects, vertices=7)
        add_beam(f"Bench_Back_Post_{index}", (x, 0.21, 0.54), (x + (0.04 if x > 0 else -0.04), 0.28, 1.03), 0.075, mats["deep"], root, objects, vertices=7)
    add_box("Bench_Underseat_Brace", (0, 0.12, 0.36), (2.18, 0.11, 0.13), mats["deep"], root, objects, rotation=(0, 0, math.radians(-0.8)), bevel=0.025)
    add_box("Bench_Backrest_Left", (-0.68, 0.28, 0.92), (1.31, 0.14, 0.27), mats["salt"], root, objects, rotation=(math.radians(-4), 0, math.radians(1.2)), bevel=0.045)
    add_box("Bench_Backrest_Right", (0.68, 0.28, 0.91), (1.31, 0.14, 0.27), mats["wood"], root, objects, rotation=(math.radians(-4), 0, math.radians(-1.0)), bevel=0.045)
    add_beam("Bench_Back_Center_Lashing", (0, 0.20, 0.75), (0, 0.29, 1.04), 0.045, mats["deep"], root, objects, vertices=7)
    for index, x in enumerate((-0.96, 0.96), 1):
        add_cylinder(f"Bench_Peg_{index}", (x, -0.315, 0.59), 0.035, 0.035, mats["iron"], root, objects, vertices=8, rotation=(math.pi / 2, 0, 0))
    add_ico("Bench_Moss", (-0.92, -0.05, 0.66), (0.34, 0.10, 0.025), mats["moss"], root, objects, irregularity=0.15)
    # Stable sockets are exported with the USDZ. Each multiplayer occupant can
    # reserve one `(placement UUID, slot ID)` without sharing a transform.
    seat_left = add_socket(
        "SeatSocket_Left",
        (-0.68, -0.02, 0.65),
        root,
        slot_id="left",
        purpose="seat",
    )
    seat_right = add_socket(
        "SeatSocket_Right",
        (0.68, -0.02, 0.65),
        root,
        slot_id="right",
        purpose="seat",
    )
    # The approach marks where the navigator stands before sitting. At -1.88 it
    # sat a full body-length out from the bench, so sitting meant walking away
    # from it first, and the only spot that triggered a sit was a 7cm ring.
    approach_left = add_socket(
        "SeatApproach_Left",
        (-0.68, -1.30, 0.0),
        root,
        slot_id="left",
        purpose="approach",
    )
    approach_right = add_socket(
        "SeatApproach_Right",
        (0.68, -1.30, 0.0),
        root,
        slot_id="right",
        purpose="approach",
    )
    export_asset(
        "driftwood_bench",
        root,
        objects,
        (seat_left, seat_right, approach_left, approach_right),
    )


def build_weathered_anchor() -> None:
    reset_scene()
    root = make_root("weathered_anchor", "Weathered_Anchor")
    objects: list[bpy.types.Object] = []
    mats = {
        "stone": material("LF_AnchorStone", "#69736D", 0.99),
        "stone_light": material("LF_AnchorStoneLight", "#909486", 0.98),
        "iron": material("LF_AnchorIron", "#293331", 0.82, metallic=0.27),
        "rust": material("LF_AnchorRust", "#744833", 0.94, metallic=0.10),
        "rope": material("LF_AnchorRope", "#9B7B53", 0.99),
        "moss": material("LF_AnchorMoss", "#566E50", 1.0),
    }
    add_ico("Anchor_Plinth", (0, 0.04, 0.14), (0.68, 0.47, 0.23), mats["stone"], root, objects, irregularity=0.13)
    add_ico("Anchor_Plinth_Cap", (0, -0.01, 0.30), (0.49, 0.35, 0.11), mats["stone_light"], root, objects, irregularity=0.08)
    # Anchor is displayed upright in the front plane for a strong placement icon silhouette.
    add_beam("Anchor_Shank", (0, -0.10, 0.36), (0, -0.10, 1.45), 0.085, mats["iron"], root, objects, vertices=8)
    add_beam("Anchor_Stock", (-0.48, -0.10, 1.19), (0.48, -0.10, 1.19), 0.065, mats["rust"], root, objects, vertices=8)
    add_torus("Anchor_Ring", (0, -0.10, 1.57), 0.19, 0.045, mats["iron"], root, objects, major_segments=12, minor_segments=4, rotation=(math.pi / 2, 0, 0))
    add_beam("Anchor_Left_Arm", (0, -0.10, 0.40), (-0.52, -0.10, 0.67), 0.075, mats["iron"], root, objects, vertices=8, end_radius=0.055)
    add_beam("Anchor_Right_Arm", (0, -0.10, 0.40), (0.52, -0.10, 0.67), 0.075, mats["iron"], root, objects, vertices=8, end_radius=0.055)
    add_cone("Anchor_Left_Fluke", (-0.57, -0.10, 0.75), 0.17, 0.03, 0.34, mats["rust"], root, objects, vertices=4, rotation=(0, math.radians(-52), 0))
    add_cone("Anchor_Right_Fluke", (0.57, -0.10, 0.75), 0.17, 0.03, 0.34, mats["rust"], root, objects, vertices=4, rotation=(0, math.radians(52), 0))
    add_torus("Anchor_Rope_Coil_Outer", (0.30, 0.18, 0.37), 0.25, 0.035, mats["rope"], root, objects, major_segments=12, minor_segments=4)
    add_torus("Anchor_Rope_Coil_Inner", (0.30, 0.18, 0.39), 0.16, 0.030, mats["rope"], root, objects, major_segments=12, minor_segments=4)
    add_ico("Anchor_Moss", (-0.27, 0.05, 0.33), (0.22, 0.12, 0.025), mats["moss"], root, objects, irregularity=0.15)
    export_asset("weathered_anchor", root, objects)


def build_net_drying_rack() -> None:
    reset_scene()
    root = make_root("net_drying_rack", "Net_Drying_Rack", "medium")
    objects: list[bpy.types.Object] = []
    mats = {
        "wood_deep": material("LF_NetRackWoodDeep", "#352A24", 1.0),
        "wood": material("LF_NetRackWood", "#6B503A", 0.98),
        "rope": material("LF_NetRackRope", "#A4865F", 0.99),
        "net": material("LF_NetRackNet", "#756F58", 1.0, double_sided=True),
        "float": material("LF_NetRackFloat", "#D36F55", 0.94),
        "sea": material("LF_NetRackSeaGlass", "#4F8175", 0.72),
    }
    for index, x in enumerate((-0.82, 0.82), 1):
        add_beam(f"Rack_Post_{index}", (x, 0, -0.03), (x + (0.04 if x < 0 else -0.04), 0, 1.65), 0.075, mats["wood"], root, objects, vertices=7)
        add_beam(f"Rack_Foot_Front_{index}", (x, -0.42, 0.02), (x, 0, 0.42), 0.055, mats["wood_deep"], root, objects, vertices=7)
        add_beam(f"Rack_Foot_Back_{index}", (x, 0.42, 0.02), (x, 0, 0.42), 0.055, mats["wood_deep"], root, objects, vertices=7)
    add_beam("Rack_Top", (-0.92, 0, 1.63), (0.92, 0, 1.63), 0.08, mats["wood_deep"], root, objects, vertices=7)
    # A coarse net reads clearly at mobile distance without a dense woven mesh.
    for index, x in enumerate((-0.66, -0.44, -0.22, 0.0, 0.22, 0.44, 0.66), 1):
        add_beam(f"Net_V_{index:02}", (x, -0.018, 0.48 + 0.08 * abs(x)), (x, -0.018, 1.50), 0.009, mats["net"], root, objects, vertices=4)
    for index, z in enumerate((0.58, 0.82, 1.06, 1.30, 1.50), 1):
        width = 0.68 + (z - 0.58) * 0.12
        add_beam(f"Net_H_{index:02}", (-width, -0.018, z), (width, -0.018, z), 0.009, mats["net"], root, objects, vertices=4)
    for index, x in enumerate((-0.62, -0.20, 0.23, 0.63), 1):
        add_ico(f"Net_Float_{index:02}", (x, -0.03, 1.52), (0.055, 0.045, 0.07), mats["float" if index % 2 else "sea"], root, objects, irregularity=0.05)
    add_beam("Net_Rope_Coil", (0.76, 0.03, 0.35), (0.76, 0.03, 0.68), 0.025, mats["rope"], root, objects, vertices=6)
    export_asset("net_drying_rack", root, objects)


def build_navigator_hammock() -> None:
    reset_scene()
    root = make_root("navigator_hammock", "Navigator_Hammock", "medium")
    root["integration_status"] = "integrated"
    root["interaction_kind"] = "sleep"
    root["sleeping_surface_length"] = 2.18
    root["sleeping_surface_width"] = 0.78
    root["sleep_facing_axis"] = "+X"
    objects: list[bpy.types.Object] = []
    mats = {
        "wood_deep": material("LF_HammockWoodDeep", "#352923", 1.0),
        "wood": material("LF_HammockWood", "#74543B", 0.99),
        "wood_salt": material("LF_HammockWoodSalt", "#967A59", 1.0),
        "rope_deep": material("LF_HammockRopeDeep", "#695642", 1.0),
        "rope": material("LF_HammockRope", "#B49A70", 0.99),
        "rope_light": material("LF_HammockRopeLight", "#D2BE91", 0.98),
        "float": material("LF_HammockFloat", "#C96E53", 0.96),
    }

    # Two salt-worn A-frames keep the prop believable on open sand and make
    # the silhouette read clearly from the Home Island's elevated camera.
    for end_index, x in enumerate((-1.46, 1.46), 1):
        inward = 0.12 if x < 0 else -0.12
        apex = (x + inward, 0.0, 1.52)
        for leg_index, y in enumerate((-0.52, 0.52), 1):
            add_beam(
                f"Hammock_Frame_{end_index}_{leg_index}",
                (x, y, -0.045),
                apex,
                0.082,
                mats["wood" if leg_index == 1 else "wood_salt"],
                root,
                objects,
                vertices=7,
                end_radius=0.068,
            )
        add_beam(
            f"Hammock_Frame_Brace_{end_index}",
            (x - 0.025, -0.43, 0.28),
            (x - 0.025, 0.43, 0.28),
            0.052,
            mats["wood_deep"],
            root,
            objects,
            vertices=7,
        )
        add_beam(
            f"Hammock_Frame_Peg_{end_index}",
            (x - 0.17, 0, 0.03),
            (x + 0.17, 0, 0.03),
            0.040,
            mats["wood_deep"],
            root,
            objects,
            vertices=7,
        )

    x_min = -1.18
    x_max = 1.18

    def net_width(x: float) -> float:
        t = (x - x_min) / (x_max - x_min)
        return 0.48 - math.sin(math.pi * t) * 0.055

    def net_height(x: float, y: float) -> float:
        t = (x - x_min) / (x_max - x_min)
        width = max(net_width(x), 0.001)
        # Long, gentle body sag with raised side ropes to cradle a lying
        # navigator. At the shipped 72% scale the clear bed is about 1.70 m.
        return 1.25 - math.sin(math.pi * t) * 0.51 + 0.075 * (abs(y) / width) ** 1.7

    # Thick perimeter cords carry the load. They are intentionally chunkier
    # than the mesh so the hammock stays legible on a phone-sized thumbnail.
    edge_steps = 14
    for side_index, sign in enumerate((-1.0, 1.0), 1):
        edge_points: list[tuple[float, float, float]] = []
        for step in range(edge_steps + 1):
            x = x_min + (x_max - x_min) * step / edge_steps
            y = sign * net_width(x)
            edge_points.append((x, y, net_height(x, y)))
        for step in range(edge_steps):
            add_beam(
                f"Hammock_Perimeter_{side_index}_{step:02}",
                edge_points[step],
                edge_points[step + 1],
                0.022,
                mats["rope_deep"],
                root,
                objects,
                vertices=5,
            )

    # Open diamond lattice: two clipped diagonal rope families follow the
    # same curved sleeping surface, leaving real holes rather than a textured
    # cloth plane. This keeps the asset unmistakably nautical at close range.
    lattice_slope = 0.42
    lattice_offsets = tuple(-0.78 + index * 0.13 for index in range(13))
    samples = 26
    rope_index = 0
    for direction in (-1.0, 1.0):
        for offset in lattice_offsets:
            previous: tuple[float, float, float] | None = None
            for sample in range(samples + 1):
                x = x_min + (x_max - x_min) * sample / samples
                y = direction * lattice_slope * x + offset
                if abs(y) <= net_width(x):
                    current = (x, y, net_height(x, y))
                    if previous is not None:
                        rope_index += 1
                        add_beam(
                            f"Hammock_Net_{rope_index:03}",
                            previous,
                            current,
                            0.0105,
                            mats["rope" if rope_index % 4 else "rope_light"],
                            root,
                            objects,
                            vertices=4,
                        )
                    previous = current
                else:
                    previous = None

    # Fan ropes gather the wide net into a single lashed point on each frame.
    for end_index, x in enumerate((x_min, x_max), 1):
        outward = -0.17 if x < 0 else 0.17
        gather = (x + outward, 0.0, 1.43)
        for tie_index, y_factor in enumerate((-1.0, -0.5, 0.0, 0.5, 1.0), 1):
            y = net_width(x) * y_factor
            add_beam(
                f"Hammock_Fan_Rope_{end_index}_{tie_index}",
                (x, y, net_height(x, y)),
                gather,
                0.014,
                mats["rope_deep"],
                root,
                objects,
                vertices=5,
            )
        add_torus(
            f"Hammock_Lashing_{end_index}",
            gather,
            0.075,
            0.020,
            mats["rope_light"],
            root,
            objects,
            major_segments=10,
            minor_segments=4,
            rotation=(math.pi / 2, 0, 0),
        )

    # Small fishing-net floats provide a restrained maritime accent without
    # turning the hammock into a brightly coloured toy.
    for float_index, (x, y) in enumerate(((-0.67, -0.47), (0.05, 0.43), (0.72, -0.46)), 1):
        add_ico(
            f"Hammock_Float_{float_index}",
            (x, y, net_height(x, y) + 0.025),
            (0.052, 0.040, 0.040),
            mats["float"],
            root,
            objects,
            irregularity=0.04,
        )

    sleep_socket = bpy.data.objects.new("SleepSocket_Center", None)
    sleep_socket.location = (0.0, 0.0, 0.80)
    sleep_socket.empty_display_type = "ARROWS"
    sleep_socket.empty_display_size = 0.18
    sleep_socket.parent = root
    sleep_socket["interaction_kind"] = "sleep"
    sleep_socket["sleep_slot_id"] = "center"
    sleep_socket["sleep_facing_axis"] = "+X"
    sleep_socket["usable_length"] = 2.18
    bpy.context.collection.objects.link(sleep_socket)

    sleep_approach = bpy.data.objects.new("SleepApproach_Center", None)
    # Keep the trigger outside the circular walking collider so walking into
    # the hammock can activate sleep before obstacle resolution stops motion.
    sleep_approach.location = (0.0, -1.72, 0.0)
    sleep_approach.empty_display_type = "ARROWS"
    sleep_approach.empty_display_size = 0.18
    sleep_approach.parent = root
    sleep_approach["interaction_kind"] = "sleep_approach"
    sleep_approach["sleep_slot_id"] = "center"
    bpy.context.collection.objects.link(sleep_approach)

    export_asset(
        "navigator_hammock",
        root,
        objects,
        sockets=(sleep_socket, sleep_approach),
    )


def build_voyage_signal_bell() -> None:
    reset_scene()
    root = make_root("voyage_signal_bell", "Voyage_Signal_Bell")
    objects: list[bpy.types.Object] = []
    mats = {
        "wood_deep": material("LF_BellWoodDeep", "#342923", 1.0),
        "wood": material("LF_BellWood", "#6B4D35", 0.98),
        "brass": material("LF_BellBrass", "#A47A37", 0.52, metallic=0.50),
        "patina": material("LF_BellPatina", "#507365", 0.84, metallic=0.18),
        "iron": material("LF_BellIron", "#293331", 0.84, metallic=0.23),
        "rope": material("LF_BellRope", "#9B7B53", 0.99),
        "stone": material("LF_BellStone", "#6B746D", 0.99),
    }
    add_ico("Bell_Base", (0, 0, 0.11), (0.52, 0.42, 0.18), mats["stone"], root, objects, irregularity=0.12)
    add_box("Bell_Post", (-0.24, 0, 0.97), (0.18, 0.18, 1.72), mats["wood"], root, objects, rotation=(0, math.radians(-2), math.radians(1)), bevel=0.025)
    add_box("Bell_Arm", (0.12, 0, 1.68), (0.86, 0.16, 0.16), mats["wood_deep"], root, objects, rotation=(0, 0, math.radians(-3)), bevel=0.025)
    add_beam("Bell_Brace", (-0.18, 0, 1.37), (0.42, 0, 1.68), 0.055, mats["wood_deep"], root, objects, vertices=7)
    add_torus("Bell_Hanger", (0.38, 0, 1.57), 0.09, 0.025, mats["iron"], root, objects, major_segments=10, minor_segments=4, rotation=(math.pi / 2, 0, 0))
    add_cone("Signal_Bell", (0.38, 0, 1.34), 0.29, 0.12, 0.40, mats["brass"], root, objects, vertices=12)
    add_torus("Bell_Lip", (0.38, 0, 1.14), 0.275, 0.035, mats["patina"], root, objects, major_segments=12, minor_segments=4)
    add_beam("Bell_Clapper", (0.38, 0, 1.38), (0.38, 0, 1.08), 0.025, mats["iron"], root, objects, vertices=6)
    add_ico("Bell_Clapper_Weight", (0.38, 0, 1.04), (0.065, 0.065, 0.075), mats["iron"], root, objects, irregularity=0.03)
    add_beam("Bell_Pull_Rope", (0.45, -0.04, 1.08), (0.48, -0.04, 0.45), 0.018, mats["rope"], root, objects, vertices=5)
    add_torus("Bell_Rope_Handle", (0.48, -0.04, 0.34), 0.10, 0.018, mats["rope"], root, objects, major_segments=10, minor_segments=4, rotation=(math.pi / 2, 0, 0))
    export_asset("voyage_signal_bell", root, objects)


def build_voyage_notice_board() -> None:
    reset_scene()
    root = make_root("voyage_notice_board", "Voyage_Notice_Board", "medium")
    # Keep this asset reproducible even when another builder is inserted ahead
    # of it in the set. The board uses a handful of intentional small tilts.
    RNG.seed(8102607)
    root["integration_status"] = "integrated"
    root["interaction_kind"] = "notice_board"
    root["interaction_facing_axis"] = "-Y"
    objects: list[bpy.types.Object] = []
    mats = {
        "wood_deep": material("LF_NoticeWoodDeep", "#352923", 1.0),
        "wood": material("LF_NoticeWood", "#654630", 0.98),
        "wood_salt": material("LF_NoticeWoodSalt", "#8A7255", 0.99),
        "paper": material("LF_NoticePaper", "#E8DDBB", 0.95, double_sided=True),
        "paper_old": material("LF_NoticePaperOld", "#C5A873", 0.98, double_sided=True),
        "paper_sea": material("LF_NoticePaperSea", "#AFC9BA", 0.97, double_sided=True),
        "paper_sky": material("LF_NoticePaperSky", "#B5C8C8", 0.97, double_sided=True),
        "ink": material("LF_NoticeInk", "#315B59", 0.98),
        "brass": material("LF_NoticeBrass", "#B28A43", 0.53, metallic=0.43),
        "rope": material("LF_NoticeRope", "#A08763", 0.99),
        "seal": material("LF_NoticeSeal", "#A94F38", 0.90),
    }
    for index, x in enumerate((-0.74, 0.74), 1):
        add_box(f"Notice_Post_{index}", (x, 0.10, 0.87), (0.17, 0.17, 1.74), mats["wood"], root, objects, rotation=(0, math.radians(1 if x < 0 else -1), 0), bevel=0.024)
    for index, z in enumerate((0.74, 1.04, 1.34), 1):
        add_box(f"Notice_Plank_{index}", (0, 0, z), (1.66, 0.13, 0.31), mats["wood_salt" if index == 2 else "wood"], root, objects, rotation=(0, 0, math.radians(RNG.uniform(-1.5, 1.5))), bevel=0.026)
    add_box("Notice_Header", (0, 0.04, 1.61), (1.92, 0.18, 0.18), mats["wood_deep"], root, objects, rotation=(0, 0, math.radians(-1.5)), bevel=0.028)
    add_box("Notice_Roof", (0, 0.02, 1.78), (2.02, 0.50, 0.12), mats["wood_salt"], root, objects, rotation=(0, 0, math.radians(1)), bevel=0.035)
    # A brass compass badge makes the silhouette recognisably KeelMira even at
    # thumbnail size. It is an emblem, not readable text, so it localises well.
    add_cylinder("Notice_Compass_Rim", (0, -0.112, 1.61), 0.105, 0.035, mats["brass"], root, objects, vertices=12, rotation=(math.pi / 2, 0, 0))
    add_cylinder("Notice_Compass_Face", (0, -0.134, 1.61), 0.074, 0.014, mats["ink"], root, objects, vertices=12, rotation=(math.pi / 2, 0, 0))
    add_beam("Notice_Compass_NS", (0, -0.148, 1.545), (0, -0.148, 1.675), 0.012, mats["paper"], root, objects, vertices=4)
    add_beam("Notice_Compass_EW", (-0.065, -0.148, 1.61), (0.065, -0.148, 1.61), 0.012, mats["paper"], root, objects, vertices=4)

    # A busy tavern board: many compact requests overlap instead of reading as
    # three carefully arranged posters. The uneven rows, muted paper colours,
    # pins and seals create density without copying language-specific artwork.
    papers = [
        (-0.66, 1.42, 0.22, 0.19, mats["paper"], -9),
        (-0.43, 1.36, 0.31, 0.24, mats["paper_old"], 5),
        (-0.15, 1.43, 0.19, 0.29, mats["paper_sky"], -3),
        (0.11, 1.34, 0.32, 0.19, mats["paper"], 9),
        (0.42, 1.41, 0.20, 0.25, mats["paper_sea"], -7),
        (0.64, 1.29, 0.18, 0.19, mats["paper_old"], 6),
        (-0.65, 1.13, 0.29, 0.31, mats["paper_old"], 3),
        (-0.39, 1.08, 0.19, 0.17, mats["paper_sky"], -11),
        (-0.14, 1.16, 0.27, 0.23, mats["paper"], 7),
        (0.10, 1.02, 0.17, 0.28, mats["paper_old"], -6),
        (0.36, 1.13, 0.32, 0.20, mats["paper_sea"], 4),
        (0.62, 1.02, 0.18, 0.27, mats["paper"], -9),
        (-0.58, 0.82, 0.24, 0.21, mats["paper_sky"], -5),
        (-0.32, 0.87, 0.33, 0.18, mats["paper"], 8),
        (-0.06, 0.77, 0.18, 0.29, mats["paper_old"], -8),
        (0.18, 0.86, 0.28, 0.22, mats["paper"], 5),
        (0.43, 0.78, 0.20, 0.18, mats["paper_sea"], -10),
        (0.64, 0.85, 0.17, 0.28, mats["paper_sky"], 6),
    ]

    def paper_point(
        x: float,
        z: float,
        angle: float,
        offset_x: float,
        offset_z: float,
    ) -> tuple[float, float]:
        radians = math.radians(angle)
        return (
            x + offset_x * math.cos(radians) - offset_z * math.sin(radians),
            z + offset_x * math.sin(radians) + offset_z * math.cos(radians),
        )

    marked_papers = {1, 3, 6, 8, 10, 12, 14, 16, 18}
    sealed_papers = {4, 10, 13, 17}
    for index, (x, z, w, h, mat, angle) in enumerate(papers, 1):
        # Slightly stagger the depth so overlapping papers never z-fight.
        y = -0.078 - (index % 4) * 0.009
        add_box(
            f"Notice_Paper_{index:02}",
            (x, y, z),
            (w, 0.012, h),
            mat,
            root,
            objects,
            rotation=(0, 0, math.radians(angle)),
            bevel=0.006,
        )
        pin_x, pin_z = paper_point(x, z, angle, 0, h * 0.38)
        add_cylinder(
            f"Notice_Pin_{index:02}",
            (pin_x, y - 0.016, pin_z),
            0.020,
            0.018,
            mats["brass"],
            root,
            objects,
            vertices=8,
            rotation=(math.pi / 2, 0, 0),
        )

        if index in marked_papers:
            for line in range(2):
                line_width = w * (0.54 if line == 0 else 0.38)
                line_x, line_z = paper_point(
                    x,
                    z,
                    angle,
                    -w * 0.10 + line_width * 0.10,
                    h * (0.06 - line * 0.20),
                )
                add_box(
                    f"Notice_Ink_{index:02}_{line}",
                    (line_x, y - 0.016, line_z),
                    (line_width, 0.009, 0.014),
                    mats["ink"],
                    root,
                    objects,
                    rotation=(0, 0, math.radians(angle)),
                    bevel=0.002,
                )

        if index in sealed_papers:
            seal_x, seal_z = paper_point(x, z, angle, w * 0.28, -h * 0.27)
            add_cylinder(
                f"Notice_Wax_Seal_{index:02}",
                (seal_x, y - 0.022, seal_z),
                0.037,
                0.014,
                mats["seal"],
                root,
                objects,
                vertices=10,
                rotation=(math.pi / 2, 0, 0),
            )

    # One tiny ribboned seal is enough to break the rectangular paper rhythm.
    add_beam("Notice_Seal_Ribbon_Left", (0.00, -0.137, 0.73), (-0.04, -0.137, 0.66), 0.010, mats["seal"], root, objects, vertices=4)
    add_beam("Notice_Seal_Ribbon_Right", (0.02, -0.137, 0.73), (0.06, -0.137, 0.66), 0.010, mats["seal"], root, objects, vertices=4)
    add_beam("Notice_Rope", (-0.72, -0.11, 0.59), (0.72, -0.11, 0.63), 0.018, mats["rope"], root, objects, vertices=5)

    interaction = bpy.data.objects.new("InteractionSocket", None)
    interaction.location = (0.0, -1.05, 0.0)
    interaction.empty_display_type = "ARROWS"
    interaction.empty_display_size = 0.18
    interaction.parent = root
    interaction["interaction_kind"] = "notice_board"
    interaction["interaction_facing_axis"] = "-Y"
    bpy.context.collection.objects.link(interaction)
    export_asset("voyage_notice_board", root, objects, (interaction,))


def add_barrel(
    prefix: str,
    location: tuple[float, float, float],
    radius: float,
    height: float,
    mats: dict[str, bpy.types.Material],
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    *,
    rotation: tuple[float, float, float] = (0, 0, 0),
) -> None:
    # The body and bands share the same transform, allowing upright or stored barrels.
    add_cone(f"{prefix}_Body", location, radius * 0.90, radius * 0.90, height, mats["wood"], root, objects, vertices=12, rotation=rotation)
    add_cone(f"{prefix}_Belly", location, radius, radius, height * 0.58, mats["wood_light"], root, objects, vertices=12, rotation=rotation)
    # Bands are cylinders with a slightly larger radius; thin depth keeps USDZ compact.
    for index, offset in enumerate((-height * 0.34, 0.0, height * 0.34), 1):
        local = Vector((0, 0, offset))
        euler = Vector(local)
        # Apply the same Euler rotation through a temporary mathutils matrix.
        from mathutils import Euler
        world_offset = Euler(rotation, "XYZ").to_matrix() @ euler
        add_cylinder(f"{prefix}_Band_{index}", tuple(Vector(location) + world_offset), radius * 1.025, 0.045, mats["iron"], root, objects, vertices=12, rotation=rotation)


def build_supply_barrels() -> None:
    reset_scene()
    root = make_root("supply_barrels", "Supply_Barrels", "medium")
    objects: list[bpy.types.Object] = []
    mats = {
        "wood_deep": material("LF_BarrelWoodDeep", "#352923", 1.0),
        "wood": material("LF_BarrelWood", "#694A34", 0.98),
        "wood_light": material("LF_BarrelWoodLight", "#896347", 0.97),
        "iron": material("LF_BarrelIron", "#293331", 0.87, metallic=0.20),
        "rust": material("LF_BarrelRust", "#754833", 0.95, metallic=0.08),
        "rope": material("LF_BarrelRope", "#9B7B53", 0.99),
    }
    add_barrel("Barrel_Large", (-0.35, 0.12, 0.58), 0.43, 1.10, mats, root, objects)
    add_barrel("Barrel_Small", (0.46, 0.18, 0.43), 0.34, 0.82, mats, root, objects)
    add_box("Barrel_Chock_Left", (-0.73, 0.11, 0.08), (0.16, 0.62, 0.15), mats["wood_deep"], root, objects, bevel=0.025)
    add_box("Barrel_Chock_Right", (0.77, 0.15, 0.08), (0.16, 0.52, 0.15), mats["wood_deep"], root, objects, bevel=0.025)
    add_torus("Barrel_Rope_Coil", (0.23, -0.31, 0.11), 0.30, 0.035, mats["rope"], root, objects, major_segments=12, minor_segments=4)
    add_cylinder("Barrel_Bung", (-0.35, -0.325, 0.77), 0.055, 0.035, mats["rust"], root, objects, vertices=8, rotation=(math.pi / 2, 0, 0))
    export_asset("supply_barrels", root, objects)


def build_compass_rose_inlay() -> None:
    reset_scene()
    root = make_root("compass_rose_inlay", "Compass_Rose_Inlay")
    objects: list[bpy.types.Object] = []
    mats = {
        "stone_deep": material("LF_CompassStoneDeep", "#3F504B", 1.0),
        "stone": material("LF_CompassStone", "#758078", 0.99),
        "stone_light": material("LF_CompassStoneLight", "#9B9985", 0.98),
        "sand": material("LF_CompassSandstone", "#B7A67C", 0.99),
        "brass": material("LF_CompassBrass", "#A47A37", 0.56, metallic=0.40),
        "moss": material("LF_CompassMoss", "#5C7455", 1.0),
    }
    for index in range(12):
        angle = math.tau * index / 12
        radius = 0.77
        add_box(
            f"Compass_Rim_{index + 1:02}",
            (math.cos(angle) * radius, math.sin(angle) * radius, 0.035),
            (0.42, 0.24, 0.09),
            mats["stone_light" if index % 3 == 0 else "stone"],
            root,
            objects,
            rotation=(0, 0, angle + math.pi / 2),
            bevel=0.035,
        )
    add_cylinder("Compass_Center_Stone", (0, 0, 0.025), 0.67, 0.06, mats["stone_deep"], root, objects, vertices=16)
    vertices: list[tuple[float, float, float]] = [(0, 0, 0.064)]
    faces: list[tuple[int, ...]] = []
    for index in range(16):
        angle = math.tau * index / 16
        radius = 0.59 if index % 2 == 0 else 0.18
        vertices.append((math.sin(angle) * radius, -math.cos(angle) * radius, 0.066))
    for index in range(16):
        faces.append((0, index + 1, (index + 1) % 16 + 1))
    star = mesh_object("Compass_Rose", vertices, faces, mats["sand"], root, objects)
    star.data.materials.append(mats["brass"])
    for index, polygon in enumerate(star.data.polygons):
        polygon.material_index = index % 2
    add_cylinder("Compass_Hub", (0, 0, 0.074), 0.09, 0.035, mats["brass"], root, objects, vertices=10)
    add_ico("Compass_Moss", (-0.55, 0.47, 0.095), (0.25, 0.11, 0.018), mats["moss"], root, objects, irregularity=0.14)
    export_asset("compass_rose_inlay", root, objects)


def grass_blade(
    name: str,
    base: tuple[float, float, float],
    height: float,
    width: float,
    lean: tuple[float, float],
    mat: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
) -> None:
    x, y, z = base
    lx, ly = lean
    vertices = [
        (x - width, y, z), (x + width, y, z),
        (x + lx + width * 0.30, y + ly, z + height * 0.72),
        (x + lx, y + ly, z + height),
    ]
    faces = [(0, 1, 2, 3), (3, 2, 1, 0)]
    mesh_object(name, vertices, faces, mat, root, objects)


def build_dune_grass_patch() -> None:
    reset_scene()
    root = make_root("dune_grass_patch", "Dune_Grass_Patch")
    objects: list[bpy.types.Object] = []
    mats = {
        "sand": material("LF_DuneGrassSand", "#C8B482", 1.0),
        "sand_light": material("LF_DuneGrassSandLight", "#DCCB9C", 0.99),
        "grass_deep": material("LF_DuneGrassDeep", "#3E5D45", 1.0, double_sided=True),
        "grass": material("LF_DuneGrass", "#66805A", 0.99, double_sided=True),
        "grass_light": material("LF_DuneGrassLight", "#87966A", 0.98, double_sided=True),
        "shell": material("LF_DuneGrassShell", "#E2D8BA", 0.96),
    }
    add_ico("Dune_Mound", (0, 0, 0.05), (0.91, 0.68, 0.13), mats["sand"], root, objects, subdivisions=2, irregularity=0.10)
    add_ico("Dune_Highlight", (-0.22, -0.18, 0.15), (0.45, 0.25, 0.025), mats["sand_light"], root, objects, irregularity=0.12)
    clusters = [(-0.42, -0.10), (0.07, 0.12), (0.46, -0.04)]
    palette = (mats["grass_deep"], mats["grass"], mats["grass_light"])
    blade_index = 0
    for cluster_index, (cx, cy) in enumerate(clusters):
        for local_index in range(8):
            blade_index += 1
            angle = math.tau * local_index / 8 + cluster_index * 0.43
            radius = 0.05 + 0.08 * (local_index % 3)
            height = 0.42 + 0.10 * ((local_index * 3 + cluster_index) % 4)
            grass_blade(
                f"Grass_Blade_{blade_index:02}",
                (cx + math.cos(angle) * radius, cy + math.sin(angle) * radius, 0.12),
                height,
                0.018,
                (math.cos(angle) * 0.14, math.sin(angle) * 0.14),
                palette[(local_index + cluster_index) % len(palette)],
                root,
                objects,
            )
    for index, (x, y, s) in enumerate(((-0.63, 0.28, 0.09), (0.28, -0.40, 0.07), (0.69, 0.22, 0.06)), 1):
        add_ico(f"Dune_Shell_{index}", (x, y, 0.17), (s, s * 0.66, s * 0.35), mats["shell"], root, objects, irregularity=0.08)
    export_asset("dune_grass_patch", root, objects)


BUILDERS = (
    build_harbor_lantern_post,
    build_driftwood_bench,
    build_weathered_anchor,
    build_net_drying_rack,
    build_navigator_hammock,
    build_voyage_signal_bell,
    build_voyage_notice_board,
    build_supply_barrels,
    build_compass_rose_inlay,
    build_dune_grass_patch,
)


requested_ids = {
    value.strip()
    for value in os.environ.get("KEELMIRA_ASSET_IDS", "").split(",")
    if value.strip()
}
selected_builders = tuple(
    builder
    for builder in BUILDERS
    if not requested_ids or builder.__name__.removeprefix("build_") in requested_ids
)

for builder in selected_builders:
    builder()

print(f"ASSET_SET_COMPLETE={len(selected_builders)}")
