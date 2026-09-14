# Thread State — Splay (modified MacParakeet-MC fork)

> **What this is:** the "you are here" pin, rewritten **in place** at the end of every thread. It answers
> three questions only: what is live and installed, what is decided but not done, and what the next thread
> starts with. It is **not** the plan (`docs/fork-product-model.md`, `docs/plans/`) and **not** the journal —
> the previous thread's block is demoted to `docs/thread-log.md` (verbatim, newest first) each time this is
> rewritten. **Hard cap: 150 lines.** If it is longer, move something to the log or to a plan/README.
>
> **Last updated:** 2026-09-14, end of thread 14 (+ a doc-only cleanup thread that created this shape).

## 1. Live state

- Branch `ios/utility-layer`, off `main`; `main` is untouched since the slice-1 iOS work. **Nothing pushed.**
- **Phone (`Mathews iPhone`, iPhone 16 Pro):** build `5bebeae6` installed 07:22 — the audio-session rework
  (`2119d600`, session per recording / engine per configuration) **plus** two follow-ups that are installed but
  **not yet pressed**: (1) no engine restart on our own `reason=category` route change; (2) clipboard writes
  defer while the app is in the background (`ios.pendingClipboardText`, flushed on `didBecomeActive`/`attach`).
- **Fifth device run passed** on `2119d600`: cold background start → 30 s → `ios_recording_saved words=63`,
  `.md` + `.m4a` in Files ▸ Splay ▸ MacParakeet-MC ▸ Meetings, session released.
- **Mac:** `/Applications/Splay.app` is a dev install (`install_local.sh`); notarized 0.1.0 exists, not published.
- **Suite:** 1793 tests, the same 5 known environmental failures (`CLAUDE.md`), zero new. Vet: clean.
- Device dev loop (install script, log pull, device id): `docs/plans/splay-ios-utility-layer.md` § Device dev loop.

## 2. Decided, not done

- **Owner decision needed — "clipboard always" from the Action Button.** The general pasteboard is refused to any
  non-foreground app (`PBErrorDomain 11`, policy; lock state irrelevant). Options: (a) Action Button → a
  *Shortcut* (Stop intent → returned text → Copy to Clipboard; Shortcuts may write from the background); (b)
  `openAppWhenRun`/`ForegroundContinuableIntent` on stop = ~1 s foreground flash; (c) accept "copied the next
  time you open Splay" + the file in Files. Plan § Decisions ▸ Delivery records the correction.
- **iOS on-device list still open:** the pending press (below), Pause/Resume from the island, a phone call
  mid-recording (interruption path), Back Tap → Shortcut, Lock Screen row, first-run UX; no recovery flow for
  orphaned sessions on iOS yet; the island bars' TimelineView pulse is choppy (`symbolEffect` later).
- **Mac visual pass (§C4 of `docs/launch-checklist.md`):** glow nudges + the talk-glow live verdict, in the tuner.
- **Second-Mac install test** of the notarized build has never been run.

## 3. ⭐ Next thread starts here — AirPods switching between phone and Mac

Owner direction at the end of thread 14: the head-of-recording restart the phone just had (a self-inflicted input
change restarting a healthy engine) has a Mac twin that is *more* frequent: **AirPods auto-switch between the
iPhone and the Mac mid-recording** (a notification on the phone, Siri, a call, or just talking to both). On the
Mac that is a HAL `kAudioHardwarePropertyDefaultInputDevice` change → `audio_default_input_changed` →
`SharedMicrophoneStream.followDefaultInputChange` → engine rebuild, and again when they come back (cold HFP,
`-10868`, the 300/800/2000 ms backoff — up to ~3 s of lost audio). Account for it *architecturally*, in the spirit
of `docs/plans/splay-ios-utility-layer.md` § Audio session model:

1. **Reproduce and measure first.** Record on the Mac with AirPods, pull a notification/call on the phone so
   they switch away and back, read `~/Library/Logs/MacParakeet/dictation-audio.log` (match pid): count
   `audio_default_input_changed` / `shared_mic_engine_restarted` / `shared_mic_follow_default_input_retry` and the
   buffer gaps. `MicrophoneEngineRealPlatformTests` has `MACPARAKEET_HAL_MUTATION_TESTS=1` for default-input
   switching — extend it rather than starting new.
2. **Decide the policy** (owner call, same shape as iOS). Leaving: keep recording on the built-in mic with the
   smallest gap. Returning: switch back (today) vs. stay put until the recording ends. Voice Memos follows the
   default both ways; Zoom/Teams stay put. Recommendation: **stay on the device that is actually delivering
   buffers; switch only when the current one stops** — a default-input change is a hint, the engine's
   silence/config change is the trigger.
3. **Unify with the iOS model where it fits.** The Mac only *logs* `AVAudioEngineConfigurationChange` (a
   sample-rate change without a device change stalls a Mac recording); `RecordingAudioSessionLifecycle` has no Mac
   counterpart. A portable "input policy" (device UID before/after + is the engine still delivering) would serve
   both platforms and be testable on the Mac. The coalescing in `followDefaultInputChange` already applies on the Mac.
4. **Then the pending iOS press** (cold, background, `5bebeae6`): expect the fifth-run shape **without**
   `shared_mic_follow_default_input` after start, `ios_clipboard_deferred reason=app_in_background`, then open the
   app → `ios_clipboard_written chars=… app_state=active` and the text pastes. Watch for a *repeating*
   `configuration_changed_restart` (a restart posting its own configuration change = loop; no rate limit yet, by
   decision). Then the rest of § 2.

## 4. Thread 14 block (verbatim; demote to `docs/thread-log.md` next rewrite)

> **Prior block (this thread, first unit):** **thread 14 — iOS AUDIO SESSION MODEL REWORKED (Voice Memos model), BUILT,
> INSTALLED ON THE PHONE.** Commit `2119d600`.
>
> ### Brief written before the fifth run (kept for the model summary)
> **What changed and why.** Thread 13's root cause was real but was two of six structural faults; fixing only those two
> would have left the recording dying anyway. The architecture is now written down in
> `docs/plans/splay-ios-utility-layer.md` § *Audio session model (iOS)* — read that table first. In one line: **the
> session is per recording, the engine is per configuration.** Policy = new `RecordingAudioSessionLifecycle`
> (SplayCore/Audio, portable, 10 tests); `AVAudioEngineMicrophonePlatform` applies it on iOS:
> - session category set once per process, `setActive(true)` once per recording, **never on a rebuild** (`.alreadyActive`);
> - route change → engine restart **only if the input port UID changed** (line now reads `audio_route_changed reason=…
>   input=a→b output=a→b input_changed=…`); the self-inflicted `new_device` after activation is ignored;
> - `AVAudioEngineConfigurationChange` (iOS: the engine *has stopped*) → `shared_mic_engine_configuration_changed_restart`
>   → engine restart, session untouched. This is what would have killed the recording even with the route fix;
> - interruption `.began` → session `interrupted`; `.ended`+`shouldResume` → re-activate (`.activateOnly`) + restart;
> - session observers live for the platform's lifetime (were per engine and died with every failed rebuild);
> - `stopEngine()` deactivates whenever the session is ours, engine running or not (the failing run leaked it — no
>   `audio_session_inactive` after the stop);
> - `SharedMicrophoneStream.followDefaultInputChange` is single-flight with coalescing (Mac too; backoff injectable,
>   4 new tests: restart keeps subscribers, 3 rapid triggers → 2 restarts, failure keeps subscribers + next trigger
>   recovers, idle trigger is a no-op).
> **Validation:** `swift build` green; iOS `SplayCore` compile green; full suite **1793 tests, the same 5 known
> environmental cases (6 assertion failures), zero new**. Vet (agentic, with history): **no issues**. Installed 06:56;
> pressed 07:05 → the fifth run above. Follow-up unit: suite the same 5 known cases, zero new; Vet: 2 doc/implementation mismatches (plan diagram, Stop intent description), both fixed.
> **Next (owner presses, app cold, phone locked, Action Button):** pull the log (command below) and expect, in order:
> `audio_session_configured`, `audio_session_active … output=…`, `ios_recording_started`, `audio_route_changed …
> input_changed=false` (ignored), possibly `shared_mic_engine_configuration_changed_restart` → `shared_mic_engine_restarted`
> with **no** `audio_session_activate_failed`, `meeting_mic_first_buffer`, then on the second press
> `meeting_mic_capture_stopped`, `audio_session_inactive`, `ios_recording_saved`, `ios_clipboard_deferred` →
> `ios_clipboard_written` after unlock. **Watch for:** a *repeating* `configuration_changed_restart` (would mean a restart
> itself posts a configuration change — a loop; no rate limit yet, by decision, until seen); and whether
> `output=` flips to `Speaker` at start — if so, dropping `.defaultToSpeaker` (functionless today) removes the
> restart and its ~400 ms gap at the head of every recording. Then the rest of the on-device list (Pause/Resume,
> Input dead, Back Tap → Shortcut, Lock Screen row). Mac-side question parked: the Mac only *logs* the
> configuration-change notification too; a sample-rate change without a device change would stall a Mac recording.
> **Log pull:** `xcrun devicectl device copy from --device D0B10BDC-0255-5F32-A804-AA87A111F4EE --domain-type
> appDataContainer --domain-identifier com.macparakeet.mc.ios --source Library/Logs/MacParakeet/dictation-audio.log
> --destination /tmp/phone.log`.
>
