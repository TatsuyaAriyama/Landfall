"""Build a single conifer for the Home Island asset library.

The tree is authored as one origin-grounded prop: a slim, slightly kinked trunk
carrying six faceted skirts that narrow toward a pointed crown, so it reads as a
conifer from any orbit angle while staying flat-shaded and low-poly. Like the
other library builders this writes an editable ``.blend`` source, an
integration-ready USDZ, and a square review render. Nothing is copied into
``Landfall/Resources``; integration happens after the shape is approved.
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
ASSET_ID = "conifer_tree"
RNG = random.Random(50713)


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[index:index + 2], 16) / 255 for index in (0, 2, 4)) + (alpha,)


def material(
    name: str,
    color: str,
    roughness: float = 0.96,
    *,
    metallic: float = 0.0,
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


def make_root(asset_id: str, display_name: str, size_class: str = "medium") -> bpy.types.Object:
    root = bpy.data.objects.new(display_name, None)
    root["asset_id"] = asset_id
    root["size_class"] = size_class
    root["integration_status"] = "not_integrated"
    root["ground_plane_z"] = 0.0
    bpy.context.collection.objects.link(root)
    return root


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
    for name, offset, energy, size, color in (
        ("PREVIEW_Key", Vector((-1.7, -2.2, 2.5)), 560, 4.2, "#FFE8BB"),
        ("PREVIEW_Fill", Vector((2.0, -0.8, 1.5)), 310, 3.4, "#77C4A5"),
        ("PREVIEW_Rim", Vector((0.8, 2.0, 2.1)), 410, 3.0, "#C8DDD0"),
    ):
        bpy.ops.object.light_add(type="AREA", location=center + offset * span)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
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
) -> None:
    blend_path = SOURCE_DIR / f"{asset_id}.blend"
    usdz_path = READY_DIR / f"{asset_id}.usdz"
    render_path = RENDER_DIR / f"{asset_id.replace('_', '-')}.png"
    for path in (blend_path, usdz_path, render_path):
        path.parent.mkdir(parents=True, exist_ok=True)

    add_preview_stage(objects)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    # Runtime draw calls stay low by joining every mesh that shares a material.
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


# Trunk waypoints keep a small lean so the silhouette is never mirror-perfect.
TRUNK_POINTS = (
    (0.000, 0.000, 0.000),
    (0.014, 0.006, 0.46),
    (-0.010, 0.014, 0.98),
    (0.016, -0.008, 1.52),
    (0.006, 0.004, 2.02),
    (0.000, 0.000, 2.30),
)
TRUNK_RADII = (0.088, 0.070, 0.056, 0.042, 0.028, 0.013)

# Each skirt is a cone: base z, base radius, height, top radius factor, tilt.
# The lowest skirt starts above half a metre so the bare trunk stays readable.
SKIRTS = (
    (0.60, 0.58, 0.56, 0.36, 0.030),
    (0.90, 0.52, 0.54, 0.34, -0.024),
    (1.18, 0.44, 0.50, 0.32, 0.020),
    (1.44, 0.35, 0.46, 0.28, -0.017),
    (1.70, 0.27, 0.42, 0.24, 0.014),
    (1.94, 0.18, 0.42, 0.00, -0.010),
)


def build_conifer_tree() -> None:
    reset_scene()
    root = make_root(ASSET_ID, "Conifer_Tree")
    objects: list[bpy.types.Object] = []
    bark_deep = material("LF_ConiferBarkDeep", "#3B2C25", 0.97)
    bark = material("LF_ConiferBark", "#5A4030", 0.94)
    bark_light = material("LF_ConiferBarkLight", "#745440", 0.92)
    needle_materials = (
        material("LF_ConiferNeedleDeep", "#20483B", 0.86),
        material("LF_ConiferNeedleShadow", "#2C5B46", 0.84),
        material("LF_ConiferNeedle", "#3D7052", 0.82),
        material("LF_ConiferNeedleLight", "#4E7F58", 0.80),
        material("LF_ConiferNeedleSun", "#6B9765", 0.78),
    )
    litter = material("LF_ConiferLitter", "#3E3122", 0.99)

    # The lowest segment is the only trunk anyone sees, so it carries the mid tone
    # and the darker barks sit higher up inside the skirts.
    trunk_materials = (bark_light, bark, bark, bark_deep, bark_deep)
    for index in range(len(TRUNK_POINTS) - 1):
        add_beam(
            f"Conifer_Trunk_{index + 1:02}",
            TRUNK_POINTS[index],
            TRUNK_POINTS[index + 1],
            TRUNK_RADII[index],
            trunk_materials[index],
            root,
            objects,
            vertices=8,
            end_radius=TRUNK_RADII[index + 1],
        )

    # Shallow radial roots settle the trunk onto any terrain without a pedestal.
    for index in range(5):
        angle = math.tau * index / 5 + 0.24
        add_beam(
            f"Conifer_Root_{index + 1:02}",
            (math.cos(angle) * 0.030, math.sin(angle) * 0.030, 0.10),
            (math.cos(angle) * 0.20, math.sin(angle) * 0.20, 0.010),
            0.044,
            bark_deep if index % 2 else bark,
            root,
            objects,
            vertices=6,
            end_radius=0.012,
        )

    # Stacked skirts: a dark under-rim reads as the shadow line between tiers,
    # and the greens lighten upward so the crown catches the key light.
    for index, (base_z, radius, height, top_factor, tilt) in enumerate(SKIRTS):
        drift = math.tau * index * 0.37
        offset_x = math.cos(drift) * 0.020
        offset_y = math.sin(drift) * 0.020
        needle = needle_materials[min(index, len(needle_materials) - 1)]
        add_cone(
            f"Conifer_Skirt_{index + 1:02}",
            (offset_x, offset_y, base_z + height * 0.5),
            radius,
            radius * top_factor,
            height,
            needle,
            root,
            objects,
            vertices=9,
            rotation=(tilt, tilt * 0.6, drift),
        )
        if index < len(SKIRTS) - 1:
            add_cone(
                f"Conifer_SkirtRim_{index + 1:02}",
                (offset_x, offset_y, base_z + 0.026),
                radius * 1.06,
                radius * 0.88,
                0.052,
                needle_materials[0] if index % 2 else needle_materials[1],
                root,
                objects,
                vertices=9,
                rotation=(tilt, tilt * 0.6, drift + 0.18),
            )

    # A few needle tufts break the cone outline where branches would push through.
    for index, (angle, height, size) in enumerate(
        (
            (0.55, 0.74, 0.14),
            (2.35, 1.10, 0.12),
            (4.05, 1.48, 0.11),
            (5.35, 0.96, 0.12),
            (1.45, 1.76, 0.09),
        ),
        1,
    ):
        radius = 0.60 - height * 0.22
        add_ico(
            f"Conifer_Tuft_{index:02}",
            (math.cos(angle) * radius, math.sin(angle) * radius, height),
            (size, size * 0.86, size * 0.64),
            needle_materials[(index + 1) % len(needle_materials)],
            root,
            objects,
            irregularity=0.16,
        )

    # A thin needle-fall ring hugs the roots. It stays inside the skirt shadow so
    # the prop still drops cleanly onto grass, sand, or a painted path.
    for index in range(5):
        angle = math.tau * index / 5 + 0.7
        distance = 0.17 + (index % 3) * 0.03
        add_ico(
            f"Conifer_NeedleFall_{index + 1:02}",
            (math.cos(angle) * distance, math.sin(angle) * distance, 0.010),
            (0.072, 0.055, 0.011),
            litter,
            root,
            objects,
            irregularity=0.24,
        )

    export_asset(ASSET_ID, root, objects)


build_conifer_tree()
