#!/bin/zsh
set -euo pipefail

# UIKit/Core Image need the booted iOS runtime; the other release probes run
# directly on macOS. This never installs or changes the user's application.
script_dir=${0:A:h}
cd "${script_dir:h}"
probe_directory=$(mktemp -d /tmp/keelmira-photo-probe.XXXXXX)
trap 'rm -rf "$probe_directory"' EXIT
simulator_sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)

SDKROOT="$simulator_sdk" xcrun swiftc \
    -sdk "$simulator_sdk" \
    -target "$(uname -m)-apple-ios17.0-simulator" \
    Landfall/Views/HomeIsland/HomeIslandBrightness.swift \
    Landfall/Views/HomeIsland/HomeIslandSky.swift \
    Landfall/Views/HomeIsland/HomeIslandPhotoExport.swift \
    Tools/RenderHarness/HomeIslandPhotoExportProbe.swift \
    -o "$probe_directory/probe"
codesign --force --sign - "$probe_directory/probe"
xcrun simctl spawn booted "$probe_directory/probe"
