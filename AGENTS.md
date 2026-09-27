# AGENTS.md — Splay

> For any coding agent working in this repo. The deeper context, rules, and gotchas are
> in [`CLAUDE.md`](./CLAUDE.md); the live "you are here" is
> [`docs/thread-state.md`](./docs/thread-state.md). Read both before editing.

## What this is

Splay is a one-gesture, on-device voice recorder for Apple Silicon Macs (macOS 14.2+,
GPL-3.0, derived from MacParakeet). Tap `fn` → mic recording; double-tap `fn` → dictation
(verbatim text pasted into the focused field); triple-tap `fn` → mic + system audio; drop a
file on the menu bar icon → file transcription. Recordings write a verbatim transcript `.md`
(+ paired audio) to a folder. Two UI surfaces only: the **island**
(notch-anchored indicator light) and the **card** (Recents · Settings · About).

Not in Splay, by decision: a main window, a CLI, in-app LLM features, YouTube, calendar,
Transforms, telemetry reporting. Do not resurrect them.

## Build & test

```bash
swift build
swift test                      # baseline = 5 known environmental failures, zero new
scripts/dev/install_local.sh    # → /Applications/Splay.app (then `open` it yourself)
scripts/dev/install_iphone_bench.sh   # iOS bench harness → connected iPhone (needs Xcode account)
```

Run `swift test` before calling
code-change work complete, and run the Vet review skill on each logical unit of change.

## Layout

```
Sources/Splay/             app target (AppKit shell, coordinators, SwiftUI views)
  Views/Island/            the two surfaces
Sources/SplayCore/         Foundation + GRDB + FluidAudio (+WhisperKit); no SwiftUI views
  Audio/ STT/ Database/ TextProcessing/ Licensing/   each has a README.md — read it first
Sources/SplayViewModels/   @MainActor @Observable view models, no UI
Sources/SplayObjCShims/    NSException trampoline
Tests/SplayTests/
spec/adr/                  architectural record (binding vs superseded list in CLAUDE.md)
docs/                      product model, thread state, launch checklist, releasing, plans/
```

## Code style

- Swift 6 language-mode / concurrency clean. Async/await for all I/O; no completion
  handlers, no Combine in new code.
- `SplayCore` never owns UI. Small AppKit adapter services are fine.
- One GRDB repository per table. Migrations, never table drops.
- Comments say *why*; identifiers say *what*. Default to none.
- Delete old approaches entirely when switching; no `_ = unused` artifacts.

## Do not

- Delete user data (DB, session folders, source audio) outside the recovery/discard flows.
- Remove the licensing/entitlement plumbing (`Sources/SplayCore/Licensing/`,
  `EntitlementsService`, `LemonSqueezyLicenseAPI`) — retained on purpose.
- Rename the kept identifiers: bundle id `com.macparakeet.mc`, data namespace
  `MacParakeet-MC`, log dir `~/Library/Logs/MacParakeet/` (see `docs/BRANDING.md`).
- Make the island panel key, or let silence fail a recording (dead ≠ silent).
- Push unless the owner asks. Mac work goes on `mac/dev`; `main` is releases only.

## Runtime locations

| Item | Path |
|---|---|
| Data | `~/Library/Application Support/MacParakeet-MC/` |
| Default transcripts | `~/Documents/MacParakeet-MC/{Transcriptions,Meetings}` |
| Logs | `~/Library/Logs/MacParakeet/dictation-audio.log` (shared dir — match `pid`/`commit`) |
