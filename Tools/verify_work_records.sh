#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
probe_dir=$(mktemp -d /tmp/keelmira-records.XXXXXX)
trap 'rm -rf "$probe_dir"' EXIT
xcrun swiftc Landfall/Views/Records/WorkRecordWeeklySummary.swift Tools/RenderHarness/WorkRecordWeeklySummaryProbe.swift -o "$probe_dir/weekly"
"$probe_dir/weekly"
xcrun swiftc Landfall/Views/Trace/WorkRecordTimeline.swift Tools/RenderHarness/WorkRecordTimelineProbe.swift -o "$probe_dir/timeline"
"$probe_dir/timeline"
Tools/verify_work_record_timing.sh
