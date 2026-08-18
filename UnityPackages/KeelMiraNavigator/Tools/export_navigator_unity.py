"""Convert the rigged KeelMira navigator GLB into editable Blender and Unity FBX files."""

from __future__ import annotations

import sys
from pathlib import Path

import bpy


def arguments() -> tuple[Path, Path, Path]:
    args = sys.argv
    values = args[args.index("--") + 1 :] if "--" in args else []
    if len(values) != 3:
        raise SystemExit(
            "Usage: blender -b --python export_navigator_unity.py -- "
            "<input.glb> <source.blend> <output.fbx>"
        )
    return tuple(Path(value).resolve() for value in values)


def descendants(root: bpy.types.Object) -> list[bpy.types.Object]:
    result = [root]
    for child in root.children:
        result.extend(descendants(child))
    return result


source_glb, blend_destination, fbx_destination = arguments()
if not source_glb.is_file():
    raise FileNotFoundError(source_glb)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(source_glb))

root = bpy.data.objects.get("Navigator_Asset")
if root is None:
    raise RuntimeError("Navigator_Asset was not found in the GLB")

blend_destination.parent.mkdir(parents=True, exist_ok=True)
fbx_destination.parent.mkdir(parents=True, exist_ok=True)

for obj in list(bpy.context.scene.objects):
    if obj not in descendants(root):
        bpy.data.objects.remove(obj, do_unlink=True)

bpy.ops.wm.save_as_mainfile(filepath=str(blend_destination))

bpy.ops.object.select_all(action="DESELECT")
for obj in descendants(root):
    obj.select_set(True)
bpy.context.view_layer.objects.active = root

bpy.ops.export_scene.fbx(
    filepath=str(fbx_destination),
    use_selection=True,
    object_types={"EMPTY", "MESH", "ARMATURE"},
    use_mesh_modifiers=True,
    mesh_smooth_type="FACE",
    use_custom_props=True,
    add_leaf_bones=False,
    bake_anim=False,
    use_armature_deform_only=False,
    apply_unit_scale=True,
    apply_scale_options="FBX_SCALE_UNITS",
    axis_forward="-Z",
    axis_up="Y",
    path_mode="AUTO",
    embed_textures=False,
)

print(f"Saved editable navigator source: {blend_destination}")
print(f"Exported Unity navigator FBX: {fbx_destination}")
