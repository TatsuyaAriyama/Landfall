"""Convert one USD/USDZ asset to a web-ready binary glTF with Blender.

Usage:
  blender --background --python convert_usdz_to_glb.py -- input.usdz output.glb
"""

from pathlib import Path
import sys

import bpy


def arguments() -> tuple[Path, Path]:
    try:
        separator = sys.argv.index("--")
        source, destination = sys.argv[separator + 1 : separator + 3]
    except (ValueError, IndexError):
        raise SystemExit("expected: -- input.usdz output.glb")
    return Path(source).resolve(), Path(destination).resolve()


source_path, destination_path = arguments()
destination_path.parent.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=str(source_path))

# The authored USD uses meters and a Y-up stage. Blender's glTF exporter applies
# the coordinate conversion while retaining object hierarchy and material names.
bpy.ops.export_scene.gltf(
    filepath=str(destination_path),
    export_format="GLB",
    export_yup=True,
    export_apply=False,
    export_materials="EXPORT",
    export_cameras=False,
    export_lights=False,
)
