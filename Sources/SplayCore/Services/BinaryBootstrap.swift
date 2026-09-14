// macOS-only: Locates the bundled FFmpeg binary; no subprocesses on iOS.
// See docs/plans/splay-ios-utility-layer.md (slice 1).
#if os(macOS)
import Foundation
import os

public enum BinaryBootstrapError: Error, LocalizedError {
    case bundledFFmpegMissing

    public var errorDescription: String? {
        switch self {
        case .bundledFFmpegMissing:
            return "Bundled FFmpeg is missing from app resources"
        }
    }
}

public actor BinaryBootstrap {
    public init() {}

    public nonisolated static func requireBundledFFmpegPath() throws -> String {
        guard let ffmpegPath = AppPaths.bundledFFmpegPath() else {
            throw BinaryBootstrapError.bundledFFmpegMissing
        }
        return ffmpegPath
    }

    /// Resolve FFmpeg for current runtime:
    /// - App bundle path in production.
    /// - Development fallback (`swift run` / tests) via env override or PATH.
    public nonisolated static func requireRuntimeFFmpegPath() throws -> String {
        guard let ffmpegPath = resolveRuntimeFFmpegPath() else {
            throw BinaryBootstrapError.bundledFFmpegMissing
        }
        return ffmpegPath
    }

    public nonisolated static func resolveRuntimeFFmpegPath(
        bundledFFmpegPath: String? = AppPaths.bundledFFmpegPath(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        if let bundledFFmpegPath,
           fileManager.isExecutableFile(atPath: bundledFFmpegPath)
        {
            return bundledFFmpegPath
        }

        if let override = environment["MACPARAKEET_FFMPEG_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty,
           fileManager.isExecutableFile(atPath: override)
        {
            return override
        }

        let extendedPATH = Self.extendedPATH(from: environment["PATH"])
        if let discovered = findExecutable(named: "ffmpeg", inPATH: extendedPATH, fileManager: fileManager) {
            return discovered
        }

        return nil
    }

    /// Find FFmpeg via PATH search only (skips bundled binary).
    /// Used as a fallback when the bundled FFmpeg fails at runtime (e.g., dyld Team ID mismatch).
    public nonisolated static func findSystemFFmpeg(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        let extendedPATH = Self.extendedPATH(from: environment["PATH"])
        return findExecutable(named: "ffmpeg", inPATH: extendedPATH, fileManager: fileManager)
    }

    // MARK: - Private

    /// Extend PATH with common binary locations that macOS GUI apps don't inherit.
    private nonisolated static func extendedPATH(from basePATH: String?) -> String {
        let current = basePATH ?? "/usr/bin:/bin"
        let extras = [
            AppPaths.binDir,
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        let existing = Set(current.split(separator: ":").map(String.init))
        let missing = extras.filter { !existing.contains($0) }
        return ([current] + missing).joined(separator: ":")
    }

    private nonisolated static func findExecutable(
        named binaryName: String,
        inPATH path: String,
        fileManager: FileManager
    ) -> String? {
        for rawComponent in path.split(separator: ":") {
            let component = String(rawComponent)
            guard !component.isEmpty else { continue }
            let candidate = URL(fileURLWithPath: component, isDirectory: true)
                .appendingPathComponent(binaryName)
                .path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
#endif
