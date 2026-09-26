# Microphone input policy — stay on the device that is delivering

> Status: **HISTORICAL for macOS** (thread 18, 2026-09-26): the Mac now runs upstream MacParakeet
> v0.8.7's mic handling — see `upstream-mic-port.md`; the hint/recheck policy, the liveness watchdog
> and the explicit System Default pin described below are gone on the Mac. **Still live on iOS**
> (`MicrophoneInputPolicy` hint/recheck half, fed by AVAudioSession route/interruption hints).
>
> Original status: ACTIVE (thread 15, 2026-09-14). Owner direction: account for AirPods
> auto-switching between the iPhone and the Mac *architecturally*, in the spirit of the iOS
> session model (`splay-ios-utility-layer.md` § Audio session model).

## The measured problem (Mac, `dictation-audio.log`, Splay builds of 2026-08-11 / 08-18)

Two real mid-recording AirPods switches, both while the built-in mic was delivering:

| event | what happened | gap |
|---|---|---|
| built-in → AirPods become default (08-11 03:09:12) | `audio_default_input_changed` → `shared_mic_follow_default_input` → engine rebuilt onto the AirPods (HFP, 24 kHz) | restart 0.9 s after the notification |
| AirPods → built-in (08-11 03:09:29) | two notifications 65 ms apart → **two** restarts 80 ms apart | 0.5 s + a redundant rebuild |
| built-in → AirPods (08-18 00:24:40) | three notifications in 100 ms → **three** restarts | 0.9 s + two redundant rebuilds |

Elsewhere in the log the cold-HFP path shows up as `shared_mic_engine_input_device_start_failed
transport=bluetooth error=-10868` (15×), i.e. the 300/800/2000 ms retry ladder, up to ~3 s lost.
Thread 14's coalescing already removes the redundant rebuilds. The remaining fault is the
*policy*: a healthy engine on the built-in mic was torn down because the system's **default**
changed — the same self-inflicted head-cut the phone had, only on every switch.

Structural faults found while reading, both Mac twins of iOS faults fixed in thread 14:
1. The HAL default-input listener is **per engine instance** (installed on start, removed on
   every teardown, including the teardown inside a *failed* rebuild). After the retry ladder
   gives up, nothing can ever bring the engine back (iOS fault 4).
2. `AVAudioEngineConfigurationChange` on the Mac is **log-only**. Apple: when the I/O unit sees
   a hardware channel-count or sample-rate change the engine *stops*. A sample-rate change
   without a device change stalls a Mac recording with no recovery (iOS fault 3).

## The policy

**A default-input change is a hint. The trigger is the engine no longer delivering buffers.**

```
hint (HAL default input changed · engine configuration changed · iOS route/interruption)
  │
  ├─ engine not running ──────────────────────────────▶ restart now (existing single-flight path)
  │
  └─ engine running ──▶ arm rechecks at +1 s, +3 s
                          recheck: last buffer older than 1 s (or none since start,
                                   after the 15 s warm-up grace) ─▶ restart
                                   buffers flowing               ─▶ ignore (log), next recheck
```

Consequences on the Mac (the scenario in the brief):
- **AirPods become the default while the built-in is delivering** → ignored. No HFP, no cold
  retries, built-in quality kept. (Voice Memos follows the default; Zoom/Teams stay put. We stay
  put — the owner's recommendation.)
- **AirPods leave while recording through them** → the engine stops (configuration change,
  `engine.isRunning == false`) → restart now onto the current default (built-in). The rechecks
  are the belt for the silent-stall shape where no notification arrives.
- **AirPods come back** → hint while the built-in delivers → ignored. No second gap.
- **Failed rebuild** → the listener outlives the engine, so the next hint retries.

On iOS the same entry point applies (`RecordingAudioSessionLifecycle` still decides *which*
route changes count; the configuration change means the engine has stopped and reads as
`engine not running` → restart now, exactly today's behaviour). A route change that leaves the
engine delivering no longer restarts it — fewer head-cuts, not more.

## Pieces

| piece | where |
|---|---|
| `MicrophoneInputPolicy` — pure verdicts (`restartNow` / `recheck` / `ignore`), the warm-up grace (15 s: a cold HFP mic takes ~10 s to its first buffer), the stale threshold (1 s), the recheck schedule (+1 s, +3 s) | `SplayCore/Audio/MicrophoneInputPolicy.swift` (+ tests) |
| Stream tracks `engineStartedAt` + `lastBufferAt` (written in `deliverBuffer` under the existing lock); `inputHint()` replaces the unconditional follow; single-flight restart path unchanged | `SharedMicrophoneStream.swift` |
| Mac: HAL listener for the platform's lifetime; configuration change checks `engine.isRunning`, tears down a stopped engine and fires the hint; log line gains `engine_is_running=` and `default_input_id=`. iOS: configuration change and interruption `.began` tear the engine down too, so the hint that follows reads `engine down` → restart now | `MicrophoneEnginePlatform.swift`, `AudioCaptureDiagnostics.swift` |
| Log grammar: `shared_mic_input_hint engine_running=… verdict=restart_now\|recheck\|ignore [after_ms=… coalesced=…]`, `shared_mic_input_recheck n=… reason=alive\|stopped\|engine_down\|warming\|never_delivered action=restart\|ignore\|recheck after_ms=…`; `shared_mic_follow_default_input*` keeps its name for the restart itself | both |
| README § What's here / § What to know | `SplayCore/Audio/README.md` |

Not in this slice: a free-running silence watchdog (would fight the ~10 s cold-HFP warm-up
that dead ≠ silent protects); the island's amber stays visual-only.

## Verification

- Unit: policy verdicts; stream — hint while delivering → no restart; hint then buffers stop →
  restart at the recheck; hint with engine down → immediate restart; hint inside the warm-up
  grace with no buffer yet → no restart; the chain is voided when the stream goes idle.
- Real platform: `MACPARAKEET_HAL_MUTATION_TESTS=1` switch test additionally asserts
  `engineRestartCount == 0` — buffers kept flowing on the original device, so the policy stayed
  put (the switch is between built-in and a virtual device here; AirPods on the owner).
- Owner: record with AirPods, pull a notification on the phone, read the log: expect
  `shared_mic_input_hint … verdict=recheck` → `shared_mic_input_recheck … reason=alive action=ignore`
  on the way out and back, and one `restart_now` only if the AirPods were the recording device.
