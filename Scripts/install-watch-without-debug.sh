#!/usr/bin/env bash
set -euo pipefail

developer_dir="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
device="${1:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
build_root="${TMPDIR%/}/Sub2WatchDeviceInstall"
app_path="$build_root/Build/Products/Debug-watchos/Sub2Watch Watch App.app"

if [[ -z "$device" ]]; then
  echo "Usage: $0 <watch-name-or-coredevice-uuid>" >&2
  echo "Find the connected Watch with: xcrun devicectl list devices" >&2
  exit 2
fi

if [[ ! -d "$developer_dir" ]]; then
  echo "Xcode developer directory not found: $developer_dir" >&2
  exit 1
fi

export DEVELOPER_DIR="$developer_dir"

echo "Building a signed watchOS app..."
xcodebuild -quiet \
  -project "$project_root/Sub2Watch.xcodeproj" \
  -scheme "Sub2Watch Watch App" \
  -configuration Debug \
  -destination "generic/platform=watchOS" \
  -derivedDataPath "$build_root" \
  -allowProvisioningUpdates \
  build

if [[ ! -d "$app_path" ]]; then
  echo "Built app not found: $app_path" >&2
  exit 1
fi

echo "Installing on $device without launching a debug session..."
xcrun devicectl device install app \
  --timeout 120 \
  --device "$device" \
  "$app_path"

echo "Installed. Launch Sub2Watch from the Watch app grid or list."
