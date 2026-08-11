# Plan: Microphone-capture resilience (Voice-Memos manners)

> Status: **ACTIVE** — 2026-08-10. Splay fork. Owner: island/recording work.

## Problem

Recording from a Bluetooth mic (AirPods) fails intermittently: the mic engine
starts but delivers **zero buffers** (`mic_first_buffer=false, mic_frames=0`) and
a hard **2-second first-buffer watchdog** kills the whole recording
(`capture_failed=true`). Root cause is the A2DP→HFP route switch on a cold
Bluetooth mic taking longer than 2s; the buffers *were* coming, just not in time.
The user (correctly) observed that Apple Voice Memos doesn't do this.

Confirmed from the diagnostic log: the record-dot **click works 100%**
(`record_dot_clicked has_handler=true` → `meeting_recording_started` every time);
`capture_failed` also hits fn/menu recordings (7 total, only 4 button) — so it is
an **intermittent Bluetooth capture issue, not a button bug and not
session-specific**.

## Why our recorder is "dumb" today

Raw `AVAudioEngine` tap + a hand-rolled 2s watchdog that assumes buffers flow
instantly and **aborts** if not. Route changes are **log-only** (nothing
re-establishes). Every capture hiccup is **terminal** — there is zero retry, zero
re-establish, and zero device fallback anywhere in the pipeline.

Voice Memos, by contrast: (1) is **patient** — waits for the route to be ready
rather than self-aborting; (2) **follows the route** — re-establishes through
device changes; (3) leans on OS route management. We won't rewrite onto
`AVCaptureSession` (fights the shared mic+system engine, ADR-015), but we can give
our own pipeline the same manners.

## Design principles (in order)

1. **Patience.** Don't hard-fail a slow start. Give the mic — especially a
   Bluetooth route mid-negotiation — a longer, smarter grace window before we even
   consider it stalled. Likely fixes the AirPods case on its own.
2. **Self-heal.** If genuinely stuck, **restart the engine** (full teardown drops
   the CoreAudio aggregate and re-negotiates the route) instead of aborting.
3. **Follow the route.** Fall back to the built-in mic if the chosen device keeps
   failing; **survive mid-recording device changes** (restart + continue).

## Key architectural decision — recovery lives *below* the state machine

The state machine invariant "**capture failure → `.error`, never `.completed`**"
(`MeetingRecordingFlowStateMachine.swift:123`, tested in
`MeetingRecordingFlowStateMachineTests.testCaptureFailureWhileRecordingIsExplicitErrorNotCompletion`)
is **preserved**. We do *not* teach the state machine to "recover." Instead, the
audio-capture layer runs a bounded recovery and only escalates to `.error` (the
existing terminal event) when recovery is **exhausted**. From the state machine's
view: either audio keeps flowing (`.recording` continues) or a final, genuine
`.error` arrives. A *recoverable* stall is simply no longer "a capture failure."

This keeps the blast radius in the audio layer and leaves the ADR-019 recovery
contract + the invariant tests green.

## Phases

### Phase 1 — Engine restart/kick mechanism (no behavior change yet)
- `SharedMicrophoneStream`: new engine action `restartEngine` (on `engineQueue`)
  that tears down + rebuilds the physical engine and **re-installs the tap without
  dropping subscriber tokens**; refresh `handlersSnapshot` so the render-thread
  fan-out is intact. Respect refcounting (pair nothing — this is a restart, not a
  subscribe), VPIO stickiness, channel-0 mono extraction.
- `MicrophoneEnginePlatform`: `restart(advanceToNextDevice:)` — tear down current
  engine + re-run the device-attempt chain, optionally starting at the next device
  (→ built-in). All on the platform `queue`.
- Exit criteria: builds clean; a manual restart re-establishes buffers.

### Phase 2 — Patience + zero-buffer recovery + built-in fallback
- Soften the first-buffer watchdog (`MicrophoneCapture.scheduleSilentBufferWatchdog`):
  longer grace, Bluetooth-aware (a Bluetooth transport gets a longer window).
- On stall, run **bounded recovery**: restart current device (kick the route) →
  re-arm watchdog → if still nothing, `restart(advanceToNextDevice:)` toward
  built-in → re-arm → on exhaustion emit the terminal `.error` (unchanged).
- New capture events `.microphoneRecovering` / `.microphoneRecovered`
  (`MeetingAudioCaptureEvent`) so the meeting session stays alive during recovery;
  the mic track just has a short gap. Only exhaustion maps to `.error`.
- `MeetingRecordingService`: handle the new events (keep session, mark mic state,
  hold off stall detection); add a `recovering` flag to `MeetingCaptureHealth`.
- Tests: mock platform simulating zero-buffer→restart→buffer (recovers, continues)
  and zero-buffer→exhausted (`.error`, invariant intact).

### Phase 3 — Mid-recording route resilience
- Ongoing mic **heartbeat** in `MicrophoneCapture` (detect buffers *stopping* after
  they'd started — mirror `SystemAudioStream`'s 1s heartbeat / stall threshold),
  triggering the same bounded recovery.
- Make the route observers actionable: `MicrophoneEnginePlatform`'s
  `AVAudioEngineConfigurationChange` + `kAudioHardwarePropertyDefaultInputDevice`
  handlers trigger recovery instead of only logging.
- `handleSourceInterruption(.microphone)` becomes recoverable (like the existing
  `.system` branch) rather than immediately fatal.
- `MeetingRecordingFlowCoordinator.isCaptureStalled`: return false while a recovery
  is in flight (its 10s window already notes route-transition tolerance).
- Optional: a subtle "reconnecting" island cue during recovery (no new terminal
  state; recording stays `.recording`).

### Phase 4 — Tests + live-test
- `swift test` green (invariant tests unchanged; new recovery tests added).
- Build + sign + install `/Applications/Splay.app`. **Manual AirPods verification
  is required** — the real HFP route-kick can't be unit-tested.
- Update `docs/thread-state.md`; strip the TEMP click diagnostics once the
  record-button question is closed.

## Constraints / invariants to respect (from the subsystem map)

- **State-machine invariant** stays (recovery is below it). Don't add a
  `.recording → .recording` on `.captureFailed`; keep `.captureFailed` terminal —
  just fire it later.
- **Shared engine** (ADR-015): one process-wide `SharedMicrophoneStream`;
  subscriber refcounting (`decideSubscribe/UnsubscribeAction`), VPIO is **sticky**
  (don't toggle mid-session), channel-0 mono extraction under VPIO, engine
  recreated on every teardown (don't cache to "restart faster" — that's the point).
  Meeting + dictation are concurrent — a restart affects both consumers.
- **STT scheduler** (ADR-016): audio capture stays outside the STT scheduler; an
  active meeting holds a **speech-engine lease** — a recover-in-place path must not
  drop/re-acquire the lease mid-meeting (would split the meeting across engines).
  Verify lease lifecycle isn't leaked by any new failure loop.
- **ADR-019**: finalize-failed-capture must still leave recoverable partial audio
  if recovery ultimately fails.
- Tap closures run on the **render thread** — no allocation / no `await`; recovery
  orchestration runs off the render thread (lifecycle queues).

## Files (from the map)

- `Sources/MacParakeetCore/Audio/SharedMicrophoneStream.swift` — restart action, fan-out.
- `Sources/MacParakeetCore/Audio/MicrophoneEnginePlatform.swift` — restart + device chain + route observers.
- `Sources/MacParakeetCore/Audio/MicrophoneCapture.swift` — watchdog softening, heartbeat, recovery orchestration, events.
- `Sources/MacParakeetCore/Audio/MeetingAudioCaptureService.swift` — new events, mic onStall mapping.
- `Sources/MacParakeetCore/Services/MeetingRecording/MeetingRecordingService.swift` — handle recovering/recovered, health `recovering`.
- `Sources/MacParakeet/App/MeetingRecordingFlowCoordinator.swift` — stall-poll tolerance, optional pill cue.
- Tests: `MeetingAudioCaptureServiceTests`, `MeetingRecordingServiceTests`, `MeetingRecordingFlowStateMachineTests` (unchanged, verify green), new recovery tests.
