# Thread State — Splay (modified MacParakeet-MC fork)

> **What this is:** the "you are here" pin, rewritten **in place** at the end of every thread. It answers
> three questions only: what is live and installed, what is decided but not done, and what the next thread
> starts with. It is **not** the plan (`docs/fork-product-model.md`, `docs/plans/`) and **not** the journal —
> the previous thread's block is demoted to `docs/thread-log.md` (verbatim, newest first) each time this is
> rewritten. **Hard cap: 150 lines.** If it is longer, move something to the log or to a plan/README.
>
> **Last updated:** 2026-09-14, thread 15 (end) — **INPUT POLICY (shared) BUILT + TESTED; iOS SIXTH RUN PASSED;
> ISLAND-DWELL FIX INSTALLED COLD, NOT YET PRESSED.** Owner direction: iOS first.

## 1. Live state

- Branch `ios/utility-layer`. **Nothing pushed.** Thread 15's unit is in the working tree (see § 3 for
  whether it is committed yet).
- **Mac:** `/Applications/Splay.app` = this tree (dev install 11:45, `install_local.sh`), **running**. It carries
  the new input policy; the log grammar it emits is in the Audio README § What to know.
- **Phone: sixth run PASSED on this tree (18:48, cold background press):** `audio_route_changed reason=category …
  input_changed=false` (ignored — the head-cut fix works), no follow/restart after start, `meeting_mic_first_buffer`
  +83 ms, 22.4 s → `ios_clipboard_deferred reason=app_in_background chars=158` → `ios_recording_saved words=29`.
  **Finding: the island never showed the green check** — `saved` was pushed and `end(dismissAfter: 3)` called in
  the same instant; ActivityKit removes an ended activity from the Dynamic Island *immediately* (the dismissal
  policy is Lock-Screen-only, verified in Apple's docs). Fixed: dwell 3 s in `.saved`/`.failed` while live, then
  `end(dismissAfter: 0)`; **reinstalled cold at ~19:00 (`install_iphone.sh NO_LAUNCH=1`), not yet pressed.**
- **Suite:** 1811 tests, the same 5 known environmental cases (6 assertion failures), zero new. iOS `SplayCore`
  compiles. **Vet:** first pass found 5 issues (1 real: iOS configuration change/interruption would have read
  `engine up` → recheck → `warming` → never rebuilt; fixed by tearing the engine down before the hint; 4 doc
  mismatches, fixed). Re-vet: 6 findings (stale comments, README wording, a missing `engine_restarts=` log field,
  the thread-14 demotion), all fixed. **The island-dwell change in `RecordingCoordinator` was never vetted —
  run `/vet` over it first thing next thread.**
- Device dev loop (install script, log pull, device id): `docs/plans/splay-ios-utility-layer.md` § Device dev loop.

## 2. Decided, not done

- **Owner decision needed — "clipboard always" from the Action Button.** The general pasteboard is refused to any
  non-foreground app (`PBErrorDomain 11`, policy). Options: (a) Action Button → a *Shortcut* (Stop intent →
  returned text → Copy to Clipboard); (b) `openAppWhenRun`/`ForegroundContinuableIntent` on stop = ~1 s
  foreground flash; (c) accept "copied the next time you open Splay" + the file in Files.
- **iOS on-device list still open:** the pending press (fifth-run shape **without** `shared_mic_follow_default_input`
  after start, `ios_clipboard_deferred reason=app_in_background` → open the app → `ios_clipboard_written`), Pause/
  Resume, a phone call mid-recording, Back Tap → Shortcut, Lock Screen row, first-run UX, no recovery flow for
  orphaned sessions, choppy bars pulse (`symbolEffect`). Watch for a *repeating* `configuration_changed_restart`.
- **Not in the input-policy slice, by decision:** a free-running silence watchdog (would fight the ~10 s cold-HFP
  warm-up); the island's amber stays visual-only.
- **Mac visual pass (§C4 of `docs/launch-checklist.md`)** and the **second-Mac install test** — unchanged.

## 3. ⭐ Next thread starts here — iOS first (owner direction, end of thread 15), then the Mac measurement

**What thread 15 did** (`docs/plans/mac-input-policy.md` is the plan; read its table first). Measured in the log:
two real August AirPods switches mid-recording restarted a healthy built-in-mic engine 0.9 s / 0.5 s after the
notification, 2–3× each (storms; coalesced since thread 14), cold-HFP `-10868` ×15 elsewhere. Two Mac twins of the
iOS faults found by reading: the HAL listener was per engine (a failed rebuild left nothing to recover), and the
Mac's configuration change was log-only. Built: **`MicrophoneInputPolicy`** (pure, 11 tests) — *stay on the device
that is delivering; switch only when the current one stops*: hint + engine down → restart now; hint + engine up →
rechecks at +1 s/+3 s, restart only if the last buffer is >1 s old (or none within 15 s of a start); **all hints on
both platforms** now enter `SharedMicrophoneStream.inputHint()`; HAL listener platform-lifetime; Mac configuration
change tears down a stopped engine and hints; `default_input_id=` + `engine_is_running=` in the log. 5 new stream
tests (hint while buffers flow → no restart; buffers stop → restart at the recheck; engine down → immediate; warm-up
→ wait; idle voids the chain).

**iOS is the priority (owner, 2026-09-14 12:00: "continue the iOS build, not the Mac application").** The
input policy is shared code and changed the phone too: a configuration change or an interruption now *tears the
engine down* before the hint, so the hint reads `engine_running=false verdict=restart_now` (immediate rebuild, as
before); a route change with the engine still delivering is no longer a restart. The sixth run (§ 1) already ran
this policy: no hint fired at all (the category route change is filtered before the hint).
**Next press (the island-dwell build is installed cold):** expect the same log shape as the sixth run, plus the
island holding the green check for ~3 s before returning to hardware, with `ios_live_activity_state=ended` now
~3 s after `ios_recording_saved` (and `dismissed` right after it). Then open the app → `ios_clipboard_written
chars=… app_state=active` and the text pastes. Then Pause/Resume, a phone call mid-recording
(`audio_session_interruption_began` → engine torn down → `…ended should_resume=true` → `shared_mic_input_hint
engine_running=false verdict=restart_now` → `shared_mic_engine_restarted`), and the rest of § 2.

**Mac, when the owner returns to it — the live measurement the brief asked for** (`/Applications/Splay.app`
already runs this code):
1. Record on the Mac **with AirPods connected but the built-in mic as the recording device** (today's typical
   case), pull a notification on the phone so the AirPods switch away and back, stop. Then
   `grep -E "audio_default_input_changed|shared_mic_input_hint|shared_mic_input_recheck|shared_mic_follow|shared_mic_engine_(restarted|configuration)" ~/Library/Logs/MacParakeet/dictation-audio.log | tail -30`.
   **Expect:** `audio_default_input_changed … default_input_id=a→b` → `shared_mic_input_hint engine_running=true
   verdict=recheck` → `shared_mic_input_recheck n=1 reason=alive action=recheck` → `n=2 reason=alive action=ignore`,
   both ways, and **no** `shared_mic_engine_restarted`. Transcript has no gap.
2. Record **through the AirPods** (select them, or make them the default before starting), pull them to the
   phone. **Expect:** `shared_mic_engine_configuration_changed … engine_is_running=false` →
   `…configuration_changed_stopped` → `shared_mic_input_hint engine_running=false verdict=restart_now` →
   `shared_mic_follow_default_input` → `shared_mic_engine_restarted` on the built-in mic, within ~0.5 s. When the
   AirPods return: a hint, rechecks `alive`, no restart. If instead the engine keeps `engine_is_running=true` but
   buffers stop, the recheck at +1 s reads `reason=stopped action=restart` — also fine; note which shape occurs.
3. If either shape misbehaves, the policy numbers (`MicrophoneInputPolicy` init defaults) are the dials; the log
   says which branch fired.
