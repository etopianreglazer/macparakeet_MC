# Fn dictation — double-tap dictates into the focused field, triple-tap is the meeting

> Status: **IN PROGRESS** (thread 19, 2026-09-27). Slices 1, 2, 4 built and installed (`1177b603`, `23bc6d7d`,
> island `edcef30b`…`a018b133`); slice 3 and 5 open — see `docs/thread-state.md` §2. Mac only.
> Slice 4 landed differently from the text below: the island is click-through, dictation shows the voice bars
> only (no caret, no timer), meetings add a second system-audio meter; tuned live by the owner.

## Why

Owner: *"I miss the dictate function where it auto-puts the transcription in the text field I'm in."*
They dictate **for a couple of minutes at a time**, so hold-to-talk (upstream's model) was rejected —
holding `fn` for minutes is tiring. Automatic meeting-vs-dictation detection was rejected too: the only
signal available at start is "is a text field focused", and a wrong guess pastes a whole meeting into
someone's message box. So: an explicit gesture.

This reverses one line of `docs/fork-product-model.md` ("Not dictation-as-paste … a dormant/future
opt-in") — update that doc in the same change.

## The gesture map

| Gesture (bare `fn`) | Result |
|---|---|
| Tap | Mic-only recording → transcript `.md` (unchanged) |
| **Double-tap** | **Dictation**: talk as long as you like; tap to stop → verbatim text pasted into the field focused *at stop* |
| **Triple-tap** | **Meeting**: mic + system audio → transcript `.md` (today's double-tap) |
| Tap while anything runs | Stop that thing |

Decided defaults (owner accepted, thread 18):
1. **Paste target = the field focused when you stop** (upstream's finish-target model). If nothing
   editable is focused, the text stays on the clipboard and the island says so.
2. **Every dictation is also kept** (Recents), so a paste that lands wrong is never lost. The user's
   clipboard is restored after the paste (`ClipboardService.pasteText(_:restoresClipboard:)`).
3. **Verbatim** — the deterministic `TextProcessingPipeline` only (ADR-004), same as transcripts. Check
   the dictation path has no AI-clean / LLM step left over from upstream.
4. **The island shows which mode is running** — dictation gets its own face so double vs triple is
   never ambiguous. Prototype in the live HTML tuner first (CLAUDE.md working method), like the meter.

Timing consequences to accept: double-tap now waits one more tap window (`FnKeyStateMachine
.defaultTapThresholdMs` = 400 ms) for a possible third tap, so dictation starts ~0.4 s after the second
tap. A too-slow triple resolves as dictation + an immediate stop tap → empty dictation, nothing pasted
(harmless; say so on the island rather than pasting nothing silently). Nothing becomes a meeting
without three taps.

## Where the code is today

- **Gesture resolution:** `Sources/SplayCore/STT/HotkeyGestureController.swift`, mode
  `.singleAndDoubleTapToggle` (`singleDoubleState`: `.idle` → `.awaitingSecondTap`, hold-window timer
  resolves single vs double). Wired in `Sources/Splay/Hotkey/HotkeyManager.swift` (`onToggleRecording`)
  and `Sources/Splay/App/AppHotkeyCoordinator.swift` `setupFnRecordingHotkey()` →
  `onFnToggleRecording(source)` → the meeting coordinator. Tests: `HotkeyGestureControllerTests`,
  `FnKeyStateMachineTests`.
- **Dictation is dormant, not deleted:** `Sources/Splay/App/DictationFlowCoordinator.swift` (1,073
  lines; still reachable — the menu bar calls `startDictation(mode: .persistent, trigger: .menuBar)`),
  `Sources/SplayCore/Services/Dictation/DictationService.swift` (record → `STTScheduler` with
  `job: .dictation` → `DictationResult`), `Sources/SplayCore/DictationFlow/` state machine,
  `Sources/SplayCore/Services/System/ClipboardService.swift` (paste + clipboard restore),
  `PasteShortcutKeyResolver.swift`. Its UI (overlay/idle pill, `Views/Dictation/`) is suppressed by
  `AppFeatures.islandReplacesDictationPill` — the island must carry dictation's states instead.
- **Shared mic:** dictation subscribes to the same `SharedMicrophoneStream` as meetings (ADR-015), now
  on upstream's Mac engine (`upstream-mic-port.md`). A dictation and a recording cannot both run from
  `fn` (a tap stops whatever runs), so no new concurrency case.

## Slices

1. **Gesture:** add a triple-tap resolution to `HotkeyGestureController` (new mode, e.g.
   `.tapDoubleTripleToggle`; keep the old mode for tests/rollback) with outputs for mic recording,
   dictation, meeting. While *anything* runs, a single tap stops it with no window wait. Unit tests
   first: tap / double / triple / slow triple / tap-while-running / stray key between taps.
2. **Routing:** `AppHotkeyCoordinator` sends double-tap to `DictationFlowCoordinator.startDictation
   (mode: .persistent, trigger: .hotkey)` and triple-tap to the meeting coordinator with
   `.microphoneAndSystem`; the stop tap goes to whichever is active. Make sure the two coordinators
   agree on "busy" (a tap during dictation transcription must not start a recording).
3. **Paste + keep:** verify the dictation path is verbatim; paste at stop into the focused field,
   clipboard fallback when nothing is focused; save each dictation where Recents shows it (check how
   upstream stores dictations — `dictations` table vs `transcriptions` — and whether the card's Recents
   needs a source filter). Accessibility permission prompt on first dictation (pasting synthesises ⌘V);
   the fn tap itself is listen-only and needs no new permission.
4. **Island:** dictation face (recording / transcribing / pasted / "copied — no text field") designed in
   the live tuner, then ported. The voice meter + timer can be shared with recording.
5. **Docs:** `fork-product-model.md` capture table, `CLAUDE.md` capture-model table, card Settings text
   that explains the gestures, this plan → HISTORICAL.

Each slice: failing test → code → focused tests → `swift test` (read **both** the XCTest lines and the
swift-testing summary) → `/vet` → commit. Install and have the owner press after slices 2, 3 and 4.

## Press list (owner, after install)

- Double-tap in a text field (Notes, Slack draft), talk ~2 min, tap → text lands at the cursor, clipboard
  unchanged afterwards, dictation visible in Recents.
- Double-tap, then click away to a non-text area before stopping → "copied" on the island, text on the
  clipboard.
- Triple-tap → meeting (mic + system) as before; single tap → mic recording as before.
- Deliberately slow triple → no paste, nothing broken.
