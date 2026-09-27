# Audio

> One mic engine per process, fanned out to dictation and meeting
> recording. This folder owns capture, format conversion, and on-disk
> diagnostic logging.

## Platforms

`SplayCore` builds for **macOS 14+ and iOS 18+** (the iPhone utility layer,
`docs/plans/splay-ios-utility-layer.md`). The mic engine, chunkers, storage
writer and scheduler are shared. What is macOS-only is gated with
`#if os(macOS)` rather than forked:

- `SystemAudioStream.swift` — ScreenCaptureKit; iOS records mic only, so the
  `MeetingAudioCaptureService` system-audio factory throws
  `MeetingAudioError.unsupportedPlatform` there.
- `AudioDeviceManager.swift` — Core Audio HAL (`AudioObject*`). iOS has no HAL;
  AVAudioSession owns routing. `AudioDevicePortable.swift` carries the shared
  `normalizedUID` helper and, on iOS, the `AudioDeviceID` typealias that
  `MeetingInputDeviceAttempt` keeps for API parity (the attempt chain is always
  empty on iOS).
- `MicrophoneEnginePlatform+iOS.swift` + `RecordingAudioSessionLifecycle.swift` —
  the iPhone's own `AVAudioEngineMicrophonePlatform` (`#if os(iOS)`; the Mac
  class in `MicrophoneEnginePlatform.swift` is `#if os(macOS)`, and the
  protocol, default device setter and error enum are shared there). On iOS the
  HAL default-input listener is replaced by `AVAudioSession` observers, and the session follows the Voice Memos model: **session per
  recording, engine per configuration** (the full table is in
  `docs/plans/splay-ios-utility-layer.md` § Audio session model). The category
  (`.playAndRecord`, `.default` mode, `.mixWithOthers` so a background start is
  allowed, Bluetooth HFP, speaker) is set once per process; `setActive(true)`
  runs once per recording; a rebuild while a recording is engaged touches the
  session not at all (re-activating from the background is refused with
  `'!int'`). A route change restarts the engine only when the *input port UID*
  changed — never for `reason=category` or when there was no input before, both
  of which are our own activation (the route line logs `input=a→b output=a→b
  input_changed=`); the
  engine's configuration-change notification — which on iOS means the engine has
  stopped — restarts it too; an interruption `.began` marks the session
  interrupted and `.ended`+`shouldResume` re-activates then restarts. The
  observers live for the platform's lifetime and act only while a recording is
  engaged. `stopEngine()` deactivates whenever the session is ours, engine
  running or not; a *first* start that fails after activating deactivates again
  so the pair stays balanced. Deactivation is what closes the background-audio
  window. The explicit-device setter always refuses on iOS.
- `AudioCaptureDiagnostics.swift` — device/transport labels read `session` on
  iOS so the shared log grammar stays greppable.
- `AudioFileConverter.swift` — the FFmpeg subprocess paths are macOS-only. On
  iOS `convert` and `mixToM4A` delegate to `AVFoundationAudioFileConverter`
  (below), and `isSupported` reports what AVFoundation decodes (no ogg/opus/
  mkv/webm there). The pure `ffmpegArguments` builders stay portable.
- `AVFoundationAudioFileConverter.swift` — `AudioFileConverting` with
  AVAssetReader/AVAssetWriter only. Same output contracts as FFmpeg (16 kHz
  mono Float32 WAV; mic+system → 48 kHz stereo AAC, L = mic, R = system, each
  delayed by its `MeetingSourceAlignment` offset; single input → 16 kHz mono AAC,
  32 kb/s because Apple's encoder refuses 64 kb/s at 16 kHz). Tested on macOS in
  `AVFoundationAudioFileConverterTests`; it is the iOS conversion path.

## Entry point

`SharedMicrophoneStream` — the process-wide microphone source. Every
consumer (dictation, meeting mic) calls
`subscribe(wantsVPIO:onEngineDeath:handler:)` and receives every
buffer. The stream owns engine lifecycle, VPIO arbitration, and
fan-out. There is exactly one instance per process, owned by
`AppEnvironment`.

## What's here

**Shared mic engine (the core of this folder)**
- `SharedMicrophoneStream.swift` — fan-out, VPIO state machine,
  subscriber tokens, `Diagnostics` snapshot. ADR-015 + ADR-016. When the
  platform reports an unrecoverable post-start death
  (`setUnexpectedStopHandler`), it invalidates every subscriber and fires
  their `onEngineDeath` (`shared_mic_diagnostics transition=platform_engine_dead`).
  **iOS only:** input *hints* (engine configuration changed, route change,
  interruption ended) enter `inputHint()`, where `MicrophoneInputPolicy`
  decides; the rebuild (300/800/2000 ms backoff, never fatal) is
  single-flight. The Mac platform never fires hints.
- `MicrophoneInputPolicy.swift` — iOS: **stay on the device that is
  delivering; switch only when the current one stops.** Pure, portable,
  unit-tested on the Mac. Engine down → rebuild now. Engine up → rechecks at
  +1 s / +3 s: a buffer older than 1 s (or none within 15 s of a start)
  → rebuild; buffers flowing → ignore.
- `MicrophoneEnginePlatform.swift` — the protocol, and the **Mac**
  `AVAudioEngine` wrapper: upstream MacParakeet v0.8.7's, taken whole
  (`docs/plans/upstream-mic-port.md`). Attempt chain selected (explicit) →
  System Default (**implicit, never pinned**) → built-in. Every start must
  deliver a usable buffer within 1 s (on Bluetooth/unknown transport,
  all-zero PCM does not count; an implicit Bluetooth default that times out
  gets one rebuilt retry). A default-input change is coalesced and **never
  tears down a healthy engine**. A configuration change that actually stops
  the engine starts one recovery episode (fresh engine per attempt, backoff
  0.5/1/2/4/8/16 s, probation); a 5 s callback gap or 2 s of invalid buffers
  on a running engine is a stall and recovers the same way. Silent valid
  PCM is never a failure. Exhausted → `unexpectedStopHandler` → the meeting
  mic sees engine death. Engine recreated on every teardown (so coreaudiod
  releases the VPAU aggregate device); VPIO AGC and ducking disabled.
- `MicrophoneEnginePlatform+iOS.swift` — see Platforms above.
- `AudioEngineLifecycleDiagnostics.swift` — upstream's per-operation
  `audio_engine_lifecycle` record (phase timings, attempt count, classified
  error; start/recovery always, prepare/stop only when slow). Local log
  only — Splay sends no telemetry.

**Mic consumers (each subscribes to the shared stream)**
- `AudioRecorder.swift` — dictation capture.
  `subscribe(wantsVPIO: false)`. Writes 16 kHz mono Float32 WAVs to
  `$TMPDIR/macparakeet/`. Owns the dictation diagnostic timers
  (first-buffer watchdog + recording heartbeat).
- `MicrophoneCapture.swift` — meeting microphone capture. Subscribes
  with `wantsVPIO: false` by default via `MeetingMicProcessingMode.raw`.
  VPIO modes remain available for explicit experiments, with raw fallback
  when `.vpioPreferred` cannot engage. Its first-buffer watchdog is
  **log-only and forgiving**: silence is never a failure (a cold Bluetooth
  route still waking, a quiet room, a user who walked away all just keep
  recording — no guillotine, no restart). The `stallObserver` still fires,
  but only for a *genuine* engine death (`makeEngineDeathDispatch`), not for
  a slow or silent start. Lifecycle is upstream's (v0.8.7): each start has an
  attempt ID, `stop()` is `async` and returns only once the shared
  subscription is removed, and buffer/death handlers carry a generation so a
  retired session's callbacks never reach a newer one.

**Meeting-side audio (independent of the mic stream)**
- `SystemAudioStream.swift` — meeting system audio via
  `ScreenCaptureKit` (`SCStream`). Independent of the
  `AVAudioEngine`. Has its own first-buffer watchdog. Every
  ScreenCaptureKit callback is **bounded** (upstream MacParakeet #814):
  shareable-content lookup and `startCapture` 10 s → `systemAudioCaptureFailed`,
  `stopCapture` 5 s → Stop returns anyway. A start that lands after its
  deadline is stopped again. Log: `system_audio_stream_start_timeout
  phase=shareable_content|start_capture`, `system_audio_stream_stop_timeout`,
  `system_audio_stream_late_start_stopped`.
- `MeetingAudioCaptureService.swift` — composes mic + system audio
  for meeting recording.
- `MeetingAudioStorageWriter.swift` — fragmented MP4 writer for
  meeting source files (ADR-019 crash recovery). Its finish is awaited
  for at most 10 s by `MeetingRecordingService.finalizeWriter`
  (`meeting_audio_writer_finalize_timeout`); on timeout the files are left
  as they are — never `cancelWriting()`, which deletes them.
- `MeetingAudioError.swift`, `MeetingMicProcessingMode.swift` —
  value types.

**Helpers**
- `BoundedCallback.swift` — `awaitBoundedCallback(timeout:onLate:_:)`:
  waits for a one-shot framework callback, but never past the deadline;
  a late callback goes to `onLate`. Use it for any completion handler
  that Stop or Start depends on.
- `AudioCaptureDiagnostics.swift` — public `append(_:)` (synchronous) and
  `appendAsync(_:)` (clocks captured at the call, written on a utility
  queue) to `~/Library/Logs/MacParakeet/dictation-audio.log`. Upstream
  v0.8.7's writer: a `flock` on the sibling `dictation-audio.log.lock`
  serialises writers across processes (never delete that file); at the
  5 MB cap the newest ~2.5 MB of complete lines are kept. A main-thread
  append never blocks — on contention or rotation it defers the same
  record to the queue. Used by every file in this folder and by
  `AppDelegate`'s boot marker.
- `AudioChunker.swift` — actor that buffers resampled audio for
  incremental STT (live meeting transcription).
- `MeetingLiveAudioChunking.swift`,
  `SpeechBoundaryMeetingLiveAudioChunker.swift`,
  `MeetingVADChunkingSimulator.swift` — meeting live-preview chunking
  strategies. The fixed adapter preserves the original 5s / 1s-overlap
  cadence; the VAD strategy cuts cached-model Parakeet sessions at
  speech boundaries and falls back to fixed on VAD errors.
- `AudioFileConverter.swift` — file-side converter (FFmpeg /
  AVFoundation) for file/YouTube/meeting transcription inputs.
- `AudioProcessor.swift` + `AudioProcessorProtocol.swift` — thin
  facade composing `AudioRecorder` + `AudioFileConverter` behind a
  single protocol. Useful where a caller wants both the dictation
  and file-conversion entry points behind one injection seam.
- `AudioDeviceManager.swift` — Core Audio HAL helpers (default
  device, set input on engine, list devices).
- `extractChannelZero` (in `AudioRecorder.swift`),
  `CMSampleBufferToPCMBuffer.swift`, `PCMBufferToSampleBuffer.swift`,
  `UncheckedSendableAudioPCMBuffer.swift`,
  `ObjCExceptionBridge.swift` — pure utilities.

## Cross-references

- ADR-014 — meeting recording (system + mic dual stream, ScreenCaptureKit).
- ADR-015 — concurrent dictation and meeting recording, the shared
  mic engine, and the channel-0 mono-extraction rule.
- ADR-016 — centralized STT scheduler. Audio buffers feed the
  scheduler; STT lifecycle lives in `../STT/`.
- ADR-019 — crash-resilient meeting recording; explains the
  fragmented MP4 writer + lock-file conventions in the meeting
  audio files above.
- ADR-021 — engine routing for multilingual STT. Active meetings
  hold a speech-engine lease; this folder enforces the audio side
  of that contract by keeping the meeting capture pipeline
  independent of dictation.
- `spec/05-audio-pipeline.md` — narrative spec.
- `journal/2026-05-03-dictation-silent-stall.md` — active
  regression hunt; the diagnostic logging in `AudioRecorder`,
  `SharedMicrophoneStream`, and `MicrophoneEnginePlatform` is part
  of that investigation.

## What to know before editing

**VPIO is sticky once engaged (process-wide).** Once any subscriber
requests VPIO, it stays on for the engine's lifetime. The state
machine in `SharedMicrophoneStream.decideSubscribeAction` enforces
this. Don't try to disengage VPIO mid-session — coreaudiod attaches
the VPAU aggregate device to the **process**, and toggling VPIO mid-
flight changes the input format under live subscribers.

**Channel 0 mono extraction is mandatory when VPIO is engaged.** VPIO
exposes a duplex layout (typically `ch=9`) where only ch[0] is the
post-AEC processed mono and the rest are reference channels. Use
`extractChannelZero(from:)` — never let `AVAudioConverter`'s default
channel reduction average across them. This was the bug PR #189
fixed; do not regress it.

**The `AVAudioEngine` is recreated on every teardown.** `tearDownLocked`
in `MicrophoneEnginePlatform` does `audioEngine = AVAudioEngine()`
deliberately. Releasing the old instance triggers coreaudiod to drop
the VPAU aggregate device. Long-lived engines inherit duplex layout
into sibling engines in the same process — exactly the bug PR #189
fixed. Do not optimize this away by caching the engine.

**Tap closures run on the audio render thread.** No allocation, no
actor hops, no `await`. State touched from the tap path uses
`OSAllocatedUnfairLock`-protected nonisolated fields. The buffer
passed in is valid only for the synchronous duration of the call —
copy via `copyPCMBufferForAsyncUse` before retaining or dispatching
async.

**A default-input change never tears down a healthy engine.** Do not add
code that restarts the engine because the system default moved. On the Mac
the upstream platform owns this (coalesced HAL listener, recovery only when
the engine actually stopped); on iOS route it through
`SharedMicrophoneStream.inputHint()` and `MicrophoneInputPolicy`. Restarting
a healthy engine cuts the head off the recording (AirPods auto-switching).

**Mac log grammar (upstream's).** Start:
`shared_mic_engine_input_device_started source=… routing=explicit|implicit
transport=… vpio=… set_device_ms=… start_engine_ms=…`, with
`…_input_device_retrying … reason=initial_readiness_timeout` for the one
Bluetooth retry and `…_input_device_start_failed` per failed attempt.
Default input moved: `audio_default_input_changed notifications=N` (no
rebuild). Engine reconfigured: `shared_mic_engine_configuration_changed` →
`…_config_change_recovery_{scheduled,attempt,ready,succeeded}` or
`…_failed` / `…_exhausted`; `…_configuration_change_ignored` for its own
echo. Frozen: `shared_mic_engine_callback_stalled`,
`shared_mic_engine_invalid_buffers`. Given up:
`shared_mic_diagnostics transition=platform_engine_dead` →
`meeting_mic_engine_death_stall`. Per operation: `audio_engine_lifecycle …`.
iOS keeps `shared_mic_input_hint` / `shared_mic_input_recheck` /
`shared_mic_follow_default_input`.

**When the mic dies in a meeting.** Mic-only: the recording fails
(held failure, audio kept). Mic + system: `meeting_capture_source_interrupted
source=microphone` and the recording carries on with system audio; it
fails only when both sources are gone (upstream's rule).

**Diagnostic logging is observability-only.** The first-buffer
watchdog and recording heartbeat in `AudioRecorder` log to
`dictation-audio.log` but **never** abort the recording. PR #210
shipped this deliberately; converting any of those signals into a
user-facing error would mask a regression as a fact of life.
Telemetry counters can be added separately, but the log path stays
non-disruptive.

**First-buffer can arrive before timers are armed.** When subscribing
from an actor, the AVAudioEngine tap can fire its first buffer
during the `await sharedStream.subscribe(...)` suspension, before
post-await `armCaptureDiagnostics` runs. State that tracks "have we
seen the first buffer yet" must be generation-keyed (see
`firstBufferSeenGeneration` in `AudioRecorder`) and the arming code
must check it before scheduling the watchdog. Bool flags get reset
on arm and lose the early buffer.

**Concurrent dictation and meeting recording is supported (ADR-015).**
A user can dictate while a meeting recording is active. Both flows
fan out from the same `SharedMicrophoneStream` instance. Don't add
state that assumes a single consumer at a time.

**System audio is a separate stream.** `SystemAudioStream` uses
`ScreenCaptureKit`, not `AVAudioEngine`. It does not share lifecycle,
VPIO state, or the fan-out path with the mic stream. Meeting
recording composes both via `MeetingAudioCaptureService`.

**The diagnostic log file is shared across processes.** Splay, upstream
MacParakeet builds running alongside it, and anything run with
`MACPARAKEET_AUDIO_DIAGNOSTICS_LOG_PATH` write
`~/Library/Logs/MacParakeet/dictation-audio.log` (`swift test` writes a
temp file instead). Every line ends with `process_id=… process_session=…
uptime_ns=…` — filter by `process_id`; `dictation_diagnostics_session_start`
still marks each launch. At the 5 MB cap the newest ~2.5 MB of complete
lines are kept (no longer deleted).

## How to verify a change

- `swift test --filter Audio` — covers the shared stream's state
  machine, the platform adapter, the recorder, and the diagnostic
  helpers under deterministic mocks.
- `swift test --filter SharedMicrophoneStream` — the VPIO state
  machine specifically.
- `swift test` — full suite (~100 s). Audio changes ripple into
  dictation, meeting, and STT scheduler tests.
- Dev-app smoke (the canonical happy-path check):
  1. `scripts/dev/install_local.sh`, then `open /Applications/Splay.app`.
  2. Dictate three times in sequence.
  3. Start a meeting recording.
  4. Dictate during the meeting.
  5. Stop the meeting; dictate once more.
  6. Inspect `~/Library/Logs/MacParakeet/dictation-audio.log` —
     expect clean `engine_started → first_buffer → heartbeat → stop`
     cycles for each dictation and a clean
     `meeting_mic_capture_started → meeting_mic_first_buffer →
     meeting_mic_capture_stopped` cycle for the meeting.
- After a stall report: cross-reference the user's log against the
  decision tree in PR #210's description.
