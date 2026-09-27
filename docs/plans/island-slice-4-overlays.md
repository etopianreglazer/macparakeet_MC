# Plan: Island Slice 4 — Settings + Library overlays

> Status: **HISTORICAL** — superseded; the overlays were replaced by the card (`splay-two-surface-rebuild.md`). Started 2026-06. Fork (MacParakeet-MC). See `docs/fork-product-model.md`,
> `docs/thread-state.md`, `docs/design/final-lookbook.html`.

## Goal

The expanded island card's **Settings** and **Library** chips currently open the full main
window (`mainWindowState.navigate(…) + onOpenMainWindow()`). Replace that with **island-matched,
flat-dark floating overlays** that reuse the existing `SettingsView` / `TranscriptionLibraryView`.
This makes the island self-sufficient — the prerequisite for Slice 6 (retiring the main window).

## Decisions (locked with user, 2026-06-09)

- **Backdrop:** flat-dark, matching the island's existing `Color(white:0.13)` + `.dark` scheme +
  rounded card. NO `NSVisualEffectView` — true vibrancy stays the separate deferred-polish item
  (corner-bleed pitfall, see `docs/thread-log.md`).
- **Library → transcript (`onSelect`):** keep routing to the main window for now. Transcript-as-
  overlay is Slice 7 (transcript/summary layering), out of scope here.

## Principle

**Copy what works.** Three existing pieces are the wheel:
- `MeetingRecordingPanelController` — the proven "host a full SwiftUI view in a floating NSPanel"
  pattern (panel subclass + createPanel/show/hide/close + window delegate).
- `TranscriptionLibraryView` — takes the `TranscriptionLibraryViewModel` the island already holds
  + `onSelect`. Near drop-in.
- The island's own dismissal pattern — `.onExitCommand` + `windowDidResignKey` + `dismissArmed`.

## Implementation status

- ✅ Controller, dependency wiring, and chip rewiring are implemented locally.
- ✅ `swift build --skip-update -q` and `git diff --check` passed on 2026-08-05.
- ✅ A signed Slice 4 build was installed locally on 2026-08-05. It has since been superseded in
  `/Applications/MacParakeet-MC.app` by the uncommitted top-center island layout build; Slice 4's
  overlay behavior remains included and still needs the live acceptance cycle below.
- ✅ **Reveal in Finder checkpoint (2026-08-05):** Library, transcript detail, and Meetings all
  route through `MeetingAudioActions.revealInFinder` → `MeetingAudioFile.mixedAudioURL`, gated by
  `isAvailable`. The local database has 7 meeting records; all 7 stored `meeting.m4a` paths exist.
  `swift test --filter MeetingAudioFileTests` passed 20/20. No path-resolution or action-wiring bug
  was found; a disabled action represents a genuinely missing/stale source file.
- ⏳ The remaining acceptance test is live interaction by the user, including repeated Settings /
  Library open-close-switch cycles, Esc and close-control dismissal, app-switch persistence,
  transcript selection, and invoking each available Show in Finder action. Then commit the six
  Slice 4 files.

## Increments (implemented; live-test after the wiring step)

1. **`IslandOverlayController`** (`Sources/MacParakeet/Views/Island/`). Copy
   `MeetingRecordingPanelController`. One controller, hosts arbitrary SwiftUI content. Centered,
   rounded, flat-dark (`Color(white:0.13)`, `.dark` colorScheme), `.floating` level,
   `canBecomeKey`. The implementation uses a titled `fullSizeContentView` panel for clean
   OS-rendered corners/shadow; dismiss explicitly with close/Esc and preserve it on app switch.
   `show(content:)` / `hide()`.
2. **Inject dependencies.** From `AppEnvironmentConfigurer`, give the overlay controller (or the
   island) what `SettingsView` needs: `settingsViewModel`, `llmSettingsViewModel`, `updater`,
   `transformsViewModel.transforms`, `onHotkeyRecordingStateChanged`; plus `libraryViewModel` for
   the Library overlay (already held). Reuse the SAME objects the main window uses.
3. **Rewire chip callbacks.** `controller.onOpenSettings` → overlay with `SettingsView`;
   `controller.onOpenLibrary` → overlay with `TranscriptionLibraryView`. Remove the
   `navigate + onOpenMainWindow()` calls for those two. Leave `onRecord`, source toggle,
   Reveal-in-Finder, and Library `onSelect` (→ main window) untouched.

## Invariants / must-not-change

- Idle/hover/recording/transcribing/done lifecycle morph — untouched.
- Click delivery + tracking for the non-expanded states — untouched.
- `onRecord` / source-mode / Reveal-in-Finder — untouched.
- Library `onSelect` still opens the transcript in the main window.
- No new vibrancy; no `.clipShape` on an `NSVisualEffectView`.

## Out of scope

- True frosted-glass vibrancy (deferred polish #1).
- Transcript-as-overlay (Slice 7).
- Settings cleanup of inert push-to-talk / ⌘⇧M rows (Slice 5).
- Retiring the main window (Slice 6).
