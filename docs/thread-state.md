# Thread State — MacParakeet-MC

> **What this is:** a handover of *where we left things*, written for the next session to
> resume cold. It is **not** a briefing (the "what's planned" lives in
> `docs/fork-product-model.md`) and **not** a build plan (`plans/active/fn-rework.md`). This is
> the "you are here" pin.
>
> **Last updated:** Slice 4 remains uncommitted and awaiting user interaction acceptance. A
> top-center island layout/color slice is also implemented locally and installed for review. See
> `plans/active/island-slice-4-overlays.md` and `plans/active/island-slice-5-top-center.md`.

---

## TL;DR — where we are right now

Personal fork **MacParakeet-MC**: slimmer, grass-green, **ambient "island"** interface, installed
side-by-side with upstream and **working**. The island is live and the user has live-confirmed it:

- **Idle** = tiny flat grey nub (bottom-center). **Hover** = grows to a 2-line hint
  ("Press **fn** to record" / "Double-tap for calls · Click to open").
- **Recording → Transcribing → Done** lifecycle pill morphs in place (red dot + waveform + timer +
  stop → spinner + bar → ✓ "Saved · N min"), driven by the shared `MeetingRecordingPillViewModel`.
- **Click the nub → expanded "Spotlight card"** grows smoothly *out of the hover pill* (same
  `.smooth` morph, same centered panel): search field (typable) + Record + Mic/Mic+System toggle +
  recents + Settings / Library / Reveal-in-Finder chips. Esc / click-away collapses it back down.
- **Fn** still records (single = mic, double = mic+system); **clicking** the nub opens the card.

## ⚠️ Immediate live state (check first next session)

- `main` has the committed island work at `3cb2d62b` (**Island UI: lifecycle pill + expanded card
  as one morphing surface**). It is currently **one commit ahead of `origin/main`**; do not push
  without the user's instruction.
- **Slice 4 is implemented but uncommitted.** Its exact state and acceptance criteria live in
  `plans/active/island-slice-4-overlays.md`.
- `swift build --skip-update -q` and `git diff --check` passed on 2026-08-05. This verifies the
  active changes compile and contain no whitespace errors; it does not replace live UI testing.
- App installed at `/Applications/MacParakeet-MC.app` includes Slice 4 plus the uncommitted
  top-center placement/color work. The release bundle was built, signed, and signature-verified on
  2026-08-05. The remaining acceptance test is user interaction; synthetic pointer automation
  cannot reliably operate the non-activating island on this machine.
- **Finder path checkpoint passed:** all 7 local meeting records resolve to an existing stored
  `meeting.m4a`; Library, transcript detail, and Meetings share the same guarded reveal action.
  `MeetingAudioFileTests` passed 20/20. A disabled Show in Finder action indicates a missing/stale
  source file, not a routing defect.
- **4 pre-existing test failures** remain (fork rebrand debt, NOT island-related): `AppPathsTests`,
  `MainWindowStateTests.testPrimarySidebarOrderRespectsMeetingFeatureFlag`,
  `AppHotkeyCoordinatorTests.testRefreshAllHotkeysIsSkippedWhileSuspended`, 3×`SettingsViewModelTests`
  default-folder asserts. They fail identically on a clean baseline. A background task was spawned to
  realign them; the island work added **zero** new failures.

## Done & verified this fork so far

- ✅ **Green reskin · nav slim (8→4) · data namespaced (`MacParakeet-MC`) · local install workflow**
  (earlier sessions).
- ✅ **Fn rework** — single-tap = mic-only, double-tap = mic+system; both route through the meeting
  pipeline → saved transcript → auto-export `.md` to `~/Documents/MacParakeet-MC/Meetings/`. ⌘⇧M +
  push-to-talk retired.
- ✅ **Island Chunk A** — `IslandController` + `IslandView` (`Sources/MacParakeet/Views/Island/`):
  one long-lived bottom-center non-activating panel; a single morphing rounded shape (capsule→card)
  with cross-fading content, `.smooth` animation; flat dark fill (NOT frosted glass — user prefers
  understated); old right-center sacred-geometry meeting pill suppressed under
  `islandReplacesDictationPill`.
- ✅ **Island Chunk B** — expanded "Spotlight card" is the `.expanded` morph **state of the same
  pill** (not a separate window). `ExpandedIslandView` is its foreground; the panel becomes key on
  expand so the search field types; Esc/click-away collapses. Chips currently open the **windowed**
  Settings/Library in the committed build.
- ✅ **Island Slice 4 (uncommitted; build-verified)** — Settings and Library chips now summon a
  shared dark floating overlay through `IslandOverlayController`, reusing the same `SettingsView`,
  `TranscriptionLibraryView`, and view models as the main app. Library transcript selection still
  dismisses the overlay and opens the transcript in the main window by design (Slice 7 owns that
  transition). The current overlay is intentionally flat-dark, titled/closable, and explicitly
  dismissed with close/Esc; it stays visible when the user switches apps.
- ✅ **Top-center island layout/color (uncommitted; build + visual verified)** — the shared
  `IslandLayout` now top-anchors the complete lifecycle surface. `IslandController` places the
  fixed stage on the physical display center (`screen.frame.midX`) and below
  `NSScreen.visibleFrame`'s menu-bar boundary. This avoids the 25pt right-shift caused when a
  left-side Dock narrows `visibleFrame`. Idle is near-black in both appearances; active semantic
  red/green states are unchanged. The installed build sits at the MacBook sensor/notch area
  without covering menu-bar controls.

## What's NEXT — remaining island work

Target visuals: `docs/design/final-lookbook.html`. Direction: `docs/fork-product-model.md`.

**Product direction reset (2026-08-05):** use `plans/active/island-only-lean-roadmap.md` as the
active roadmap. The island becomes the primary/sole workflow in phases; do not conflate its basic
meeting recorder with the separate dictation pipeline. First safe implementation slice is hiding
YouTube entry points only, retaining underlying code/data until replacement verification. That
slice is now implemented locally and build-verified; it still needs live review alongside the
uninstalled dark-overlay palette change.

**Surface invariant (user-locked):** the small top-center pill is the idle/resting state of the
same single morphing `IslandPanel` as the authoritative expanded black panel. It must never open
a separate overlay/window. Library, Settings, detail, export, recording, transcribing, done, and
optional live preview are router substates inside this one adaptive surface; Back/Close returns
within it, normally to the idle pill.

1. **Finish combined Slice 4 + top-center review** — have the user live-test the installed build:
   confirm the top position is comfortable and does not block the menu bar, then open the island, Settings,
   Library, search/type in both, repeatedly close/reopen and switch between them, close with Esc and
   close control, switch apps and return, select a transcript (which must open the main-window
   detail), and invoke every available Show in Finder action from Library/transcript contexts. If
   accepted, commit the six active files and update the plan to COMPLETE.
2. **Settings cleanup (slice 5)** — drop the now-inert push-to-talk + ⌘⇧M rows.
3. **Retire the main window (slice 6)** — once overlays stand alone.
4. **Transcript/summary layering (slice 7, separate track)** — verbatim + **Flag** pass, Distill/Decide
   as summary ops, **drop Polish**, stacked positional hotkeys.
5. **Glassiness (deferred polish)** — current fill is intentionally flat dark (`Color(white:0.13)`).
   Real `NSVisualEffectView` vibrancy bled past rounded corners; if revisited, round it via
   `maskImage`, not SwiftUI `.clipShape`.

## Tribal knowledge / gotchas (hard-won this session)

- **★ COPY WORKING ELEMENTS BEFORE REINVENTING.** AppKit floating-panel click/render/animation is a
  minefield; every island fix came from copying an existing *working* element and adjusting its
  properties — not hand-rolling. When something UI-ish doesn't work, find the element in this app that
  already does it and copy that first.
- **Island click delivery (the big one):** a non-key, non-activating `NSPanel` **never receives the
  idle click** — macOS routes it elsewhere. Hover works (tracking areas bypass this); clicks don't.
  Fix = catch the click with an **`NSEvent` global/local monitor** (see `IslandController.installClickMonitors`)
  + `canBecomeKey`/`acceptsFirstMouse`. Also: a `hitTest` that returns the **contentView itself** is
  treated as a window-background click and drops `mouseDown` — the hit target must be a **subview**
  (mirrors the meeting pill's `PillContentView`).
- **Clean rounded card = a titled window.** The expanded card reads clean because chrome (rounded
  corners + shadow) is **OS-drawn** — borderless + hand-drawn shadow/`compositingGroup` cast a visible
  rectangle. But for the **morph** we render the card in the **same ambient panel** as a SwiftUI
  `.expanded` state (not a window), so it grows with the identical `.smooth` curve as hover. (The
  earlier separate-window approach `flew in` / mis-centered — superseded.)
- **The morph trick:** one `RoundedRectangle(cornerRadius: min(height/2, 20))` = capsule at small
  heights, 20pt card when large → morphs capsule↔card as the frame animates. `IslandLayout` is the
  single source of truth for sizes; the AppKit tracker derives hit-rects from it.
- **`.expanded` wins in `IslandLayout.visual(...)`**; `IslandChromeModel.isExpanded` drives it; the
  tracker steps aside (`hitTest → nil`) when expanded so SwiftUI controls get clicks.
- **Decorative waveform** in the recording pill is self-animating (TimelineView), NOT metered audio —
  matches the lookbook.
- **`os_log` `.info` is not persisted** — use `.notice`+ for `log show` to retrieve it. (All island
  diagnostic logging was stripped before commit.)
- **xcodebuild is BROKEN here.** Use `swift build` + `scripts/dev/install_local.sh` (release build
  ~5–10 min, signs, installs to `/Applications/MacParakeet-MC.app`) → `open` it. Only the **user can
  live-test** the panel behavior — build, install, hand off.

## Authoritative references (read to resume)

- `Sources/MacParakeet/Views/Island/` — `IslandView.swift` (states + morph + layout),
  `IslandController.swift` (panel, tracking, click monitors, expand/collapse, key handoff),
  `ExpandedIslandView.swift` (card foreground).
- `Sources/MacParakeet/App/AppEnvironmentConfigurer.swift` — where the island is created + wired
  (record/select/settings/library/reveal callbacks). `AppDelegate.swift` retains it.
- `plans/active/island-slice-4-overlays.md` — **current execution state and acceptance boundary**.
  `Sources/MacParakeet/Views/Island/IslandOverlayController.swift` — Slice 4 panel host;
  `AppWindowCoordinator.swift` — overlay construction and Library → main-window transition.
- `plans/active/island-slice-5-top-center.md` — placement/color work layered on top of Slice 4;
  `IslandView.swift` / `IslandController.swift` own its geometry and screen placement.
- `docs/fork-product-model.md` — north star. `docs/design/final-lookbook.html` — visual target.
- Auto-memory: `~/.claude/projects/-Users-mathewcleveland-macparakeet-MC/memory/`.

## Working style (user preferences)

- **Copy working UI/effects elements before reinventing the wheel** (stated explicitly, and proven out
  this session).
- Prefers **understated/flat** over heavy frosted glass for the ambient surfaces.
- Open, exploratory conversation; builds in installable slices and live-tests each personally.
- Firm principle: **a transcript is never polished; only a summary can be.**
