#!/usr/bin/env bash
# Build SplayBench (ios/SplayBench) in Release, install it on the connected
# iPhone, launch it, and stream its console here.
#
# Prereqs: Xcode with the iOS platform, `brew install xcodegen`, the phone paired
# and in Developer Mode, an Apple ID for the team in Xcode ▸ Settings ▸ Accounts.
#
# Env:
#   DEVICE          devicectl device identifier (default: first connected iPhone)
#   CONFIGURATION   Debug|Release (default: Release — benchmarks are meaningless in Debug)
#   NO_LAUNCH=1     build + install only
#   COMPILE_ONLY=1  generic iOS build with signing off; exits non-zero on failure
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export XCODEGEN_DIR="$ROOT/ios/SplayBench"
export PROJECT="SplayBench.xcodeproj"
export SCHEME="SplayBench"
export CONFIGURATION="${CONFIGURATION:-Release}"
export BUILD_DIR="$XCODEGEN_DIR/build"
export BUNDLE_ID="com.macparakeet.mc.splaybench"

source "$ROOT/scripts/dev/lib/iphone_common.sh"
ios_main
