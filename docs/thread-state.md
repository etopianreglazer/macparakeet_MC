# Thread State — MacParakeet-MC

> **What this is:** a handover of *where we left things*, written for the next session to
> resume cold. It is **not** a briefing (the "what's planned" lives in
> `docs/fork-product-model.md`) and **not** a build plan (`plans/active/fn-rework.md`). This is
> the "you are here" pin.
>
> **Last updated:** end of the session that built the **ambient island UI** — Chunk A (idle ·
> hover · recording · transcribing · done lifecycle pill) and Chunk B (the expanded "Spotlight
> card" as a true morph of the same pill).

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

- The island work is **committed on `main`** (this session). Verify pushed:
  `git -C /Users/mathewcleveland/macparakeet_MC log --oneline origin/main..main` — if empty it's
  pushed. `gh auth` now works (SSH, account `etopianreglazer`), so `git push origin main` works
  directly; the user has also pushed via GitHub Desktop before.
- App installed at `/Applications/MacParakeet-MC.app`, last build = unified-morph island.
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
  Settings/Library (glass overlays are still TODO — slice 4).

## What's NEXT — remaining island work

Target visuals: `docs/design/final-lookbook.html`. Direction: `docs/fork-product-model.md`.

1. **Glassiness (deferred polish)** — the user said the card "isn't glassy enough for my taste, but
   that might be for later." Current fill is flat dark (`Color(white:0.13)`). Real `NSVisualEffectView`
   vibrancy bled past rounded corners (can't be clipped from SwiftUI) — if revisited, round it via
   `maskImage`, not SwiftUI `.clipShape`.
2. **Glass Settings + Library overlays (slice 4)** — make the card's Settings/Library chips summon
   dark-vibrancy overlays (reusing `SettingsView` / `TranscriptionLibraryView`) instead of opening the
   main window.
3. **Settings cleanup (slice 5)** — drop the now-inert push-to-talk + ⌘⇧M rows.
4. **Retire the main window (slice 6)** — once overlays stand alone.
5. **Transcript/summary layering (slice 7, separate track)** — verbatim + **Flag** pass, Distill/Decide
   as summary ops, **drop Polish**, stacked positional hotkeys.

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
- `docs/fork-product-model.md` — north star. `docs/design/final-lookbook.html` — visual target.
- Auto-memory: `~/.claude/projects/-Users-mathewcleveland-macparakeet-MC/memory/`.

## Working style (user preferences)

- **Copy working UI/effects elements before reinventing the wheel** (stated explicitly, and proven out
  this session).
- Prefers **understated/flat** over heavy frosted glass for the ambient surfaces.
- Open, exploratory conversation; builds in installable slices and live-tests each personally.
- Firm principle: **a transcript is never polished; only a summary can be.**
