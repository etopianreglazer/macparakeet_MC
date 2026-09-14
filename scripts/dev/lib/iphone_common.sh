#!/usr/bin/env bash
# Shared plumbing for the iPhone scripts (install_iphone.sh, install_iphone_bench.sh):
# device discovery, an xcodebuild wrapper that fails when the build fails, and
# install + launch through devicectl. Source this file; do not run it.
#
# Every function needs: XCODEGEN_DIR (folder with project.yml), PROJECT (xcodeproj
# name), SCHEME, CONFIGURATION, BUILD_DIR, BUNDLE_ID.

ios_require_xcodegen() {
  command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen" >&2; exit 1; }
}

# An iPhone's CoreDevice identifier (or $DEVICE if set): a cable-connected one
# first, else a paired one reachable over the local network — devicectl opens
# the tunnel on demand, so no cable is needed, only an unlocked phone. Parses
# devicectl's JSON rather than its table, so names with spaces are safe.
ios_pick_device() {
  if [[ -n "${DEVICE:-}" ]]; then printf '%s' "$DEVICE"; return; fi
  local json; json="$(mktemp)"
  xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 || { rm -f "$json"; return; }
  python3 - "$json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
phones = [dev for dev in d.get("result", {}).get("devices", [])
          if dev.get("hardwareProperties", {}).get("deviceType") == "iPhone"]
def rank(dev):
    conn = dev.get("connectionProperties", {})
    if conn.get("tunnelState") == "connected": return 0
    if conn.get("pairingState") == "paired" and conn.get("tunnelState") != "unavailable": return 1
    return 9
phones.sort(key=rank)
if phones and rank(phones[0]) < 9:
    print(phones[0]["identifier"])
PY
  rm -f "$json"
}

# Build for generic iOS. Prints only the interesting lines but exits non-zero
# when xcodebuild does (PIPESTATUS, not the grep's status). Extra args are
# passed to xcodebuild (e.g. CODE_SIGNING_ALLOWED=NO).
ios_build() {
  local label="$1"; shift
  echo "Building $SCHEME ($CONFIGURATION, $label)…"
  ( cd "$XCODEGEN_DIR" && xcodegen generate --quiet )
  # Log to a file and grep afterwards: the exit status is xcodebuild's own,
  # not the grep's, and no `|| true` can reset it.
  local log="$BUILD_DIR/xcodebuild-$SCHEME-$CONFIGURATION.log"
  mkdir -p "$BUILD_DIR"
  local status=0
  xcodebuild -project "$XCODEGEN_DIR/$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
    -destination "generic/platform=iOS" -derivedDataPath "$BUILD_DIR" \
    -skipPackagePluginValidation -skipMacroValidation "$@" build > "$log" 2>&1 || status=$?
  grep -E "error:|warning: .*/ios/|BUILD (SUCCEEDED|FAILED)" "$log" || true
  if [[ $status -ne 0 ]]; then
    echo "xcodebuild failed (exit $status); full log: $log" >&2
    exit "$status"
  fi
  # A failed rebuild into the same derived data can leave a stale .app behind;
  # the exit code above is the truth, this is a sanity check on the artefact.
  APP="$BUILD_DIR/Build/Products/$CONFIGURATION-iphoneos/$SCHEME.app"
  [[ -d "$APP" ]] || { echo "Build reported success but $APP is missing" >&2; exit 1; }
}

ios_install_and_launch() {
  local device="$1"
  echo "Installing on $device…"
  xcrun devicectl device install app --device "$device" "$APP"
  if [[ "${NO_LAUNCH:-0}" == "1" ]]; then exit 0; fi
  echo "Launching (console streams below; Ctrl-C to detach — the app keeps running)…"
  xcrun devicectl device process launch --device "$device" --console "$BUNDLE_ID"
}

# The whole flow: compile-only when COMPILE_ONLY=1, otherwise build → install → launch.
ios_main() {
  ios_require_xcodegen
  if [[ "${COMPILE_ONLY:-0}" == "1" ]]; then
    ios_build "unsigned" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
    exit 0
  fi
  local device; device="$(ios_pick_device)"
  if [[ -z "$device" ]]; then
    echo "No reachable iPhone (xcrun devicectl list devices): pair it once over a cable, then keep it unlocked on the same Wi-Fi." >&2
    exit 1
  fi
  ios_build "signed" -allowProvisioningUpdates
  ios_install_and_launch "$device"
}
