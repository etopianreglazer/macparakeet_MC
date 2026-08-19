# Publish inventory — what ships, what gets rewritten, what stays home

> Status: **ACTIVE**. Started 2026-08-19, during the launch prep.
> Companion to `docs/launch-checklist.md` (the gate) and `docs/releasing.md` (the mechanics).
> This one answers a narrower question: **for every asset and every document in this repo,
> is it in order?**

Legend: ✅ **SHIP** (correct as-is) · ✏️ **REWRITE** (belongs, still says MacParakeet) ·
📦 **HISTORICAL** (keep, mark superseded) · 🚫 **EXCLUDE** (should not be in a public Splay repo)

---

## 1. Identity assets

| Asset | State | Notes |
|---|---|---|
| `Assets/AppIcon.icns` | ✅ | Splay icon, replaced in `55be635d`. Ships as `Contents/Resources/AppIcon.icns`. |
| `Assets/AppIcon-1024x1024.png` | ✅ | Splay icon; used as the README hero. |
| `Sources/Splay/Resources/splay-three-mark.png` | ✅ | The menu bar mark. Loaded as a **template** image so it adapts to light/dark. |
| `Assets/menubar-icon.png` / `@2x` | 📦 | **Upstream MacParakeet's** menu bar icon (`4df48900`). Now only the *second* fallback in `BreathWaveIcon.loadBaseMenuBarIcon`. Harmless, but it means a resource-loading failure degrades to MacParakeet's mark rather than something obviously wrong. Consider dropping the fallback so failures are loud. |
| `Assets/menubar-icon-preview.png` | 🚫 | Development preview artifact, not shipped, not needed publicly. |
| `brand-assets/` | ✏️ | Upstream's **MacParakeet** brand kit (parakeet marks, coral "Pop" palette, Warhol grid posters). None of it is Splay's. Either replace with Splay's own or exclude. |

### ⚠️ Finding: the dev install and the release build load resources differently

`install_local.sh` builds with `BUILD_SYSTEM=swiftpm`, which does **not** emit SwiftPM
resource bundles into the app. The installed `/Applications/Splay.app` therefore contains
**no `Splay_Splay.bundle`** — it resolves `Bundle.module` from `.build/` on this machine.
It works here and would fail on any other Mac.

The release path (`BUILD_SYSTEM=xcodebuild`, the default in `build_app_bundle.sh`) copies
the bundles correctly — a dry-run build produces `Splay_Splay.bundle`,
`GRDB_GRDB.bundle`, `swift-crypto_Crypto.bundle`, `swift-transformers_Hub.bundle`.

**Consequence:** every live test in every thread so far ran against a build whose resource
loading is machine-dependent. The menu bar icon, and anything else read from
`Bundle.module`, has never actually been verified on a shipping build.
**Verify the menu bar mark on the notarized artifact, not the dev install.**

---

## 2. Legal + attribution

| Document | State | Notes |
|---|---|---|
| `LICENSE` | ✅ | **Updated 2026-08-19.** Splay's copyright (Mathew Cleveland) added *alongside* Daniel Moon's, with an explicit derivation statement and date — GPL-3.0 §5(a). Ships inside the app at `Contents/Resources/Legal/LICENSE`. |
| `THIRD_PARTY_LICENSES.md` | ✅ | Accurate. All 11 SwiftPM dependencies in `Package.resolved` are covered, plus FFmpeg / yt-dlp / Node.js and the model licences. The "WhisperKit" heading correctly points at `argmaxinc/argmax-oss-swift`. Ships at `Contents/Resources/Legal/`. |
| `CREDITS.md` | ✅ | **New 2026-08-19.** The thank-you letter: MacParakeet and Daniel Moon first and at length, then the speech stack, libraries, bundled tools, and design influences (DynamicNotchKit's blur; Talkify's dead-≠-silent doctrine). |
| About card (`SplayCards.swift`) | ✏️ | Says *"Splay is a personal fork of MacParakeet."* Accurate but now inconsistent with the README's framing. Reword to name Daniel Moon and link the repo, matching `CREDITS.md`. |

---

## 3. Root documents

| Document | State | Notes |
|---|---|---|
| `README.md` | ✅ | Rewritten as Splay's own (2026-08-18). Awaiting owner review. |
| `LICENSE` / `THIRD_PARTY_LICENSES.md` / `CREDITS.md` | ✅ | See above. |
| `CLAUDE.md` | ✏️ | Describes **MacParakeet** in full — three capture modes, Transforms, calendar, the 9-item nav, upstream's release flow. Deeply stale for Splay. It is also *useful internal tooling*. Decide: rewrite for Splay, or exclude from the public repo. |
| `AGENTS.md` | ✏️ | Same situation, smaller. |
| **Missing:** `CONTRIBUTING.md` | — | Optional. Reasonable to omit and say so in the README ("built for one workflow; issues welcome, PRs unlikely to be merged"). |
| **Missing:** `CHANGELOG.md` | — | Worth adding at first release — it is what the Sparkle appcast release notes are written from. |
| **Missing:** `SECURITY.md` | — | Optional for a project this size. |

---

## 4. `docs/` — 44 files

**Splay's own (✅ SHIP):** `launch-checklist.md`, `releasing.md`, `publish-inventory.md`
(this file), `fork-product-model.md`, `BRANDING.md`, `thread-state.md`.

**Rewrite or exclude (✏️/🚫):** `brand-identity.md`, `marketing.md`, `design-overhaul.md`,
`ui-inspiration.md`, `telemetry.md`, `cli-testing.md`, `commit-guidelines.md`,
`voicemail-agent.md`, `agents/*` — all written for MacParakeet.

**Mark historical (📦):** `distribution.md` (upstream R2 flow — superseded by `releasing.md`),
`runtime-revalidation-checklist.md` (already marked HISTORICAL),
`README-macparakeet-original.md` (deliberate archive).

**Exclude from a public repo (🚫):** `research/*` (11 files — competitor reverse-engineering,
WisprFlow deep dives), `planning/*` (8 files — abandoned local-LLM benchmarking),
`audits/*` (4 files), `blog/*`. These are upstream's internal thinking. Keeping them
public is noise at best, and the reverse-engineering write-ups are the kind of thing you
would not choose to publish under your own name.

---

## 5. `spec/` (38), `plans/` (81), `integrations/` (3), `marketing/` (3)

**125 files, essentially all upstream MacParakeet's**, describing features Splay is cutting:
Transforms, calendar auto-start, YouTube, diarization, meeting workspaces, licensing/trial
flows, the CLI as a public contract.

This is the single largest identity problem in the repo. A visitor cloning "Splay" finds a
`spec/` folder describing a different application in prescriptive present tense.

Three options:

1. **Exclude from the public repo** — keep them locally / on a private branch. Cleanest
   read for a visitor. Loses the ADR rationale that still governs the architecture.
2. **Keep `spec/adr/` only**, drop the narrative specs and plans. The ADRs are genuinely
   still the architecture's source of truth and are honest history.
3. **Ship everything with a banner.** Most honest, worst first impression.

**Recommendation: option 2.** Keep `spec/adr/` (with a note that ADR-017/018/020/022 cover
features Splay has cut), drop `spec/*.md`, `plans/`, `integrations/`, `marketing/`.
`plans/active/splay-*.md` is Splay's own and should move to `docs/`.

---

## 6. Build hygiene

| Item | State | Notes |
|---|---|---|
| `dist/` | 🚫 | Contains stale `MacParakeet.app`, `MacParakeet-MC.app`, `MacParakeet.dSYM` from earlier builds. Confirm `dist/` is git-ignored and clean it before release. |
| `screenshots/` | ✏️ | Verify these are Splay's UI, not MacParakeet's — the README does not use them, but a public repo folder called `screenshots/` will be looked at. |

---

## Open decisions

1. **`spec/` + `plans/`** — which of the three options above (recommend 2).
2. **`CLAUDE.md` / `AGENTS.md`** — rewrite for Splay, or keep private.
3. **`brand-assets/`** — replace with Splay's, or exclude.
4. **`docs/research/`** — confirm exclusion; these are upstream's competitor analyses.
5. **About card wording** — align with README and `CREDITS.md`.
