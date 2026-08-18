# Splay — Launch Checklist ("r2launch")

> Status: **ACTIVE**. Written 2026-08-18 (thread 7d).
>
> This is the pre-publish gate: everything that must be true before Splay goes public
> on GitHub. The owner's shorthand for it is **"r2launch"** — recorded here because it
> had never been written down. The name comes from the upstream Cloudflare-**R2**
> release flow in `docs/distribution.md`, but **that flow does not apply to Splay**:
> Splay publishes to **GitHub**, not to upstream's R2 bucket or appcast. The name is
> kept only so the owner's vocabulary finds this file.
>
> Related: `docs/fork-product-model.md` (product north star),
> `plans/active/splay-two-surface-rebuild.md` (build phases),
> `docs/thread-state.md` (where we are right now).

## Decisions that scope this launch (2026-08-18)

- **Destination: GitHub, as its own project.** Splay is presented as its own product,
  not as "a MacParakeet fork" — the owner's words: *"we're basically a different thing
  by now."* Identity, README, and framing are Splay's.
- **Phase 6 (the cut) lands first.** Retire the main window and remove the cut-list
  features from user-facing surfaces, so only the two surfaces exist before we check.
  Phase 5 (first-run cards) is **not** in this launch — see Known gaps.
- **The deferred glow "nudges" get dialled** in the live HTML tuner during the final
  visual pass (drift visibility / brightness / extend sway to ready, `SplayGlowTuning`),
  together with the long-open talk-glow verdict.

## The one hard legal constraint

MacParakeet is **GPL-3.0**. Splay is a derivative work of it regardless of how much has
been rewritten. GPL-3.0 therefore requires, non-negotiably:

- [ ] The **GPL-3.0 licence text stays** in `LICENSE`.
- [ ] Daniel Moon's **existing copyright notice is preserved** (add Splay's own alongside
      it — do not replace it).
- [ ] **Significant changes are marked as ours**, with a date.
- [ ] **Splay itself is released under GPL-3.0**, sources included.
- [ ] `THIRD_PARTY_LICENSES.md` still covers the bundled deps (FluidAudio, GRDB, Sparkle,
      WhisperKit, yt-dlp, FFmpeg).

None of this conflicts with presenting Splay as its own product. Attribution can live in
`README.md` (a short "Built on MacParakeet by Daniel Moon, GPL-3.0" line) and the About
card, without framing the project as a fork.

---

## A. Blockers — must be fixed before any publish

### A1. Sparkle points at upstream's appcast 🚨
The shipped bundle carries `SUFeedURL = https://macparakeet.com/appcast.xml`,
`SUEnableAutomaticChecks = true`, and upstream's `SUPublicEDKey`. Live evidence on the
owner's machine: `SULastCheckTime = 2026-08-16` and a stored `NSWindow Frame SUUpdateAlert2`
— Splay has been polling Daniel Moon's appcast and has already shown an update prompt.
Accepting one downloads `MacParakeet.dmg` **over `/Applications/Splay.app`**.

- [ ] Decide: **remove Sparkle** (simplest — GitHub Releases has no auto-update) **or**
      stand up Splay's own appcast + a **newly generated EdDSA keypair** (never reuse
      upstream's public key — we do not hold its private half).
- [ ] Clear the stale Sparkle state from the owner's defaults domain
      (`com.macparakeet.MacParakeet`) so no queued update can fire.
- [ ] Verify a built bundle no longer resolves any upstream feed.

### A2. The build is not distributable
- [ ] Signed with **Developer ID Application**, not `Apple Development` (today's install
      is a development cert — it runs only on this machine).
- [ ] **Notarized + stapled**, then verified with `spctl -a -vv` on a clean path.
- [ ] Confirm bundled helpers still validate after signing (`yt-dlp` needs
      `com.apple.security.cs.disable-library-validation` — see `CLAUDE.md`).

### A3. Identity still says MacParakeet
- [ ] `README.md` is still upstream's (MacParakeet icon, name, macparakeet.com,
      `downloads.macparakeet.com` DMG badge, DeepWiki badge) — rewrite as Splay's.
- [ ] `CFBundleShortVersionString` is `0.6.0` (upstream's) — pick Splay's own version.
- [ ] `NSCalendarsFullAccessUsageDescription` is still in `Info.plist` though calendar is
      being cut — remove usage strings for permissions Splay no longer requests.
- [ ] Decide the bundle id. `com.macparakeet.mc` and the `MacParakeet-MC` data namespace
      were deliberately kept for migration-free local rebranding
      (`docs/BRANDING.md`); changing them **moves the user's existing data**. Either keep
      them and document why, or write a migration.
- [ ] `docs/distribution.md` documents upstream's R2/appcast path — mark **HISTORICAL**
      or replace with Splay's GitHub Releases flow.
- [ ] Repo-level docs (`CLAUDE.md`, `spec/`, `AGENTS.md`) describe MacParakeet. Decide
      what a public Splay repo should carry vs. what stays internal.

---

## B. Phase 6 — the cut (do before the check)

Goal from the plan: *"only the two surfaces exist; no main window; cut features gone from
the UI."* Concrete inventory of what is still reachable today:

**The main window.** `AppWindowCoordinator.openMainWindow()` is still called from 10+ call
sites across `AppDelegate` and `MenuBarCoordinator` (incl. `openMainWindowToSettings(tab:)`
for AI settings). All must be re-routed to cards or removed.

**The menu bar `Go` menu** still lists every retired destination:
Transcribe · Library · Dictations · Meetings · Vocabulary · Transforms · Feedback · Settings…

**The `Capture` menu** still offers New Transcription · Start Dictation · File Transcription ·
Record Meeting · Create Transform.

**The `Window` menu** still has *Show Splay* → `openMainWindow`.

**Feature flags all still on:** `meetingRecordingEnabled`, `calendarEnabled`,
`transformsEnabled`, `meetingVadLiveChunkingEnabled`, `islandReplacesDictationPill`.

- [ ] Re-route or delete every `openMainWindow` / `openMainWindowToSettings` call site.
- [ ] Rebuild the app menus to the two-surface reality (keep Edit; keep About/Quit).
- [ ] Turn off / hide the cut-list features: Transforms, calendar auto-start, YouTube,
      Discover, Dictations-as-separate-surface, prompts, chat, diarization, stats,
      provider config, engine picker.
- [ ] Delete the now-dead Slice-4 overlay path (`IslandOverlayController`,
      `openSettingsOverlay` / `openLibraryOverlay`) the plan left in place for this phase.
- [ ] **Hide before deleting.** `CLAUDE.md` forbids removing licensing/entitlement plumbing
      and meeting-recovery artifacts as "dead code" without explicit owner sign-off.

---

## C. The final check — the actual test pass

Run against a **freshly installed, Developer-ID-signed** build.

### C1. Capture — the spine
- [ ] Single-tap fn → mic-only recording → transcript file written.
- [ ] Double-tap fn → mic + system audio → transcript file written.
- [ ] Click the island's fn chip → records (mic).
- [ ] Stop from the island; the light runs red → amber → done.
- [ ] Cold-Bluetooth (AirPods from sleep): amber waiting light appears, then goes red as
      HFP wakes; recording is **not** killed by silence (thread-7 doctrine: dead ≠ silent).
- [ ] A genuinely dead input surfaces the failure card with real text — never a silent vanish.
- [ ] File drop onto the island → straight to transcribing.
- [ ] Import an AirDropped iPhone voice memo (the owner's real workflow).

### C2. The two surfaces
- [ ] Mark click opens the menu card **every time**, including twice in a row via the
      Close button (thread-7d fix — verify `src=local` appears in the log).
- [ ] Card does not steal focus from the app being typed in.
- [ ] Esc, click-away, and Close all dismiss; tab switching (Recents/Settings/About)
      resizes top-anchored without the top edge hopping.
- [ ] Recents lists the last five; "Open folder" reveals the right folder.
- [ ] Settings toggles persist across relaunch (audio source, launch-at-login, start sound).
- [ ] About shows Splay's version + GPL-3.0 attribution.
- [ ] No third surface appears anywhere.

### C3. Output
- [ ] Transcript `.md` lands in the configured folder; audio in `Recordings/`.
- [ ] Transcript is **verbatim** — never silently polished (layering principle).
- [ ] Re-open a transcript from Recents; copy works.

### C4. Visual pass (the deferred items)
- [ ] Dial the glow nudges in the live HTML tuner → port to `SplayGlowTuning`.
- [ ] Confirm the talk-glow reacts to voice (open since thread 6) and dial via the
      Settings "Talking glow" slider / `SplayTalkGlowTuning`.
- [ ] Island geometry: top-flush, camera housing never covered, nothing drawn on the face.

### C5. Fresh-machine sanity
- [ ] Install from the published artifact on a path with no prior Splay state.
- [ ] Permissions prompt correctly (mic; system audio only for double-tap).
- [ ] Gatekeeper opens it without a right-click bypass.
- [ ] First launch is *survivable* without Phase 5 onboarding — see Known gaps.

### C6. Housekeeping
- [ ] `swift build` clean; `swift test` = the known 7 environmental fork-debt failures only.
- [ ] Agentic Vet clean on the release diff.
- [ ] Strip the TEMP `f125f21d` diagnostic markers (keep the `src=` click tags — cheap and
      genuinely diagnostic).
- [ ] `docs/thread-state.md` updated.

---

## Known gaps shipping with this launch

- **No first-run onboarding (Phase 5 unbuilt).** A fresh install drops the user straight
  into the island with no welcome → mic → system-audio → destination → shortcut walk.
  Acceptable for a GitHub publish aimed at people who read the README; a real blocker
  the moment Splay is recommended to non-technical users. **Document it in the README.**
- **Phase 4 is partial** — storage is not yet the iCloud `Splay/` folder; the start-sound
  toggle persists but does not gate playback.
- **7 known environmental test failures** carried from the fork (AppPaths, 3×
  SettingsViewModel, MainWindowState, 2× AppHotkeyCoordinator).

## Order of work

1. **A1** — kill the upstream Sparkle feed (do this first; it is live on the owner's machine).
2. **B** — Phase 6, the cut.
3. **A3** — identity: README, version, usage strings, docs.
4. **C4** — visual pass in the tuner.
5. **A2** — Developer ID sign + notarize.
6. **C** — the full check on the notarized build.
7. Publish.
