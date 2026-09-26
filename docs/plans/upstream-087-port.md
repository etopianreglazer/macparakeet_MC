# Upstream 0.8.7 port — Mac bug fixes worth taking

> Status: **IN PROGRESS** (thread 16, 2026-09-25). Owner direction: Mac, not iOS, this thread.
> Thread 17: steps 1–5 pressed OK on Parakeet (2026-09-25); step 4's own policy is to be replaced by
> upstream's (`upstream-mic-port.md`). Next here after that port: the FluidAudio bump, then the small items.

Splay forked MacParakeet at `20f4daac` (≈ v0.6.17, 2026-06-01). Upstream shipped v0.6.18 → v0.8.7
(~3,350 commits) since. A four-way survey (audio · STT/ANE · meeting lifecycle · hotkey/safety) found
that almost all of that volume is Library/LLM/CLI/engine work Splay cut; what matters is a handful of
bug fixes. None had been ported. This plan ports them in Splay's shape, not upstream's.

## Decided

- **SUPERSEDED (thread 17, owner):** adopt upstream's mic handling wholesale on macOS instead —
  brief in `docs/plans/upstream-mic-port.md`. The original decision, kept for the record:
  **Keep the explicit System Default pin** (`MicrophoneCapture.swift` `appendExplicit(.systemDefault…)`),
  which upstream reverted in 0.6.18 for silent recordings. Splay's input policy ("stay on the device that
  is delivering", `docs/plans/mac-input-policy.md`) depends on it. Fix the failure mode instead (step 4).
- **Not taken:** Caps Lock/`fn` (#1099) and hold-to-talk (#1096) — the bugs live in post-fork upstream
  code; stop-time stack overflow (#810) — the handler it lives in does not exist here; new engines
  (Parakeet Unified, Nemotron, Cohere); AEC/LocalVQE; role-explicit filenames; import/split; everything
  Library/LLM/CLI.

## Steps

| # | Fix | Upstream ref | State |
|---|---|---|---|
| 1 | Bound ScreenCaptureKit content/start/stop (10 s / 5 s) and writer finish (10 s) so Stop always returns. Never `cancelWriting()` (deletes the file). Late start success is stopped again. | #814, 92810829, df8f7dcf | done |
| 2 | A failed transcription holds with **Retry** instead of vanishing after 5 s; green only after the `.md` is written. | #761/#762/#869, #818, #698 | done |
| 3 | Bare-`fn` event tap `.listenOnly`; crash report kept as a content-free line in the log instead of being deleted unread; invalidate the tap's Mach port on teardown. | #1142/c9b972bf, #1021, a9aeac35 | done |
| 4 | *(to be replaced by the upstream mic port — `upstream-mic-port.md`)* Mic that starts silent or freezes: explicit-default attempt with no callback in a bounded window → one rebuild on the implicit route; callback-gap watchdog armed after the first buffer (callbacks, not loudness — dead ≠ silent); `routing=` in the log. | #860, #1010 | done — Mac-only watchdog (off on iOS) |
| 5 | Sonoma long-file crash: `parallelChunkConcurrency: 1` + encoder off the ANE on macOS 14; later FluidAudio 0.14.5 → 0.15.7 with a before/after WER check. | #998, #1089, ab2671a5 | first half done (whole-model CPU+GPU on 14); FluidAudio bump open |

Smaller, unscheduled: fn tap during transcription is dropped (#535-lite queue); Accessibility granted
after launch is not picked up; a stray key between two `fn` taps still counts as a double tap; live
preview STT runs although the island never shows it (#1041); trailing 0.5 s pad for short captures
(#615/#632); Sparkle trust-anchor build check (#618).
