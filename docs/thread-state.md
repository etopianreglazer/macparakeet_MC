# Thread State — Splay (modified MacParakeet-MC fork)

> **What this is:** the "you are here" pin, rewritten **in place** at the end of every thread. It answers
> three questions only: what is live and installed, what is decided but not done, and what the next thread
> starts with. It is **not** the plan (`docs/fork-product-model.md`, `docs/plans/`) and **not** the journal —
> the previous thread's block is demoted to `docs/thread-log.md` (verbatim, newest first) each time this is
> rewritten. **Hard cap: 150 lines.** If it is longer, move something to the log or to a plan/README.
>
> **Last updated:** 2026-09-26, thread 18 — **MAC: UPSTREAM 0.8.7 MIC HANDLING PORTED (4 slices) + DISCARD BUG FIXED,
> INSTALLED, NOT YET PRESSED.** Owner direction: Mac first, iPhone later "in depth". Thread 17's block is in `docs/thread-log.md`.

## 1. Live state

- Branch `ios/utility-layer`, fast-forwarded to thread 17's worktree branch at the start (`fca4668b`). **Nothing pushed.**
  New: `82c10ed8` (Discard deletes the stuck DB row + launch sweep of orphaned `processing` rows; recovery now logs
  `meeting_recovery_*`), `7fa52805` / `352f77e2` / `e3490f5f` / `ccf9e349` (mic port slices 1–4).
- **Mac:** `/Applications/Splay.app` = `ccf9e349` (dev install 2026-09-26 ~15:55), **running, not yet used for a
  recording.** On launch it swept the two stuck rows (`meeting_recovery_swept_orphan_row` ×2); DB has 0 `processing`.
  Owner confirmed the 2026-09-25 12:22 recording was deleted by their own **Discard** click (no data-loss bug).
- **Suite:** 1960 XCTest (same 5 known environmental cases, 6 assertions) + 17 swift-testing, all green otherwise.
  **Check both frameworks** — the `swift test` output ends with a swift-testing summary; an issue there does not show
  up in the XCTest `error: -[…]` lines (a classifier test failed that way mid-thread and Vet caught it). iOS
  `SplayCore` compiles. **Vet:** every slice vetted; last round no issues.

## 2. What the mic port changed (full record: `docs/plans/upstream-mic-port.md` § "As built")

- **Mac engine = upstream's, taken whole and unedited** (except `routing=` on the started line + the macOS gate):
  implicit System Default (no pin), 1 s usable-buffer start gate (zero Bluetooth PCM doesn't count, one retry),
  default-input changes never rebuild a healthy engine, stop/stall → one recovery episode 0.5→16 s (~31 s) → engine
  death. Unused upstream bits (prewarm `prepare`, a notification nobody observes, nil lifecycle fields, long
  functions) kept **on purpose** for upstream parity — Vet flags them; declined.
- **Gone on the Mac:** Splay's liveness watchdog, hint/recheck rebuilds, the explicit-default pin
  (`mac-input-policy.md` is HISTORICAL for the Mac, still live for iOS).
- **iPhone unchanged:** own class in `MicrophoneEnginePlatform+iOS.swift`, hint/recheck path intact.
- **Dead mic mid-recording:** mic-only → recording fails after the recovery (held failure, audio kept). Mic + system
  → `meeting_capture_source_interrupted source=microphone`, recording carries on with system audio, island turns
  **amber** (`MeetingCaptureHealth.microphoneInterrupted`), meter flat; both sources gone → fails. (Upstream's rule.)
- `MicrophoneCapture.stop()` is now `async` (returns after real teardown); log lines carry `process_id=` — filter by it.

## 3. ⭐ Next thread starts here — press the Mac build (`ccf9e349`)

Log grammar: `Sources/SplayCore/Audio/README.md` § "Mac log grammar". Filter `dictation-audio.log` by Splay's
`process_id` (upstream MacParakeet writes the same file).
1. **Plain tap, talk, stop** → `shared_mic_engine_input_device_started source=system_default routing=implicit …`,
   `audio_engine_lifecycle operation=start outcome=success …`, green, `.md` written. Starts may take up to ~1 s longer
   than before (the start gate) — note if the island ambers at start.
2. **Double-tap, stop** → promptly stopped, no `system_audio_stream_*_timeout`.
3. **AirPods (the point of the port):** (a) record on the built-in mic with AirPods connected, trigger a switch → expect
   `audio_default_input_changed notifications=N` and **no** rebuild, bars keep moving. (b) record *through* AirPods and
   move them to the phone → `shared_mic_engine_configuration_changed` → `…_config_change_recovery_attempt` →
   `…_succeeded` on the built-in mic, bars resume. Silence in a quiet room must never produce `…_callback_stalled`.
4. Still unpressed from thread 16: the Retry path and typing-lag check (thread-log, thread 16 block §3).

## 4. Decided, not done

- **iPhone "in depth" comes after the Mac** (owner). Owed there: `/vet` the thread-15 island-dwell change in
  `ios/Splay/App/RecordingCoordinator.swift`; decide whether iOS moves to upstream-style recovery too.
- **Open from before:** Whisper cold load looks like a hang (low priority on Parakeet); visual refresh of the other
  island/card surfaces (ask which, prototype in the live tuner); FluidAudio 0.14.5 → 0.15.7 with a WER check and the
  small items in `docs/plans/upstream-087-port.md`; Mac visual pass + second-Mac install (`docs/launch-checklist.md` §C4).
- Held failures block `fn` until the island is clicked (owner's earlier decision) — revisit if it annoys.
