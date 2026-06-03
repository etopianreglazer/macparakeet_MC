# MacParakeet-MC — Fork Product Model

> Status: **ACTIVE**. This is the north star for this fork. Where it conflicts with the
> upstream `CLAUDE.md`/`spec/` framing of the product, **this document wins** for product
> shape and UX. (Architecture ADRs and "don't delete user data / licensing plumbing"
> rules still hold.)

## Why this fork exists

Upstream MacParakeet is a capable but broad app: dictation + file + YouTube + meetings +
Transforms + calendar + Discover. For this owner's actual use it carries weight that
doesn't earn its place. The fork keeps the engine, sheds the surface area, and re-themes.

Two goals: **make it feel effortless again** (lighter nav, fewer surfaces) and **make it
mine** (green, not coral).

## The owner's real workflow

Everything is **capture → transcript document → export**. Nothing pastes into other apps.

- **Face-to-face conversations** — laptop open, mic only.
- **Video calls / meetings** — mic + system audio.
- **Phone voice memos** — recorded on iPhone, AirDropped to Downloads, **imported** as a file.
- Occasionally **interviews from YouTube** — pulled in to analyze (kept, but a side-piece).
- **Not** dictation-as-paste (speak → text into the active app). Possible future use
  ("talking to myself to take notes"), not a today need.

The upstream split between "dictation" and "meeting recording" is artificial for this
owner — they are the *same intent* (record a conversation) with a different **audio source**.

## Capture model (the spine)

One key — **Fn** — two gestures, distinguished by audio source. Both produce a transcript
document in the Library. No push-to-talk.

| Gesture | Audio source | Pipeline | Result |
|---------|-------------|----------|--------|
| **Single tap Fn** | Mic only | recording → document | transcript in Library |
| **Double tap Fn** | Mic + system audio | recording → document | transcript in Library |
| **Import file** | AirDropped phone memo, any audio/video | file transcription | transcript in Library |
| **YouTube** (side-piece) | URL | file transcription | transcript in Library |

Consequences:
- **Single-tap is NOT the old paste-dictation.** It is mic-only recording-to-document
  (the meeting pipeline with system audio off).
- `⌘⇧M` (old meeting hotkey) **retires** — double-tap Fn replaces it.
- Push-to-talk (hold Fn) is **removed**.
- Paste-style dictation becomes a dormant/future opt-in, not a primary gesture.

## Transcript vs. summary — the layering principle

> **A transcript is never polished. A summary can be.**

- **Layer 1 — Transcript (verbatim, untouchable).** The only processing allowed is a
  **Flag** pass: mark inaudible / garbled / ambiguous / unretraceable spans *as such*,
  mirroring the `voice-memo-digest` skill's "label what you can't retrace" behavior.
  Flagging **preserves** doubt; polishing **hides** it. For analyzing team dynamics, the
  flagged uncertainty is signal.
- **Layer 2 — Summary / analysis (processing welcome).** Where **Distill** and **Decide**
  live. Summary operations are *supposed* to compress and reshape.

The Transforms engine should be **layer-aware**: transcript view offers only Flag; summary
view offers Distill / Decide. This resolves the "first-level or second-level doc?" ambiguity
— the layer decides what's appropriate.

### Transforms decisions
- **Distill** — keep (summary layer).
- **Decide** — keep (summary layer).
- **Polish** — **drop.** It was harmful at the transcript layer and redundant at the summary
  layer (Distill covers the good half). Replace its slot with the transcript-layer **Flag**.
- Transforms overall: treat as a **later pass**. Build Distill/Decide/Flag, then let real use
  reveal what else is actually wanted before adding more.

### Stacked hotkeys (idea, 2026-06)
Positional, game-style hotkeys that stay consistent across menu levels:
- On a transcript / processing surface: **⌥1 = Distill, ⌥2 = Decide, ⌥3 = Export** (mirrors the
  existing system-wide Transforms ⌥1/2/3).
- **Inside** a chosen action, reuse the bare number keys for the variant: e.g. ⌥1 Distill →
  **1** Tight / **2** Bullets / **3** Exec summary. Same finger positions, different layer.
This makes the processing actions muscle-memory fast and consistent everywhere.

## Navigation: 9 → 4

Old sidebar (9): Transcribe · Library · Dictations · Meetings · Transforms · Vocabulary ·
Feedback · Settings · Discover.

New spine (4): **Capture · Library · (Transforms?) · Settings.**

| Old item | Fate |
|----------|------|
| Transcribe | → **Capture** (front door; record + import + YouTube side-piece) |
| Library | **Keep** — unified history: recordings · imports · YouTube, via filter chips |
| Meetings | **Fold into Library** (redundant with the Meetings filter chip) |
| Dictations | **Fold into Library** (it's just history) |
| Transforms | **Demote** — config, not a daily destination → Settings (or a thin top-level if it earns it) |
| Vocabulary | **Demote** → Settings section |
| Feedback | **Demote** → Settings link / menu-bar item |
| Settings | **Keep** — absorbs Vocabulary, Transforms config, Feedback |
| Discover | **Cut** |

Nothing is *deleted* except Discover — lesser surfaces move into Settings/Library. The win is
visual weight removed, not function lost.

## Interface direction: the island (chosen 2026-06)

MacParakeet-MC is an **ambient app, not a windowed one**. Confirmed direction; mockups in
`docs/design/` (`island-interface-mockup.html`, `final-lookbook.html`).

- **Idle = the current app's flat, empty pill** at bottom-center — no dots, no green, no
  waveform. Reuse the existing idle island exactly.
- **Hover = ONE line**: ambient waveform + short hint "fn to record · 2× fn for calls · click
  to open". Tight copy, single row.
- **Click** = open the **enlarged island** (Spotlight-style search line + Record + Mic/Mic+System
  + recents + Settings/Library/Reveal-in-Finder chips).
- **One morphing pill, button changes meaning per state.** The island is a single Live-Activity-
  style surface that morphs through the capture lifecycle, then collapses back to idle:
  - **Recording** — red dot + green waveform + ticking timer + **Stop** (white rounded square, right).
  - **Transcribing** — spinner + "Transcribing…" + green progress bar + % (on-device, no button).
  - **Done** — green ✓ + title + "saved · N min" + **Open / Export**; auto-collapses to idle after a beat.
  No separate "play" control on the live pill (you're capturing, not playing). Playback/play lives
  in the Done state and the transcript view. Pause/resume mid-recording is a possible later add.
- **Auto-export transcripts to Finder** is a first-class setting ("it just works"): finished
  transcripts are written to `~/Documents/MacParakeet-MC/` so the user just opens the Finder file.
- **Settings and Library are summoned glass layers** (dark `NSVisualEffectView` vibrancy),
  expanding from the island Spotlight-style, dismissable. Not permanent window chrome.
- **Transcripts live as files in organized Finder folders** (`Documents/MacParakeet-MC/`:
  Transcripts / Meetings / Imports). The OS is the primary library browser; the in-app Library
  shrinks to a thin glass search overlay.
- **The windowed app (sidebar) retires.** The slimmed 4-item sidebar was an interim step.
- Visual language: dark vibrancy glass, Grass accent, SF type, generous rounding. "Mac-ier"
  than iPhone's Dynamic Island (wider, flatter, desktop-class), Action-Button-like intent.
- Feasibility: reuses existing non-activating floating-panel tech (`KeylessPanel`/idle pill/
  meeting pill). The one fiddly bit is focus handoff — the panel stays non-key when idle but
  becomes key on click so the search field accepts typing.

## Color

Coral → **green**, leaf/lush ("Ireland/Scotland" green, not neon lime). Centralized in
`Sources/MacParakeet/Views/Components/DesignSystem.swift` (`DesignSystem.Colors.accent` +
`accentLight` / `accentDark`). Candidates rendered for selection: **Lime / Leaf / Emerald**.
Watch the meeting pill's separate `sacredGlow` / `sacredStem` greens so they don't muddy
against a green accent.

## Sequencing

1. **Green reskin** — ✅ done. Grass accent in `DesignSystem.swift`; custom green sidebar rows.
2. **Nav slim (interim)** — ✅ done. Sidebar reduced to Capture/Library/Transforms/Settings.
   This is a stepping stone; the windowed nav is superseded by the island direction below.
3. **Fn rework** — single-tap Fn = mic-only recording → document; double-tap = mic+system;
   retire `⌘⇧M`; drop push-to-talk. **Foundational for the island — do next.**
4. **Island states** — idle → hover → click, reusing the existing floating-panel tech.
5. **Wire the island** — record controls, recents, Reveal-in-Finder, auto-save transcripts to
   organized Finder folders.
6. **Transcript/summary layering** — verbatim transcript + Flag pass; Distill/Decide as summary
   actions in the transcript/processing surface.
7. **Glass Settings + Library overlays** — summoned vibrancy panels reusing existing views.
8. **Retire the main window.**

## Locked guardrails (from upstream CLAUDE.md — still apply)

- Don't delete user data (meeting session folders, recovery artifacts).
- Don't strip licensing plumbing (`EntitlementsService`, LemonSqueezy) as "dead code."
- CLI external commands are a public contract.
- ADRs in `spec/adr/` remain the architecture source of truth.
