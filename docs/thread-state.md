# Thread State — Splay (modified MacParakeet-MC fork)

> **What this is:** the "you are here" pin, rewritten **in place** at the end of every thread. It answers
> three questions only: what is live and installed, what is decided but not done, and what the next thread
> starts with. It is **not** the plan (`docs/fork-product-model.md`, `docs/plans/`) and **not** the journal —
> the previous thread's block is demoted to `docs/thread-log.md` (verbatim, newest first) each time this is
> rewritten. **Hard cap: 150 lines.** If it is longer, move something to the log or to a plan/README.
>
> **Last updated:** 2026-09-27, thread 20 (end) — **CLEANUP + BRANCH MODEL (main = releases, mac/dev = Mac work);
> ISLAND: IDLE NUB IGNORES THE CURSOR, RUNNING CAPTURE LIFTS ON HOVER, PINNED ABOVE DESKTOP SWIPES (private CGS
> space), METER BARS 18 PT, DICTATION METER SCALE FIXED. INSTALLED 25c64f84, owner pressed it: "very smooth".**
> Owner direction: Mac first, iPhone later "in depth". Thread 19's block is in `docs/thread-log.md`.

## 1. Live state

- **Branches:** `main` = releases only (`18524b40`, pushed). **`mac/dev`** = all Mac work, pushed at thread end.
  `ios/dev` does not exist yet — cut it from `mac/dev` when iOS resumes; `SplayCore` changes land on `mac/dev`
  first. The old `ios/utility-layer` (mixed Mac + iOS, never pushed) is gone; history before today interleaves
  both. Old worktree removed; `upstream` tracks `main` only. Short-lived `mac/<topic>` branches are fine.
- **Mac:** `/Applications/Splay.app` = `25c64f84`, running. Suite: 1990 XCTest (same 5 known environmental
  cases, 6 assertions) + 17 swift-testing. **Check both frameworks.**
- **fn gestures** unchanged: tap = mic recording, double = dictation (pastes at stop), triple = meeting.
- **Island** (owner pressed all of it this thread):
  - Idle nub visible again with the nub → pill expansion; it **ignores the cursor** (hover growth only with
    `AppFeatures.islandTakesMouse`). Note: `ignoresMouseEvents` does NOT stop tracking-area events.
  - A running capture scales to `SplayGeometry.captureHoverScale` (1.08, top-anchored) under the cursor;
    still click-through. Cleared when the pill leaves `.recording` and on `resetHover`.
  - **Pinned above Space swipes:** `IslandSpacePin` puts the panel in a private SkyLight space at max absolute
    level (dlsym'd `SLS*`/`CGS*`, no-op if missing; flag `AppFeatures.islandPinnedAcrossSpaces`). Re-pinned on
    the 3 s ambient re-order. Owner: "movement is stabilized". Log line `splay_island space_pin created`.
  - Meter: `SplayMeterTuning.maxHeight` 15 → 18 (owner's call; gain/release/wobble unchanged). Dictation level
    doubled before the island (AudioRecorder is RMS×5, recording flow RMS×10).
  - Dead per-control hover/press chain removed; stale comments swept (Vet: no bugs on `a04304e8..HEAD`).
- **Docs:** plan statuses fixed (fn-rework, island slices 4/5, two-surface, notch-island → HISTORICAL; iOS plan
  → PAUSED); README says triple-tap asks for Screen & System Audio.

## 2. ⭐ Next thread starts here

1. **Owed by the owner (blocked for the agent by the auto-mode classifier):**
   - ~~CLAUDE.md / AGENTS.md edits~~ — done thread 21 (branches, gestures, flags, ADR 005, push rule).
   - **Delete dead scripts:** `scripts/dev/{run_app,reset_and_run_fresh,benchmark_qwen_models,quality_eval_qwen}.sh`,
     then fix the `run_app.sh` mention in `docs/BRANDING.md` (~line 45).
2. **Press the pinned island** over Mission Control, a full-screen app, and the lock screen (boring.notch had
   it drawing over Mission Control's space labels). If it misbehaves: hide/unpin around those, or flag off.
3. **Fn dictation slice 3** (`docs/plans/fn-dictation-double-tap.md`): nothing-focused → keep text on the
   clipboard + "copied" face (today it pastes blind); dictations in the card's Recordings; decide Escape.
   Then slice 5 (product-model capture table + Settings gesture text) and mark the plan HISTORICAL.

## 3. Decided, not done

- **iPhone "in depth" comes after the Mac** (owner), on `ios/dev`. Owed there: `/vet` the thread-15
  island-dwell change in `ios/Splay/App/RecordingCoordinator.swift`; decide upstream-style recovery for iOS.
- Meter liveliness beyond height (gain 2.6 / release 0.09 / wobble 0.40 were offered in a tuner) — owner chose
  height only; revisit only if asked.
- Mic port presses still owed: AirPods switch cases (grammar in `Sources/SplayCore/Audio/README.md`), Retry path,
  typing-lag check.
- **Open from before:** Whisper cold load looks like a hang; FluidAudio 0.14.5 → 0.15.7 with a WER check
  (`docs/plans/upstream-087-port.md`); Mac visual pass + second-Mac install (`docs/launch-checklist.md` §C4).
- Held failures still block `fn`; a tap opens the failure card (menu ▸ Recordings does too).
- Vet via the claude CLI can hit the session limit and print an error instead of a review — read the output.
