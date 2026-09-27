# Plan: Island Slice 5 — Top-center placement + adaptive black chrome

> Status: **HISTORICAL** — superseded; the top-centre island has since been redesigned (thread 19, 2026-09-27). Fork
> (MacParakeet-MC). This sits on top of, but does not replace, the Slice 4 overlay closeout.

## Goal

Move the ambient island from bottom center to top center, visually relating its idle nub to the
MacBook sensor/notch area without covering menu-bar controls. Replace the idle flat-grey fill with
near-black adaptive chrome; retain semantic recording/transcribing/done accents.

## Implemented

- `IslandLayout` top-anchors the lifecycle surface and derives the visible pill and enlarged idle
  hit target from the same geometry. The expanded card grows downward from the top, preserving the
  single-surface morph and all active-state hit rectangles.
- `IslandController` uses `screen.frame.midX` for the physical display/webcam axis and
  `NSScreen.visibleFrame.maxY` only as macOS's safe boundary below the menu bar. The notched
  display gets no additional panel gap plus the view's 8pt inset; notchless/external displays keep
  a 10pt fallback gap.
- `IslandView` uses near-black opacity in light and dark appearance rather than an opaque grey;
  red/green lifecycle semantics remain unchanged.
- `swift build --skip-update -q` and `git diff --check` passed. The release bundle was signed and
  installed at `/Applications/MacParakeet-MC.app`; a screenshot confirmed top-center placement on
  the available MacBook display.
- **Center correction (2026-08-05):** the built-in display's visible frame starts at x=50 because
  the left Dock is visible, shifting `visibleFrame.midX` 25pt right of the webcam axis. The
  corrected build is rebuilt, signed, installed, and running.

## Acceptance before commit

1. Confirm the idle nub is comfortable below/against the sensor area and leaves all menu-bar
   controls reachable.
2. Verify hover/click expands the island; recording, transcribing, done, and expanded-card geometry
   remain aligned with their hit targets.
3. Run the still-required Slice 4 stress path: repeated Settings/Library open-close-switch cycles,
   Esc/close behavior, app-switch persistence, transcript selection, and every available Show in
   Finder action.
4. Check both light and dark appearances if available.

## Guardrails

- Do not cover the menu bar or change its controls.
- Do not alter recording lifecycle behavior, callbacks, or Finder resolution.
- Do not commit or push until the user accepts both outstanding review paths.
