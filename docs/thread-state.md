# Thread State — Splay (modified MacParakeet-MC fork)

> **What this is:** a handover of *where we left things*, written for the next session to
> resume cold. It is **not** a briefing (the "what's planned" lives in
> `docs/fork-product-model.md`) and **not** a build plan (`plans/active/fn-rework.md`). This is
> the "you are here" pin.
>
> **Last updated:** 2026-08-08 — **Phase 3 (cards) + seven-accent theming + breathing motion, and this
> whole two-surface rebuild WIP, COMMITTED to `main`** (still local — do **not** push). Read the next
> section first. Everything below the "CURRENT DIRECTION" section describes the *previous*
> island-as-router approach, now **superseded** *and deleted* (the router files are gone). Kept for the
> panel mechanics/gotchas, not as the product direction.
>
> **Next thread starts with a decision (not yet acted on):** whether to adopt **DynamicNotchKit**
> (MrKai77, MIT — https://github.com/MrKai77/DynamicNotchKit) as the island's presentation substrate
> (it owns the notch window / insets / non-notch floating fallback / compact↔expanded morph we
> hand-rolled) and layer a `SplayActivity` state-machine on top — vs. keeping our controller and cribbing
> technique from **boring.notch** (GPL-3.0). Recommended move: a throwaway spike porting idle→ready→
> recording onto DynamicNotchKit to see if it hosts our below-windows glow panel + record-dot
> hit-testing. See the research summary in the session that added this note.

---

## ⭐ CURRENT DIRECTION (2026-08-07) — two-surface rebuild

**The final design arrived and it changes the skeleton.** The authoritative design is now
`docs/design/splay-island-handoff/` (README = final intent + tokens; `Splay Island Fiber.dc.html`
= interactive prototype). The active plan is **`plans/active/splay-two-surface-rebuild.md`**.
`plans/active/island-only-lean-roadmap.md` is now **HISTORICAL** (its island-as-router model is
rejected).

**The model:** exactly **two surfaces**. ① the **island** = a flat-black pill hanging from the
notch, **indicator only** — its identity is the *light behind it* (ambient bloom + fiber stripe)
that breathes red while recording; nothing is drawn on its face beyond one/two glyphs. ② the
**card** = a centred modal over a dimmed scrim, carrying *everything else* (first run, permissions,
recents, settings, alerts). No in-island router, no dropdown, no settings window, no second window.
Trigger = **double-tap fn** + an on-screen clickable **fn** chip (⌥Space was dropped as unreadable,
2026-08-07). System audio is a persistent toggle.

**Decisions locked (2026-08-07):**
- File-first **and** keep paste: the file is *always* written; the *destination* is the post-save
  handoff (Folder / Obsidian / Claude / Clipboard / **Paste-into-app**). Accessibility only if paste on.
- Storage = **iCloud Drive** `Splay/` folder (`~Library/Mobile Documents/com~apple~CloudDocs/Splay`,
  `~/Splay` fallback). One flat folder, `.md` + paired `.m4a`, sorted by date. Enables a future
  iPhone app with no backend (Phase 7).
- Phase order: 1 light+indicator → 2 trigger (fn + on-screen fn chip) → 3 card system →
  4 storage+destinations → 5 first-run cards → 6 retire old surfaces + cut list → 7 (later) iPhone.

**Phase 1.1 tuning (2026-08-07 live-test feedback):** removed the leftover lavender notch-cue
seam/glints (the "bright bar" the user spotted); added hover hysteresis (`IslandLayout.hoverStayRect`
+ wider `notchRevealRect`) so reaching the notch activates ready and it stays active on the tile;
replaced the unreadable `⌥␣` with a clickable system-font **fn** chip (right cluster of the ready
pill, `SplayIslandIndicator.fnButton`) whose hit region is `IslandLayout.fnButtonRect` →
`tracker.onRecordClick` → `onRecord(.microphoneOnly)`. Ready pill widened 248→264 to seat the chip.

**Phase 1.2 tuning (2026-08-07, second live-test round):**
- **Desktop glow.** The big ambient bloom was moved OFF the pill panel onto its **own panel below app
  windows** so the light sprays onto the wallpaper instead of hovering over the user's work. New
  `SplayGlow.swift` (`SplayGlowView` + `SplayIslandState.resolve`); `IslandController` builds a
  `glowPanel` at `NSWindow.Level.normal - 1`, `ignoresMouseEvents`, `.canJoinAllSpaces/.stationary`,
  positioned to the idle frame (`installGlowPanel`/`positionGlowPanel`), re-ordered in
  `restoreAmbientVisibility`, torn down in `hide`. The pill keeps only a small local shadow-glow +
  the fiber stripe so it still reads as alive on top. `Breathe` + `SplayMotion.bloomIntensityScale`
  moved to `SplayIslandLight.swift` (shared by indicator + glow).
- **fn chip** shrunk (11→10.5pt, tighter padding) and made a **Capsule** to echo the island's rounding.
- **Mark** given more breathing room (face horizontal padding 6→14, clears the corner curve) + its own
  soft **breathing accent glow** (`.shadow` on the glyph).
- Build clean; signed install pending user live-test. **Key thing to verify:** open a window over the
  top of the screen and confirm the recording glow now sits *behind* it (on the desktop), while the
  pill + fiber stay visible on top.

**Phase 1.3 tuning (2026-08-07, third live-test round):**
- **Record dot replaces the fn chip.** Ready state now shows a simple Voice-Memos-style red circle
  (`SplayIslandIndicator.recordButton`, `SplayLight.recordRed` #FF5A52); `fnButtonRect` renamed
  `recordButtonRect`. ("fn" felt random.)
- **Smoother fades.** Island morph curve 0.32→**0.42s** `.smooth`; the desktop glow now cross-fades
  between states via `.id(state)` + `.transition(.opacity)` + `.animation(.easeInOut(0.42), value:)`
  (gradient colours don't interpolate, so it dissolves instead of snapping). `SplayIslandState` is
  now `Hashable`.
- **Glow ~25% stronger** — bumped `bloomL1`/`bloomL2` base opacities and the gradient `endFraction`
  (0.72/0.70 → 0.80/0.78). Deliberately mid-strength (user: "leaning closer to what we have now").

**Phase 1.4 tuning (2026-08-07, fourth live-test round):**
- **Record dot** shrunk 18→13pt to match the mark's visual weight.
- **Spawn/pop animation** — island morph curve is now a `.spring(response:0.3, damping:0.72)` (was a
  slow 0.42 fade, which felt like it "encompassed static elements"). The island pops in via
  `.scale(0.85, anchor:.top)+opacity`; cluster elements (mark/record dot/glyphs) scale-in via a
  shared `spawn` transition; the desktop glow bursts via `.scale(0.8)+opacity` on a spring.
- **Glow wraps AROUND the island (3D)** — instead of more downward spread, the bloom is now centred
  on the pill's vertical middle (`SplayAmbientBloom` offset = pillHeight/2, was the CSS downward
  bias) and widened sideways (`bloomL1`/`bloomL2` widths up ~15%); heights unchanged. Panel widened
  720→840 to contain the 740px recording bloom.
- **Fiber no-gap** — the rim light now traces the pill's exact edge (removed the −1/−3 outward inset
  + radius+1 that caused the visible gap in the screenshots).

### ▶ NEXT SESSION STARTS HERE (Phase 3 landed 2026-08-08)

**Latest session = Phase 3, the card system (the second surface).** Build-clean; a signed
`/Applications/Splay.app` install was produced for live-test. All uncommitted; do not push.

- **What landed (see `plans/active/splay-two-surface-rebuild.md` → Phase 3 for the full list):**
  - **Three new files** in `Views/Island/`: `SplayCard.swift` (reusable `SplayCardView` shell +
    all five body blocks + `SplayCardPalette`), `SplayCardController.swift` (full-screen scrim panel,
    behind-window blur, Esc + click-away), `SplayCards.swift` (the two wired cards).
  - **Two cards wired to real data:** **Recent recordings** (last 5 from `TranscriptionLibraryViewModel`,
    "Open folder" reveals the current save folder) and **Settings** (three live toggles + Quit).
  - **Router retired / deleted:** `ExpandedIslandView.swift`, `IslandRoute.swift`,
    `IslandRoutePages.swift` are gone. `IslandView` is now a pure indicator; `IslandController` lost all
    expand/collapse/route/resize code and gained a single `onOpenCard` callback. The island **never
    expands into a control surface** anymore.
  - **Entry points → cards:** menu-bar "Open Splay" and app-reopen → recents card; every Settings
    menu item → settings card; island idle/done click → recents card. A finished recording no longer
    force-opens a surface (island lights `done`, file is waiting).

- **To verify live (hand-off checklist):** open the recents card (click the idle island, or menu-bar
  "Open Splay") and the settings card (menu-bar "Settings…"); confirm both render faithfully vs
  `docs/design/splay-island-handoff/` (scrim dim + blur, card shell, list/toggles); Esc dismisses;
  clicking the scrim outside the card dismisses; toggling "Record system audio too" / "Launch at login"
  sticks; the island itself still records/transcribes and no longer grows into a card.

- **Polish round after first live-test (2026-08-08b):**
  - **Card is no longer a modal.** Dropped the full-screen scrim + backdrop blur; the card is now a
    small **floating window** centred on screen (panel sized to card + a 44pt shadow/dismiss margin),
    nothing dimmed or locked. Dismiss via Esc, Done/Close, a click in the margin, or a click outside
    the panel (armed `resignKey`). See `SplayCardFloat` in `SplayCardController.swift`.
  - **Feedback feel on card controls.** Buttons (`SplayCardButton` + `SplayPressStyle`: hover
    lift/brighten + press dip + pointer cursor), the switch (hover scale/brighten + pointer), and
    destination rows (hover highlight + pointer) all now "answer" to hover/press. Shared pointer toggle
    = `SplayHoverCursor`.
  - **Pill morph fixed (was "static").** Root cause: `SplayIslandIndicator.body` swapped between an
    `if/else` (animated `TimelineView` vs static pill), which breaks SwiftUI geometry interpolation → the
    width/radius/colour snapped. Now **one stable render path** (a single `TimelineView(.animation(paused:
    !animated))` — paused when idle so the always-on island still costs nothing), so the pill glides
    between states. Parent morph spring relaxed 0.26→0.34 response.

- **Colour palette — DONE (2026-08-08c).** User provided `SevenAccentsColorVariations.zip` (Claude
  design export; canonical file preserved at `docs/design/splay-accents/Wind Palette Export.dc.html`).
  Seven accents — Ember/Marine/Amber/**Iris**/Fern/Rose/Coral — each with accent / hover / `accent-dark`
  (bright-on-dark) / ground gradient. **Iris (`#4A38A6`, bright `#A99BF2`) is the current lavender** and
  the default. Implemented:
  - New `Views/Island/SplayTheme.swift` — `SplayAccent` (the 7 presets + hex→Color) and
    `@MainActor @Observable SplayTheme.shared` (persists `splay.accent` to UserDefaults). Reading
    `SplayTheme.shared.accent` in any SwiftUI body recolours **live**.
  - **Only BRAND surfaces are themed:** the island's dormant/ready/transcribing bloom+fiber+mark, the
    transcribing spinner, the done "folder" button, and the card brand (buttons, glyph tile, toggle-on,
    selection, list dots). **Status colours stay semantic** (recording red, done green, warning amber) —
    per the export's `--state-*` "never themed" note, and to protect the tuned recording glow.
  - **Picker:** a 7-swatch `SplayAccentPicker` row in the Settings card (with an "Accent" label); pick →
    island + open card recolour together, persisted.

- **Motion — DONE (2026-08-08c), per "breathing" direction:**
  - **Card breathes in/out.** Replaced the rise-from-bottom (`riseC`) with a centred scale: grows from
    0.86 → settles with a soft spring overshoot (`response 0.42, damping 0.66`), and **contracts + fades
    on dismiss** (panel torn down after the exit). Driven by `SplayCardPresentation` in
    `SplayCardController`; no Y translation — it grows "out of itself".
  - **Idle island holds open with the card.** `IslandChromeModel.heldOpen` + `IslandController.setHeldOpen`;
    presenting a card sets it (island morphs to ready and stays), dismissing releases it (both close
    together). Wired via `SplayCardController.onDismiss` → `setHeldOpen(false)`.
  - Pill morph identity fix + spring 0.34 from the previous round remain.

- **Coral accent tuned + kept (2026-08-08c).** User: the export's coral (`#D8583C`) read as plain orange;
  retuned Coral to a vibrant Living-Coral (`#FB5E4D` / hover `#FF7263` / bright `#FF9A8C`) in
  `SplayTheme.swift`. User verdict: "Love the coral. That's a keeper."

- **Research done — reuse over rebuild (2026-08-08c).** Looked for an existing "Dynamic-Island element."
  Findings: **DynamicNotchKit** (MIT, macOS 13+, SwiftUI, ~446★) is the one real *library* — it owns the
  notch window / insets / non-notch floating fallback / compact↔expanded morph; MIT is fine in our
  GPL-3.0 tree. **boring.notch** (GPL-3.0) is a full app but a good technique reference (Core Animation
  transitions, non-intrusive event handling). Atoll / Notchy / SuperIsland / DynamicIsland_Mac are apps,
  reference-only. Decision deferred to next thread (see top note).

- **Glow nudges = deferred to final review (per user):** the three `SplayGlowTuning` one-liners (drift
  visibility, brightness, extend sway to ready) are intentionally untouched this session; dial them at
  the very end.

- **Then:** Phase 4 — file-first storage + destinations (iCloud `~/Splay`, always-write `.md` + paired
  `.m4a`, destination handoff incl. paste). The recents card's folder + the persisted
  `splay.playSoundOnStart` toggle get their real behaviour there. Phase 5 wires the first-run + alert
  cards (the shell + destination/permission/key-cap blocks already exist). Phase 6 deletes the now-unused
  Slice-4 overlay path (`IslandOverlayController`, `AppWindowCoordinator.openSettingsOverlay/…`).

---

#### Earlier this day — the island-feedback + glow-motion round

- **Done & user-accepted this session (all live-tested, verdict "looking good"):**
  - **Widths de-wobbled.** Was 6 near-identical pill widths; now 3 — dormant 206, ready 248, and a
    single active max **280** (`SplayGeometry.size` + its twin `IslandLayout.pillSize`). Recording
    sits at the max; no width change across recording→transcribing→done. `SplayGeometry.maxWidth`.
  - **Mark/glyphs recolor per state** — `markColor = palette.fiber` (recording coral, done green, …)
    in `SplayIslandIndicator`. Done state cut to **one** "folder" icon (two buttons were vanishing
    behind the notch dead-zone at 280 width).
  - **Hover resize fixed** — `panel.acceptsMouseMovedEvents = true` in `IslandController.show()`. The
    resting nub now grows on hover; before, hover-enter lived entirely in `mouseMoved`, which an
    NSPanel doesn't deliver unless this flag is set. (Reusable gotcha.)
  - **Transitions tightened** — `IslandView.motion` spring 0.26/0.82; `spawn` scale 0.8.

- **THE BIG ONE — the glow is now a "light-vector" model, NOT a pulse** (settled after ~5 iterations):
  One soft, **dim** (peak 0.20), **contained** (footprint 490), **very-blurred** (90) light whose
  *direction* slowly sways on an organic Lissajous path. There is **no visible moving source** — only
  the island's own lighting shifts. The user's reference: **Philips Ambilight** bias light (soft,
  enhancing, not flashy). Earlier failed framings (kept here so we don't relitigate): a brightness
  *pulse* (too heartbeat-y), *visible orbiting blobs* (don't want to see the source), a *big field
  pouring outward* (must stay concentrated at the island).
  - **All tunables live in one block: `SplayGlowTuning`** (top of `SplayIslandLight.swift`). Values
    were dialed by the user in a live HTML slider tuner, then ported. Current: footprint 490,
    blurL1 90 / blurL2 63, peak 0.20, sway 15, speed 0.20, swirl 2.1, haloRadius 26, haloOpacity 0.64,
    rimOpacity 0.40.
  - `SplayMotion.lightVector(t)` returns the sway offset (replaced the removed `bloomIntensityScale`).
    Both bloom layers (`SplayAmbientBloom.sway`) **and** the pill's own halo lean by the same vector,
    so the light moves as one body. The pill halo uses `palette.bloomHue` (opaque) at `haloOpacity`,
    leaning by `sway*0.16` — it carries most of the *visible* light because the wide desktop bloom
    (0.20, on the below-windows glow panel) is faint and often occluded by a window.
  - Only **recording / transcribing / dropped** sway; **dormant idle is untouched** (accepted).
  - Glow panel widened to `IslandLayout.glowPanelWidth` = 1400 (room for the soft wash to fade).

- **Open nudges the user flagged for next time (all one-liners in `SplayGlowTuning`):**
  1. Is the drift **visible enough** live? sway 15 is subtle; bump `sway` and/or the halo lean factor
     (hard-coded `0.16` in `SplayIslandIndicator.pill`).
  2. **Brightness** — SwiftUI blur reads dimmer than the CSS tuner; lift `peak` (0.20) / `haloOpacity`
     (0.64) if too faint in situ.
  3. Optionally extend the light-vector drift to the **ready/hover** state (only active states sway now).

- **Working style that clicked (see auto-memory `visual-tuning-with-live-tuner`):** for subjective
  visual params, build an **inline HTML slider tuner** (`show_widget`, faithful to the SwiftUI params,
  with an Apply→`sendPrompt` button) and let the user dial it live — then port the numbers. This beat
  the ~8-min build→install→eyeball loop by a mile for the glow work.

- **State of tree:** builds clean (`swift build` green); `/Applications/Splay.app` is the installed
  light-vector build. **Everything uncommitted** (many modified + new island files). Do NOT commit/push
  without the user asking.

- **Then (still pending from before):** Phase 3 — the **card system** (centred modal for
  recents/settings/first-run/permissions), retiring the temporary routed-pill "bridge" that still
  opens on pill-body click.

**Phase 1 status (in progress):** rebuilt the island as a pure indicator with the light.
- New files: `Views/Island/SplayIslandLight.swift` (palette/geometry/bloom/fiber/mark from the
  handoff) and `Views/Island/SplayIslandIndicator.swift` (the 9 states + single TimelineView driving
  bloom breath / fiber pulse / mark; recording bloom blends live `micLevel`/`systemLevel` with the
  design's irregular `voice` beat).
- `IslandView.swift`: lifecycle states now render `SplayIslandIndicator`; the old
  face content (dot/waveform/timer/stop) + decorative helpers were deleted; `.expanded` keeps the old
  routed card **only as a temporary bridge** (retired in Phase 3). `IslandLayout` pill sizes updated
  to the handoff geometry so the AppKit tracker hit-rects still match the drawn pill; panel widened
  to 720 to contain the 640px recording bloom.
- **Verified only that `swift build` passes.** A signed `/Applications/Splay.app` release build was
  kicked off for live test; **not yet user-verified.** Do NOT claim the visual is confirmed until the
  user looks at it. Things to eyeball first: bloom vertical position relative to the notch/menu bar,
  fiber-stripe crispness, dormant faintness, recording red breathing with the voice.
- Bridge still active this phase: clicking the pill opens the old routed card so Settings/Library
  stay reachable; fn still records; the recording pill's right ~38px is still a hidden stop zone.

---

## TL;DR — where we are right now (⚠️ describes the SUPERSEDED router approach — see above)

### Current verification checkpoint — 2026-08-06

#### Latest notch companion proof — supersedes earlier notch placement notes

- The installed Splay notch rest now uses two panels: a completely inert
  status-bar-level camera-housing anchor and a separate popup-level,
  `hidesOnDeactivate=false` companion. The companion deliberately starts at
  `screen.frame.maxY` (not `visibleFrame.maxY`) and overlaps only its central
  island width in the menu-bar band. Its actual internal-display WindowServer
  frame is `X=604, Y=0, W=520, H=460` for `screen={{0, 0}, {1728, 1117}}`, at
  level 101; its top is physically the display top.
- The temporary magenta AppKit composition probe was removed. The companion now
  renders a low-opacity lavender halo, 128×4pt seam, and two slow deterministic
  glints. The clean-launch screenshot visibly confirms that cue immediately
  below the menu bar/housing, instead of the former detached 32pt-lower pill.
  Cue decoration and the hardware anchor return `nil` from hit testing / ignore
  mouse events. Expanded hit testing is constrained to the actual route-sized
  black card; transparent companion pixels do not consume menu/status clicks.
- The hover-only reveal zone is 180×56pt and flush to that seam. Click targets
  remain narrow and are aligned to the zero-inset notch visual. On route resize,
  the long-lived companion keeps its top at `screen.frame.maxY`, so Home,
  Library, Settings, Setup, and detail grow downward from the physical edge.
  Transparent pixels remain pass-through; the app restores the existing
  non-key companion after accessory-policy hiding/Space transitions.
- Verification: `swift test --filter IslandPlacementTests` passed 2/2;
  `/Applications/Splay.app` was clean-launched through LaunchServices as PID
  42781, was still alive after 57 seconds, and WindowServer reported its
  companion on screen at the physical top; the screenshot is
  `/private/tmp/splay-physical-top-final-review-2.png`;
  `codesign --verify --deep --strict` passed; installed
  `NSPrefersDisplaySafeAreaCompatibilityMode=false`. No commit or push.

- **Notch placement implementation:** `Automatic` now resolves through public
  `NSScreen.safeAreaInsets.top`: a built-in notched screen uses the Splay notch
  rest position and every notchless/external screen uses the below-menu-bar
  fallback. Settings persistently exposes Automatic, Notch and Below menu bar;
  an unavailable manual Notch choice safely falls back. The notch idle surface
  is lifted eight points into the safe area and leaves a small violet status
  dot plus a 30pt hit target below the cut-out. Deterministic geometry tests
  pass. The signed `/Applications/Splay.app` release build was installed and
  relaunched successfully; process stability was confirmed. Manual physical
  notch/route click review remains the final human acceptance step.

- **Notch hover correction:** the idle click target remains narrow, but the
  AppKit tracking view now has a separate 180×56pt central hover-only approach
  rect below the physical top edge when Notch resolves. Entering it expands the
  same panel without a click; it does not broaden click capture or cover menu
  extras. The current signed installed executable hash matches `dist/Splay.app`
  and is running as `/Applications/Splay.app/Contents/MacOS/Splay`.

- **Splay rebrand installed and launched.** The supplied full Splay icon is the packaged app icon;
  the supplied three-splay mark appears in compact island idle/setup/empty states and the menu bar.
  Island primary/selection/readiness accents now share the restrained lavender/deep-violet Splay
  palette over near-black surfaces; error and warning colors remain semantic red/amber. The app
  bundle displays/executed as `Splay`, but deliberately retains `com.macparakeet.mc` and the
  `MacParakeet-MC` data namespace to preserve existing recordings, settings, and privacy grants.
  `/Applications/Splay.app` deep signature verification and five-second launch stability passed.
  The prior `/Applications/MacParakeet-MC.app` was left untouched. See `docs/BRANDING.md`.

- Island Library and Settings have been replaced locally with purpose-built compact dark pages.
  Library is a single-column saved-recordings list (search, title, date/duration, detail route) and
  excludes remote-video records/categories. Settings now contains only source selection, permission
  status/retry/system-settings actions, plus a small Advanced disclosure for launch/menu-bar
  behavior. Neither page embeds the window-first card/grid views. Release build is installed for
  review; no commit/push.
- Spatial polish is installed too: `IslandLayout.contentInset` is the shared 16pt route inset and
  the adaptive AppKit stage includes the 32pt notch offset plus a 12pt bottom buffer. This prevents
  Home, Library, Settings, and detail controls from clipping or sitting against the rounded edge;
  compact rows/actions maintain 32–46pt minimum hit heights.
- Native motion pass is installed: router mutations, the long-lived panel's anchored frame, and
  route-content crossfades share a restrained 0.32s smooth/ease transition. Reduce Motion uses
  immediate state changes. Automated route-click visual confirmation remains blocked by macOS
  routing synthetic clicks to the app behind the floating panel; the Home reopen morph is visible.
- Setup is now an in-island route, not an old Settings tab. It presents the recommended multilingual
  local Parakeet model (with English-only alternative, quality/speed/size tradeoff), reflects cache
  state, drives the existing warm-up/download/retry service with progress and cancellation, checks
  just the permissions required by the selected recording source, and exposes a final Record now
  action. The signed release build is installed; no commit/push.

- The installed app launches and reopens into the **single expanded island Home panel**, with no
  legacy main window observed. The idle pill is now placed below (not inside) the physical notch.
- A recording health loop polls the service once per second while actively recording. It checks
  engine mode, successful writer append time, in-memory written frames, and output-file byte
  snapshots. A stopped/stalled pipeline (10-second safe threshold) now ends in an explicit island
  error and finalizes partial audio only for recovery; it **does not** transcribe/publish a normal
  completion. Paused capture is explicitly exempt.
- `MeetingRecordingFlowStateMachineTests` passes 18/18, including the new invariant that a capture
  failure is an error rather than a completed transcription. Release build, bundle signature, and
  process launch all passed.
- Synthetic pointer automation can open Home through app reopen, but cannot yet provide a reliable
  Settings/Library click assertion on this desktop because `System Events` sends those coordinate
  clicks to the app behind the floating surface. The host was changed from `nonactivatingPanel` to
  a borderless key-capable panel specifically to eliminate that first-click forwarding path; user
  live verification remains required for the full click loop and a real microphone smoke recording.

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

**Unified-host progress:** Home, Library, and the existing full SettingsView now route inside the
long-lived island panel (build-verified). This is not yet the finished island-only product:
transcript detail/export/reveal and removal of obsolete overlay/window callbacks remain.

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
- **Island click delivery (the big one):** the host must be a borderless, key-capable panel—not a
  `nonactivatingPanel`, which can forward a first click to the app behind it. Idle interaction also
  uses an **`NSEvent` global/local monitor** (see `IslandController.installClickMonitors`). A `hitTest` that returns the **contentView itself** is
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
