#!/bin/zsh

# Build, validate, and install the Simulator app without discarding app data.
# Do not add CODE_SIGNING_ALLOWED=NO here: Firebase Auth needs the app's signed
# identifier in order to persist its user in the Simulator Keychain.

set -euo pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h}
derived_data_path=${KEELMIRA_DERIVED_DATA_PATH:-/tmp/keelmira-signed-simulator}
bundle_id=com.tatsuyaariyama.Landfall

booted_ids=$(xcrun simctl list devices booted \
    | sed -nE 's/.*\(([0-9A-F-]{36})\) \(Booted\).*/\1/p')

if [[ -z "$booted_ids" ]]; then
    print -u2 "No booted iOS Simulator was found."
    exit 1
fi

first_id=${booted_ids%%$'\n'*}

cd "$repo_root"
xcodebuild \
    -project Landfall.xcodeproj \
    -scheme Landfall \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination "platform=iOS Simulator,id=$first_id" \
    -derivedDataPath "$derived_data_path" \
    build

app_path="$derived_data_path/Build/Products/Debug-iphonesimulator/Landfall.app"

codesign --verify --deep --strict "$app_path"
signed_identifier=$(codesign -dvv "$app_path" 2>&1 \
    | sed -n 's/^Identifier=//p')
plist_identifier=$(plutil -extract CFBundleIdentifier raw "$app_path/Info.plist")
if [[ "$plist_identifier" != "$bundle_id" || "$signed_identifier" != "$bundle_id" ]]; then
    print -u2 "The Simulator app has an invalid signing identifier. Refusing to install it."
    print -u2 "Expected: $bundle_id"
    print -u2 "Info.plist: $plist_identifier"
    print -u2 "Code signature: $signed_identifier"
    exit 1
fi

while IFS= read -r simulator_id; do
    [[ -z "$simulator_id" ]] && continue
    xcrun simctl terminate "$simulator_id" "$bundle_id" 2>/dev/null || true
    xcrun simctl install "$simulator_id" "$app_path"
    xcrun simctl launch "$simulator_id" "$bundle_id"
    print "Installed signed KeelMira build on $simulator_id"
done <<< "$booted_ids"
