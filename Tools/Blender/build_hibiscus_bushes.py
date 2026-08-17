"""Build the hibiscus bushes for the Home Island asset library.

Red, pink, and orange share one authored shape, and that shape reuses the rose
bush's leaf mound so a mixed flower bed keeps a single planting scale — the
hibiscus matches it to the centimetre in height and width. The flower itself is
the difference: five flat petals around a throat, with the long staminal column
that makes a hibiscus readable at a glance.
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
# Every variant re-seeds this generator, so the three bushes come out as the
# same shape and only their bloom colour differs.
SHAPE_SEED = 60214
RNG = random.Random(SHAPE_SEED)


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


def make_root(asset_id: str, display_name: str, size_class: str = "small") -> bpy.types.Object:
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
    # Lights are placed proportionally to the prop, so their energy has to follow
    # the inverse-square law or a small prop like this bush blows out to white
    # and the bloom colour cannot be judged. 2.4 is the span the presets suit.
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


# One authored shape, three colourways: the petal face, the shaded throat, and
# the deeper tone used for buds and fallen petals.
VARIANTS = (
    ("hibiscus_bush_red", "Red", "#C42B2E", "#9C1D22", "#7B1419"),
    ("hibiscus_bush_pink", "Pink", "#E0708F", "#C4526F", "#A63F58"),
    ("hibiscus_bush_orange", "Orange", "#E87A28", "#C85F17", "#A34A10"),
)

# Identical to the rose bush mound, so the two plants share a planting scale.
FOLIAGE = (
    (0.000, 0.000, 0.115, 0.145, 0.138, 0.105),
    (0.115, 0.070, 0.098, 0.105, 0.098, 0.076),
    (-0.105, 0.090, 0.100, 0.100, 0.095, 0.074),
    (0.035, -0.130, 0.094, 0.105, 0.092, 0.072),
    (-0.075, -0.110, 0.088, 0.092, 0.086, 0.068),
    (0.010, 0.035, 0.165, 0.098, 0.092, 0.072),
)

# Same stations as the roses, lowered by the length of the staminal column so
# the finished bush tops out at exactly the same height.
BLOOMS = (
    (0.40, 0.166, 0.268),
    (1.70, 0.208, 0.230),
    (3.00, 0.126, 0.298),
    (4.30, 0.194, 0.240),
    (5.50, 0.158, 0.280),
)

BUDS = (
    (2.40, 0.250, 0.245),
    (5.00, 0.265, 0.228),
)


def build_hibiscus_bush(
    asset_id: str,
    display_name: str,
    petal: str,
    petal_shade: str,
    petal_deep: str,
) -> None:
    reset_scene()
    RNG.seed(SHAPE_SEED)
    root = make_root(asset_id, f"Hibiscus_Bush_{display_name}")
    objects: list[bpy.types.Object] = []
    leaf_deep = material("LF_HibiscusLeafDeep", "#1F4433", 0.88)
    leaf = material("LF_HibiscusLeaf", "#2F6544", 0.85)
    leaf_light = material("LF_HibiscusLeafLight", "#458050", 0.83)
    stem = material("LF_HibiscusStem", "#4C6B45", 0.90)
    bloom = material("LF_HibiscusPetal", petal, 0.72)
    bloom_shade = material("LF_HibiscusThroat", petal_shade, 0.74)
    bloom_deep = material("LF_HibiscusPetalDeep", petal_deep, 0.76)
    column = material("LF_HibiscusColumn", "#F0D486", 0.70)
    pollen = material("LF_HibiscusPollen", "#F8ECBB", 0.68)

    leaf_materials = (leaf, leaf_deep, leaf_light)
    for index, (x, y, z, sx, sy, sz) in enumerate(FOLIAGE, 1):
        add_ico(
            f"Hibiscus_Heartwood_{index:02}",
            (x, y, z),
            (sx, sy, sz),
            leaf_deep,
            root,
            objects,
            irregularity=0.14,
        )

    for index in range(18):
        bearing = math.tau * index * 0.618 + 0.35
        tier = index % 3
        distance = (0.255, 0.195, 0.120)[tier]
        z = (0.098, 0.158, 0.215)[tier]
        lift = (-0.62, -0.72, -0.86)[tier]
        leaf_object = add_ico(
            f"Hibiscus_Leaf_{index + 1:02}",
            (math.cos(bearing) * distance, math.sin(bearing) * distance, z),
            (0.115, 0.072, 0.021),
            leaf_materials[index % len(leaf_materials)],
            root,
            objects,
            irregularity=0.18,
        )
        leaf_object.rotation_euler = (0.0, lift + RNG.uniform(-0.10, 0.10), bearing)

    for index, (angle, distance, height) in enumerate(BLOOMS, 1):
        x = math.cos(angle) * distance
        y = math.sin(angle) * distance
        add_beam(
            f"Hibiscus_Stem_{index:02}",
            (x * 0.35, y * 0.35, 0.06),
            (x, y, height - 0.02),
            0.013,
            stem,
            root,
            objects,
            vertices=6,
            end_radius=0.009,
        )
        # Five flat petals laid around a shallow throat. Tipping each petal up
        # at the rim gives the saucer a hibiscus reads as, not a flat disc.
        for petal_index in range(5):
            petal_angle = math.tau * petal_index / 5 + angle * 0.6
            petal_object = add_ico(
                f"Hibiscus_Bloom_{index:02}_Petal{petal_index + 1}",
                (
                    x + math.cos(petal_angle) * 0.052,
                    y + math.sin(petal_angle) * 0.052,
                    height + 0.008,
                ),
                (0.059, 0.044, 0.011),
                bloom,
                root,
                objects,
                irregularity=0.14,
            )
            petal_object.rotation_euler = (0.0, -0.30, petal_angle)
        add_cone(
            f"Hibiscus_Bloom_{index:02}_Throat",
            (x, y, height + 0.012),
            0.030,
            0.014,
            0.026,
            bloom_shade,
            root,
            objects,
            vertices=7,
        )
        # The staminal column is the signature of the flower: a slim stalk well
        # clear of the petals, tipped with pollen.
        add_beam(
            f"Hibiscus_Bloom_{index:02}_Column",
            (x, y, height + 0.018),
            (x + math.cos(angle) * 0.012, y + math.sin(angle) * 0.012, height + 0.082),
            0.0075,
            column,
            root,
            objects,
            vertices=6,
            end_radius=0.005,
        )
        add_ico(
            f"Hibiscus_Bloom_{index:02}_Pollen",
            (x + math.cos(angle) * 0.012, y + math.sin(angle) * 0.012, height + 0.086),
            (0.014, 0.014, 0.011),
            pollen,
            root,
            objects,
            irregularity=0.12,
        )

    for index, (angle, distance, height) in enumerate(BUDS, 1):
        x = math.cos(angle) * distance
        y = math.sin(angle) * distance
        add_beam(
            f"Hibiscus_BudStem_{index:02}",
            (x * 0.35, y * 0.35, 0.06),
            (x, y, height - 0.02),
            0.012,
            stem,
            root,
            objects,
            vertices=6,
            end_radius=0.009,
        )
        add_ico(
            f"Hibiscus_Bud_{index:02}",
            (x, y, height + 0.010),
            (0.026, 0.024, 0.042),
            bloom_shade,
            root,
            objects,
            irregularity=0.10,
        )
        add_cone(
            f"Hibiscus_BudCalyx_{index:02}",
            (x, y, height - 0.022),
            0.030,
            0.016,
            0.030,
            leaf_deep,
            root,
            objects,
            vertices=6,
        )

    for index, (angle, distance) in enumerate(((1.15, 0.28), (3.45, 0.26), (5.75, 0.30)), 1):
        add_ico(
            f"Hibiscus_FallenPetal_{index:02}",
            (math.cos(angle) * distance, math.sin(angle) * distance, 0.009),
            (0.048, 0.036, 0.010),
            bloom,
            root,
            objects,
            irregularity=0.18,
        )

    export_asset(asset_id, root, objects)


for variant in VARIANTS:
    build_hibiscus_bush(*variant)

print(f"HIBISCUS_SET_COMPLETE={len(VARIANTS)}")
