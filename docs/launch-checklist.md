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

### A1. Sparkle points at upstream's appcast 🚨 — ✅ RESOLVED 2026-08-18
The shipped bundle carries `SUFeedURL = https://macparakeet.com/appcast.xml`,
`SUEnableAutomaticChecks = true`, and upstream's `SUPublicEDKey`. Live evidence on the
owner's machine: `SULastCheckTime = 2026-08-16` and a stored `NSWindow Frame SUUpdateAlert2`
— Splay has been polling Daniel Moon's appcast and has already shown an update prompt.
Accepting one downloads `MacParakeet.dmg` **over `/Applications/Splay.app`**.

- [x] Kept Sparkle, with Splay's **own** appcast + a freshly generated EdDSA keypair.
      Public key `UjG8RmU9eOGL2ZNFdfc72QUhFH5z6KgYWTYBgmRJ6no=`; private half in the
      login keychain (service `https://sparkle-project.org`, account `ed25519`).
      Upstream's key was never usable — we do not hold its private half.
- [x] `scripts/dist/build_app_bundle.sh` now emits
      `SUFeedURL = https://etopianreglazer.github.io/splay/appcast.xml`.
- [x] Cleared the stale Sparkle state (`SULastCheckTime`, `SUUpdateGroupIdentifier`,
      `SUUpdateAlert2` frame, `SUHasLaunchedBefore`) from `com.macparakeet.MacParakeet`.
- [ ] **Back up the private key** — it exists in exactly one place. Losing it means no
      existing install can ever be updated. See `docs/releasing.md` Part 4.
- [ ] Stand up GitHub Pages so the feed URL actually resolves (see `docs/releasing.md` 2.2).
- [x] Verify a freshly built bundle resolves no upstream URL (source sweep = 0; re-check on the artifact).

### A2. The build is not distributable — 🟡 Apple setup DONE, build not yet cut
- [x] **Developer ID Application certificate created 2026-08-19** via Xcode's Manage
      Certificates. `Developer ID Application: Mathew Cleveland (76K8473JHR)`, expires
      2027-02-01. Verified: signs with hardened runtime, chains to Apple Root CA, and
      obtains an Apple secure timestamp.
- [x] **notarytool credentials stored** as keychain profile `splay`; authenticated
      against Apple (empty submission history returned, not an auth error).
- [ ] Back up the certificate + private key as a `.p12` off this machine (5 Developer ID
      certs exist per account, ever).
- [x] Actually build and sign a release bundle with that identity (0.1.0, build 20260822010535, 2026-08-21).
- [x] **Notarized + stapled**, then verified with `spctl -a -vv` (app + DMG accepted, Notarized Developer ID).
- [x] Confirm bundled helpers still validate after signing (only `ffmpeg` remains; yt-dlp/node are gone).

### A3. Identity still says MacParakeet
- [x] `README.md` is still upstream's (MacParakeet icon, name, macparakeet.com,
      `downloads.macparakeet.com` DMG badge, DeepWiki badge) — rewrite as Splay's.
- [x] `CFBundleShortVersionString` — Splay starts at `0.1.0`.
- [x] `NSCalendarsFullAccessUsageDescription` is still in `Info.plist` though calendar is
      being cut — remove usage strings for permissions Splay no longer requests.
- [ ] Decide the bundle id. `com.macparakeet.mc` and the `MacParakeet-MC` data namespace
      were deliberately kept for migration-free local rebranding
      (`docs/BRANDING.md`); changing them **moves the user's existing data**. Either keep
      them and document why, or write a migration.
- [x] `docs/distribution.md` (upstream R2/appcast) is superseded by **`docs/releasing.md`**,
      the GitHub Releases + Pages flow. Mark the old file HISTORICAL.
- [x] Repo-level docs (`CLAUDE.md`, `spec/`, `AGENTS.md`) describe MacParakeet. (Rewritten for Splay 2026-08-21.) Decide
      what a public Splay repo should carry vs. what stays internal.

### A4. Telemetry reported to upstream's server 🚨 — ⚠️ MITIGATED 2026-08-18
Same class of bug as A1. `TelemetryService` defaulted to **enabled** (`?? true`) and posts
to `https://macparakeet.com/api` — upstream MacParakeet's infrastructure. Every Splay
install was reporting anonymous usage and crash events into another project's backend
without its agreement, and `README` privacy claims could not have been made truthfully.

- [x] Telemetry is now **opt-in** (`?? false`) in both `AppPreferences.isTelemetryEnabled`
      and `TelemetryService.init` — nothing is sent unless the user turns it on.
- [x] **Decide the endgame:** removed entirely (thread 8). ~~remove the reporting entirely (simplest, and honest for a
      project this size), or point `baseURL` at infrastructure you own. Leaving an
      upstream URL in the binary is not acceptable at publish, even unreachable.
- [x] Same check for `CrashReporter` (rides the same No-Op seam).
- [ ] Confirm the Settings toggle reflects the new default sensibly.

### A6. Every remaining pointer at upstream infrastructure 🚨 — OPEN
A full sweep of shipping code (2026-08-19) found A1 and A4 were not isolated incidents.
**Five network endpoints and seven user-facing links still resolve to upstream.**

**Endpoints that send data to `macparakeet.com`:**

| Service | Endpoint | Severity |
|---|---|---|
| `FeedbackService` | `macparakeet.com/api` | 🚨 **Worst of the set.** The in-app feedback form posts the user's message — and optionally their email and a screenshot — to upstream's Cloudflare function, which files a **GitHub Issue on Daniel Moon's repository**. Splay users' bug reports would land in another project's tracker, carrying their content. |
| `TelemetryService` | `macparakeet.com/api` | Mitigated (opt-in as of A4); endpoint unchanged. |
| `DiscoverService` | `macparakeet.com/api/discover.json` | Discover is on the cut list; the fetch still exists. |
| `DiscoverThoughtsService` | `macparakeet.com/api/discover-thoughts` | Same. |
| Help menu | `macparakeet.com` | Opens upstream's marketing site from Splay's Help menu. |

**User-facing links to `github.com/moona3k/macparakeet`** (7): the About card's repo link,
`AppDelegate` repoLink, the Settings telemetry-docs link, the menu bar "View on GitHub",
**`FeedbackView`'s "Issues" link** (sends users to file bugs upstream), and two CLI help
strings (`transcribe`, `config`).

- [x] `FeedbackService` — remove the feature or repoint it. Do not ship a form that posts
      user content to someone else's backend.
- [x] `DiscoverService` / `DiscoverThoughtsService` — Discover is cut; remove the fetches.
- [x] Repoint or remove all 7 repo links, including the two CLI help strings.
- [x] Help menu → Splay's own repo or README.
- [x] Re-run this sweep before release (0 hits, 2026-08-21):
      `grep -rn "macparakeet\.com\|moona3k" --include="*.swift" Sources/`

> **Note on `SparkleUpdateGuard`:** it blocks updates only for versions literally `0.0.0`,
> `dev`, empty, or containing `pdx`. The installed dev builds were `0.6.0`, so the guard
> never applied — consistent with an update alert actually being shown. It is not a
> safety net for A1; the feed URL fix is.

### A5. Attribution and identity draft — 🟡 IN PROGRESS
- [x] `README.md` rewritten as Splay's own (`docs/README-macparakeet-original.md` keeps
      the original for reference). Presents Splay as its own product, names MacParakeet
      and Daniel Moon, points users who want the broader feature set back upstream.
- [ ] Owner review of the README draft — particularly the Status section, which states
      the no-onboarding gap plainly.
- [x] `LICENSE`: add Splay's copyright line **alongside** Daniel Moon's, do not replace.
- [x] Add a change-marking note (GPL-3.0 §5(a)) — the README's "Built on MacParakeet"
      section is most of it; make sure it is dated.

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

- [x] Re-route or delete every `openMainWindow` / `openMainWindowToSettings` call site.
- [x] Rebuild the app menus to the two-surface reality (keep Edit; keep About/Quit).
- [x] Turn off / hide the cut-list features: Transforms, calendar auto-start, YouTube,
      Discover, Dictations-as-separate-surface, prompts, chat, diarization, stats,
      provider config, engine picker.
- [x] Delete the now-dead Slice-4 overlay path (`IslandOverlayController`,
      `openSettingsOverlay` / `openLibraryOverlay`) the plan left in place for this phase.
- [x] **Hide before deleting.** `CLAUDE.md` forbids removing licensing/entitlement plumbing
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
- [x] `swift build` clean; `swift test` = the known 5 environmental fork-debt failures only (2026-08-21).
- [ ] Agentic Vet clean on the release diff.
- [x] Strip the TEMP `f125f21d` diagnostic markers (done 2026-08-21; (keep the `src=` click tags — cheap and
      genuinely diagnostic).
- [x] `docs/thread-state.md` updated.

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

1. ~~**A1** — kill the upstream Sparkle feed.~~ ✅ done 2026-08-18.
2. ~~**A4** — stop telemetry reporting to upstream.~~ ✅ mitigated (endgame decision open).
2b. **A6** — the rest of the upstream pointers (feedback endpoint is the urgent one).
   Overlaps heavily with Phase 6, which cuts Feedback and Discover anyway.
3. ~~**A2 Part 1** — Apple setup: Developer ID cert + notarytool credentials.~~
   ✅ done 2026-08-19.
4. **B** — Phase 6, the cut.
5. **A3** — finish identity: LICENSE line, version, usage strings, repo name/detach.
6. **C4** — visual pass in the tuner.
7. **A2** — build, sign, notarize.
8. **C** — the full check on the notarized build, including a **second Mac**.
9. Publish (`docs/releasing.md` Part 3).
