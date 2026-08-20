# Plan: Fn rework (island foundation)

> Status: **ACTIVE**. Started 2026-06. See docs/fork-product-model.md.

## Goal
- **Single-tap Fn** = start/stop a **mic-only recording → saved transcript document**
  (route through the meeting pipeline with system audio OFF).
- **Double-tap Fn** = start/stop a **mic + system-audio** recording (normal meeting).
- **Remove push-to-talk** (hold Fn).
- **Retire ⌘⇧M** (`HotkeyTrigger.defaultMeetingRecording`).
- Paste-style dictation stays in the code but is **no longer driven by Fn** (dormant; not deleted).

## Why this order
The gesture rewire is meaningless until (a) the meeting pipeline can record mic-only, and
(b) the start path accepts a per-gesture source override. So build bottom-up.

## Increments (build + test after each)

1. **Mic-only audio support (Core).** ✅ DONE (Core builds clean)
   - `MeetingAudioSourceMode`: added `microphoneOnly` + `capturesSystemAudio`; `capturesMicrophone`
     now `!= .systemOnly`. ✅
   - `MeetingAudioCaptureService.start`: system-stream factory + `systemCapture.start` gated on
     `capturesSystemAudio` (ScreenCaptureKit + its permission skipped for mic-only). ✅
   - Audited `MeetingRecordingService`: `.systemBuffer` path never fires without a system stream;
     `canMuteMicrophone` correct; no hard system-track requirement. Mic-only → saved transcript. ✅
   - No behavior change yet (default stays `.microphoneAndSystem`).

2. **Per-gesture source override (App/coordinator).** ✅ DONE (compiles)
   - `MeetingRecordingFlowCoordinator.startRecording`/`toggleRecording` take
     `sourceModeOverride: MeetingAudioSourceMode?`, stored as `pendingAudioSourceModeOverride`
     before `.startRequested`, consumed in `.checkPermissions`. Screen-recording prompt now
     gated on `sourceMode.capturesSystemAudio` (mic-only never prompts). ✅

3. **New gesture mode (Core, pure + testable).** ✅ DONE (compiles, 4 unit tests pass)
   - Chose **threshold-wait** (~400ms) disambiguation — right for recording (not push-to-talk).
   - `HotkeyGestureController.Mode.singleAndDoubleTapToggle`: first tap arms the double-tap
     window (`scheduleHoldWindow`); a second tap → `toggleRecording(.microphoneAndSystem)`;
     timeout → `toggleRecording(.microphoneOnly)`. New `Output.toggleRecording(source:)`. ✅
   - `HotkeyManager`: `actsOnReleaseTap` treats the new mode like singleTapToggle (act on the
     completed tap via release); dispatches `.toggleRecording` to new `onToggleRecording`
     callback; `resumeMode` returns nil for the new mode. ✅
   - Tests: single→mic-only, double→mic+system, escape-cancels, typing-doesn't-cancel. ✅

4. **Wire Fn → meeting (App).** ✅ DONE in island Slice 1 (compiles).
   - `AppHotkeyCoordinator.setupFnRecordingHotkey()`: one Fn `HotkeyManager` with
     `.singleAndDoubleTapToggle`, `onToggleRecording` → new `onFnToggleRecording` closure.
   - `setupAllHotkeys` calls it instead of dictation+meeting hotkeys; `setupMeetingHotkey`
     neutered (⌘⇧M retired); push-to-talk no longer wired.
   - `AppEnvironmentConfigurer`: `onFnToggleRecording` → `meeting.toggleRecording(.hotkey, override)`.
   - Dictation idle pill suppressed via `AppFeatures.islandReplacesDictationPill`.
   - Auto-export to Finder default-ON (AutoSaveService gate + SettingsViewModel reads).

5. **Settings + defaults cleanup.** ⏸ Later slice (drop push-to-talk + meeting-hotkey rows from
   Settings UI; they're now inert but still visible).

## Sequencing note (2026-06)
Increments 4–5 re-point Fn away from dictation, which is wired into the **idle/floating pill**
(it shows "tap fn to dictate" and is driven by the dictation hotkey managers). The island phase
*replaces* that pill (idle → hover → recording lifecycle). Doing the Fn wiring now would leave a
mismatched pill (dictation hints while Fn records meetings) and throwaway glue. So the foundation
(1–3) is complete and verified; the Fn→meeting wiring is best done as the first step of the island
build, where Fn behavior and the pill UI are designed together. Foundation is not wasted — the
island phase consumes `singleAndDoubleTapToggle` + `onToggleRecording` + `sourceModeOverride` directly.

## Risks / invariants (from wiring audit)
- ADR-015 concurrent dictation+meeting: Fn now owns meeting start/stop. Dictation reachable only
  via dormant paths until the island phase. OK for now.
- ADR-021 engine leases: single-tap meetings start far more often — verify rapid start/stop is fine.
- Mic-only must NOT trigger the ScreenCaptureKit permission prompt.
- Double-tap latency on single-tap start — pick provisional vs threshold and document.
