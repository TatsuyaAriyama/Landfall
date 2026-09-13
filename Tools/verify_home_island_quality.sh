#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
probe_directory=$(mktemp -d /tmp/keelmira-island-quality.XXXXXX)
trap 'rm -rf "$probe_directory"' EXIT
for name in PlacementSnap PhotoFraming CatalogPreferences FoundationRaycast; do
    xcrun swiftc \
        "Landfall/Views/HomeIsland/HomeIsland${name}.swift" \
        "Tools/RenderHarness/HomeIsland${name}Probe.swift" \
        -o "$probe_directory/$name"
    "$probe_directory/$name" Landfall/Resources
done
