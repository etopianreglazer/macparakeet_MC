# Splay branding

Splay is a modified local fork of MacParakeet-MC. Its **user-facing identity**
and its **Swift package / module identity** are both "Splay", but a small set of
**data, permission, and CLI-contract identifiers are deliberately kept** on the
original `macparakeet` names so that updating an existing local installation
preserves settings, recordings, transcripts, and the current macOS privacy
grants — and so downstream callers of the CLI keep working.

## What is named "Splay"

- The installed app is **Splay** (`Splay.app`), with the supplied full Splay app
  icon; compact island surfaces use the supplied three-splay mark and violet
  palette.
- The **SwiftPM package and modules** are `Splay*`: the app target/product
  `Splay`, and the libraries `SplayCore`, `SplayViewModels`, and the ObjC shim
  `SplayObjCShims`. The test target is `SplayTests`. Source directories are
  `Sources/Splay`, `Sources/SplayCore`, `Sources/SplayViewModels`,
  `Sources/SplayObjCShims`, and `Tests/SplayTests`.

## What is deliberately KEPT (do not rename)

These are stored-data / OS-permission / public-CLI contracts. Renaming them would
orphan existing local data or break callers, so they intentionally stay:

- **Bundle identifier** `com.macparakeet.mc` — the installed app's TCC identity;
  keeping it preserves mic / accessibility / screen-recording grants across
  rebuilds.
- **Application-support data namespace** `MacParakeet-MC`
  (`AppPaths.appFolderName`) — the fork's database, recordings, models, and
  settings live under `~/Library/Application Support/MacParakeet-MC/`.
- **CLI defaults domain** `com.macparakeet.MacParakeet` — the domain the CLI
  reads/writes when run outside the app bundle.
- **CLI executable / product name** `macparakeet-cli` (target `CLI`) — the
  versioned public surface consumed by scripts and downstream agent skills.
- **Info.plist key contracts** such as `MacParakeetCheckoutURL` and
  `MacParakeetLemonSqueezyVariantID` — read in Swift via
  `forInfoDictionaryKey` and written by `scripts/dist/build_app_bundle.sh`; the
  read and write sides must agree, so both keep the original key names.

## Build/install scripts

`scripts/dev/install_local.sh` → `scripts/dist/build_app_bundle.sh` is the fork's
build/install path; its SwiftPM product references were updated to the `Splay`
product. Upstream's xcodebuild dev runner (`run_app.sh`) was deleted in thread 21.

## License

The fork remains subject to the repository's GPL license and attribution. The
packaged app continues to include `LICENSE` and `THIRD_PARTY_LICENSES`; neither is
renamed or removed by this branding layer.
