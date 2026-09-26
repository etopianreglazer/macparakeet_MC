import AVFoundation
import CoreAudio
import XCTest
@testable import SplayCore

final class MicrophoneCaptureTests: XCTestCase {
    func testSubscribesWithVPIOForVPIOPreferred() async throws {
        let platform = SharedMicTestPlatform()
        let stream = SharedMicrophoneStream(platform: platform, bufferSize: 1024)
        let capture = MicrophoneCapture(
            sharedStream: stream,
            permissionProvider: { true }
        )

        let report = try await capture.start(
            processingMode: .vpioPreferred,
            handler: { _, _ in },
            onStall: nil
        )
        addTeardownBlock { await capture.stop() }

        XCTAssertEqual(report.requestedMode, .vpioPreferred)
        XCTAssertEqual(report.effectiveMode, .vpio)
        XCTAssertEqual(platform.configureAndStartCalls.count, 1)
        XCTAssertEqual(platform.configureAndStartCalls.first?.vpioEnabled, true)
        XCTAssertTrue(stream.diagnostics.engineRunning)
    }

    func testSharedModeSubscribesRawForRawProcessing() async throws {
        let platform = SharedMicTestPlatform()
        let stream = SharedMicrophoneStream(platform: platform, bufferSize: 1024)
        let capture = MicrophoneCapture(
            sharedStream: stream,
            permissionProvider: { true }
        )

        let report = try await capture.start(
            processingMode: .raw,
            handler: { _, _ in },
            onStall: nil
        )
        addTeardownBlock { await capture.stop() }

        XCTAssertEqual(report.effectiveMode, .raw)
        XCTAssertEqual(platform.configureAndStartCalls.first?.vpioEnabled, false)
    }

    func testSharedModeForwardsBuffersToHandler() async throws {
        let platform = SharedMicTestPlatform()
        let stream = SharedMicrophoneStream(platform: platform, bufferSize: 1024)
        let capture = MicrophoneCapture(
            sharedStream: stream,
            permissionProvider: { true }
        )
        let counter = MicrophoneCaptureTestCounter()

        _ = try await capture.start(
            processingMode: .vpioPreferred,
            handler: { _, _ in counter.increment() },
            onStall: nil
        )
        addTeardownBlock { await capture.stop() }

        let buffer = makeSharedTestBuffer()
        let time = AVAudioTime(hostTime: 0)
        platform.deliverBuffer(buffer, time: time)
        platform.deliverBuffer(buffer, time: time)

        XCTAssertEqual(counter.value, 2)
    }

    // MARK: - First-buffer patience (silence is never a failure)

    /// A start that delivers no buffers — cold Bluetooth route still waking, a
    /// quiet room, a user who walked away — must NOT fail and must NOT restart
    /// the engine. Silence is forgiven: no stall is surfaced and there is
    /// exactly one engine start (the fragile "kick" that rebuilt onto a
    /// not-yet-ready device is gone). Genuine engine death still stalls — see
    /// `testSharedModeEngineDeathSurfacesAsStall`.
    func testZeroBufferStartIsForgivenWithNoStallAndNoRestart() async throws {
        let platform = SharedMicTestPlatform()
        let stream = SharedMicrophoneStream(platform: platform, bufferSize: 1024)
        let capture = MicrophoneCapture(
            sharedStream: stream,
            permissionProvider: { true },
            firstBufferGrace: 0.05
        )
        let stallBox = MicrophoneCaptureTestStallBox()
        _ = try await capture.start(
            processingMode: .raw,
            handler: { _, _ in },
            onStall: { error in stallBox.record(error) }
        )
        addTeardownBlock { await capture.stop() }

        // Let the first-buffer grace elapse with no buffer delivered.
        try await Task.sleep(for: .milliseconds(250))

        XCTAssertNil(
            stallBox.recordedError,
            "Silence must never be flagged as a failure."
        )
        XCTAssertEqual(
            platform.configureAndStartCalls.count, 1,
            "No restart 'kick': the patient watchdog only logs, it never rebuilds the engine."
        )
    }

    func testSharedModeVPIOForwardsChannelZeroOnly() async throws {
        let platform = SharedMicTestPlatform()
        let stream = SharedMicrophoneStream(platform: platform, bufferSize: 1024)
        let capture = MicrophoneCapture(
            sharedStream: stream,
            permissionProvider: { true }
        )
        let snapshotBox = MicrophoneCaptureTestBufferSnapshotBox()

        _ = try await capture.start(
            processingMode: .vpioPreferred,
            handler: { buffer, _ in snapshotBox.record(buffer) },
            onStall: nil
        )
        addTeardownBlock { await capture.stop() }

        let buffer = try makeSharedMultiChannelFloatBuffer(channels: 4, frames: 16) { channel, frame in
            channel == 0 ? Float(frame) + 0.25 : Float((channel + 1) * 100 + frame)
        }
        platform.deliverBuffer(buffer, time: AVAudioTime(hostTime: 0))

        let snapshot = try XCTUnwrap(snapshotBox.snapshot)
        XCTAssertEqual(snapshot.channelCount, 1)
        XCTAssertEqual(snapshot.samplesByChannel.count, 1)
        for frame in 0..<16 {
            XCTAssertEqual(snapshot.samplesByChannel[0][frame], Float(frame) + 0.25, accuracy: 0.0001)
        }
    }

    func testSharedModeRawPreservesMultiChannelBuffers() async throws {
        let platform = SharedMicTestPlatform()
        let stream = SharedMicrophoneStream(platform: platform, bufferSize: 1024)
        let capture = MicrophoneCapture(
            sharedStream: stream,
            permissionProvider: { true }
        )
        let snapshotBox = MicrophoneCaptureTestBufferSnapshotBox()

        _ = try await capture.start(
            processingMode: .raw,
            handler: { buffer, _ in snapshotBox.record(buffer) },
            onStall: nil
        )
        addTeardownBlock { await capture.stop() }

        let buffer = try makeSharedMultiChannelFloatBuffer(channels: 4, frames: 8) { channel, frame in
            Float((channel + 1) * 100 + frame)
        }
        platform.deliverBuffer(buffer, time: AVAudioTime(hostTime: 0))

        let snapshot = try XCTUnwrap(snapshotBox.snapshot)
        XCTAssertEqual(snapshot.channelCount, 4)
        XCTAssertEqual(snapshot.samplesByChannel.count, 4)
        XCTAssertEqual(snapshot.samplesByChannel[0][3], 103, accuracy: 0.0001)
        XCTAssertEqual(snapshot.samplesByChannel[3][3], 403, accuracy: 0.0001)
    }

    func testSharedModeVPIOPreferredFallsBackToRawWhenSubscribeThrows() async throws {
        let platform = SharedMicTestPlatform()
        platform.configureAndStartError = MicrophoneCaptureMockError.simulatedFailure
        let stream = SharedMicrophoneStream(platform: platform, bufferSize: 1024)
        let capture = MicrophoneCapture(
            sharedStream: stream,
            permissionProvider: { true }
        )

        // Failure on the first attempt (VPIO). Clear the error so the raw
        // retry succeeds.
        platform.configureAndStartError = nil
        platform.failNextStartCount = 1

        let report = try await capture.start(
            processingMode: .vpioPreferred,
            handler: { _, _ in },
            onStall: nil
        )
        addTeardownBlock { await capture.stop() }

        XCTAssertEqual(report.effectiveMode, .raw, "vpioPreferred falls back to raw when VPIO subscribe fails")
        XCTAssertGreaterThanOrEqual(platform.configureAndStartCalls.count, 2, "Both vpio and raw subscribe attempts occur")
        XCTAssertEqual(platform.configureAndStartCalls.last?.vpioEnabled, false, "Final attempt must be the raw retry")
    }

    func testSharedModeVPIORequiredThrowsOnSubscribeFailure() async {
        let platform = SharedMicTestPlatform()
        platform.configureAndStartError = MicrophoneCaptureMockError.simulatedFailure
        let stream = SharedMicrophoneStream(platform: platform, bufferSize: 1024)
        let capture = MicrophoneCapture(
            sharedStream: stream,
            permissionProvider: { true }
        )

        do {
            _ = try await capture.start(
                processingMode: .vpioRequired,
                handler: { _, _ in },
                onStall: nil
            )
            XCTFail("vpioRequired must throw when VPIO can't engage")
        } catch MeetingAudioError.microphoneProcessingUnavailable(let mode, _) {
            XCTAssertEqual(mode, .vpioRequired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(stream.diagnostics.subscriberCount, 0)
    }

    func testSharedModeVPIORequiredThrowsWhenEngagementIsDeferred() async throws {
        let platform = SharedMicTestPlatform()
        let stream = SharedMicrophoneStream(platform: platform, bufferSize: 1024)
        let capture = MicrophoneCapture(
            sharedStream: stream,
            permissionProvider: { true }
        )
        let blocker = try await stream.subscribe(wantsVPIO: false) { _, _ in }

        do {
            _ = try await capture.start(
                processingMode: .vpioRequired,
                handler: { _, _ in },
                onStall: nil
            )
            XCTFail("vpioRequired must throw when VPIO engagement is deferred by an active raw subscriber")
        } catch MeetingAudioError.microphoneProcessingUnavailable(let mode, let reason) {
            XCTAssertEqual(mode, .vpioRequired)
            XCTAssertTrue(reason.contains("deferred"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let diag = stream.diagnostics
        XCTAssertEqual(diag.subscriberCount, 1, "Only the raw blocker should remain subscribed")
        XCTAssertFalse(diag.vpioEngaged)
        XCTAssertFalse(diag.vpioDeferred)

        await stream.unsubscribe(blocker)
    }

    func testSharedModeThrowsPermissionDeniedWhenProviderFalse() async {
        let platform = SharedMicTestPlatform()
        let stream = SharedMicrophoneStream(platform: platform, bufferSize: 1024)
        let capture = MicrophoneCapture(
            sharedStream: stream,
            permissionProvider: { false }
        )

        do {
            _ = try await capture.start(
                processingMode: .raw,
                handler: { _, _ in },
                onStall: nil
            )
            XCTFail("Expected microphonePermissionDenied")
        } catch MeetingAudioError.microphonePermissionDenied {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(platform.configureAndStartCalls.count, 0, "Permission gate must short-circuit before any platform call")
    }

    func testSharedModeStopDuringSubscribeUnsubscribesOrphanToken() async throws {
        // Race scenario: `stop()` is called while `start()` is awaiting
        // `subscribe`. The post-subscribe state re-check must detect that
        // the lifecycle left `.starting(attemptID)` and unsubscribe the just-issued
        // token so the shared stream isn't left with a live subscriber that
        // nobody owns. Without the guard, the engine would stay running with
        // an orphan handler attached.
        let platform = SharedMicTestPlatform()
        let arrived = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        platform.configureAndStartHook = {
            arrived.signal()
            release.wait()
        }
        let stream = SharedMicrophoneStream(platform: platform, bufferSize: 1024)
        let capture = MicrophoneCapture(
            sharedStream: stream,
            permissionProvider: { true }
        )

        let startTask = Task {
            try await capture.start(
                processingMode: .raw,
                handler: { _, _ in },
                onStall: nil
            )
        }

        XCTAssertEqual(arrived.wait(timeout: .now() + 5), .success, "Mock platform should have been entered")
        // stop() runs while subscribe is paused inside the platform.
        let stopTask = Task { await capture.stop() }
        // Let subscribe complete. start's post-subscribe re-check must now
        // detect the missing .starting state and clean up.
        release.signal()

        do {
            _ = try await startTask.value
            XCTFail("start() should throw when stop ran during subscribe")
        } catch MeetingAudioError.audioEngineStartFailed {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        await stopTask.value

        XCTAssertEqual(stream.diagnostics.subscriberCount, 0, "Orphan token must be unsubscribed")
        XCTAssertFalse(stream.diagnostics.engineRunning, "Engine must be stopped after orphan cleanup")
    }

    func testStopReturnsOnlyAfterSharedSubscriptionIsRemoved() async throws {
        let platform = SharedMicTestPlatform()
        let stopEntered = DispatchSemaphore(value: 0)
        let releaseStop = DispatchSemaphore(value: 0)
        platform.stopEngineHook = {
            stopEntered.signal()
            releaseStop.wait()
        }
        let stream = SharedMicrophoneStream(platform: platform, bufferSize: 1024)
        let capture = MicrophoneCapture(
            sharedStream: stream,
            permissionProvider: { true }
        )
        _ = try await capture.start(
            processingMode: .raw,
            handler: { _, _ in },
            onStall: nil
        )

        let stopCompleted = MicrophoneCaptureTestCounter()
        let stopReturned = DispatchSemaphore(value: 0)
        let stopTask = Task {
            await capture.stop()
            stopCompleted.increment()
            stopReturned.signal()
        }

        XCTAssertEqual(stopEntered.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(
            stopReturned.wait(timeout: .now() + 0.05),
            .timedOut,
            "Stop must await physical subscription teardown"
        )

        releaseStop.signal()
        await stopTask.value

        XCTAssertEqual(stream.diagnostics.subscriberCount, 0)
        XCTAssertFalse(stream.diagnostics.engineRunning)
        XCTAssertEqual(stopCompleted.value, 1)
    }

    func testStoppedStartCannotClaimReplacementSession() async throws {
        let platform = SharedMicTestPlatform()
        let firstConfigureEntered = DispatchSemaphore(value: 0)
        let releaseFirstConfigure = DispatchSemaphore(value: 0)
        let configureCount = MicrophoneCaptureTestCounter()
        platform.configureAndStartHook = {
            guard configureCount.incrementAndGet() == 1 else { return }
            firstConfigureEntered.signal()
            releaseFirstConfigure.wait()
        }
        let stream = SharedMicrophoneStream(platform: platform, bufferSize: 1024)
        let capture = MicrophoneCapture(
            sharedStream: stream,
            permissionProvider: { true }
        )
        let firstSessionBuffers = MicrophoneCaptureTestCounter()
        let replacementSessionBuffers = MicrophoneCaptureTestCounter()

        let firstStart = Task {
            try await capture.start(
                processingMode: .raw,
                handler: { _, _ in firstSessionBuffers.increment() },
                onStall: nil
            )
        }
        XCTAssertEqual(
            firstConfigureEntered.wait(timeout: .now() + 5),
            .success,
            "the first subscription should be suspended inside engine start"
        )

        let stopTask = Task { await capture.stop() }
        try await Task.sleep(for: .milliseconds(10))
        let replacementStart = Task {
            try await capture.start(
                processingMode: .raw,
                handler: { _, _ in replacementSessionBuffers.increment() },
                onStall: nil
            )
        }
        releaseFirstConfigure.signal()

        do {
            _ = try await firstStart.value
            XCTFail("the stopped start attempt must not claim the replacement session")
        } catch MeetingAudioError.audioEngineStartFailed {
            // Expected.
        }
        await stopTask.value
        _ = try await replacementStart.value
        addTeardownBlock { await capture.stop() }

        let orphanSettled = await waitUntil(timeoutSeconds: 1) {
            stream.diagnostics.subscriberCount == 1
        }
        XCTAssertTrue(orphanSettled)
        XCTAssertTrue(stream.diagnostics.engineRunning)

        platform.deliverBuffer(makeSharedTestBuffer(), time: AVAudioTime(hostTime: 0))
        XCTAssertEqual(firstSessionBuffers.value, 0)
        XCTAssertEqual(replacementSessionBuffers.value, 1)
    }

    func testSharedModeEngineDeathSurfacesAsStall() async throws {
        // When a deferred-VPIO promotion fails, MicrophoneCapture must
        // forward the engine-death notification to its `onStall` observer.
        let platform = SharedMicTestPlatform()
        let stream = SharedMicrophoneStream(platform: platform, bufferSize: 1024)
        let capture = MicrophoneCapture(
            sharedStream: stream,
            permissionProvider: { true }
        )
        let stallBox = MicrophoneCaptureTestStallBox()

        // Pre-seed a non-VPIO blocker so the capture's VPIO subscribe gets deferred.
        let blockerToken = try await stream.subscribe(wantsVPIO: false) { _, _ in }
        defer { Task { await stream.unsubscribe(blockerToken) } }

        _ = try await capture.start(
            processingMode: .vpioPreferred,
            handler: { _, _ in },
            onStall: { error in stallBox.record(error) }
        )
        addTeardownBlock { await capture.stop() }
        XCTAssertTrue(stream.diagnostics.vpioDeferred)

        // Make the deferred promotion fail when the blocker leaves.
        platform.configureAndStartError = MicrophoneCaptureMockError.simulatedFailure
        await stream.unsubscribe(blockerToken)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNotNil(stallBox.recordedError, "Engine death must reach onStall")
    }

    func testInputDeviceAttemptsPreferSelectedThenDefaultThenBuiltIn() {
        let attempts = meetingInputDeviceAttempts(
            selectedUID: "usb-mic",
            selectedInputDeviceID: { uid in uid == "usb-mic" ? AudioDeviceID(10) : nil },
            defaultInputDevice: { AudioDeviceID(20) },
            builtInMicrophone: { AudioDeviceID(30) }
        )

        XCTAssertEqual(
            attempts,
            [
                MeetingInputDeviceAttempt(source: .selected(uid: "usb-mic"), deviceID: 10),
                .implicitSystemDefault(resolvedDeviceID: 20),
                MeetingInputDeviceAttempt(source: .builtIn, deviceID: 30),
            ]
        )
    }

    func testInputDeviceAttemptsSkipMissingSelectedDevice() {
        let attempts = meetingInputDeviceAttempts(
            selectedUID: "missing-mic",
            selectedInputDeviceID: { _ in nil },
            defaultInputDevice: { AudioDeviceID(20) },
            builtInMicrophone: { AudioDeviceID(30) }
        )

        XCTAssertEqual(
            attempts,
            [
                .implicitSystemDefault(resolvedDeviceID: 20),
                MeetingInputDeviceAttempt(source: .builtIn, deviceID: 30),
            ]
        )
    }

    func testSystemDefaultSelectionPinsResolvedDefaultBeforeImplicitFallback() {
        let attempts = meetingInputDeviceAttempts(
            selectedUID: nil,
            selectedInputDeviceID: { _ in nil },
            defaultInputDevice: { AudioDeviceID(20) },
            builtInMicrophone: { AudioDeviceID(30) }
        )

        XCTAssertEqual(
            attempts,
            [
                MeetingInputDeviceAttempt(source: .systemDefault, deviceID: 20),
                .implicitSystemDefault(resolvedDeviceID: 20),
                MeetingInputDeviceAttempt(source: .builtIn, deviceID: 30),
            ]
        )
        XCTAssertFalse(attempts[0].usesImplicitSystemDefault)
        XCTAssertTrue(attempts[1].usesImplicitSystemDefault)
        XCTAssertEqual(attempts[0].explicitDeviceID, 20)
        XCTAssertNil(attempts[1].explicitDeviceID)
    }

    func testInputDeviceAttemptsDeduplicateDefaultAndBuiltIn() {
        let attempts = meetingInputDeviceAttempts(
            selectedUID: nil,
            selectedInputDeviceID: { _ in nil },
            defaultInputDevice: { AudioDeviceID(30) },
            builtInMicrophone: { AudioDeviceID(30) }
        )

        XCTAssertEqual(
            attempts,
            [
                MeetingInputDeviceAttempt(source: .systemDefault, deviceID: 30),
                .implicitSystemDefault(resolvedDeviceID: 30),
            ]
        )
    }

    func testInputDeviceAttemptsCanUseBuiltInWhenDefaultMissing() {
        let attempts = meetingInputDeviceAttempts(
            selectedUID: nil,
            selectedInputDeviceID: { _ in nil },
            defaultInputDevice: { nil },
            builtInMicrophone: { AudioDeviceID(30) }
        )

        XCTAssertEqual(
            attempts,
            [
                .implicitSystemDefault(resolvedDeviceID: nil),
                MeetingInputDeviceAttempt(source: .builtIn, deviceID: 30),
            ]
        )
    }

    func testSystemDefaultAttemptUsesImplicitEngineRouting() {
        let attempts = meetingInputDeviceAttempts(
            selectedUID: "usb-mic",
            selectedInputDeviceID: { uid in uid == "usb-mic" ? AudioDeviceID(10) : nil },
            defaultInputDevice: { AudioDeviceID(10) },
            builtInMicrophone: { nil }
        )

        XCTAssertEqual(
            attempts,
            [
                MeetingInputDeviceAttempt(source: .selected(uid: "usb-mic"), deviceID: 10),
                .implicitSystemDefault(resolvedDeviceID: 10),
            ]
        )
        XCTAssertFalse(attempts[0].usesImplicitSystemDefault)
        XCTAssertTrue(attempts[1].usesImplicitSystemDefault)
        XCTAssertEqual(attempts[0].explicitDeviceID, 10)
        XCTAssertNil(attempts[1].explicitDeviceID)
    }

    func testExplicitSystemDefaultAttemptCanStillPinDevice() {
        let attempt = MeetingInputDeviceAttempt(source: .systemDefault, deviceID: 20)

        XCTAssertFalse(attempt.usesImplicitSystemDefault)
        XCTAssertEqual(attempt.explicitDeviceID, 20)
    }

    func testPlatformSkipsInputDeviceSetterForImplicitSystemDefaultAttempt() throws {
        let recorder = MicrophoneCaptureInputDeviceSetterRecorder()
        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [
                    MeetingInputDeviceAttempt(source: .selected(uid: "usb-mic"), deviceID: 10),
                    .implicitSystemDefault(resolvedDeviceID: 20),
                    MeetingInputDeviceAttempt(source: .builtIn, deviceID: 30),
                ]
            },
            inputDeviceSetter: { deviceID, _ in
                recorder.record(deviceID)
                return false
            },
            engineStarter: { _, _, _, _ in }
        )

        try platform.configureAndStart(
            vpioEnabled: false,
            bufferSize: 1024,
            tapHandler: { _, _ in }
        )
        defer { platform.stopEngine() }

        XCTAssertEqual(recorder.deviceIDs, [10])
        XCTAssertEqual(platform.lastSucceededAttempt, .implicitSystemDefault(resolvedDeviceID: 20))
    }

    /// The explicit System Default pin started but never delivered (the failure
    /// upstream reverted the pin for): the next start skips it once and uses the
    /// implicit route; the start after that pins again.
    func testPlatformSkipsExplicitDefaultOnceAfterNeverDelivered() throws {
        let recorder = MicrophoneCaptureInputDeviceSetterRecorder()
        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [
                    MeetingInputDeviceAttempt(source: .systemDefault, deviceID: 20),
                    .implicitSystemDefault(resolvedDeviceID: 20),
                ]
            },
            inputDeviceSetter: { deviceID, _ in
                recorder.record(deviceID)
                return true
            },
            engineStarter: { _, _, _, _ in }
        )
        defer { platform.stopEngine() }

        try platform.configureAndStart(vpioEnabled: false, bufferSize: 1024, tapHandler: { _, _ in })
        XCTAssertEqual(platform.lastSucceededAttempt, MeetingInputDeviceAttempt(source: .systemDefault, deviceID: 20))

        platform.noteCurrentEngineNeverDelivered()
        try platform.configureAndStart(vpioEnabled: false, bufferSize: 1024, tapHandler: { _, _ in })
        XCTAssertEqual(platform.lastSucceededAttempt, .implicitSystemDefault(resolvedDeviceID: 20))

        try platform.configureAndStart(vpioEnabled: false, bufferSize: 1024, tapHandler: { _, _ in })
        XCTAssertEqual(platform.lastSucceededAttempt, MeetingInputDeviceAttempt(source: .systemDefault, deviceID: 20))
        XCTAssertEqual(recorder.deviceIDs, [20, 20], "only the two pinned starts set the device")
    }

    func testNeverDeliveredOnImplicitRouteChangesNothing() throws {
        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [
                    MeetingInputDeviceAttempt(source: .selected(uid: "usb-mic"), deviceID: 10),
                    .implicitSystemDefault(resolvedDeviceID: 20),
                ]
            },
            inputDeviceSetter: { _, _ in true },
            engineStarter: { _, _, _, _ in }
        )
        defer { platform.stopEngine() }

        try platform.configureAndStart(vpioEnabled: false, bufferSize: 1024, tapHandler: { _, _ in })
        platform.noteCurrentEngineNeverDelivered()
        try platform.configureAndStart(vpioEnabled: false, bufferSize: 1024, tapHandler: { _, _ in })

        XCTAssertEqual(
            platform.lastSucceededAttempt,
            MeetingInputDeviceAttempt(source: .selected(uid: "usb-mic"), deviceID: 10),
            "a user-selected device is never skipped"
        )
    }

    func testPlatformFallsBackToImplicitSystemDefaultWhenExplicitDefaultSetFails() throws {
        let recorder = MicrophoneCaptureInputDeviceSetterRecorder()
        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [
                    MeetingInputDeviceAttempt(source: .systemDefault, deviceID: 20),
                    .implicitSystemDefault(resolvedDeviceID: 20),
                ]
            },
            inputDeviceSetter: { deviceID, _ in
                recorder.record(deviceID)
                return false
            },
            engineStarter: { _, _, _, _ in }
        )

        try platform.configureAndStart(
            vpioEnabled: false,
            bufferSize: 1024,
            tapHandler: { _, _ in }
        )
        defer { platform.stopEngine() }

        XCTAssertEqual(recorder.deviceIDs, [20])
        XCTAssertEqual(platform.lastSucceededAttempt, .implicitSystemDefault(resolvedDeviceID: 20))
    }

    func testPlatformFallsBackToImplicitSystemDefaultWhenExplicitDefaultStartFails() throws {
        let recorder = MicrophoneCaptureInputDeviceSetterRecorder()
        let startAttempts = MicrophoneCaptureTestCounter()
        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [
                    MeetingInputDeviceAttempt(source: .systemDefault, deviceID: 20),
                    .implicitSystemDefault(resolvedDeviceID: 20),
                ]
            },
            inputDeviceSetter: { deviceID, _ in
                recorder.record(deviceID)
                return true
            },
            engineStarter: { _, _, _, _ in
                startAttempts.increment()
                if startAttempts.value == 1 {
                    throw MicrophoneCaptureMockError.simulatedFailure
                }
            }
        )

        try platform.configureAndStart(
            vpioEnabled: false,
            bufferSize: 1024,
            tapHandler: { _, _ in }
        )
        defer { platform.stopEngine() }

        XCTAssertEqual(recorder.deviceIDs, [20])
        XCTAssertEqual(startAttempts.value, 2)
        XCTAssertEqual(platform.lastSucceededAttempt, .implicitSystemDefault(resolvedDeviceID: 20))
    }

    private func waitUntil(
        timeoutSeconds: TimeInterval,
        pollInterval: Duration = .milliseconds(25),
        condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        repeat {
            if condition() { return true }
            try? await Task.sleep(for: pollInterval)
        } while Date() < deadline
        return condition()
    }

    private func makeSharedTestBuffer() -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256)!
        buffer.frameLength = 256
        return buffer
    }

    private func makeSharedMultiChannelFloatBuffer(
        channels: AVAudioChannelCount,
        frames: AVAudioFrameCount,
        fill: (_ channel: Int, _ frame: Int) -> Float
    ) throws -> AVAudioPCMBuffer {
        let layoutTag = AudioChannelLayoutTag(kAudioChannelLayoutTag_DiscreteInOrder) | channels
        let layout = try XCTUnwrap(AVAudioChannelLayout(layoutTag: layoutTag))
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            interleaved: false,
            channelLayout: layout
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let data = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(frames) {
                data[channel][frame] = fill(channel, frame)
            }
        }
        return buffer
    }
}

// MARK: - Test doubles for shared-stream path

private enum MicrophoneCaptureMockError: Error, Equatable {
    case simulatedFailure
}

private final class MicrophoneCaptureInputDeviceSetterRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var deviceIDsLocked: [AudioDeviceID] = []

    var deviceIDs: [AudioDeviceID] {
        lock.withLock { deviceIDsLocked }
    }

    func record(_ deviceID: AudioDeviceID) {
        lock.withLock {
            deviceIDsLocked.append(deviceID)
        }
    }
}

private final class MicrophoneCaptureTestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    func increment() { lock.withLock { _value += 1 } }
    func incrementAndGet() -> Int {
        lock.withLock {
            _value += 1
            return _value
        }
    }
    var value: Int { lock.withLock { _value } }
}

private struct MicrophoneCaptureTestBufferSnapshot {
    let channelCount: AVAudioChannelCount
    let samplesByChannel: [[Float]]
}

private final class MicrophoneCaptureTestBufferSnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _snapshot: MicrophoneCaptureTestBufferSnapshot?

    func record(_ buffer: AVAudioPCMBuffer) {
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        let samplesByChannel: [[Float]]
        if let data = buffer.floatChannelData {
            samplesByChannel = (0..<channelCount).map { channel in
                Array(UnsafeBufferPointer(start: data[channel], count: frameCount))
            }
        } else {
            samplesByChannel = []
        }
        lock.withLock {
            _snapshot = MicrophoneCaptureTestBufferSnapshot(
                channelCount: buffer.format.channelCount,
                samplesByChannel: samplesByChannel
            )
        }
    }

    var snapshot: MicrophoneCaptureTestBufferSnapshot? {
        lock.withLock { _snapshot }
    }
}

private final class MicrophoneCaptureTestStallBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _error: MeetingAudioError?
    func record(_ error: MeetingAudioError) {
        lock.withLock { _error = error }
    }
    var recordedError: MeetingAudioError? {
        lock.withLock { _error }
    }
}

/// Lightweight platform double for `MicrophoneCapture` shared-mode tests.
/// Mirrors `SharedMicrophoneStreamTests`'s `MockMicrophonePlatform` shape but
/// duplicated here to keep the two test files independent.
private final class SharedMicTestPlatform: MicrophoneEnginePlatform, @unchecked Sendable {
    struct ConfigureCall: Equatable {
        let vpioEnabled: Bool
        let bufferSize: AVAudioFrameCount
    }

    private let lock = NSLock()
    private var _isRunning = false
    private var _configureCalls: [ConfigureCall] = []
    private var _stopCount = 0
    private var _tapHandler: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?
    var configureAndStartError: Error?
    /// Counts down on each successful start. While >0, treat the call as a
    /// failure even if `configureAndStartError` is nil. Lets a test simulate
    /// "first attempt fails, second succeeds."
    var failNextStartCount: Int = 0
    /// Optional hook invoked at the top of `configureAndStart` (before the
    /// error injection check). Lets a test pause the platform mid-subscribe
    /// so it can interleave a `stop()` and exercise the start-during-stop
    /// race-guard. Read without holding `lock` so the hook can call back
    /// into the platform without deadlocking.
    private let hookLock = NSLock()
    private var _configureAndStartHook: (@Sendable () -> Void)?
    var configureAndStartHook: (@Sendable () -> Void)? {
        get { hookLock.withLock { _configureAndStartHook } }
        set { hookLock.withLock { _configureAndStartHook = newValue } }
    }
    private var _stopEngineHook: (@Sendable () -> Void)?
    /// Invoked at the top of `stopEngine` (outside `lock`) so a test can hold
    /// teardown open and observe that `stop()` waits for it.
    var stopEngineHook: (@Sendable () -> Void)? {
        get { hookLock.withLock { _stopEngineHook } }
        set { hookLock.withLock { _stopEngineHook = newValue } }
    }

    var isEngineRunning: Bool {
        lock.withLock { _isRunning }
    }

    var inputFormat: AVAudioFormat? {
        AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)
    }

    var configureAndStartCalls: [ConfigureCall] {
        lock.withLock { _configureCalls }
    }

    var stopEngineCallCount: Int {
        lock.withLock { _stopCount }
    }

    func configureAndStart(
        vpioEnabled: Bool,
        bufferSize: AVAudioFrameCount,
        tapHandler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) throws {
        configureAndStartHook?()
        let shouldThrow: Error? = lock.withLock {
            _configureCalls.append(ConfigureCall(vpioEnabled: vpioEnabled, bufferSize: bufferSize))
            if let err = configureAndStartError { return err }
            if failNextStartCount > 0 {
                failNextStartCount -= 1
                return MicrophoneCaptureMockError.simulatedFailure
            }
            return nil
        }
        if let shouldThrow {
            throw shouldThrow
        }
        lock.withLock {
            _isRunning = true
            _tapHandler = tapHandler
        }
    }

    func stopEngine() {
        stopEngineHook?()
        lock.withLock {
            _isRunning = false
            _tapHandler = nil
            _stopCount += 1
        }
    }

    func deliverBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        let handler = lock.withLock { _tapHandler }
        handler?(buffer, time)
    }
}
