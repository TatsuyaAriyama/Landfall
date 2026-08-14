#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
TARGET_DIR="$PROJECT_DIR/Vendor/EOSSDK.xcframework"
ARCHIVE_URL="https://onlineservices.epicgames.com/api/cosmos/sdk/download?archive_id=879&archive_type=ios"
ARCHIVE_SHA256="5f07ffe31db78ed0a5b71cfa344644221684cccea00eefe3a54514960660d179"
SDK_VERSION="1.19.1.2"

if [ -d "$TARGET_DIR" ]; then
    echo "EOS iOS SDK already exists at $TARGET_DIR"
    echo "Remove that exact directory manually before changing SDK versions."
    exit 0
fi

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/keelmira-eos.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM
ARCHIVE_PATH="$TEMP_DIR/eos-ios-sdk.zip"

echo "Downloading Epic Online Services iOS SDK $SDK_VERSION..."
curl --fail --location --silent --show-error "$ARCHIVE_URL" --output "$ARCHIVE_PATH"

ACTUAL_SHA256=$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')
if [ "$ACTUAL_SHA256" != "$ARCHIVE_SHA256" ]; then
    echo "EOS SDK checksum mismatch." >&2
    echo "Expected: $ARCHIVE_SHA256" >&2
    echo "Actual:   $ACTUAL_SHA256" >&2
    exit 1
fi

unzip -q "$ARCHIVE_PATH" -d "$TEMP_DIR/extracted"
SOURCE_DIR=$(find "$TEMP_DIR/extracted" -type d -path '*/SDK/Bin/IOS/EOSSDK.xcframework' -print -quit)
if [ -z "$SOURCE_DIR" ]; then
    echo "EOSSDK.xcframework was not found in the verified archive." >&2
    exit 1
fi

mkdir -p "$PROJECT_DIR/Vendor"
ditto "$SOURCE_DIR" "$TARGET_DIR"

INFO_PLIST="$TARGET_DIR/Info.plist"
LIBRARY_COUNT=$(/usr/libexec/PlistBuddy -c 'Print :AvailableLibraries' "$INFO_PLIST" | grep -c 'Dict {' || true)
SUPPORTED_PLATFORM=$(/usr/libexec/PlistBuddy -c 'Print :AvailableLibraries:0:SupportedPlatform' "$INFO_PLIST")
if [ "$LIBRARY_COUNT" -ne 1 ] || [ "$SUPPORTED_PLATFORM" != "ios" ]; then
    echo "Unexpected EOS SDK platform layout; refusing to continue." >&2
    exit 1
fi

echo "Installed EOS iOS SDK $SDK_VERSION at $TARGET_DIR"
echo "This SDK is device-only; iOS Simulator must use the Firestore fallback."
