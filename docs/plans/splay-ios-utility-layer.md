# Plan: Splay for iPhone — a utility layer, not an app

> Status: **ACTIVE**. Drafted 2026-09-13 from a design conversation; slice 1 started the same day.
> Product north star still `docs/fork-product-model.md`; this plan extends it to iOS.

## Why

The owner's real constraint is the phone. Dictation on iPhone (Notes, Claude, ChatGPT)
needs spoken punctuation and drops names; Wispr Flow and friends are cloud, paid, and
dead without cell signal. Splay's Mac model — one gesture, local Parakeet, verbatim
`.md` — is exactly what the phone lacks. Local-only is a hard requirement (no signal
is the normal case, not the edge case). Bundle size is not a concern (1–2 GB is fine).

## Decisions taken

| Decision | Choice | Why |
|---|---|---|
| Surface | **No app UI you ever open.** Trigger + island + delivery only. | Same philosophy as the Mac: a layer on the OS, not a destination. |
| Trigger | **Action Button** (primary) via a Control; **Back Tap** via a Shortcut (secondary, see risks). | Built-in gestures; "be smarter than the rest, not deeper." |
| Indicator | **Live Activity in the Dynamic Island**, styled like Now Playing: compact = red dot + elapsed; expanded = level meter, elapsed, one **Stop** button. | Same information the Mac island shows, one control instead of a cover. |
| STT | **Parakeet TDT 0.6B v3 via FluidAudio** on the Neural Engine. WhisperKit not ported in v1. | Fastest, non-hallucinating on silence, already Splay's stack. |
| Text | **Verbatim.** `TextProcessingPipeline` only. No LLM clean-up, no autocorrect, ever in the capture step. | "If you don't know what you're cleaning up you introduce uncertainty." The reader's LLM has the full context; the phone does not. |
| Names / brands | **Parked.** Accepted as slightly off in v1. Revisit as a deterministic personal dictionary, never a model-side guess. | Editing decision for later, not a capture decision. |
| Delivery | Transcript `.md` + paired audio in the app's Files container; text also on the **clipboard**; the App Intent **returns the text** so a Shortcut can route it (paste, share, append to a note). | Composable; no keyboard extension needed. |
| Keyboard | **None.** | iOS forbids mic access in keyboard extensions; not needed for this flow. |
| Cloud fallback | **None.** | Local is the point. |

## Platform facts that shape the build (verified 2026-09-13)

- Keyboard extensions cannot touch the microphone, with or without Full Access. Every
  third-party dictation keyboard bounces to its app. We skip the keyboard entirely.
- `AudioRecordingIntent` (iOS 18+) exists precisely so a **Control** can start recording
  without foregrounding the app. Apple's rule: you **must** start a Live Activity when
  recording begins and keep it alive, or the recording is stopped. Pair it with
  `LiveActivityIntent` so the activity can be created from within the intent.
- A developer report shows "Live Activity start failed: Target is not foreground" when an
  intent is fired from a plain Shortcut rather than a Control. Treat **Back Tap → Shortcut**
  as *verify on device*; the fallback is `ForegroundContinuableIntent` (a ~1 s foreground
  flash, then back), which another open-source recorder uses only when the Live Activity
  path is unavailable.
- The Action Button can be assigned directly to a third-party Control on iOS 18+.
- Live Activity buttons run App Intents; that is how the island's Stop works.
- FluidAudio declares iOS 17+; Parakeet v3 CoreML ≈ 600 MB; Argmax measured the ANE path
  ≈ 4.3× the GPU path on iPhone 16 Pro. No public iPhone RTF figure exists — measure it.
- `SplayCore` is Foundation + GRDB + FluidAudio with no SwiftUI/AppKit, so capture,
  chunking, scheduler, storage writer and the text pipeline port as they stand.
  `Package.swift` currently declares `.macOS(.v14)` only.

## Architecture

```
Action Button ──▶ Control (ControlWidget)
Back Tap ───────▶ Shortcut ──▶ StartRecordingIntent  (AudioRecordingIntent + LiveActivityIntent)
                                     │
                                     ▼
                    Main app process, background-audio mode
                    ┌──────────────────────────────────────────┐
                    │ SharedMicrophoneStream (AVAudioEngine)   │
                    │  ├─ MeetingAudioStorageWriter (fMP4)     │  ← REDCODE-style: crash loses one fragment
                    │  └─ VAD chunker → STTScheduler(Parakeet) │  ← chunks transcribed WHILE recording
                    │       └─ TextProcessingPipeline          │
                    │ Live Activity: state + elapsed + Stop    │
                    └──────────────────────────────────────────┘
                                     │  Stop (island button / trigger again)
                                     ▼
                    last chunk → final .md + audio in Files; clipboard; intent result
```

**The REDCODE point.** Because chunks are transcribed as they close, "stop" only has to
finish the tail chunk. Latency at stop is seconds regardless of session length, and a
crash or an iOS kill loses at most the current fragment. This is the Mac's live-chunking
path (`AppFeatures.meetingVadLiveChunkingEnabled`) reused, not new machinery. The container
question is moot: the chunker works on in-memory PCM; the on-disk fMP4 only exists for
crash safety.

**Background budget.** The audio background mode keeps the process alive while the
session is active; the ANE is usable during that time. After Stop the app has a short
background grace window, which is why the tail chunk must be the only outstanding work.

## Slices

1. **Core port** — add `.iOS(.v18)` to `SplayCore`/`SplayViewModels`; make the mic engine,
   storage writer, chunker and scheduler compile and run on iOS. Benchmark Parakeet v3 on a
   16 Pro: RTF on ANE, peak memory, thermals over 45 min. *Exit: a CLI-less test target
   transcribes a bundled WAV on device.*
2. **Session + intents** — `StartRecordingIntent` / `StopRecordingIntent` adopting
   `AudioRecordingIntent` + `LiveActivityIntent`; a Control; recording starts from the
   Action Button with the app never visible. *Exit: Action Button → recording → Action
   Button → `.md` in Files.*
3. **The island** — Live Activity: compact red-dot + elapsed; expanded level meter, elapsed,
   Stop. Amber while the tail chunk transcribes, green flash when written. Port the
   `SplayGlowTuning` states, not the AppKit views.
4. **Delivery** — clipboard write on stop; intent returns the transcript string; a sample
   Shortcut ("Splay → paste into front app"). Verify Back Tap path; fall back to
   `ForegroundContinuableIntent` if the Live Activity cannot be started from a Shortcut.
5. **Recents + Settings** — the minimum: a Files-provider view of transcripts and one
   settings sheet (language, output folder). Both reachable only if you go looking.

## Slice 1 log

**2026-09-13 — SplayCore compiles for iOS (both `swift build --triple arm64-apple-ios18.0`
and `xcodebuild -scheme SplayCore -destination generic/platform=iOS`).** GRDB, FluidAudio and
WhisperKit all compile for the iOS SDK unchanged. Two walls were hit and gated with
`#if os(macOS)` (never forked): (1) macOS-only frameworks — ScreenCaptureKit, Core Audio HAL,
AppKit, Carbon, ApplicationServices, ServiceManagement; (2) `Process` — FFmpeg, osascript,
thumbnail extraction. Full list and reasons: `Sources/SplayCore/Audio/README.md` § Platforms,
plus `ExportService` (PDF/DOCX are AppKit text-system exports; txt/md/srt/vtt/json are
portable), `PermissionService` (mic on both; screen/AX/settings deep-links macOS), and
`ThumbnailCacheService` (protocol portable; frame extraction throws on iOS).

**Decisions taken in slice 1:**
- `SplayViewModels` stays macOS-only. It is the card/panel/pill logic for the Mac
  surfaces (AppKit, Metal, `NSWorkspace`); the phone gets its own thin view models
  in the iOS target. Nothing in it is needed to record or transcribe.
- `AudioFileConverter` is *closed* on iOS rather than half-ported: `convert` and
  `mixToM4A` throw. The meeting pipeline calls `mixToM4A` at stop, so slice 2 must ship
  an AVFoundation implementation before the first end-to-end recording.
- macOS build and full suite unchanged: 1760 XCTest + 16 swift-testing, the same 5
  known environmental failures, zero new.

**Bench harness:** `ios/SplayBench/` (XcodeGen spec + one SwiftUI file) runs Parakeet v3
through `STTClient` on a bundled 73 s TTS clip, prints RTF per run, a 10-run sustained RTF,
`phys_footprint`, and thermal state to stdout and to a JSON in the app's Documents.
`scripts/dev/install_iphone_bench.sh` = generate → Release build → install → launch with
console streaming. Needs the phone connected and unlocked; not yet run on device.

## Risks

- **Back Tap may need the foreground flash.** Acceptable; Action Button is the primary.
- **iOS may kill a long background session** under memory pressure. Chunk-as-you-go makes
  this a lost-tail, not a lost-session; the fMP4 recovery flow (ADR-019) already handles it.
- **Live Activity has an 8-hour cap** and limited update frequency; elapsed time uses a
  timer-text, not pushed updates.
- **Names/brands** remain the main accuracy complaint. Parked by decision; dictionary later.

## Out of scope for v1

Keyboard extension, WhisperKit/multilingual, SpeechAnalyzer fallback, any cloud path,
any clean-up or summarisation, Mac ↔ iPhone sync.
