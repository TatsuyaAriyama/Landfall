#!/bin/zsh
set -euo pipefail
repo_root="${0:A:h:h}"
cd "$repo_root"
probe_dir="$(mktemp -d /tmp/keelmira-record-timing.XXXXXX)"
trap 'rm -rf "$probe_dir"' EXIT
# Exercise the production implementation while keeping every App Group write isolated.
python3 - "$probe_dir/WidgetTimerShared.swift" <<'PY'
from pathlib import Path
import sys, uuid
source = Path('Shared/WidgetTimerShared.swift').read_text()
source = source.replace('static let appGroup = "group.com.tatsuyaariyama.Landfall"',
                        'static let appGroup = "keelmira-timing-probe.' + str(uuid.uuid4()) + '"', 1)
Path(sys.argv[1]).write_text(source)
PY
xcrun swiftc -target "$(uname -m)-apple-macos14.0" \
  "$probe_dir/WidgetTimerShared.swift" \
  Tools/RenderHarness/WorkRecordTimingProbe.swift \
  -o "$probe_dir/probe"
"$probe_dir/probe"
