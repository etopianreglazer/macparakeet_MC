# Thread State — MacParakeet-MC

> **What this is:** a handover of *where we left things*, written for the next session to
> resume cold. It is **not** a briefing (the detailed "what's planned" lives in
> `docs/fork-product-model.md`) and **not** a build plan (the executable step-by-step lives in
> `plans/active/fn-rework.md`). This is the "you are here" pin.
>
> **Last updated:** 2026-06-03, end of the session that did: green reskin → nav slim → fork
> docs/mockups → Fn rework foundation → **island Slice 1** → git/version-control setup.

---

## TL;DR — where we are right now

Personal fork **MacParakeet-MC**: slimmer, grass-green, moving toward an **ambient "island"**
interface. It's installed side-by-side with upstream and **working**. We just shipped and
live-tested **island Slice 1**: the global **Fn key is now a recording key** (single-tap = mic
only, double-tap = mic + system), and finished transcripts **auto-export as `.md` to Finder**.
The user confirmed it works (single + double tap + md auto-creation).

## ⚠️ Immediate live state (check this first next session)

- **Two local commits on `main` are committed but may be UNPUSHED.** The user was pushing them
  via **GitHub Desktop** (this machine has no working git CLI credentials; `gh` is now installed
  but `gh auth login` may or may not have been completed).
  - Commits: `b383af1b` (Rebrand fork…) + `a2ae009b` (Fn rework + island Slice 1…) — and possibly
    a 3rd adding this file.
  - **Verify at session start:** `git -C /Users/mathewcleveland/macparakeet_MC log --oneline origin/main..main` — if empty, the push succeeded. `origin` = `github.com/etopianreglazer/macparakeet_MC`, `upstream` = `moona3k/macparakeet`.
  - If still unpushed and CLI auth now works (`gh auth status`), offer to `git push origin main`.
- App is installed at `/Applications/MacParakeet-MC.app` and was last running.

## Done & verified this fork so far

- ✅ **Green reskin** — `DesignSystem` accent = grass green (`#39C24A`/`#5BDB57`); custom green
  sidebar rows (macOS ignores `.tint` on native sidebar selection).
- ✅ **Nav slim 8 → 4** — `Capture · Library · Transforms · Settings`.
- ✅ **Data namespaced** — `AppPaths.appFolderName = "MacParakeet-MC"`; side-by-side, no shared DB.
- ✅ **Local install workflow** — `scripts/dev/install_local.sh`.
- ✅ **Fn rework foundation + Slice 1** — new gesture mode, mic-only capture, per-gesture source
  override, Fn→meeting wiring, ⌘⇧M + push-to-talk retired, dictation idle pill suppressed,
  auto-export to Finder default-on. Full test suite green; 4 new gesture unit tests pass.

## What's NEXT — remaining island slices

Target visuals: `docs/design/final-lookbook.html`. Direction spec: `docs/fork-product-model.md`
§"Interface direction: the island". Suggested order:

1. **Island idle + hover pill** (most visible gap). Right now the old dictation pill is suppressed
   (`AppFeatures.islandReplacesDictationPill = true`) and **nothing floats when idle** — only the
   menu-bar icon. Build the flat empty idle pill + 2-line hover ("Press **fn** to record" /
   small "Double-tap for calls · Click to open"). Reuse `KeylessPanel`/floating-panel tech.
2. **Recording lifecycle pill restyle** — currently reuses the existing meeting "sacred-geometry"
   pill (works, gives recording UI free). Lookbook wants: recording (one-line: red dot + waveform
   + timer + stop) → transcribing (spinner + progress) → done (✓ + Open/Export) → collapse to idle.
3. **Expanded island (click state)** — Spotlight-style search + Record + Mic/Mic+System toggle +
   recents + Settings/Library/Reveal-in-Finder chips. The fiddly bit: `KeylessPanel` must stay
   non-key when idle but become key on click so the search field accepts typing (focus handoff).
4. **Glass Settings + Library overlays** — summoned dark-vibrancy (`NSVisualEffectView`) panels
   reusing existing Settings/Library views.
5. **Settings cleanup** — drop the now-inert **push-to-talk** + **meeting-hotkey (⌘⇧M)** rows from
   the Settings UI (they still render but do nothing). See `plans/active/fn-rework.md` increment 5.
6. **Retire the main window** (the slim sidebar is interim).
7. **Transcript/summary layering** (separate track) — verbatim transcript + **Flag** pass (mark
   uncertainty, don't smooth); **Distill**/**Decide** as summary ops; **drop Polish**; stacked
   hotkeys (⌥1/2/3 for actions, nested 1/2/3 for variants).

## Tribal knowledge / gotchas (not obvious from code)

- **xcodebuild is BROKEN on this machine** (stale `DVTDownloads.framework`). NEVER use
  `scripts/dev/run_app.sh` or `BUILD_SYSTEM=xcodebuild`. Use `swift build` + `install_local.sh`
  (which uses `BUILD_SYSTEM=swiftpm`). Optional fix the user can run: `sudo xcodebuild -runFirstLaunch`.
- **Install/test loop:** edit → `scripts/dev/install_local.sh` (release build ~5–10 min, signs
  with the user's Apple Development cert, installs to `/Applications/MacParakeet-MC.app`) → relaunch
  `open "/Applications/MacParakeet-MC.app"`. Permissions persist across rebuilds (stable cert).
  Only the **user can live-test Fn timing** — build, install, hand off.
- **Quick compile check:** `swift build --target MacParakeet`. **Full suite:** `swift test`
  (~1–2 min). Note: `swift test … | tail` buffers — wait for the task-completion notification, don't
  poll the file.
- **Fn behavior now:** single tap = mic-only (no screen-recording prompt), double tap = mic+system;
  ~400 ms threshold wait on a single tap is intentional (disambiguating double-tap). Both route
  through the meeting pipeline → saved transcript → `.md` to `~/Documents/MacParakeet-MC/Meetings/`.
- **Gesture FSM is heavily edge-cased + unit-tested.** New mode = `singleAndDoubleTapToggle`
  (`HotkeyGestureController`) + `actsOnReleaseTap` (`HotkeyManager`) + `onToggleRecording`.
- **Guardrails (from upstream CLAUDE.md):** don't delete user data / meeting recovery artifacts;
  don't strip licensing plumbing as dead code; CLI external commands are a public contract.

## Authoritative references (read these to resume)

- `docs/fork-product-model.md` — **north star** (product model + island direction + all decisions).
- `plans/active/fn-rework.md` — Fn rework plan with per-increment status.
- `docs/design/final-lookbook.html` (+ `island-interface-mockup.html`, `color-options.html`) — the
  approved visual target.
- Auto-memory: `~/.claude/projects/-Users-mathewcleveland-macparakeet-MC/memory/` —
  `macparakeet-mc-fork.md`, `xcodebuild-broken-use-swiftpm.md`, `work-style-open-conversation.md`.

## Working style (user preferences)

- Prefers **open, exploratory conversation** over pure multiple-choice; thinks out loud.
- Holds a firm principle: **a transcript is never polished; only a summary can be.**
- Likes building in **installable slices** and testing the final flow personally.
