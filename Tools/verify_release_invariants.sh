#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root"

probe_binary="$(mktemp /tmp/keelmira-first-voyage-probe.XXXXXX)"
progression_probe_binary="$(mktemp /tmp/keelmira-progression-probe.XXXXXX)"
ocean_probe_binary="$(mktemp /tmp/keelmira-ocean-wave-probe.XXXXXX)"
trap 'rm -f "$probe_binary" "$progression_probe_binary" "$ocean_probe_binary"' EXIT

xcrun swiftc \
  Landfall/Models/FirstVoyageRoutingPolicy.swift \
  Landfall/Models/VoyageTimerMath.swift \
  Tools/RenderHarness/FirstVoyageRegressionProbe.swift \
  -o "$probe_binary"
"$probe_binary"

xcrun swiftc \
  Landfall/Models/ProgressionUnlockPolicy.swift \
  Tools/RenderHarness/ProgressionUnlockProbe.swift \
  -o "$progression_probe_binary"
"$progression_probe_binary"

xcrun swiftc \
  Landfall/OceanWaveSpectrum.swift \
  Tools/RenderHarness/OceanWaveSpectrumProbe.swift \
  -o "$ocean_probe_binary"
"$ocean_probe_binary"

search_swift() {
  /usr/bin/grep -R -n -E --include='*.swift' "$1" Landfall Shared LandfallWidget
}

if search_swift 'timerStart[[:space:]]*>[[:space:]]*0'; then
  print -u2 'Release gate failed: use VoyageTimerMath.isActive instead of a raw timerStart comparison.'
  exit 1
fi

if search_swift 'Int\(.*timeIntervalSince1970[[:space:]]*-[[:space:]]*timerStart'; then
  print -u2 'Release gate failed: raw persisted-timer conversion can recreate an epoch-sized duration.'
  exit 1
fi

if ! /usr/bin/grep -q -E 'FirstVoyageRoutingPolicy\.route' Landfall/LandfallApp.swift; then
  print -u2 'Release gate failed: app entry no longer uses the account-aware first-voyage policy.'
  exit 1
fi

if ! /usr/bin/grep -A8 -E 'id: "gardenEstate"' Landfall/Models/Boat.swift \
    | /usr/bin/grep -q -E 'requiresVoyagePass: true'; then
  print -u2 'Release gate failed: Garden Estate must remain Voyage Pass-exclusive.'
  exit 1
fi

if ! /usr/bin/grep -A8 -E 'id: "corsair"' Landfall/Models/Boat.swift \
    | /usr/bin/grep -q -E 'unlockLevel: 10'; then
  print -u2 'Release gate failed: the pirate ship must unlock at level 10.'
  exit 1
fi

if ! /usr/bin/grep -q -E 'buildConfiguration = "Release"' Landfall.xcodeproj/xcshareddata/xcschemes/Landfall.xcscheme; then
  print -u2 'Release gate failed: the archive action must use the signed Release configuration.'
  exit 1
fi

build_version_count="$(
  /usr/bin/grep -E -o 'CURRENT_PROJECT_VERSION = [0-9]+' Landfall.xcodeproj/project.pbxproj \
    | awk '{print $3}' \
    | sort -u \
    | wc -l \
    | tr -d ' '
)"
if [[ "$build_version_count" != "1" ]]; then
  print -u2 'Release gate failed: app and widget build numbers do not match.'
  exit 1
fi

marketing_version_count="$(
  /usr/bin/grep -E -o 'MARKETING_VERSION = [0-9]+\.[0-9]+' Landfall.xcodeproj/project.pbxproj \
    | awk '{print $3}' \
    | sort -u \
    | wc -l \
    | tr -d ' '
)"
if [[ "$marketing_version_count" != "1" ]]; then
  print -u2 'Release gate failed: app and widget marketing versions do not match.'
  exit 1
fi

print 'KeelMira release invariants: PASS'
