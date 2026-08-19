import Foundation

// Splay ships with telemetry reporting REMOVED. Upstream MacParakeet posted
// anonymous usage/crash events to a hosted backend; Splay has no
// backend of its own and does not report anything. Only the No-Op sink below is
// wired in `AppEnvironment`, so every `Telemetry.send(...)` call across the app
// (and `CrashReporter`, which sends via this protocol) is inert — no network,
// no queue, no upstream URL in the binary. The event-spec plumbing
// (`TelemetryEventSpec`, `TelemetryEvent`) is kept because it also drives local
// diagnostics/logging and is referenced throughout the codebase.

// MARK: - Protocol

public protocol TelemetryServiceProtocol: Sendable {
    func send(_ event: TelemetryEventSpec)
    @discardableResult
    func sendAndFlush(_ event: TelemetryEventSpec) async -> Bool
    func clearQueue()
    func flush() async
    func flushForTermination()
}

// MARK: - Static Convenience

/// Ergonomic static wrapper for fire-and-forget telemetry.
///
/// Usage:
/// ```swift
/// Telemetry.send(.dictationCompleted(durationSeconds: 12.5, wordCount: 84, mode: .persistent))
/// Telemetry.send(.appLaunched)
/// ```
///
/// In Splay the configured sink is always `NoOpTelemetryService`, so these calls
/// do nothing. The API is retained so the ~40 call sites do not have to change.
public enum Telemetry {
    private final class ServiceStore: @unchecked Sendable {
        private let lock = NSLock()
        private var service: TelemetryServiceProtocol?

        func set(_ service: TelemetryServiceProtocol) {
            lock.lock()
            self.service = service
            lock.unlock()
        }

        func get() -> TelemetryServiceProtocol? {
            lock.lock()
            defer { lock.unlock() }
            return service
        }
    }

    private static let serviceStore = ServiceStore()

    private static func configuredService() -> TelemetryServiceProtocol? {
        serviceStore.get()
    }

    public static func configure(_ service: TelemetryServiceProtocol) {
        serviceStore.set(service)
    }

    public static func send(_ event: TelemetryEventSpec) {
        configuredService()?.send(event)
    }

    public static func clearQueue() {
        configuredService()?.clearQueue()
    }

    public static func flush() async {
        await configuredService()?.flush()
    }

    public static func flushForTermination() {
        configuredService()?.flushForTermination()
    }
}

// MARK: - No-Op Implementation

/// The only telemetry sink Splay wires in. Discards every event.
public final class NoOpTelemetryService: TelemetryServiceProtocol {
    public init() {}
    public func send(_ event: TelemetryEventSpec) {}
    public func sendAndFlush(_ event: TelemetryEventSpec) async -> Bool { true }
    public func clearQueue() {}
    public func flush() async {}
    public func flushForTermination() {}
}
