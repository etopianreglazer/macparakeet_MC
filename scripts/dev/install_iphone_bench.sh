#!/usr/bin/env bash
# Build SplayBench (ios/SplayBench) in Release, install it on the connected
# iPhone, launch it, and stream its console here.
#
# Prereqs: Xcode with the iOS platform, `brew install xcodegen`, the phone paired
# and in Developer Mode, the Apple Development cert in the login keychain.
#
# Env:
#   DEVICE        devicectl device name/UDID (default: first connected iPhone)
#   CONFIGURATION Debug|Release (default: Release — benchmarks are meaningless in Debug)
#   NO_LAUNCH=1   build + install only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BENCH_DIR="$ROOT/ios/SplayBench"
BUILD_DIR="$BENCH_DIR/build"
CONFIGURATION="${CONFIGURATION:-Release}"
BUNDLE_ID="com.macparakeet.mc.splaybench"

command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen" >&2; exit 1; }

pick_device() {
  if [[ -n "${DEVICE:-}" ]]; then printf '%s' "$DEVICE"; return; fi
  # First row that looks like a connected iPhone (State column = connected).
  xcrun devicectl list devices 2>/dev/null \
    | awk 'NR>2 && $0 ~ /iPhone/ && $0 ~ /connected/ { print $1 " " $2; exit }' \
    | sed -E 's/ +$//'
}
DEVICE_NAME="$(pick_device)"
if [[ -z "$DEVICE_NAME" ]]; then
  echo "No connected iPhone found (xcrun devicectl list devices). Plug it in, unlock it, trust this Mac." >&2
  exit 1
fi
echo "Device: $DEVICE_NAME"

cd "$BENCH_DIR"
xcodegen generate --quiet

echo "Building SplayBench ($CONFIGURATION)…"
xcodebuild \
  -project SplayBench.xcodeproj \
  -scheme SplayBench \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$BUILD_DIR" \
  -allowProvisioningUpdates \
  -skipPackagePluginValidation -skipMacroValidation \
  build \
  | grep -E "error:|warning: .*SplayBench|BUILD (SUCCEEDED|FAILED)" || true

APP="$BUILD_DIR/Build/Products/$CONFIGURATION-iphoneos/SplayBench.app"
[[ -d "$APP" ]] || { echo "Build failed: $APP missing" >&2; exit 1; }

echo "Installing…"
xcrun devicectl device install app --device "$DEVICE_NAME" "$APP"

if [[ "${NO_LAUNCH:-0}" == "1" ]]; then exit 0; fi

echo "Launching (console streams below; Ctrl-C to detach — the app keeps running)…"
xcrun devicectl device process launch --device "$DEVICE_NAME" --console "$BUNDLE_ID"
