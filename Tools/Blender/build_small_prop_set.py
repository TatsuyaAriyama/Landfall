"""Build three compact, standalone low-poly props for KeelMira.

The assets are intentionally kept outside Landfall/Resources so running this
script never adds them to the game. Each build emits an editable Blender source,
an integration-ready USDZ under Assets3D/ready, and a square review render.
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "Assets3D/source"
READY_DIR = ROOT / "Assets3D/ready"
RENDER_DIR = ROOT / "marketing/3d"
RNG = random.Random(80826)


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[index : index + 2], 16) / 255 for index in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float = 0.94,
    *,
    metallic: float = 0.0,
    emission: str | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    value = bpy.data.materials.new(name)
    value.diffuse_color = rgba(color)
    value.use_nodes = True
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
    for collection in (bpy.data.meshes, bpy.data.curves, bpy.data.cameras, bpy.data.lights, bpy.data.materials):
        for block in list(collection):
            collection.remove(block)


def make_root(asset_id: str, display_name: str) -> bpy.types.Object:
    root = bpy.data.objects.new(display_name, None)
    root["asset_id"] = asset_id
    root["size_class"] = "small"
    root["integration_status"] = "not_integrated"
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
    """Author a gameplay contact point inside the asset itself."""
    socket = bpy.data.objects.new(name, None)
    socket.location = location
    socket.empty_display_type = "ARROWS"
    socket.empty_display_size = 0.12
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
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius1,
        radius2=radius2,
        depth=depth,
        location=location,
    )
    return keep(bpy.context.object, name, mat, root, objects)


def add_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    mat: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    *,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel: float = 0.0,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        modifier = obj.modifiers.new(name="Softened edges", type="BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.rotation_euler = rotation
    return keep(obj, name, mat, root, objects)


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
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=major_segments,
        minor_segments=minor_segments,
        location=location,
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
        RNG.uniform(-0.10, 0.10),
        RNG.uniform(-0.10, 0.10),
        RNG.uniform(-0.35, 0.35),
    )
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return keep(obj, name, mat, root, objects)


def add_beam(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius1: float,
    radius2: float,
    mat: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    *,
    vertices: int = 6,
) -> bpy.types.Object:
    start_value = Vector(start)
    end_value = Vector(end)
    direction = end_value - start_value
    obj = add_cone(
        name,
        tuple((start_value + end_value) * 0.5),
        radius1,
        radius2,
        direction.length,
        mat,
        root,
        objects,
        vertices=vertices,
    )
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return obj


def add_preview_stage(
    target: tuple[float, float, float],
    camera_location: tuple[float, float, float],
) -> None:
    ground_mat = material("PREVIEW_Ground", "#31554F", 1.0)
    bpy.ops.mesh.primitive_plane_add(size=100, location=(0, 0, -0.018))
    ground = bpy.context.object
    ground.name = "PREVIEW_Ground"
    ground.data.materials.append(ground_mat)

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#103A35")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.28

    for name, location, energy, size, color in (
        ("PREVIEW_Key", (-3.8, -4.8, 5.6), 520, 4.2, "#FFE8BB"),
        ("PREVIEW_Fill", (4.2, -1.4, 3.5), 290, 3.4, "#77C4A5"),
        ("PREVIEW_Rim", (1.2, 4.0, 4.8), 390, 3.0, "#C8DDD0"),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = rgba(color)[:3]
        light.rotation_euler = (Vector(target) - light.location).to_track_quat("-Z", "Y").to_euler()

    bpy.ops.object.camera_add(location=camera_location)
    camera = bpy.context.object
    camera.name = "PREVIEW_Camera"
    camera.data.lens = 58
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera


def export_asset(
    asset_id: str,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    target: tuple[float, float, float],
    camera_location: tuple[float, float, float],
    sockets: tuple[bpy.types.Object, ...] = (),
) -> None:
    blend_path = SOURCE_DIR / f"{asset_id}.blend"
    usdz_path = READY_DIR / f"{asset_id}.usdz"
    render_path = RENDER_DIR / f"{asset_id.replace('_', '-')}.png"
    for path in (blend_path, usdz_path, render_path):
        path.parent.mkdir(parents=True, exist_ok=True)

    add_preview_stage(target, camera_location)
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
    scene.render.filepath = str(render_path)
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.render.render(write_still=True)

    triangles = sum(len(polygon.vertices) - 2 for obj in export_objects for polygon in obj.data.polygons)
    print(f"ASSET={asset_id} MESHES={len(export_objects)} TRIANGLES={triangles}")
    print(f"BLEND={blend_path}")
    print(f"USDZ={usdz_path}")
    print(f"RENDER={render_path}")


def build_small_stump() -> None:
    reset_scene()
    root = make_root("small_stump", "Small_Stump")
    root["seat_capacity"] = 1
    root["seat_socket_schema"] = 1
    objects: list[bpy.types.Object] = []
    mats = {
        "bark": material("LF_StumpBark", "#674937", 0.98),
        "bark_dark": material("LF_StumpBarkDark", "#3D3028", 1.0),
        "bark_light": material("LF_StumpBarkLight", "#866047", 0.97),
        "cut": material("LF_StumpCutWood", "#C8A36F", 0.95),
        "ring": material("LF_StumpGrowthRings", "#79533D", 0.98),
        "moss": material("LF_StumpMoss", "#61745A", 1.0),
    }

    add_cone("Stump_Trunk", (0, 0, 0.29), 0.43, 0.34, 0.56, mats["bark"], root, objects, vertices=11)
    add_cone("Stump_Cut", (0, 0, 0.578), 0.337, 0.326, 0.025, mats["cut"], root, objects, vertices=11)

    for index, angle in enumerate((0.15, 1.22, 2.35, 3.46, 4.57, 5.61), 1):
        start = (math.cos(angle) * 0.30, math.sin(angle) * 0.30, 0.18)
        length = 0.48 if index in (1, 4) else 0.38
        end = (math.cos(angle) * (0.30 + length), math.sin(angle) * (0.30 + length), 0.055)
        add_beam(
            f"Stump_Root_{index:02}", start, end, 0.13, 0.035,
            mats["bark_dark" if index % 2 else "bark"], root, objects, vertices=5,
        )

    for index, angle in enumerate((0.2, 1.7, 3.1, 4.6), 1):
        add_box(
            f"Stump_Bark_Ridge_{index:02}",
            (math.cos(angle) * 0.352, math.sin(angle) * 0.352, 0.33),
            (0.055, 0.03, 0.38),
            mats["bark_light" if index % 2 else "bark_dark"],
            root,
            objects,
            rotation=(0.0, 0.0, angle),
            bevel=0.008,
        )

    add_torus("Stump_Ring_Outer", (0, 0, 0.594), 0.235, 0.009, mats["ring"], root, objects, major_segments=11)
    add_torus("Stump_Ring_Inner", (0, 0, 0.596), 0.125, 0.007, mats["ring"], root, objects, major_segments=11)
    mesh_object(
        "Stump_Top_Crack",
        [(0.02, -0.01, 0.604), (0.23, -0.07, 0.604), (0.12, 0.015, 0.605)],
        [(0, 1, 2)],
        mats["bark_dark"], root, objects,
    )
    for index, (location, scale) in enumerate(
        [((-0.27, 0.20, 0.59), (0.16, 0.12, 0.025)), ((-0.39, 0.12, 0.33), (0.08, 0.12, 0.035))],
        1,
    ):
        add_ico(f"Stump_Moss_{index:02}", location, scale, mats["moss"], root, objects, irregularity=0.13)

    sockets = (
        # Sits a little above the cut face: at 0.605 the navigator's shins and
        # boots clipped into the front of the trunk once seated.
        add_socket(
            "SeatSocket_Stump",
            (0, 0, 0.670),
            root,
            slot_id="stump",
            purpose="seat",
        ),
        # The approach must sit outside the navigator's own body radius plus the
        # stump's collider, or the spot that triggers sitting is one the player
        # can never stand on. 1.08 leaves a comfortable step of clearance.
        add_socket(
            "SeatApproach_Stump",
            (0, -1.25, 0),
            root,
            slot_id="stump",
            purpose="approach",
        ),
    )
    export_asset(
        "small_stump",
        root,
        objects,
        (0, 0, 0.30),
        (2.05, -3.10, 2.10),
        sockets,
    )


def build_small_lighthouse() -> None:
    reset_scene()
    root = make_root("small_lighthouse", "Small_Lighthouse")
    objects: list[bpy.types.Object] = []
    mats = {
        "stone": material("LF_SmallLighthouseStone", "#DDD2B5", 0.97),
        "stone_shadow": material("LF_SmallLighthouseStoneShadow", "#A69D88", 0.99),
        "coral": material("LF_SmallLighthouseCoralBand", "#D8755D", 0.93),
        "roof": material("LF_SmallLighthouseRoof", "#21463F", 0.86, metallic=0.10),
        "iron": material("LF_SmallLighthouseIron", "#263B38", 0.82, metallic=0.18),
        "glass": material("LF_SmallLighthouseGlass", "#5B9C91", 0.38, metallic=0.04),
        "door": material("LF_SmallLighthouseDoor", "#624330", 0.96),
        "light": material(
            "LF_SmallLighthouseBeacon", "#F3C766", 0.28,
            emission="#FFD878", emission_strength=5.0,
        ),
        "moss": material("LF_SmallLighthouseMoss", "#66785D", 1.0),
    }

    add_cone("Lighthouse_Footing", (0, 0, 0.09), 0.62, 0.52, 0.18, mats["stone_shadow"], root, objects, vertices=10)
    add_cone("Lighthouse_Tower", (0, 0, 0.70), 0.47, 0.31, 1.18, mats["stone"], root, objects, vertices=12)
    add_cone("Lighthouse_Coral_Band", (0, 0, 0.82), 0.405, 0.385, 0.16, mats["coral"], root, objects, vertices=12)
    add_box("Lighthouse_Door", (0, -0.438, 0.34), (0.22, 0.035, 0.36), mats["door"], root, objects, bevel=0.018)
    add_box("Lighthouse_Window", (-0.315, -0.17, 0.91), (0.035, 0.20, 0.18), mats["iron"], root, objects, rotation=(0, 0, math.radians(-62)), bevel=0.008)

    add_cone("Lighthouse_Balcony", (0, 0, 1.33), 0.43, 0.43, 0.08, mats["iron"], root, objects, vertices=16)
    add_torus("Lighthouse_Railing", (0, 0, 1.57), 0.39, 0.018, mats["iron"], root, objects, major_segments=16)
    for index in range(8):
        angle = math.tau * index / 8
        add_cone(
            f"Lighthouse_Rail_Post_{index + 1:02}",
            (math.cos(angle) * 0.39, math.sin(angle) * 0.39, 1.46),
            0.014, 0.014, 0.23, mats["iron"], root, objects, vertices=5,
        )

    add_cone("Lighthouse_Lantern_Glass", (0, 0, 1.51), 0.25, 0.25, 0.34, mats["glass"], root, objects, vertices=8)
    for index in range(8):
        angle = math.tau * index / 8
        add_cone(
            f"Lighthouse_Lantern_Post_{index + 1:02}",
            (math.cos(angle) * 0.245, math.sin(angle) * 0.245, 1.51),
            0.012, 0.012, 0.36, mats["iron"], root, objects, vertices=5,
        )
    add_ico("Lighthouse_Beacon", (0, -0.01, 1.51), (0.10, 0.10, 0.10), mats["light"], root, objects, subdivisions=2, irregularity=0.0)
    add_cone("Lighthouse_Roof", (0, 0, 1.79), 0.35, 0.02, 0.30, mats["roof"], root, objects, vertices=10)
    add_cone("Lighthouse_Finial", (0, 0, 1.98), 0.035, 0.008, 0.16, mats["roof"], root, objects, vertices=6)

    for index, (location, scale) in enumerate(
        [((-0.42, 0.22, 0.18), (0.19, 0.15, 0.045)), ((0.32, 0.37, 0.14), (0.14, 0.12, 0.035))],
        1,
    ):
        add_ico(f"Lighthouse_Moss_{index:02}", location, scale, mats["moss"], root, objects, irregularity=0.12)

    export_asset("small_lighthouse", root, objects, (0, 0, 0.95), (3.0, -4.6, 2.65))


def build_small_rock() -> None:
    reset_scene()
    root = make_root("small_rock", "Small_Rock")
    objects: list[bpy.types.Object] = []
    mats = {
        "rock": material("LF_SmallRock", "#68736D", 0.99),
        "rock_light": material("LF_SmallRockLight", "#879087", 0.98),
        "crack": material("LF_SmallRockCrack", "#34413E", 1.0),
        "moss": material("LF_SmallRockMoss", "#60765B", 1.0),
    }

    rock = add_ico("Rock_Main", (0, 0, 0.35), (0.62, 0.49, 0.46), mats["rock"], root, objects, subdivisions=2, irregularity=0.14)
    rock.rotation_euler.z = math.radians(-12)
    for vertex in rock.data.vertices:
        vertex.co.z = max(vertex.co.z, -0.33)
    rock.data.update()
    rock.data.materials.append(mats["rock_light"])
    for index, polygon in enumerate(rock.data.polygons):
        if polygon.center.z > 0.05 and index % 5 in (0, 1):
            polygon.material_index = 1

    moss = add_ico(
        "Rock_Moss", (-0.18, 0.01, 0.64), (0.24, 0.20, 0.018),
        mats["moss"], root, objects, irregularity=0.12,
    )
    moss.rotation_euler = (math.radians(4), math.radians(-8), math.radians(-10))
    add_beam("Rock_Crack_Upper", (0.10, -0.48, 0.62), (0.02, -0.49, 0.49), 0.014, 0.009, mats["crack"], root, objects, vertices=4)
    add_beam("Rock_Crack_Lower", (0.02, -0.49, 0.49), (0.11, -0.46, 0.39), 0.011, 0.006, mats["crack"], root, objects, vertices=4)

    export_asset("small_rock", root, objects, (0, 0, 0.36), (2.1, -3.2, 1.85))


build_small_stump()
build_small_lighthouse()
build_small_rock()
