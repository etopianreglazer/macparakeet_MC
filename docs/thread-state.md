# Thread State — Splay (modified MacParakeet-MC fork)

> **What this is:** the "you are here" pin, rewritten **in place** at the end of every thread. It answers
> three questions only: what is live and installed, what is decided but not done, and what the next thread
> starts with. It is **not** the plan (`docs/fork-product-model.md`, `docs/plans/`) and **not** the journal —
> the previous thread's block is demoted to `docs/thread-log.md` (verbatim, newest first) each time this is
> rewritten. **Hard cap: 150 lines.** If it is longer, move something to the log or to a plan/README.
>
> **Last updated:** 2026-09-27, thread 21 (end) — **FN DICTATION SLICE 3 DONE + PRESSED: no blind paste (no
> text field → clipboard + island copy face), dictations in the card's Recordings, Escape → 3·2·1 undo countdown
> (fn keeps it). CLAUDE.md/AGENTS.md brought current; dead upstream scripts deleted. INSTALLED f986f26d.**
> Owner direction: next a few small **design continuity checks**, then **work towards the iOS app**.
> Thread 20's block is in `docs/thread-log.md`.

## 1. Live state

- **Branches:** `main` = releases only (`18524b40`). **`mac/dev`** = all Mac work, head `bcae2c02`, **not pushed
  this thread** (push when the owner asks). `ios/dev` does not exist yet — cut it from `mac/dev` when iOS starts.
- **Mac:** `/Applications/Splay.app` = `f986f26d` (docs-only commit after it). Suite: 2008 XCTest (same 5 known
  environmental cases, 6 assertions) + 17 swift-testing. **Check both frameworks.**
- **fn gestures:** tap = mic recording, double = dictation, triple = meeting (mic + system).
- **Dictation, thread 21 (owner pressed all three: "works"):**
  - Paste target is whatever is focused **when you stop**. `AccessibilityService.focusedPasteTarget()` → editable
    (text roles, `AXEditable`, settable caret range) / not editable / unknown (no AX grant → paste path as before).
    Not editable → text stays on the clipboard, island shows the copy face. Every decision logs
    `dictation_paste_target verdict= role= app=` — Electron apps (Slack, VS Code) are the likely false "copied".
  - Card Recordings interleaves dictations (`dictations` table, via `Dictation.displayText`) with recordings,
    newest 5; a text-cursor glyph marks dictations; click copies.
  - **Escape** while capturing → `DictationFlowTiming.cancelCountdownSeconds` (3, upstream 5) on the island
    (`.cancelling` ring with the digit); fn tap = undo (transcribe + paste); Escape again / expiry = discard.
    Escape is ignored by recordings, meetings, and a *transcribing* dictation (`FnCaptureRouter.escape`,
    `isEscapeCancellable`) — the state machine's cancel there has no undo window (Vet caught it).
- **Island:** unchanged from thread 20 (click-through, pinned above Space swipes, idle nub, 18 pt bars).

## 2. ⭐ Next thread starts here

1. **Small design continuity checks** (owner's pick, scope not yet named — ask which surfaces). Candidates seen
   this thread: the new `.cancelling` countdown ring (neutral grey `C9C4D8`, 9.5 pt digit — first cut, never
   tuned) next to the ✓ / copy glyphs; the dictation text-cursor glyph in the card's Recordings; the card's
   empty-state text still says "Hold your shortcut…". Visual tuning goes in the live HTML tuner, not install loops.
2. **Fn dictation slice 5** (small, can ride along): card Settings text explaining the gestures (+ Escape),
   the empty-state line, `fork-product-model.md` capture table; then mark `docs/plans/fn-dictation-double-tap.md`
   HISTORICAL.
3. **Then towards iOS:** cut `ios/dev` from `mac/dev`; read `docs/plans/splay-ios-utility-layer.md` (PAUSED)
   first. Owed there: `/vet` the thread-15 island-dwell change in `ios/Splay/App/RecordingCoordinator.swift`;
   decide upstream-style recovery for iOS. `SplayCore` iOS compile check is in CLAUDE.md.
4. Still unpressed from thread 20: the pinned island over Mission Control, a full-screen app, the lock screen.

## 3. Decided, not done

- Meter liveliness beyond height (gain 2.6 / release 0.09 / wobble 0.40 offered in a tuner) — owner chose height
  only; revisit only if asked.
- Mic port presses still owed: AirPods switch cases (grammar in `Sources/SplayCore/Audio/README.md`), Retry path,
  typing-lag check.
- **Open from before:** Whisper cold load looks like a hang; FluidAudio 0.14.5 → 0.15.7 with a WER check
  (`docs/plans/upstream-087-port.md`); Mac visual pass + second-Mac install (`docs/launch-checklist.md` §C4).
- Held failures still block `fn`; a tap opens the failure card (menu ▸ Recordings does too).
- Vet (`--agentic --agent-harness claude`) can take >10 min — run it in the background; it can also hit the
  session limit and print an error instead of a review — read the output.
