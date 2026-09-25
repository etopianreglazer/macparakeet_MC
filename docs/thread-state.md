# Thread State — Splay (modified MacParakeet-MC fork)

> **What this is:** the "you are here" pin, rewritten **in place** at the end of every thread. It answers
> three questions only: what is live and installed, what is decided but not done, and what the next thread
> starts with. It is **not** the plan (`docs/fork-product-model.md`, `docs/plans/`) and **not** the journal —
> the previous thread's block is demoted to `docs/thread-log.md` (verbatim, newest first) each time this is
> rewritten. **Hard cap: 150 lines.** If it is longer, move something to the log or to a plan/README.
>
> **Last updated:** 2026-09-25, thread 16 (end) — **MAC: UPSTREAM 0.8.7 BUG FIXES PORTED (5 commits), INSTALLED,
> NOT YET PRESSED.** Owner direction this thread: Mac only, no iOS work. Thread 15's block is in `docs/thread-log.md`.

## 1. Live state

- Branch `ios/utility-layer`. **Nothing pushed.** Five new commits on top of thread 15: `5a95b210` (bounded
  ScreenCaptureKit/writer callbacks), `5073d1ea` (held failure + Retry; green only once the .md is written),
  `fa04691f` (listen-only fn tap, tap port released, crash reports kept locally), `27e5f39a` (mic liveness
  watchdog + implicit-route fallback), `54b6dd09` (macOS 14 Parakeet one window at a time on CPU+GPU).
- **Mac:** `/Applications/Splay.app` = `54b6dd09` (dev install 2026-09-25 ~10:53, `install_local.sh`), **running**,
  **not yet used for a recording.**
- **Phone:** untouched this thread. Still carries thread 15's island-dwell build (installed cold, never pressed).
- **Suite:** 1845 tests, the same 5 known environmental cases (6 assertion failures), zero new. iOS `SplayCore`
  compiles (pre-existing deprecation warnings only). **Vet:** every unit vetted; all findings fixed (notably: Retry
  would have duplicated the DB row → now re-transcribes the failed row in place; Sonoma config now keeps
  FluidAudio's GPU low-precision default).
- **The plan:** `docs/plans/upstream-087-port.md` — what upstream changed v0.6.17→v0.8.7, what was taken, what was
  deliberately not (Caps Lock/fn #1099 and hold-to-talk #1096 cannot happen here; new engines, AEC, Library/LLM/CLI).
  Decided there: **keep the explicit System Default pin** (the input policy needs it); fix its silent-start case instead.

## 2. Decided, not done

- **Carried from thread 15 (unchanged):** the "clipboard always" Action Button decision (owner); the iOS on-device
  list; the thread-15 island-dwell change in `RecordingCoordinator` was **never vetted** — `/vet` it before the next
  iOS unit; Mac visual pass (§C4 of `docs/launch-checklist.md`) and the second-Mac install test.
- **Upstream port, open:** FluidAudio 0.14.5 → 0.15.7 (long-form seam fixes; encoder-only GPU on 14) with a
  before/after WER check on real recordings; unscheduled small items listed at the bottom of the plan (fn tap
  during transcription dropped; Accessibility granted after launch not picked up; stray key between two fn taps;
  live-preview STT running unseen; 0.5 s trailing pad; Sparkle trust-anchor build check).
- **Behaviour to be aware of:** a held failure (capture *or* transcription) blocks `fn` until the island is clicked —
  the owner's earlier capture-failure decision, now applied to transcription failures too. Revisit if it annoys.
- **The liveness watchdog is Mac-only** (`MicrophoneInputPolicy.defaultLivenessInterval` is nil on iOS). Turning it
  on for iOS needs on-device evidence around interruptions.

## 3. ⭐ Next thread starts here — press the Mac build

`/Applications/Splay.app` runs `54b6dd09`. Log grammar for everything new is in `Sources/SplayCore/Audio/README.md`.
1. **Plain tap, talk, stop.** Expect the usual shape plus `shared_mic_engine_input_device_started source=system_default
   routing=explicit …`; no `shared_mic_liveness` line; green, and the `.md` in the folder. Silence in a quiet room
   must never produce `shared_mic_liveness`.
2. **Double-tap (mic + system), stop.** Stop returns promptly; no `system_audio_stream_*_timeout`.
3. **Thread 15's AirPods measurement** (still owed, now with the watchdog in play) — see the thread-log block for the
   exact steps and expected lines. New: if a frozen engine shows up it now reads `shared_mic_liveness
   reason=callbacks_stopped action=restart`; a pinned default that never delivers reads `reason=never_delivered` →
   `shared_mic_engine_skip_explicit_default` → `… routing=implicit`.
4. **Retry path (optional, deliberate):** point the meeting save folder at a location that is gone (e.g. an ejected
   volume), record, stop → island holds the failure; click → card "Transcript not saved" with Retry / Dismiss;
   restore the folder, Retry → green and the file appears; Recents shows the recording once.
5. **Typing feel:** with Splay running, typing in other apps should never lag, even while Splay is busy transcribing
   (the fn tap is listen-only now).
6. After a crash (if any): `~/Library/Application Support/MacParakeet-MC/crash-reports/` holds the report and the log
   has `app_previous_launch_crashed …`.
