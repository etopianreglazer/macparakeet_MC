#!/usr/bin/env bash
# Build the Splay iPhone app (ios/Splay), install it on the connected iPhone,
# and launch it. Mirrors install_local.sh for the phone.
#
# Prereqs: Xcode with the iOS platform, `brew install xcodegen`, the phone paired
# and in Developer Mode, and an Apple ID for the team in Xcode ▸ Settings ▸ Accounts
# (automatic signing needs it to mint the iOS profiles).
#
# Env:
#   DEVICE          devicectl device identifier (default: first connected iPhone)
#   CONFIGURATION   Debug|Release (default: Debug)
#   NO_LAUNCH=1     build + install only
#   COMPILE_ONLY=1  generic iOS build with signing off (CI / no phone); exits non-zero on failure
#   MODELS_SOURCE   FluidAudio cache to stage the bundled models from
#                   (default: ~/Library/Application Support/FluidAudio/Models)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export XCODEGEN_DIR="$ROOT/ios/Splay"
export PROJECT="Splay.xcodeproj"
export SCHEME="Splay"
export CONFIGURATION="${CONFIGURATION:-Debug}"
export BUILD_DIR="$XCODEGEN_DIR/build"
export BUNDLE_ID="com.macparakeet.mc.ios"

source "$ROOT/scripts/dev/lib/iphone_common.sh"
ios_stage_bundled_models
ios_main
