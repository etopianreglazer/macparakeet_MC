# Plan: Lean island-only product

> Status: **ACTIVE — discovery complete; first safe slice queued.** This supersedes the broad
> window-first roadmap, while preserving the uncommitted Slice 4/5 review work.

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
2. **Shared adaptive island host/router.** Replace separate `IslandOverlayController` presentation
   with expanded states in the existing long-lived `IslandPanel`. Add an explicit router and
   content-driven animated sizes; Library and Settings become in-panel pages with Back/Close.
3. **Lean island card/detail.** Record row + source toggle, compact search/history rows, transcript
   detail, explicit Markdown export, and Reveal in Finder all remain contextual island states.
4. **Retire window routes.** Remove main-window navigation only once those same-island states are
   equivalently available, including safe failure fallbacks.
5. **Deletion review.** Only after replacement verification, decide whether to delete YouTube and
   dormant dictation code/data migrations.

## First-slice acceptance

- No YouTube command appears in menu-bar/user-facing Capture surfaces.
- Existing YouTube records remain readable.
- Meeting recording, dictation, Library, and exports remain unchanged.
- No capture semantic change or deletion.
