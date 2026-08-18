# Tideway Navigator prototype archive

Status: **editing prototype — do not ship or release**.

This directory holds runtime exports preserved only for future Blender editing
and visual review. They are intentionally outside both `Landfall/Resources`
and `web/public`.

- `tideway_navigator.usdz`: archived SceneKit/USD export
- `tideway_navigator.twmotion`: archived sampled motion data
- `tideway_navigator.glb`: archived web/Blender interchange export
- `ios/TidewayNavigator.experimental.swift`: archived iOS loader and animator

Editable source remains in `Assets3D/source/tideway_navigator.blend`, and the
generator remains in `Tools/Blender/build_tideway_navigator.py`. The generator
is configured to write runtime exports back into this archive only. Motion
compiler examples also target this archive, never the application Resources.
