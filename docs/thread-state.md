# Thread State — Splay (modified MacParakeet-MC fork)

> **What this is:** the "you are here" pin, rewritten **in place** at the end of every thread. It answers
> three questions only: what is live and installed, what is decided but not done, and what the next thread
> starts with. It is **not** the plan (`docs/fork-product-model.md`, `docs/plans/`) and **not** the journal —
> the previous thread's block is demoted to `docs/thread-log.md` (verbatim, newest first) each time this is
> rewritten. **Hard cap: 150 lines.** If it is longer, move something to the log or to a plan/README.
>
> **Last updated:** 2026-09-26, thread 17 (end) — **MAC: 54b6dd09 PRESSED OK; ISLAND VOICE METER BUILT, INSTALLED,
> PRESSED OK ("looking really cool"); GLOW REMOVED.** Owner direction: Mac only. Thread 16's block is in `docs/thread-log.md`.

## 1. Live state

- Branch `ios/utility-layer`. **Nothing pushed.** New this thread: `ee8a669c` (island voice meter + timer; glow removed)
  and the end-of-thread docs commit. (Worked in worktree branch `claude/upbeat-mccarthy-3350ca`, fast-forwarded
  from `ios/utility-layer` — owner: fast-forward `ios/utility-layer` to it.)
- **Mac:** `/Applications/Splay.app` = `ee8a669c` (dev install 2026-09-26 ~12:18), **running**, pressed once: double-tap,
  45 s, completed, no `_timeout` / `shared_mic_liveness` / restart lines.
- **Engine is now Parakeet.** Splay's `speechRecognitionEngine` was `whisper` (large-v3-turbo); its Neural-Engine
  compile cache had been dropped, so the first load compiled for >3.5 min and looked like a hang (killed twice).
  Owner chose Parakeet (`defaults write com.macparakeet.mc speechRecognitionEngine parakeet`).
- **Upstream `MacParakeet.app` (0.8.7) runs alongside Splay** and is used for dictation — shares the log; filter by pid.
- **Suite:** 1855 tests, the same 5 known environmental cases (6 assertion failures), zero new. **Vet:** no issues.

## 2. Thread 17 results

- **§3 checks of thread 16, all on Parakeet:** plain tap ×2 and double-tap ×2 — `routing=explicit` built-in mic, first
  buffer 40–100 ms, rechecks `alive → ignore`, Stop → stopped 0.19–0.58 s, no system-audio timeouts, and a 10 s+
  pause produced **no** `shared_mic_liveness` (dead ≠ silent holds). AirPods / Retry / typing-lag were not pressed:
  the owner redirected (below).
- **Island voice meter** (`docs/plans/island-voice-meter.md`, picked in a live prototype tuner, variant D = Voice
  Memos layout): recording = 5 red bars left (mic level only; still the menu control) + `m:ss` timer right (stop
  control). Silent = flat red; dead = flat motionless amber. **All glow removed** (desktop bloom panel, halo, rim +
  mark shadows, talk sway, Settings "Talking glow" slider). Thin rim line kept as the state colour. Owner: "the new
  UI looks better, the old feels a bit dated" — the rest of the island/card may get the same treatment.

## 3. ⭐ Next thread starts here

1. **Port upstream's mic handling (macOS)** — owner: *"stop forcing our own approach."* The brief is
   `docs/plans/upstream-mic-port.md`: check/refine it first (§ "Check / refine"), confirm iOS keeps its current
   path, then build in slices, test, `/vet`, install, and have the owner press the AirPods cases listed there.
2. **Bugs found this thread (not fixed):**
   - **Discard leaves a DB row stuck `processing`** — `MeetingRecordingRecoveryService.discard` deletes the session
     folder but not the `transcriptions` row (the 2026-09-25 12:22 row and one from 2026-09-08 sit in `processing`).
     The 12:22 recording (killed during the Whisper compile) was deleted at the 12:33 relaunch — only the launch
     dialog's **Discard** can do that; **ask the owner** whether they clicked it (asked twice, unanswered).
   - **Recovery is invisible in `dictation-audio.log`** (os_log `.info` only) — add diagnostics lines.
   - **Whisper cold load looks like a hang** — no feedback on the island, no timeout, and `whisperOptimizedVariants`
     still says "warm" after the ANE cache is gone. Low priority while Parakeet is the engine.
3. **Visual refresh (owner, open):** the new meter look is liked, "the old feels a bit dated" — ask which surfaces next
   (card? transcribing/done faces?) and prototype in the live tuner before porting.
4. Still owed: the iOS island-dwell change in `ios/Splay/App/RecordingCoordinator.swift` was **never vetted** (thread
   15) — `/vet` it before the next iOS unit. FluidAudio 0.14.5 → 0.15.7 and the small items in
   `docs/plans/upstream-087-port.md` stay open (after the mic port).
