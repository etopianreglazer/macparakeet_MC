# File transcription feedback — say that it runs, where it went, and when it failed

> Status: **IN PROGRESS** (thread 22, 2026-09-27). Mac only.

## Why

Owner (thread 22): Transcribe File "doesn't come with an indication of where something is saved or what
it does exactly and if it works." A trace confirmed the pipeline works (DB row, `.md` auto-saved to
`~/Documents/MacParakeet-MC/Transcriptions/`) but the feedback died with upstream's main window:

- `TranscriptionViewModel` publishes progress/error state nothing reads. Only the menu bar icon's generic
  `.processing` look shows a job (and it flickers between batch files).
- The island shows nothing. Success: a chime, a banner only when Splay is *not* frontmost (the open panel
  just made it frontmost). The `.md` path is never shown; `saveIfEnabled` swallows a failed write.
- Failure: `errorMessage` has no reader — nothing at all; the `.error` row then sits in Recordings as a
  blank, uncopyable row.
- Choosing Transcribe File again mid-job plays the "accepted" sound and silently no-ops. No cancel.
- The card's Open folder opens Meetings, not Transcriptions.

## Decided (owner, thread 22)

- **Menu:** while a job runs the Transcribe File item shows it is working (progress glyph, "Transcribing
  *name*… 42%" / "… 2 of 5") and is **disabled** — no second pick until done. A separate **Cancel
  Transcription** item appears only while a job runs.
- **Island:** file jobs use the existing faces — amber spinner while running, green check when saved,
  failure light on error. No bars, no timer (nothing is recording). Meetings and dictation outrank it.
- **Banner, always** (also when Splay is frontmost): "Transcribed *x.m4a*" · "Saved to Transcriptions".
  Click reveals the `.md` in Finder (batch: the folder). Failures get a banner with the reason. A drop
  during a job gets a "still transcribing" banner instead of the accepted sound.
- **Recordings:** failed/cancelled jobs stay, marked as such (the reason shows); Open folder opens the
  folder of the newest row (file job → Transcriptions, recording → Meetings).

## Slices

1. **View model events** — `TranscriptionViewModel.onFileJobEvent` (`started` / `progress` /
   `finished(FileJobOutcome)`), `isFileJobActive` (no inter-file flicker), auto-save through the throwing
   `save()` so the outcome carries the written URL or the save error; notifier copy for success (folder
   name), failure, batch. Tests.
2. **Island** — `IslandFileJobPhase` (`transcribing` / `done` / `failed`) on `IslandChromeModel`,
   `IslandLayout.effectiveState` priority meeting > dictation > file; a dwell for done/failed. Tests.
3. **Menu** — item title/glyph/enabled from the view model (observation-tracked, updates while open),
   Cancel item, busy drop → banner; menu bar icon keyed on `isFileJobActive`.
4. **Banner** — `UNUserNotificationCenter` delegate: present in foreground, click → reveal in Finder.
5. **Recordings** — failed/cancelled row marking; Open folder follows the newest row.

Each slice: tests → `swift test` (both frameworks) → `/vet` → commit; install + owner press at the end.

## Press list

Transcribe one file (menu + drop): island spinner → check, menu item disabled with progress, banner with
the file, click → Finder. A folder of 3 (one bad file): "2 of 3", batch banner with 1 failed. A corrupt
file: failure light + reason banner, marked row in Recordings. Cancel mid-job. Open folder.
