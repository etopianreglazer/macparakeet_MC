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
| Delivery | **Clipboard whenever iOS allows it** (owner decision 2026-09-13: the clipboard is the safety net, no Copy button ever). ⚠️ Corrected 2026-09-14: iOS forbids *any* app that is not in the foreground from touching the general pasteboard (`PBErrorDomain 11`, a policy — the lock state is irrelevant), so a recording stopped from the Action Button **cannot** copy in the background. The text is held on disk and written the next time the app is foregrounded; the background-capable delivery is the Stop intent's **returned text** routed by a Shortcut (Shortcuts may write the clipboard from the background). Transcript `.md` + paired audio in Files always. **Owner decision pending:** ship the Action Button as a Shortcut (Toggle → Copy to Clipboard) rather than the bare Control, or accept a ~1 s foreground flash (`openAppWhenRun`) on stop. | Nothing gets lost; the file is the record; the clipboard is best-effort by platform rule. |
| Auto-paste | **Wanted** (same feel as the Mac's paste-into-focused-field). iOS only lets a **keyboard extension** insert text into another app's field, so auto-paste = a *paste-only* Splay keyboard: no keys, a short strip, inserts the transcript the moment it lands while it is the active keyboard. It never records. Slice 6; verify whether reading the App Group needs Full Access. | The keyboard is the only sanctioned path; keep it minimal. |
| Keyboard | **No typing keyboard.** Only the paste-only strip above, and only for auto-paste. | iOS forbids mic access in keyboard extensions; recording stays in the app. |
| Cloud fallback | **None.** | Local is the point. |
| Model delivery | **Bundle Parakeet v3 in the app** (owner ask 2026-09-13): the compiled `parakeet-tdt-0.6b-v3` folder (461 MB, 4 `.mlmodelc` + vocab) as an app resource, copied into `Library/Application Support/FluidAudio/Models/` on first launch so FluidAudio finds it where it looks. Silero VAD (1 MB) likewise. | The first-run Hugging Face download failed twice on the phone's Wi-Fi during the bench; sideloading the Mac's cached folder worked in 14 s. App Store limit is 4 GB; cellular installs over 200 MB just prompt. |

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

## Audio session model (iOS) — decided 2026-09-14

The reference is Voice Memos: **the session is per recording, the engine is per
configuration**, and the two lifecycles never cross.

```
press ─▶ Live Activity ─▶ session: setCategory (once per process) + setActive(true)   [active]
                       └▶ engine: build graph, install tap, start                      buffers flow

routeChangeNotification      reason=categoryChange, or no input port before ─▶ log only (that is
                             our own setCategory/activation; the engine that follows starts on
                             the new route anyway)
                             input port UID unchanged ─▶ log only (an output override, etc.)
                             input port UID changed  ──▶ restart the ENGINE (session untouched)
AVAudioEngineConfigurationChange   the engine HAS STOPPED (I/O hardware changed under it) ─▶
                                   restart the ENGINE (session untouched)
interruption .began          system holds the session; engine stopped        [interrupted]
interruption .ended          shouldResume ─▶ setActive(true) again + restart the engine
                             (the one legitimate re-activation)              [active]

stop ─▶ engine torn down (if it was still up) ─▶ setActive(false) whenever the session is
        ours, running engine or not                                          [idle]
```

Policy lives in `RecordingAudioSessionLifecycle` (SplayCore/Audio, portable, unit-tested on
the Mac); `AVAudioEngineMicrophonePlatform` applies it. Points of failure this replaces, all
seen in the fourth device run (2026-09-14 06:37) or implied by the code:

1. **Session activation lived inside engine start.** Every rebuild re-issued `setCategory` +
   `setActive(true)`; from the background iOS refused with `'!int'`. Now a rebuild during a
   recording is `.alreadyActive` → no session call at all.
2. **Every route change was treated as an input change** (a HAL habit from the Mac). On iOS
   `.newDeviceAvailable` fired 50 ms after our own activation with the input still the
   built-in mic. Now only a changed input-port UID (previous route vs current) restarts the
   engine; the line logs `input=<prev>→<cur> output=…` so the self-inflicted ones are visible.
   Fifth run (2026-09-14 07:05) added two exclusions: `reason=category` (only we set the
   category, before the first engine start) and `previous input = none` (nothing could have been
   recording from a route with no input) — that pair restarted a healthy engine 350 ms into every
   recording and cut the head off it.
3. **The engine's configuration-change notification was only logged.** On iOS it means the
   engine has stopped (the I/O unit saw the output flip to the speaker); the recording would
   have died even with (2) fixed. Now, while a recording is engaged, it drives the same
   restart-the-engine path.
4. **The session observers were per engine instance** and were removed by every teardown —
   including the teardown inside a *failed* rebuild — so after the retries gave up nothing
   could ever resume the recording. Now they are installed once for the platform's lifetime
   and gated on the session being engaged.
5. **`stopEngine` returned early when the engine was already down**, so the session was never
   deactivated (no `audio_session_inactive` in the log): mic indicator on, background window
   open, until the process died. Now deactivation follows the session state, not the engine.
6. **Concurrent follow-the-input tasks.** A route change and a configuration change arrive
   together; each spawned its own restart-with-backoff task. `SharedMicrophoneStream` now runs
   one at a time and coalesces triggers that arrive mid-flight into a single rerun (Mac too).

**Thread 15 (2026-09-14) — the island never showed Saved.** Platform fact (ActivityKit docs,
"Displaying live data with Live Activities"): the system removes an *ended* Live Activity from the
Dynamic Island immediately; `ActivityUIDismissalPolicy` only decides how long it stays on the Lock
Screen. `saved()` used to push the green check and end with a 3 s dismissal in the same instant, so
the island went straight from Finishing to hardware (sixth run: recording fine, 29 words saved, no
check seen). Now: push `.saved` → dwell 3 s while still live → `end(…, dismissAfter: 0)`. The dwell
is awaited inside the Stop/Toggle intent, which keeps the process alive for it. Same for a
non-retryable failure.

**Thread 15 (2026-09-14) — the shared input policy.** Every hint above (route change with a changed
input UID, configuration change, interruption ended) now enters `SharedMicrophoneStream.inputHint()`
and `MicrophoneInputPolicy` decides (`docs/plans/mac-input-policy.md`): engine down → rebuild now;
engine up → rechecks at +1 s/+3 s and a rebuild only if buffers have stopped. So that the
configuration change and an interruption keep their immediate rebuild, the platform now *tears the
engine down* (session untouched) when they arrive — `shared_mic_engine_configuration_changed_stopped`
in the log — and the hint that follows reads `engine_running=false verdict=restart_now`. A route
change that leaves the engine delivering no longer restarts it.

Kept as is: `.mixWithOthers` (required for background activation), `.playAndRecord`
(`.record` cannot mix), the 300/800/2000 ms backoff (a cold Bluetooth mic). Open question
for a later run: `.defaultToSpeaker` has no function today (nothing plays) and may be what
flips the output route and stops the engine right after start — the route-change line now
shows the output port so this can be decided from a log, not a guess.

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
6. **Auto-paste** — a paste-only keyboard extension (App Group handoff from the app). Exit:
   Splay keyboard active in Claude/Notes → Action Button → talk → Action Button → the text
   appears at the cursor with no further touch. Clipboard is still written regardless.

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

**Slice 1 exit — measured on the owner's iPhone 16 Pro, iOS 26.6.1, 2026-09-13 (`docs/bench/`):**

| Metric | Value |
|---|---|
| Model load, cold, from disk | 17.4 s |
| Warm runs, 72.8 s clip | 0.37–0.42 s → **172–199× real time** |
| Sustained, 10 back-to-back (12 min of audio) | 4.3 s → **170× real time** |
| Peak process footprint | 58 MB (CoreML keeps the weights outside the app's footprint) |
| Thermal state, start → end | nominal → nominal |
| Transcript vs fixture | verbatim; Parakeet lower-cases proper nouns ("splay", "parakeet") |

The Hugging Face download failed twice on the phone's Wi-Fi ("network connection was
lost"); the Mac's cached model folder pushed with `devicectl device copy to` into
`Library/Application Support/FluidAudio/Models/` worked in 14 s — hence the bundle-the-model
decision above.

## Slice 2 log

**2026-09-13 — device-free half done on branch `ios/utility-layer`.**
- `AVFoundationAudioFileConverter` (commit `d32c6958`): the iOS conversion path, same
  contracts as FFmpeg, 7 tests on macOS. `mixToM4A` at stop now works on iOS.
- iOS `AVAudioSession` in `AVAudioEngineMicrophonePlatform`: `.playAndRecord` activated
  before the engine starts, deactivated only in `stopEngine()` (never on a route-change
  rebuild) and on a start that fails after activating; route changes and
  interruption-ended-with-`shouldResume` funnel into the existing follow-the-input handler.
  Vet caught the unbalanced first version; fixed.
- **`ios/Splay/` — the app.** XcodeGen `project.yml`: app target (`com.macparakeet.mc.ios`,
  SplayCore, background mode `audio`, Live Activities, document sharing on) + WidgetKit
  extension (`…ios.widgets`). `SplayEnvironment` composes SplayCore mic-only.
  `RecordingCoordinator` (MainActor singleton) = start → mic permission → Live Activity →
  `startRecording(.microphoneOnly)`; pause/resume; stop → finishing → `stopRecording` →
  `transcribeMeeting` → `completeTranscription` → `AutoSaveService.saveIfEnabled(.meeting)`
  (`.md` + paired audio in Documents/MacParakeet-MC/Meetings) → **clipboard** → saved →
  activity ends after 3 s; failure keeps the activity with Retry; a 2 s health watch flips
  to *Input dead* when `captureHealth.mode == .stopped`. Intents (`Toggle/Start/Stop/Pause/
  Resume/RetryTranscription`) adopt `AudioRecordingIntent + LiveActivityIntent`; their
  bodies compile only under `SPLAY_APP` so the widget target can reference the types.
  `SplayLiveActivity` is the v5 mock: compact glyph + bars, 84 pt expanded row, one 44 pt
  filled circle (Pause white / Resume red / Retry white), tinted key line, Lock Screen row.
  `SplayRecordControl` = Control Center button → `ToggleRecordingIntent` (assign to the
  Action Button). `scripts/dev/install_iphone.sh` = generate → build → install → launch;
  `COMPILE_ONLY=1` builds unsigned for generic iOS (what CI can do).
- **Compiles for generic iOS, unsigned. Not yet run on a device.** Known gaps to verify on
  the phone: whether a Control-started `AudioRecordingIntent` really records without the
  app in the foreground (Apple's rule says yes if the Live Activity starts at once); the
  bars in the island are a timeline pulse, not the live mic level (WidgetKit cannot update
  per frame); first launch downloads the Parakeet model with no progress UI yet.

**First device run of the app (2026-09-13 20:37–20:38, owner's 16 Pro):** end to end **works** —
23 s recorded, 44 words, `.md` + `.m4a` in Files ▸ Splay ▸ MacParakeet-MC ▸ Meetings. Two findings:
1. **Background start was refused** five times: `AVAudioSession` activation failed with `'!int'`
   (`cannotInterruptOthers`, 560557684) while the app was in the background; it worked once the app
   was foregrounded. Fix: `.mixWithOthers` in the category options (mixable sessions may activate
   in the background). Cost: other apps' audio keeps playing under the recording.
2. **Clipboard write refused while locked** (`PBErrorDomain 11`). Fix: hold the text and flush on
   `protectedDataDidBecomeAvailable` / `didBecomeActive`, verified by read-back.
Also: the first launch compiles the encoder for the ANE (~41 s, cached by iOS afterwards) —
bundling the model does not remove that; the app's launch warm-up hides it.

**Model bundling (2026-09-13, after the first device run):** the app ships `Models/` (a
folder reference, `ios/Splay/Resources/Models`, git-ignored) holding `parakeet-tdt-0.6b-v3`
and `silero-vad` laid out exactly like FluidAudio's cache. `scripts/dev/install_iphone.sh`
stages them from the Mac's `~/Library/Application Support/FluidAudio/Models` (an APFS clone;
`MODELS_SOURCE` overrides; a repo the Mac has not cached is skipped with a warning and the app
downloads it as before). On launch, before the STT warm-up, `BundledModelSeeder` (SplayCore,
8 tests) copies each repo into `Application Support/FluidAudio/Models/` unless the cache
already holds every bundled file at the same size; copies are staged and renamed so an
interrupted copy is never trusted. Log lines: `bundled_models seeded=… complete=…`,
`bundled_models absent`, `bundled_models_seed_failed`. Debug app is now ~490 MB; the folder
is `optional` in `project.yml` so a CI compile without it still builds.

**Second device run (2026-09-13 20:56, owner alone, build `59d6f21f`-equivalent + the two fixes):**
the Action Button with the app not running **did** start a recording in the background —
`audio_session_active` (so `.mixWithOthers` fixed `'!int'`), Live Activity requested, first mic
buffer landed — and then the process **vanished ~1 s later**: no stop line, session
`3238D80E…` left with `recording.lock`, a 5.7 KB `microphone.m4a` (header only) and no chunks; no
crash report and no JetsamEvent on the phone (checked the synced
`~/Library/Logs/CrashReporter/MobileDevice/Mathews iPhone/`). A second press 22 s later launched a
new process whose `AVAudioSession` activation failed with `'!pla'` (`cannotStartPlaying`,
561015905). The silent kill matches the `AudioRecordingIntent` rule ("the system terminates the
recording if a Live Activity is not visible") — the island rendering has never been verified on
the device — but the file log cannot prove it: `Logger` lines never reach it. Fixed the blind
spot first: `RecordingCoordinator` now logs app state at start, `ActivityAuthorizationInfo`,
the activity id and every `ActivityState` transition, all errors (via `note`), and the process
lifecycle notifications. The device's unified log (`sudo log collect --device-name "Mathews
iPhone" --start "…"`) is the other half; it needs root on the Mac.

**Third device run (2026-09-14 06:25, owner, instrumented build):** the island *did* appear
(bars animating, "not smooth" — the WidgetKit timeline pulse, a known limitation), and the
instrumented log explained the rest. The press came 6 s after the owner opened the app;
`ios_start app_state=active activities_enabled=true`, the Live Activity went `active` at once,
but the **mic did not start for 15 s**: `startRecording` loads the shared Silero VAD lazily on the
first session after launch, and that CoreML load queued behind the Parakeet encoder compile the
launch warm-up had started. By then the phone was locked (`ios_app_did_enter_background`), the
audio session could not be activated from the background (`'!pla'`, `cannotStartPlaying`), the
coordinator showed Failed and the activity ended 3 s later — what looked like a crash. Fix (in
SplayCore, so the Mac gets it too): `MeetingRecordingService` now loads the VAD once in a shared
unstructured task, a starting session waits **at most 250 ms** for it (`liveVADReadyBudget`) and
otherwise uses fixed chunking for that session (`meeting_live_chunking_mode … reason=vad_not_ready`;
live preview only — the final transcript never depended on VAD); `prepareLiveVAD()` starts the
load at launch, and the phone runs it *before* the Parakeet warm-up. `meeting_recording_start_timing
lease_ms=… setup_ms=…` is logged before capture starts so the press-to-mic latency is always visible.
Last night's silent kill ~1 s into a background-started recording is still unexplained (the
unified log for that window is what would settle it).

**Fifth device run (2026-09-14 07:05, app not running, background start, build `2119d600`):** the model
holds — `audio_session_configured` → `audio_session_active … output=Speaker` → engine up in 180 ms →
first buffer 90 ms later → 30 s → `shared_mic_engine_stopped` → `audio_session_inactive` → **63 words saved**,
`.md` + `.m4a` in Files; no `'!int'`, no `configuration_changed` at all this time (iOS is not
reproducible about which notification it posts after activation — the structure now handles any of
them). Two findings: (1) `audio_route_changed reason=category input=none→MicrophoneBuiltIn
input_changed=true` 2 ms after activation restarted the just-started engine (fixed: category
changes and no-prior-input never restart); (2) `ios_clipboard_write_refused` with the app in the
background — the pasteboard is foreground-only by iOS policy, see § Decisions ▸ Delivery.

**Fourth device run (2026-09-14 06:37, app not running, phone locked):** the VAD fix holds —
`ios_start app_state=background`, `setup_ms=106`, `audio_session_active`, engine running,
`ios_recording_started` within 1.1 s of the press. 50 ms later iOS posted `audio_route_changed
reason=new_device` (our own activation routing the built-in mic), the follow-the-input handler
rebuilt the engine and **re-activated the session, which failed with `'!int'` three times**
(`shared_mic_engine_restart_failed`, then `gave_up recording_continues=true`), so no buffer ever
arrived → amber "No input" → the second press stopped a session with no audio
(`noAudioCaptured`) → Failed → the island ended. This is almost certainly last night's silent
kill too (same route change ~50 ms after the first buffer). Fix for the next thread, in
`MicrophoneEnginePlatform.swift`: (1) on iOS, ignore a route change whose input port UID did not
change (`AVAudioSession.currentRoute.inputs.first?.uid` before vs after), and the
`.newDeviceAvailable` that follows our own activation; (2) `startEngineLocked` must not call
`activateAudioSession()` when the session is already active (track it) — a rebuild keeps the
session, it only restarts the engine.

## Device dev loop (salvaged from the thread journal, 2026-09-14)

- Build + install: `scripts/dev/install_iphone.sh` (Wi-Fi is enough; phone unlocked). `NO_LAUNCH=1`
  keeps the app cold so the owner's Action Button press is the first launch.
- Phone: `Mathews iPhone` (iPhone 16 Pro), device id `D0B10BDC-0255-5F32-A804-AA87A111F4EE`.
- The app's diagnostics do **not** stream through `devicectl … launch --console` (FluidAudio lines
  only). They are written inside the container; pull them with:

  ```bash
  xcrun devicectl device copy from --device D0B10BDC-0255-5F32-A804-AA87A111F4EE --domain-type appDataContainer --domain-identifier com.macparakeet.mc.ios --source Library/Logs/MacParakeet/dictation-audio.log --destination /tmp/phone.log
  ```

- Debug app code lives in `Splay.app/Splay.debug.dylib`. My process cannot read `~/Desktop`; use `/tmp`.
- The unified log is owner-only: `sudo log collect --device-name "Mathews iPhone" --start …`.
- The Control is found under Action Button ▸ **Controls** ▸ search "Splay" (not a top-level entry).
- After any reinstall that wipes the container, the bundled model seeds itself; the older
  `devicectl device copy to` of the Mac's cached `parakeet-tdt-0.6b-v3` + `silero-vad` is no longer needed.

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
