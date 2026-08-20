#!/usr/bin/env bash
set -euo pipefail

# Build, sign, and install Splay.app into /Applications for personal use.
#
# This is the "apply a fix and get it into /Applications" loop for the fork. It:
#   - builds a real .app bundle via SwiftPM (BUILD_SYSTEM=swiftpm) — no xcodebuild,
#     so it works even when the machine's xcodebuild toolchain is broken
#   - signs inside-out with your Apple Development certificate (stable identity →
#     mic/accessibility/screen-recording permissions persist across rebuilds)
#   - installs Splay while deliberately retaining the existing fork bundle id
#     and data folder, so local transcripts and macOS permissions persist
#
# It deliberately does NOT notarize or use the hardened runtime — neither is needed
# to run an app locally, and skipping the hardened runtime avoids library-validation
# friction with the bundled ffmpeg helper.
#
# Env overrides:
#   APP_NAME       (default: Splay)
#   BUNDLE_ID      (default: com.macparakeet.mc)
#   VERSION        (default: 0.6.0)
#   INSTALL_DIR    (default: /Applications)
#   SIGN_IDENTITY  (default: first "Apple Development: …" cert in your keychain)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="${APP_NAME:-Splay}"
BUNDLE_ID="${BUNDLE_ID:-com.macparakeet.mc}"
VERSION="${VERSION:-0.6.0}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
APP_PATH="$ROOT_DIR/dist/${APP_NAME}.app"

pick_identity() {
  if [[ -n "${SIGN_IDENTITY:-}" ]]; then printf '%s' "$SIGN_IDENTITY"; return; fi
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n1
}
SIGN_IDENTITY="$(pick_identity)"
if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "No Apple Development signing identity found." >&2
  echo "Add one via Xcode > Settings > Accounts, or pass SIGN_IDENTITY=\"…\"." >&2
  exit 1
fi
echo "Signing identity: $SIGN_IDENTITY"

echo "[1/4] Building ${APP_NAME}.app (SwiftPM release, no xcodebuild)…"
APP_NAME="$APP_NAME" BUNDLE_ID="$BUNDLE_ID" VERSION="$VERSION" BUILD_SYSTEM=swiftpm \
  "$ROOT_DIR/scripts/dist/build_app_bundle.sh"

echo "[2/4] Signing inside-out with ${SIGN_IDENTITY}…"
sign() { codesign --force --sign "$SIGN_IDENTITY" "$@"; }

# Sparkle.framework (inside-out: XPC services, nested apps, standalone execs, then framework)
SPARKLE_FW="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FW" ]]; then
  while IFS= read -r -d '' x; do sign "$x"; done < <(find "$SPARKLE_FW" -name "*.xpc" -type d -print0 2>/dev/null || true)
  while IFS= read -r -d '' x; do sign "$x"; done < <(find "$SPARKLE_FW" -name "*.app" -type d -print0 2>/dev/null || true)
  while IFS= read -r -d '' x; do sign "$x"; done < <(find "$SPARKLE_FW/Versions/B" -maxdepth 1 -type f -perm -111 -print0 2>/dev/null || true)
  sign "$SPARKLE_FW"
fi

# Bundled dylibs and any other frameworks
while IFS= read -r -d '' d; do sign "$d"; done < <(find "$APP_PATH/Contents/Frameworks" -maxdepth 1 -type f -name "*.dylib" -print0 2>/dev/null || true)
while IFS= read -r -d '' fw; do sign "$fw"; done < <(find "$APP_PATH/Contents/Frameworks" -maxdepth 1 -name "*.framework" -type d ! -name "Sparkle.framework" -print0 2>/dev/null || true)

# Helper binaries under Resources (ffmpeg)
while IFS= read -r -d '' b; do sign "$b"; done < <(
  find "$APP_PATH/Contents/Resources" -maxdepth 1 -type f -perm -111 \
    \( -name "ffmpeg" \) -print0 2>/dev/null || true
)

# Other executables in MacOS (e.g. bundled macparakeet-cli) — skip the app's own exec
while IFS= read -r -d '' b; do
  [[ "$(basename "$b")" == "$APP_NAME" ]] && continue
  sign "$b"
done < <(find "$APP_PATH/Contents/MacOS" -maxdepth 1 -type f -perm -111 -print0 2>/dev/null || true)

# The app itself, with entitlements (audio-input, calendars, network)
sign --entitlements "$ROOT_DIR/scripts/dist/MacParakeet.entitlements" "$APP_PATH"

echo "[3/4] Verifying signature…"
codesign --verify --strict --verbose=2 "$APP_PATH"

echo "[4/4] Installing to ${INSTALL_DIR}…"
osascript -e "quit app \"${APP_NAME}\"" >/dev/null 2>&1 || true
rm -rf "${INSTALL_DIR:?}/${APP_NAME}.app"
cp -R "$APP_PATH" "$INSTALL_DIR/"

echo ""
echo "✅ Installed: ${INSTALL_DIR}/${APP_NAME}.app"
echo "   Launch:   open \"${INSTALL_DIR}/${APP_NAME}.app\""
echo "   First launch: grant mic / accessibility / screen-recording once — they'll"
echo "   persist across future rebuilds because the signing identity is stable."
