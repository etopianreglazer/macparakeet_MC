# Plan: Splay — two-surface rebuild (island indicator + card)

> Status: **HISTORICAL** — carried out; the island + card are the app as it stands. Written 2026-08-07.
> This supersedes `island-only-lean-roadmap.md`, whose "Library/Settings/detail are
> substates *inside* the island" model is **rejected** by the final design. The island is an
> **indicator only**; everything else is a **card**.

## North star

The authoritative design is the handoff in **`docs/design/splay-island-handoff/`**
(`README.md` = final intent + tokens; `Splay Island Fiber.dc.html` = interactive prototype).
Fidelity is **high** — colours, sizes, radii, timings, and copy in that README are final. Match them.

Splay is a **one-gesture local recorder**: **double-tap fn** (or click the on-screen **fn** chip),
it records anything audible (your voice and/or system audio), transcribes on-device, and writes a
Markdown file. (The handoff proposed ⌥Space; the user found it unreadable and prefers fn — see
Decisions.) The UI is exactly **two surfaces and no third**:

1. **The island** — a flat-black pill hanging from the notch. **Indicator only.** It never asks a
   question, never holds a control beyond one or two glyphs. Its identity is the **light behind it**
   (ambient bloom + fiber stripe) that breathes red while recording. Nothing is drawn on its face.
2. **The card** — a centred modal over a dimmed scrim. Carries *everything else*: first run,
   permissions, confirmations, alerts, recent recordings, settings.

There is **no** dropdown off the island, **no** menu-bar popover panel, **no** settings window,
**no** in-island router.

## Decisions captured (2026-08-07)

- **Dictation model — file-first, plus an optional paste handoff (synthesis).** The design cuts
  paste-into-app; the user still wants it available. Resolution: the **file is *always* written**
  (store of record, never clipboard-only), and the *destination* governs the **post-save handoff**.
  "Paste into current app" is **added** to the design's four destinations. Accessibility permission
  is requested **only if** the paste handoff is enabled — otherwise, as the design says, never.
- **Storage — iCloud Drive.** The default folder destination is
  `~/Library/Mobile Documents/com~apple~CloudDocs/Splay/` (shows as **Splay** in iCloud Drive) so a
  future iPhone app reads/writes the same files with no backend. Fall back to `~/Splay` if iCloud is
  unavailable. No Supabase/Postgres — raw voice notes are just files.
- **iPhone — later phase, not blocking.** Same iCloud folder, on-device transcription. See Phase 7.
- **Trigger — keep fn, drop ⌥Space (2026-08-07 live-test).** The ⌥Space glyph read poorly; the user
  prefers double-tapping fn. Hardware fn keeps single = mic / double = mic+system. The island's ready
  state shows a clickable **fn** chip (system font) — the one deliberate on-screen affordance, since a
  fully headless island "makes you wonder why there's any interface apart from the colour." Clicking
  the chip records (mic). The old lavender notch-cue seam/glints are retired (the bloom + fiber stripe
  are the light now). Hover uses hysteresis: reaching the notch activates ready; it stays active while
  the cursor is on the tile.

## Keep / cut / build (grounded in the current tree)

**Keep — the hard-won plumbing:**
- STT transcribe path (Parakeet via FluidAudio) and `STTRuntime`/`STTScheduler`.
- Mic capture (AVAudioEngine) + system-audio capture (ScreenCaptureKit).
- The record → transcribe → write-`.md` pipeline (`MeetingRecordingFlowCoordinator`,
  `MeetingRecordingService`, `AutoSaveService`) — re-framed from "meeting" to just "a recording".
- The **recording-health watchdog** (10s stall → explicit error, keeps partial audio). Matches the
  design's "failure keeps the audio, so nothing is ever recorded twice."
- The AppKit **panel host + click monitors + morph mechanics** in `IslandController` (the genuinely
  painful part — copy-and-adjust, do not re-hand-roll).
- `IslandPlacement` resolver (notch vs. below-menu-bar), adjusted to the design's **top-flush**
  geometry.
- Splay assets: `SplayMark.swift`, app icon, `splay-three-mark.png`. (Verify the mark paths match
  the handoff's `viewBox="180 180 640 660"` three-path glyph.)
- The paste-into-app mechanism from `DictationFlowCoordinator` — repurposed as the paste destination.

**Cut / demote — contradicts the design (~900 lines of island router):**
- `IslandRoute.swift` (the 6-route router), `IslandRoutePages.swift` (in-island
  Library/Settings/Setup/Transcript pages), `ExpandedIslandView.swift` (the Spotlight card with
  search + Record + source toggle + chips). The island does not expand into a control surface.
- The `.expanded` `IslandVisual` and its expansion machinery in `IslandView`/`IslandController`.
- The **fn single/double-tap** trigger and its hover-hint copy.
- Face content on the recording pill (dot + waveform + timer + stop button) — the face stays black;
  the light does the talking.

**Build new:**
- **The light** — ambient bloom (two blurred radial gradients behind the pill) + **fiber stripe**
  (a 2px opaque line tracing the pill's silhouette, sides + bottom only), per-state colours, and the
  breathing animations (`voice`, `rimlive`, `rimsoft`, `latent`, `breathe`). This is the entire
  visual identity and **does not exist yet**.
- The **9 indicator states** with correct geometry (top edge flush to screen, bottom corners only,
  180×32 camera dead zone, left/right clusters).
- The **card system** — one reusable centred-modal component reused ~13 ways.
- The **destinations** — Folder (default, iCloud) / Obsidian / Claude / Clipboard / Paste-into-app.
- The **⌥Space** global hotkey (hold to start / press to stop).

## Phases (each phase installs and is live-testable)

> Build order front-loads the signature visual (Phase 1) and the biggest new surface (Phase 3).
> Each phase ends with a signed `/Applications/Splay.app` for the user to live-test; nothing is
> committed until the user accepts that slice.

### Phase 0 — Foundations (doc + tokens, no behaviour change)
- Port the design tokens into `DesignSystem` (island surface `#0B0813`, brand `#4A38A6`, accent
  `#A99BF5`, danger `#B3352F`/`#F0837A`, warning `#F4BE59`, card surface `rgba(252,251,255,.98)`;
  radii 9/11/12/13/14/16, spacing 6/7/8/11/14/16/20/26; Inter Tight + Instrument Serif wordmark).
- Verify `SplayMark` matches the handoff glyph paths.
- Mark `island-only-lean-roadmap.md` HISTORICAL, pointing here.
- **Accept:** builds; tokens resolve; no visible change yet.

### Phase 1 — The light + island as pure indicator (the signature)
- Rewrite `IslandView` to render a flat-black **top-flush** pill with the **ambient bloom + fiber
  stripe** behind it and the breathing animations, across the lifecycle states
  (dormant/ready/recording/transcribing/done/copied/warning/failed/dropped), driven by the existing
  `MeetingRecordingPillViewModel`. **No content on the face** beyond the mark/glyph the design
  specifies.
- Geometry + bloom sizes + state colours per the handoff tables.
- **Bridge:** leave click-to-open reachable (temporarily opening the current expanded view) so
  Settings/Library stay accessible until Phase 3 replaces them with cards.
- **Accept:** the light breathes red on record and cross-fades between states; pill geometry
  animates; nothing is drawn on the face; the camera housing is never covered.

### Phase 2 — Trigger: keep fn + on-screen fn chip (⌥Space dropped)
- Keep hardware fn (single = mic, double = mic+system). Add the clickable **fn** chip in the ready
  state (done in the Phase-1.1 tuning). ⌥Space is not used.
- File-drop on the island → straight to transcribing (design behaviour) — still to wire.
- **Accept:** fn records; the on-screen fn chip records; file-drop transcribes.

### Phase 3 — The card system (the second surface)  — **IMPLEMENTED (awaiting live-test) 2026-08-08**
- Build one reusable `SplayCard` (scrim `rgba(36,31,56,.2)` + blur; card
  `rgba(252,251,255,.98)`, radius 16; glyph tile; title; body; optional body block; button row;
  optional dots) with the `riseC` entry.
- Implement the five **body blocks**: destination list, permission row, key caps, recording list,
  toggle list.
- Route the menu-bar item and island affordances to cards. Retire `IslandRoute`/`IslandRoutePages`/
  `ExpandedIslandView`.
- **Accept:** Recent-recordings and Settings cards render faithfully; Esc/click-away dismisses; the
  island no longer expands into a control surface.

**What landed (uncommitted, build-clean, signed install pending live-test):**
- New `Views/Island/SplayCard.swift` — reusable card shell (`SplayCardView` + `SplayCardChrome`) and
  all **five body blocks** (`SplayDestinationList`, `SplayPermissionRow`, `SplayKeyCaps`,
  `SplayRecordingList`, `SplayToggleList` + `SplaySwitch`), plus `SplayCardPalette` (fixed sRGB
  tokens). `riseC` entry on the card.
- New `Views/Island/SplayCardController.swift` — full-screen, key-capable borderless panel
  (level `popUpMenu+1`, above the island) rendering scrim (behind-window `NSVisualEffectView` blur +
  violet tint) + centred card. Esc (local key monitor + `.onExitCommand`) and click-away (scrim tap +
  armed `windowDidResignKey`) dismiss.
- New `Views/Island/SplayCards.swift` — **UPDATED (thread 4, `9166348c`):** the two one-shot cards were
  merged into one tabbed `SplayMenuCard` (Recents · Settings · **About**), reusing `SplayCardView` via a
  pluggable `header` (the tab strip). **Recents** (last 5 from the library VM, "Open folder"), **Settings**
  (three live toggles → `meetingAudioSourceMode`, `launchAtLogin`, persisted `splay.playSoundOnStart`;
  "Quit Splay"), **About** (version + GPL-3.0 attribution + "Check for Updates" via the Sparkle updater).
  `SplayCardController.refit` resizes the floating panel on tab switch.
- **Retired the router:** deleted `ExpandedIslandView.swift`, `IslandRoute.swift`,
  `IslandRoutePages.swift`. `IslandView` is now a pure indicator; `IslandController` lost all
  expand/collapse/route/resize machinery and gained `onOpenCard`. `IslandLayout` lost the `.expanded`
  visual + route sizing; `IslandChromeModel` lost `isExpanded`; `SplayGlow.resolve` dropped `expanded`.
- **Wiring:** menu-bar "Open Splay" → recents card; all Settings menu items → settings card; island
  idle/done click → recents card; app-reopen → recents card. A finished recording no longer force-opens
  any surface (the island lights `done`; the file is waiting). The Slice-4 overlay path
  (`IslandOverlayController`, `AppWindowCoordinator.openSettingsOverlay/openLibraryOverlay`) is now
  unreferenced but left in place for Phase 6 to delete.

**Deferred to final review (per user):** the glow "nudges" (drift visibility / brightness / extend
sway to ready) from the 2026-08-08 glow round — dial in `SplayGlowTuning` at the very end.

**Known Phase-3 gaps (by design, later phases):** the recents card shows/reveals the *current* save
folder (not the iCloud `~/Splay` folder — Phase 4); the "Play a sound when it starts" toggle persists
but does not yet gate playback (Phase 4); first-run + alert cards are built (shell + blocks exist) but
not yet wired (Phase 5).

### Phase 4 — File-first storage + destinations (+ paste)
- Every recording **always** writes `Splay/<date-title>.md` to the iCloud folder, with paired audio
  in `Splay/Audio/<date-title>.m4a` (fallback `~/Splay` if iCloud unavailable). Raw transcript
  format with `[mic]`/`[system]` tags + timestamps (per the prototype's `MD` sample) — **verbatim,
  never summarised**.
- Destination handoff after save: **Folder** (default) / **Obsidian** / **Claude** / **Clipboard** /
  **Paste into current app**. Accessibility requested only when paste is enabled.
- **Accept:** every recording produces a `.md` (+ audio) in iCloud Splay; the chosen handoff fires;
  nothing is clipboard-only unless picked; paste works when enabled.

### Phase 5 — First-run + permission/repair cards
- Wire the 5 first-run cards (welcome → microphone → system audio → destination → shortcut) with
  dots, plus the denied-mic, denied-system-audio, and model-repair alert cards.
- **One local model** (Parakeet v3 multilingual), **no engine picker**; the repair card handles a
  missing/incomplete model.
- **Accept:** a fresh launch walks the five cards; denied-permission and model-repair cards appear
  and route to System Settings / repair correctly.

### Phase 6 — Retire old surfaces + execute the cut list
- Remove the main window and remaining router files once cards fully cover their functions.
- Remove from user-facing surfaces (hide first, delete after verification): meeting/dictation split
  framing, Transforms, Discover, calendar auto-start, prompts, chat, diarization, stats, provider
  config, engine picker, YouTube. **Respect CLAUDE.md's retained-licensing-plumbing rule** — do not
  delete entitlement/telemetry code without explicit owner sign-off; hide it.
- **Accept:** only the two surfaces exist; no main window; cut features gone from the UI; app builds
  and the core ⌥Space → file flow works end to end.

### Phase 7 (later, non-blocking) — iPhone companion
- New iOS target; extract a minimal shared core (capture/naming + storage/destination logic).
  On-device transcription via WhisperKit (confirm; research Parakeet/FluidAudio iOS support). Same
  iCloud `Splay/` folder — sync is free via iCloud.
- **Accept:** iPhone records → transcribes locally → writes to the same iCloud folder the Mac reads.

## Folder layout (Phase 4)

> **Revision 2026-08-10 (user):** audio goes in a **`Recordings/` subfolder** next to the transcripts,
> not side-by-side. A focused first step landed ahead of the full Phase-4 iCloud relocation:
> `AutoSaveService.saveIfEnabled` now copies a meeting's `.m4a` (the mixed playback file at
> `transcription.filePath`) into `<save-folder>/Recordings/<same-basename>.m4a` after writing the `.md`
> (best-effort, idempotent; tests in `AutoSaveServiceTests`). This applies to the *current* auto-save
> bookmark folder — the iCloud `Splay/` relocation + date-title naming below is still unbuilt. Existing
> recordings are not retro-paired yet (a backfill would copy each DB record's `filePath` into `Recordings/`).

**Superseded flat layout (user preference 2026-08-07):** everything drops into a single `Splay/`
folder so it sorts by date / most-recent in Finder. The `.md` and its paired `.m4a` share a
date-prefixed basename and sit side by side — no subfolders.

```
Splay/                      (in iCloud Drive; ~/Splay fallback)
├── 2026-08-07 14-32 Design review.md      (verbatim transcript, [mic]/[system] tags)
├── 2026-08-07 14-32 Design review.m4a     (paired basename, same folder)
├── 2026-08-07 08-31 Thinking out loud.md
└── 2026-08-07 08-31 Thinking out loud.m4a
```
Flat, greppable, portable, sorts newest-first by name. A summary (if ever added) is a **separate**
file — never baked into the raw transcript. Enforces the user's "raw footage, not edited footage / a
transcript is never polished" principle at the filesystem level.

## Invariants (do not break)
- Two surfaces only; the island never becomes a control surface or opens a second window.
- The file is always written; nothing is ever clipboard-only unless the user explicitly picks it.
- A capture failure is an **error that keeps the audio**, never a success-like completion.
- Transcripts are **verbatim**; only a summary may be edited/condensed.
- On-device by default; the only network is the one-time model fetch/repair (and user-chosen
  handoffs like "open in Claude").
- Respect meeting-recovery artifacts and retained licensing plumbing per CLAUDE.md.

## Out of scope (for this rebuild)
- Cloud/Supabase storage, accounts, sharing.
- Any summarisation/LLM processing of the transcript beyond the optional Claude handoff.
- The features in the cut list above.
