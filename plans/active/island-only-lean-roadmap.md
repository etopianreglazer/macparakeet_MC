# Plan: Lean island-only product

> Status: **HISTORICAL — superseded 2026-08-07 by `splay-two-surface-rebuild.md`.**
> This plan's central premise — that Library, Settings, detail, etc. are *expanded substates inside
> the island* (an island-as-router model) — is **rejected** by the final design handoff
> (`docs/design/splay-island-handoff/`). In the final design the island is an **indicator only** and
> everything else is a **centred card**; there is no in-island router. Kept for context; do not build
> from it. See `splay-two-surface-rebuild.md`.
>
> ---
>
> _(original status: ACTIVE — discovery complete; first safe slice queued. Preserved below.)_

## Current identity

The local product is now **Splay**: the installed review build is `/Applications/Splay.app` with
the supplied full icon and compact three-splay mark. Near-black remains the surface foundation;
lavender/deep-violet is the single island primary, selection, and readiness accent. The existing
bundle identifier (`com.macparakeet.mc`) and application-support namespace remain intentionally
stable for a safe local migration-free rebrand. Internal modules remain MacParakeet for build and
data compatibility; GPL/license attribution remains intact. See `docs/BRANDING.md`.

## Non-negotiable surface invariant

The small top-center pill is **the idle/resting state of the exact same island surface** shown in
the authoritative expanded-panel screenshot. There are never two independently presented
interfaces: the one long-lived `IslandPanel` morphs between idle pill and the content-sized black
panel. Recording, transcribing, done, optional live preview, history/search, transcript detail,
Settings, Markdown export, and Reveal in Finder are **expanded substates** of that one surface.
Back, close, and failure recovery return within that state machine, normally to the idle pill.

## Product boundary

The island is the primary workflow: basic meeting record/stop → transcribing → done, compact
history, explicit Export Markdown, and only necessary Settings. Dictation remains a separate
legacy capability until deliberately retired; it must not be silently redirected into recording.
YouTube is retired from user-facing entry points first, never deleted with its data/code paths.

## Audit

- Island Record uses `MeetingRecordingFlowCoordinator` with a microphone/system source override;
  it is already separate from dictation.
- The coordinator owns record → stop → `transcribeMeeting` and exposes `transcriptUpdates`, a safe
  future seam for an optional compact live preview.
- Library overlay exists, but transcript selection still opens the main window. Export Markdown
  currently lives in `TranscriptResultView`, so window retirement must wait for an overlay detail /
  export surface.
- YouTube remains exposed in `MenuBarCoordinator` and its hotkey route. Underlying downloader,
  transcript records, and existing details remain untouched.

## Phases

1. **Hide YouTube entry points (first safe slice).** **Implemented locally, uncommitted.**
   Menu-bar Capture/quick-menu items and the registered YouTube hotkey are removed; services,
   stored records, and existing transcript rendering remain. `swift build --skip-update -q` and
   `git diff --check` pass. Live-check Meeting record and file history before commit.
2. **Shared adaptive island host/router.** **Implemented locally; compact redesign installed for review.** The existing
   long-lived `IslandPanel` now routes Home → Library → Settings internally. Library renders from
   the existing library model; the full existing SettingsView is injected from AppWindowCoordinator
   into the island host rather than presented as an overlay. Back returns to Home and Close to the
   pill. Remove obsolete overlay callbacks after detail/export routes land.
3. **Lean island card/detail.** **Implemented locally; acceptance pending.** Record row + source toggle,
   compact search/history rows, transcript detail, explicit Markdown export, and Reveal in Finder
   remain contextual island states. Recording failures are now a separate recovery/error path,
   never a normal completion: the service health snapshot (mode, frames, byte growth, last append)
   is checked every second and a 10-second active-capture stall surfaces explicitly.
   Setup/readiness is also now in-island: model choice, safe runtime setup, permission remediation,
   and ready-to-record state. It remains subject to user acceptance of the floating-panel interaction.
4. **Retire window routes.** Remove main-window navigation only once those same-island states are
   equivalently available, including safe failure fallbacks.
5. **Deletion review.** Only after replacement verification, decide whether to delete YouTube and
   dormant dictation code/data migrations.

## First-slice acceptance

- No YouTube command appears in menu-bar/user-facing Capture surfaces.
- Existing YouTube records remain readable.
- Meeting recording, dictation, Library, and exports remain unchanged.
- No capture semantic change or deletion.
