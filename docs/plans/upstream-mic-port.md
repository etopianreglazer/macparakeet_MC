# Upstream mic handling — adopt MacParakeet 0.8.7's approach (macOS)

> Status: **BRIEF — check and refine before starting** (written end of thread 17, 2026-09-26).
> Supersedes the "keep the explicit System Default pin" decision in `upstream-087-port.md` and the
> policy in `mac-input-policy.md` for **macOS**. iOS keeps today's behaviour.

## Why

Owner, thread 17, asked to press the AirPods measurement: *"can we just go for what the original
MacParakeet does and just stop forcing our own approach … steal it, build it in, test it."* Splay kept
upstream's one-release System Default pin (fork point `20f4daac` *is* the pin commit; upstream reverted
it in 0.6.18, `cd335310`/`e7742e86`) and grew its own policy on top (hint/recheck, liveness watchdog,
implicit-route fallback). Upstream solved the same problems differently over ~12 PRs. Take theirs.

## What upstream 0.8.7 does (tag `v0.8.7`, `Sources/MacParakeetCore/Audio/`)

- **Route:** selected device (explicit) → System Default **implicit, never pinned** → built-in
  (`MicrophoneCapture.swift:77-105`; prewarm stays implicit, `MicrophoneEnginePlatform.swift:611-618`).
- **Start gate:** every start must deliver a usable buffer within 1 s (`:495`); on Bluetooth/unknown
  transport all-zero PCM does not count (`:1049`). An implicit Bluetooth default that times out gets
  one rebuilt retry (`:1099-1135`, `…_retrying … reason=initial_readiness_timeout`). A default change
  mid-start cancels that start (`:1754-1770`).
- **Default-input change (HAL):** coalesced (≤0.1 s), logs `audio_default_input_changed notifications=N`;
  **never tears down a healthy running engine** (`:2152-2214`).
- **Configuration change:** ignores its own prepare echo; recovers only if the current engine actually
  stopped while a start is active (`:1643-1724`, `:1787-1794`).
- **Freeze:** 1 s liveness tick; 5 s callback gap → `shared_mic_engine_callback_stalled`; 2 s of
  invalid buffers → `…invalid_buffers`. Silent valid PCM is never a failure (`df01ce80`).
- **Recovery:** one episode, fresh engine per attempt, backoff 0.5/1/2/4/8/16 s (~31 s), probation
  window; exhausted → `unexpectedStopHandler` → `platform_engine_dead` → meeting sees a stall.
- **Silent start:** 2 s no buffer → stall observer (`MicrophoneCapture.swift:590-630`).

## What changes in Splay (macOS)

- Replace with upstream's version: `MicrophoneEnginePlatform.swift` (2,259 lines — upstream has no
  `#if os`; re-wrap Splay's iOS AVAudioSession block `:362-404`, `:672-818` in `#if os(iOS)` and
  upstream's HAL/Bluetooth/`AudioDeviceManager` calls in `#if os(macOS)`), `SharedMicrophoneStream.swift`,
  `MicrophoneCapture.swift` (async `stop()` → every caller changes), `AudioDeviceManager.swift`
  (`bluetoothInputState`, `resolvedTransportType`).
- New from upstream: `AudioEngineLifecycleDiagnostics.swift`, `DiagnosticLogScope.swift`,
  `AudioCaptureDiagnostics.appendAsync`, `UncheckedSendableAudioEngine.wraps/isEngineRunning()`.
- Remove on macOS: the pin (`MicrophoneCapture.swift:93-97`), `skipExplicitSystemDefaultOnce`,
  the liveness watchdog, `MicrophoneInputPolicy` hint/recheck path.
- **iOS (must not regress):** route-change/interruption observers feed `inputHint` → `onHint/onRecheck`
  → `restart()`. Either keep that path under `#if os(iOS)` (with `MicrophoneInputPolicy`'s hint half
  and `RecordingAudioSessionLifecycle`) or route iOS into upstream's recovery episode. **Recommend:
  keep it, iOS-gated** — upstream has no iOS model to copy. Compile-check iOS `SplayCore` after.
- Check `MeetingAudioCaptureService` / `AudioRecorder` against upstream for the engine-death/stall
  consumers. `MeetingMicHealthMonitor` (upstream #523, detection-only) is optional — skip first pass.
- Tests: delete `MicrophoneInputPolicyTests`, the follow/hint/recheck/liveness block of
  `SharedMicrophoneStreamTests` (467-696 + setup/mock), pin/skip tests in `MicrophoneCaptureTests`,
  `engineRestartCount` asserts in `MicrophoneEngineRealPlatformTests`; port upstream's
  `MicrophoneEnginePlatformConfigChangeRecoveryTests`, `…StartupReadinessTests`,
  `…PrewarmRoutingTests`, `MutableMicrophoneTapHandlerTests`.
- Docs: `Sources/SplayCore/Audio/README.md` (log grammar), mark `mac-input-policy.md` HISTORICAL.

## Check / refine before starting

1. Confirm with the owner: iOS keeps its current path (recommended) — no iOS behaviour change.
2. Diff Splay's `Audio/` against `v0.8.7` once more for Splay-only fixes that must survive (bounded
   ScreenCaptureKit calls `5a95b210`, the dead-≠-silent writer-health signal feeding the island amber,
   `audioAlive`). The island's amber depends on `MeetingRecordingFlowCoordinator.updateAudioAliveness`,
   not on the removed watchdog — verify it still fires.
3. Commit in slices: (a) platform + stream + capture swap with tests green, (b) removals, (c) docs.

## Press after install (owner)

Plain tap; double-tap; **AirPods:** record on the built-in mic with AirPods connected, pull a phone
notification so they switch away/back → expect `audio_default_input_changed` and **no** engine rebuild;
record *through* AirPods and move them to the phone → expect `shared_mic_engine_configuration_changed`
→ `config_change_recovery_attempt` → `…_succeeded` on the built-in mic, bars keep moving, no gap.
Silence in a quiet room must never produce a stall line.
