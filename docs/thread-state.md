# Thread State — Splay (modified MacParakeet-MC fork)

> **What this is:** the "you are here" pin, rewritten **in place** at the end of every thread. It answers
> three questions only: what is live and installed, what is decided but not done, and what the next thread
> starts with. It is **not** the plan (`docs/fork-product-model.md`, `docs/plans/`) and **not** the journal —
> the previous thread's block is demoted to `docs/thread-log.md` (verbatim, newest first) each time this is
> rewritten. **Hard cap: 150 lines.** If it is longer, move something to the log or to a plan/README.
>
> **Last updated:** 2026-09-27, thread 19 (end) — **MAC: FN DICTATION LIVE (tap = recording, double = dictation,
> triple = meeting); ISLAND REDESIGNED (click-through, no rim, dictation face, meeting twin meter); MENU BAR
> REBUILT + ICON RESCUED FROM BEHIND THE NOTCH. INSTALLED a018b133, owner pressed most of it.**
> Owner direction: Mac first, iPhone later "in depth". Thread 18's block is in `docs/thread-log.md`.

## 1. Live state

- Branch `ios/utility-layer`, 10 commits this thread (`1177b603` … `a018b133`). **Nothing pushed.** Tree clean.
- **Mac:** `/Applications/Splay.app` = `a018b133`, running. Suite: 1989 XCTest (same 5 known environmental
  cases, 6 assertions) + 17 swift-testing, green otherwise. **Check both frameworks.**
- **fn gestures** (`HotkeyGestureController.tapDoubleTripleToggle` → `FnCaptureRouter`): tap = mic recording,
  double = dictation (upstream `DictationFlowCoordinator`, verbatim pipeline, pastes at stop), triple = meeting;
  a tap while anything runs stops it; a tap on a held failure opens its card. Owner pressed: double + triple work.
- **Island** (owner-tuned in the live tuner, 3 rounds): click-through (`AppFeatures.islandTakesMouse = false` —
  its click monitors were stealing address-bar/tab clicks and stopping dictations); no mark, no record dot, no
  fiber rim ("red halo"). Recording = red bars left of camera + timer right; meeting = + faint blue system bars
  (`systemLevel` now pushed); dictation = bars only, short ear right (the one asymmetric face). Geometry:
  `SplayGeometry.layout(for:kind:notchAttached:)` (size + offset), shared with `IslandLayout.pillRect`.
  Upstream dictation overlay replaced by `HiddenDictationOverlayController`. **Owner has not yet pressed `a018b133`.**
- **Menu bar:** Splay-shaped menu with SF Symbols (Recordings ⌘O, Paste Last Dictation, Recent Dictations,
  Start/Stop Recording, Transcribe File, fn hint line, Settings, Updates, Quit); card tab renamed "Recordings".
  The icon was invisible: macOS had remembered it 781pt from the right = behind the camera. Launch now resets a
  hidden/absent position right of the notch (`MenuBarCoordinator.correctedStatusItemPosition`).
- **Not bugs, for the record:** doubled dictation text = **upstream MacParakeet 0.8.7 also running** and also
  dictating on fn double-tap (owner's app; not touched). The "killed" recording 07:46 = owner quit Splay and
  picked **Discard Recording** in the quit dialog (`meeting_recording_cancelled`).

## 2. ⭐ Next thread starts here

1. **Vet leftovers (owner said: next thread).** Vet on `00a48963..a04304e8`, no bugs, docs/dead code only:
   (a) the per-control hover/press chain is dead — `IslandChromeModel.hoveredControl/pressedControl`,
   `IslandTrackingView.onControlHover/onControlPress/setControlHover/pressPulse/lastControl` are written, never
   read (a removal was drafted and reverted at wrap; easy redo); `AppFeatures.islandTakesMouse` doc overclaims
   "restores clicks and hover" (per-control pop is gone); (b) `SplayIslandLight.readyWidth` comment says the
   ready step is "no longer reached" — wrong, `heldOpen` (card open) still morphs the nub to 248×38;
   (c) `IslandView.pillSize` comment names the deleted `SplayGeometry.size`; (d) `IslandCaptureKind.dictation`
   doc still says "meter + text cursor"; (e) stale "pop / depress" comments in `IslandController` dispatchClick
   and `IslandView.control(at:)`. **Then run `/vet` on `a018b133`** (not yet reviewed).
2. **Owner press of `a018b133`:** tap / double / triple faces on the notch; timer right; dictation ear.
3. **Fn dictation slice 3** (`docs/plans/fn-dictation-double-tap.md`): nothing-focused → keep text on the
   clipboard + "copied" face (today it pastes blind; `.copied` only on paste failure); dictations in the card's
   Recordings (today only menu ▸ Recent Dictations); Escape does not cancel an fn dictation (decide). Then
   slice 5: `fork-product-model.md` capture table + card Settings gesture text; mark the plan HISTORICAL.

## 3. Decided, not done

- **iPhone "in depth" comes after the Mac** (owner). Owed there: `/vet` the thread-15 island-dwell change in
  `ios/Splay/App/RecordingCoordinator.swift`; decide whether iOS moves to upstream-style recovery too.
- Mic port presses still owed: AirPods switch cases (grammar in `Sources/SplayCore/Audio/README.md`), Retry path,
  typing-lag check.
- **Open from before:** Whisper cold load looks like a hang; FluidAudio 0.14.5 → 0.15.7 with a WER check
  (`docs/plans/upstream-087-port.md`); Mac visual pass + second-Mac install (`docs/launch-checklist.md` §C4).
- Held failures still block `fn`; a tap now opens the failure card (menu ▸ Recordings does too).
- Vet via the claude CLI can hit the session limit and print an error instead of a review — read the output,
  rerun after the reset.
