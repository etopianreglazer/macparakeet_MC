# Thread State — Splay (modified MacParakeet-MC fork)

> **What this is:** the "you are here" pin, rewritten **in place** at the end of every thread. It answers
> three questions only: what is live and installed, what is decided but not done, and what the next thread
> starts with. It is **not** the plan (`docs/fork-product-model.md`, `docs/plans/`) and **not** the journal —
> the previous thread's block is demoted to `docs/thread-log.md` (verbatim, newest first) each time this is
> rewritten. **Hard cap: 150 lines.** If it is longer, move something to the log or to a plan/README.
>
> **Last updated:** 2026-09-27, thread 22 (end) — **FN DICTATION DONE (slice 5): Settings shows a read-only fn
> gesture legend instead of the dead "Record system audio too" toggle; Menu ▸ Start Recording is mic-only; empty
> state fixed; dictation plan HISTORICAL. Accent/app-icon colours parked for iOS. INSTALLED b01b9ad8.**
> Thread 21's block is in `docs/thread-log.md`.

## 1. Live state

- **Branches:** `main` = releases only (`18524b40`). **`mac/dev`** = all Mac work, **not pushed** since thread 20
  (push when the owner asks). `ios/dev` does not exist yet — cut it from `mac/dev` when iOS starts.
- **Mac:** `/Applications/Splay.app` = `b01b9ad8`. Suite: 2008 XCTest (same 5 known environmental cases,
  6 assertions) + 17 swift-testing. **Check both frameworks.**
- **fn gestures:** tap = mic recording, double = dictation, triple = meeting (mic + system); esc during a
  dictation = 3·2·1 undo countdown. The gesture is the only source picker: both source-mode providers
  (`AppEnvironment`, `AppEnvironmentConfigurer`) return `.microphoneOnly`, fn passes an explicit override;
  the stored `meetingAudioSourceMode` preference is dormant (left in `SettingsViewModel`, unused by the card).
- **Card Settings:** `SplayGestureLegend` (in `SplayCard.swift`, esc row reads
  `DictationFlowTiming.cancelCountdownSeconds`) → Launch at login · Play a sound → Accent picker.
- **Island / dictation:** unchanged from thread 21 (see the log).

## 2. ⭐ Next thread starts here

1. **Owner press (new, unpressed):** open the card ▸ Settings — does the legend read right and fit? Empty
   Recordings line. Menu ▸ Start Recording records mic only.
2. **Towards iOS:** cut `ios/dev` from `mac/dev`; read `docs/plans/splay-ios-utility-layer.md` (PAUSED) first.
   Owed there: `/vet` the thread-15 island-dwell change in `ios/Splay/App/RecordingCoordinator.swift`; decide
   upstream-style recovery for iOS. New row in its Decisions table: accents + alternate app icons (owner idea,
   thread 22 — the Mac deliberately does **not** recolour its icon; no macOS API for it).
3. Still unpressed from thread 20: the pinned island over Mission Control, a full-screen app, the lock screen.

## 3. Decided, not done

- The Escape countdown ring is a neutral grey (`C9C4D8`, 9.5 pt digit), never tuned. Owner skipped colour work
  on the Mac this thread; revisit only if asked.
- Meter liveliness beyond height (gain 2.6 / release 0.09 / wobble 0.40 offered in a tuner) — owner chose height
  only; revisit only if asked.
- Mic port presses still owed: AirPods switch cases (grammar in `Sources/SplayCore/Audio/README.md`), Retry path,
  typing-lag check.
- **Open from before:** Whisper cold load looks like a hang; FluidAudio 0.14.5 → 0.15.7 with a WER check
  (`docs/plans/upstream-087-port.md`); Mac visual pass + second-Mac install (`docs/launch-checklist.md` §C4).
- Held failures still block `fn`; a tap opens the failure card (menu ▸ Recordings does too).
- Vet (`--agentic --agent-harness claude`) takes 10–15 min here — run it in the background; it can also hit the
  session limit and print an error instead of a review — read the output.
