#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
probe_dir=$(mktemp -d /tmp/keelmira-deletion.XXXXXX)
trap 'rm -rf "$probe_dir"' EXIT
xcrun swiftc -target "$(uname -m)-apple-macos14.0" \
  Shared/WidgetTimerShared.swift \
  Landfall/Models/PlayerLevel.swift \
  Landfall/Models/StudyItem.swift \
  Landfall/Models/StudyDay.swift \
  Tools/RenderHarness/SessionDeletionReliabilityProbe.swift \
  -o "$probe_dir/probe"
"$probe_dir/probe"
