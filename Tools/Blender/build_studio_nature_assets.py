"""Build the modular island foundation used by 3D Studio.

The foundation is authored as an independent, origin-grounded prop, and stays
deliberately shallow so several of them can be combined without looking like
thick cylinders. An editable .blend source, the runtime USDZ file, and a review
render are generated.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "Assets3D/source"
RESOURCE_DIR = ROOT / "Landfall/Resources"
RENDER_DIR = ROOT / "marketing/3d"


def rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[index : index + 2], 16) / 255 for index in (0, 2, 4)) + (alpha,)


def make_material(
    name: str,
    color: str,
    roughness: float = 0.9,
    *,
    double_sided: bool = False,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = rgba(color)
    material.use_nodes = True
    material.use_backface_culling = not double_sided
    shader = next(node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = rgba(color)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = 0.0
    return material


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def mesh_object(
    name: str,
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    material: bpy.types.Material,
    root: bpy.types.Object,
    asset_objects: list[bpy.types.Object],
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(material)
    mesh.validate(clean_customdata=False)
    mesh.update()
    for polygon in mesh.polygons:
        polygon.use_smooth = False
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = root
    asset_objects.append(obj)
    return obj


def make_root(name: str) -> bpy.types.Object:
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    return root


def look_at(obj: bpy.types.Object, point: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_preview_stage(
    target: tuple[float, float, float],
    camera_location: tuple[float, float, float],
    ground_color: str,
) -> None:
    preview_ground = make_material("PREVIEW_Ground", ground_color, 0.96)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.012))
    ground = bpy.context.object
    ground.name = "PREVIEW_Ground"
    ground.data.materials.append(preview_ground)

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#294D45")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.30

    for name, location, energy, size, color in (
        ("PREVIEW_Key", (-4.5, -5.0, 6.2), 560, 4.5, "#FFF0D0"),
        ("PREVIEW_Fill", (4.8, -1.8, 4.0), 360, 3.8, "#8FD3B6"),
        ("PREVIEW_Rim", (1.0, 4.2, 5.2), 430, 3.0, "#D5E9D4"),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = rgba(color)[:3]
        look_at(light, target)

    bpy.ops.object.camera_add(location=camera_location)
    camera = bpy.context.object
    camera.name = "PREVIEW_Camera"
    camera.data.lens = 58
    look_at(camera, target)
    bpy.context.scene.camera = camera


def export_asset(
    root: bpy.types.Object,
    asset_objects: list[bpy.types.Object],
    blend_path: Path,
    usdz_path: Path,
    render_path: Path,
) -> None:
    blend_path.parent.mkdir(parents=True, exist_ok=True)
    usdz_path.parent.mkdir(parents=True, exist_ok=True)
    render_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    # Runtime draw calls stay low by combining meshes that share a material.
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
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 1100
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = str(render_path)
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.render.render(write_still=True)

    triangles = sum(
        len(polygon.vertices) - 2
        for obj in export_objects
        for polygon in obj.data.polygons
    )
    print(f"ASSET={root.name} MESHES={len(export_objects)} TRIANGLES={triangles}")
    print(f"BLEND={blend_path}")
    print(f"USDZ={usdz_path}")
    print(f"RENDER={render_path}")


def island_point(radius: float, angle: float, height: float) -> tuple[float, float, float]:
    irregularity = 1.0 + math.sin(angle * 3.0 + 0.7) * 0.045 + math.sin(angle * 7.0 - 0.3) * 0.025
    return (
        math.cos(angle) * 1.64 * radius * irregularity,
        math.sin(angle) * 1.13 * radius * irregularity,
        height,
    )


def ring_surface(
    name: str,
    inner_radius: float,
    outer_radius: float,
    inner_height: float,
    outer_height: float,
    segments: int,
    material: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
) -> bpy.types.Object:
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for index in range(segments):
        angle = math.tau * index / segments
        ripple = math.sin(angle * 4.0 + 0.4) * 0.018
        vertices.append(island_point(inner_radius, angle, inner_height + ripple))
        vertices.append(island_point(outer_radius, angle, outer_height + ripple * 0.55))
    for index in range(segments):
        next_index = (index + 1) % segments
        a, b = index * 2, next_index * 2
        faces.extend(((a, a + 1, b), (b, a + 1, b + 1)))
    return mesh_object(name, vertices, faces, material, root, objects)


def side_facets(
    name: str,
    upper_radius: float,
    lower_radius: float,
    upper_height: float,
    lower_height: float,
    segments: int,
    group_index: int,
    group_count: int,
    material: bpy.types.Material,
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
) -> bpy.types.Object:
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for index in range(segments):
        if index % group_count != group_index:
            continue
        next_index = (index + 1) % segments
        angle = math.tau * index / segments
        next_angle = math.tau * next_index / segments
        top_a = island_point(upper_radius, angle, upper_height + math.sin(angle * 4.0 + 0.4) * 0.010)
        top_b = island_point(upper_radius, next_angle, upper_height + math.sin(next_angle * 4.0 + 0.4) * 0.010)
        bottom_a = island_point(lower_radius, angle, lower_height)
        bottom_b = island_point(lower_radius, next_angle, lower_height)
        start = len(vertices)
        vertices.extend((top_a, bottom_a, top_b, bottom_b))
        faces.extend(((start, start + 1, start + 2), (start + 2, start + 1, start + 3)))
    return mesh_object(name, vertices, faces, material, root, objects)


def build_island_base() -> None:
    reset_scene()
    root = make_root("Island_Foundation")
    objects: list[bpy.types.Object] = []
    materials = {
        "grass": make_material("LF_IslandGrass", "#668B69", 0.96),
        "grass_light": make_material("LF_IslandGrassLight", "#789A72", 0.94),
        "sand": make_material("LF_IslandSand", "#C4B58D", 0.98),
        "sand_light": make_material("LF_IslandSandLight", "#D6C9A4", 0.97),
        "rock_dark": make_material("LF_IslandRockDark", "#485B52", 0.99),
        "rock": make_material("LF_IslandRock", "#607168", 0.98),
        "rock_light": make_material("LF_IslandRockLight", "#758178", 0.97),
    }
    segments = 32

    # A gently crowned top avoids the flat-disc look while remaining easy to build on.
    center_vertices = [(0, 0, 0.385)]
    center_faces: list[tuple[int, ...]] = []
    for index in range(segments):
        angle = math.tau * index / segments
        center_vertices.append(island_point(0.46, angle, 0.365 + math.sin(angle * 3.0) * 0.012))
    for index in range(segments):
        center_faces.append((0, index + 1, (index + 1) % segments + 1))
    mesh_object("Foundation_Grass_Crown", center_vertices, center_faces, materials["grass_light"], root, objects)
    ring_surface("Foundation_Grass_Field", 0.46, 0.87, 0.365, 0.305, segments, materials["grass"], root, objects)
    ring_surface("Foundation_Sand_Rim", 0.87, 1.02, 0.305, 0.235, segments, materials["sand_light"], root, objects)

    # Three alternating facet colors give the shallow cliff readable depth without thickness.
    rock_materials = (materials["rock_dark"], materials["rock"], materials["rock_light"])
    for group_index, rock_material in enumerate(rock_materials):
        side_facets(
            f"Foundation_UpperCliff_{group_index}", 1.02, 0.93, 0.235, 0.105,
            segments, group_index, len(rock_materials), rock_material, root, objects,
        )
        side_facets(
            f"Foundation_LowerCliff_{group_index}", 0.93, 0.72, 0.105, 0.018,
            segments, (group_index + 1) % 3, len(rock_materials), rock_material, root, objects,
        )

    bottom_vertices = [(0, 0, 0.014)]
    bottom_faces: list[tuple[int, ...]] = []
    for index in range(segments):
        angle = math.tau * index / segments
        bottom_vertices.append(island_point(0.72, angle, 0.018))
    for index in range(segments):
        bottom_faces.append((0, (index + 1) % segments + 1, index + 1))
    mesh_object("Foundation_Underside", bottom_vertices, bottom_faces, materials["rock_dark"], root, objects)

    # Sparse edge stones break the perfect outline but leave the top open for placed props.
    for index in range(9):
        angle = math.tau * index / 9 + 0.22 * math.sin(index * 1.7)
        radius = 0.99 + (index % 3) * 0.025
        location = island_point(radius, angle, 0.245)
        size = 0.075 + (index % 4) * 0.014
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=size, location=location)
        rock = bpy.context.object
        rock.name = f"Foundation_EdgeStone_{index + 1:02}"
        rock.scale = (1.25, 0.86, 0.70 + (index % 3) * 0.11)
        rock.rotation_euler = (0.12 * index, 0.18 * index, angle)
        rock.data.materials.append(rock_materials[index % len(rock_materials)])
        rock.parent = root
        objects.append(rock)

    add_preview_stage((0, 0, 0.22), (3.25, -4.6, 2.75), "#24453F")
    export_asset(
        root,
        objects,
        SOURCE_DIR / "island_base.blend",
        RESOURCE_DIR / "island_base.usdz",
        RENDER_DIR / "island-base.png",
    )


build_island_base()
