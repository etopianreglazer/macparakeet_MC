# CLAUDE.md

> Context for AI coding assistants working on **Splay**. Keep this file short and true;
> a stale line here is worse than a missing one.

## What Splay is

A one-gesture, on-device voice recorder for Apple Silicon Macs. Tap `fn`, talk, get a
verbatim transcript file. It began as a fork of MacParakeet (GPL-3.0, Daniel Moon) and
has since been cut down to exactly **two surfaces**:

1. **The island** — a flat-black pill hanging from the notch. Indicator only: no glow, no
   rim, takes no clicks. Five red bars follow *your mic* left of the camera (a meeting adds
   fainter blue system-audio bars), a timer counts up right of it; dictation is the bars
   alone, with only a short ear past the camera. An amber spinner while
   transcribing, a green check when done (a copy glyph when a dictation had no text field
   to paste into, a 3·2·1 ring while an Escaped dictation counts down). Flat, motionless
   amber bars mean the input is *dead* (not merely silent).
2. **The card** — one centred modal (Recordings · Settings · About) opened from the menu
   bar icon (Splay's status item). Everything that isn't capture lives here.

There is **no main window, no CLI, no in-app LLM, no YouTube, no calendar, no Transforms,
no Discover, no feedback form, no telemetry endpoint.** If you find code that implies
otherwise, it is dead weight from upstream, not a feature to keep alive.

**Product north star:** `docs/fork-product-model.md` (wins over anything upstream-shaped).
**Where we are right now:** `docs/thread-state.md` — read it first on every cold start.

## Capture model

| Gesture | Audio | Result |
|---|---|---|
| Tap `fn` | Mic only | transcript `.md` + paired audio |
| Double-tap `fn` | Mic | **dictation**: verbatim text pasted into the field focused at stop |
| Triple-tap `fn` | Mic + system audio (ScreenCaptureKit) | transcript `.md` + paired audio |
| Drop a file on the menu bar icon / Menu ▸ Transcribe File | Any audio/video (FFmpeg demux) | transcript `.md` in Transcriptions; island spinner → ✓, banner says where (click reveals) |

Tap again to stop whatever runs. The gesture picks the audio source — there is no system-audio
setting (Settings shows a read-only gesture legend); Menu ▸ Start Recording is mic-only. **Escape** during a dictation starts upstream's undo
countdown (3·2·1 on the island): tap `fn` to keep it, Escape again or wait to discard.
Escape never touches a recording, a meeting, or a dictation that is already transcribing.
`HotkeyGestureController.tapDoubleTripleToggle` resolves the
gesture; `FnCaptureRouter` routes it. Tap and triple-tap run the *same* meeting-recording
pipeline with a different audio source; double-tap runs upstream's `DictationFlowCoordinator`
(plan: `docs/plans/fn-dictation-double-tap.md`).
Transcripts are **verbatim** — the deterministic `TextProcessingPipeline` only (ADR-004);
nothing polishes them.

## Tech stack (locked)

| Layer | Choice |
|---|---|
| Platform | macOS 14.2+, Apple Silicon only (the shipped app). `SplayCore` also builds for **iOS 18+** — the iPhone utility layer, **paused** until the Mac is done (`docs/plans/splay-ios-utility-layer.md`); macOS-only code is gated `#if os(macOS)`, never forked |
| Language | Swift (tools-version 5.9), Swift 6 language-mode clean, SwiftUI + AppKit panels |
| STT | Parakeet TDT 0.6B v3 via FluidAudio CoreML (default); WhisperKit optional for other languages. One process-wide `STTRuntime` + `STTScheduler` (ADR-016) |
| Audio | `SharedMicrophoneStream`/AVAudioEngine mic; ScreenCaptureKit system audio; bundled FFmpeg for file import |
| Database | SQLite via GRDB, one repository per table |
| Updates | Sparkle 2, Splay's own EdDSA key + appcast on GitHub Pages |

## Repo layout

```
Package.swift            Splay (app) · SplayCore · SplayViewModels · SplayObjCShims · SplayTests
Sources/Splay/           AppKit app: AppDelegate, App/ (coordinators), Hotkey/, Views/
  Views/Island/          the two surfaces: IslandController/View, SplayIslandMeter, SplayCard*, theme
  Views/MeetingRecording/ Notes/Transcript panel shown while recording (the floating pill is off)
  Views/Dictation/       unused upstream overlay/idle pill; the island carries dictation
                         (`HiddenDictationOverlayController` stands in)
  Views/Onboarding/      upstream first-run flow (not wired into first launch yet)
Sources/SplayCore/       Foundation + GRDB + FluidAudio (+WhisperKit). No SwiftUI views.
  Audio/ STT/ Database/ TextProcessing/ Licensing/   ← each has a README.md — read it first
  Services/ MeetingRecordingFlow/ DictationFlow/ Models/
Sources/SplayViewModels/ @MainActor @Observable view models, testable without the GUI
Tests/SplayTests/        XCTest + swift-testing
spec/adr/                upstream ADRs, kept as the architectural record (see below)
docs/                    Splay's own docs: product model, thread state, launch, releasing, plans/
scripts/dev/             install_local.sh (the dev loop)   scripts/dist/  build + sign + notarize
                         install_iphone.sh / install_iphone_bench.sh (iOS app / bench → connected iPhone)
ios/Splay/               the iPhone app (XcodeGen): App/ (environment, RecordingCoordinator, Recents),
                         Shared/ (Live Activity attributes, App Intents), Widgets/ (island, Control)
ios/SplayBench/          XcodeGen spec + harness that benchmarks Parakeet v3 on a real iPhone
```

`AppFeatures` flags: `meetingRecordingEnabled`, `meetingVadLiveChunkingEnabled`
(VAD-guided live-preview chunking, fixed-chunker fallback, final transcript unaffected),
`islandReplacesDictationPill`, `islandPinnedAcrossSpaces` (private CGS space so the island rides
above Space swipes; no-op if the symbols are missing) (all `true`), and `islandTakesMouse`
(`false`: click-through island).

## ADRs

`spec/adr/` is upstream MacParakeet's decision record. Still binding for Splay: **001, 002,
004, 007, 010, 014, 015, 016, 019, 021**. Marked **SUPERSEDED for Splay** (feature removed):
011, 013, 018, 020, 022. Historical/dormant: 003, 005 (onboarding not wired into first launch), 006 (licensing
plumbing — see below), 008, 009, 012 (telemetry reporting removed), 017 (calendar removed).

## Rules that are not obvious from the code

- **Never lose user data.** Meeting session folders, lock files, and source audio are
  user data; only the recovery/discard flows delete them. Write DB migrations, never drop
  tables casually. Orphaned upstream tables (prompts, chats, quick prompts) are left
  **dormant** on purpose.
- **Licensing plumbing stays.** `EntitlementsService`, `LemonSqueezyLicenseAPI`, and the
  `Sources/SplayCore/Licensing/` folder are retained future-option code. Do not delete as
  dead code without explicit owner direction.
- **Kept identifiers (do not rename):** bundle id `com.macparakeet.mc`, data namespace
  `MacParakeet-MC` (`AppPaths.appFolderName`), defaults domain, `MacParakeet*` Info.plist
  keys, and the shared log dir `~/Library/Logs/MacParakeet/`. Renaming moves the user's
  data and revokes TCC grants. See `docs/BRANDING.md`.
- **Dead ≠ silent.** Silence never fails a recording. Only genuine engine death does.
- **The island must never become key — and takes no clicks.** It sits over the top-centre
  of the screen, so its click monitors stole clicks meant for apps beneath (address bars,
  tabs). It is click-through (`AppFeatures.islandTakesMouse = false`); fn starts/stops,
  the menu bar icon opens the card (a held failure's card too). If clicks ever return:
  local *and* global monitors are needed (AppKit never reports own-app events to a global
  monitor). `SplayCardController.yieldActivationIfIdle` hands focus back after the card
  closes. Tooltips on these panels need `NSTrackingArea(.activeAlways)`.
- **STT goes through the scheduler.** Use `STTScheduler.transcribe(...)`; never create
  standalone `AsrManager`s in app code.
- **Timers in `.common` run-loop mode**; heavy work off `@MainActor` via `Task.detached`.
- `??` does not take `try await` on its right-hand side; use `if let … else`.
- GRDB stores UUIDs via Codable — never raw SQL `WHERE id = ?` with `uuidString`.
- Commit messages with apostrophes break `git commit -m` in this shell; use `git commit -F -`.

## Build, install, test

```bash
swift build                      # everything
swift test                       # ~1–2 min. Baseline: 5 known environmental failures
                                 #   (AppPaths + 3× SettingsViewModel pre-"-MC" asserts,
                                 #   AX-gated AppHotkeyCoordinator). Zero new = green.
                                 #   Also read the swift-testing summary at the end —
                                 #   its issues don't appear in XCTest `error: -[…]` lines.
scripts/dev/install_local.sh     # SwiftPM bundle → signs with Apple Development → /Applications/Splay.app
                                 #   does NOT relaunch; wait ~2s then `open /Applications/Splay.app`
```

iOS: `swift build --target SplayCore --triple arm64-apple-ios18.0 --sdk $(xcrun --sdk iphoneos --show-sdk-path)`
is the fast compile check; device installs need an Apple ID in Xcode ▸ Settings ▸ Accounts (profiles).
The dev install resolves `Bundle.module` out of `.build/` (no resource bundles); verify
resource-backed UI on a release artifact. Release mechanics: `docs/releasing.md`; the
pre-publish gate: `docs/launch-checklist.md`.

## Working method

- Read `docs/thread-state.md`, then the subsystem README for any `SplayCore/` folder you
  touch. At the end of every thread **rewrite the pin in place** (live state · decided-not-done ·
  next thread starts here), demote the previous thread's block verbatim to the top of
  `docs/thread-log.md`, and keep `thread-state.md` under **150 lines**. Durable facts go to a
  README, a plan, or this file — never accumulate in the pin.
- Bug fix: failing test → fix → focused tests → `swift test`.
- Run the **Vet** review skill (`/vet`) after each logical unit of change; it has caught
  real regressions here.
- Multi-file work gets a plan in `docs/plans/`. Mark finished plans `> Status: **HISTORICAL**`.
- Visual tuning is done in a live HTML slider tuner, not build-install loops; port the
  dialled constants into the matching tuning enum (e.g. `SplayMeterTuning`).
- Push only when the owner asks.

## Branches

- `main` = releases only. **`mac/dev`** = all Mac work; short-lived `mac/<topic>` branches are fine.
- **`ios/dev`** = iOS work (cut from `mac/dev` 2026-09-28). `SplayCore` changes land on `mac/dev` first and
  flow Mac → iOS. The `upstream` remote tracks MacParakeet's `main` only.

## Runtime locations

| Item | Path |
|---|---|
| App | `/Applications/Splay.app` |
| Data (DB, models, session folders) | `~/Library/Application Support/MacParakeet-MC/` |
| Default transcript folders | `~/Documents/MacParakeet-MC/{Transcriptions,Meetings}` (user-changeable) |
| Parakeet models | FluidAudio default cache (~465 MB) |
| Whisper models | `~/Library/Application Support/MacParakeet-MC/models/stt/whisper/` |
| Logs | `~/Library/Logs/MacParakeet/dictation-audio.log` — shared with other MacParakeet-family builds; match `pid`/`commit` before trusting a line |

## Privacy

Speech recognition is on-device. Network use: the one-time model download and Sparkle
update checks. Telemetry reporting and crash upload are no-ops (the network class was
deleted). No accounts. Permissions: Microphone (first record), Screen & System Audio
Recording (first triple-tap only), Accessibility (first dictation paste), Notifications (first file transcription — banners say where the
transcript went; without it the island still shows the check / failure light).
