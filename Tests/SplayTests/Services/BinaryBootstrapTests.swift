import Foundation
import XCTest
@testable import SplayCore

final class BinaryBootstrapTests: XCTestCase {
    private var rootDir: URL!

    override func setUp() {
        super.setUp()
        rootDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("binary-bootstrap-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let rootDir {
            try? FileManager.default.removeItem(at: rootDir)
        }

        rootDir = nil
        super.tearDown()
    }

    func testResolveRuntimeFFmpegPathReturnsBundledBinaryWhenPresent() throws {
        let bundledDir = rootDir.appendingPathComponent("bundled", isDirectory: true)
        try FileManager.default.createDirectory(at: bundledDir, withIntermediateDirectories: true)
        let bundledFFmpeg = bundledDir.appendingPathComponent("ffmpeg")
        try createExecutable(at: bundledFFmpeg)

        let resolved = BinaryBootstrap.resolveRuntimeFFmpegPath(
            bundledFFmpegPath: bundledFFmpeg.path,
            environment: [:],
            fileManager: .default
        )

        XCTAssertEqual(resolved, bundledFFmpeg.path)
    }

    func testResolveRuntimeFFmpegPathUsesEnvOverride() throws {
        let devDir = rootDir.appendingPathComponent("dev", isDirectory: true)
        try FileManager.default.createDirectory(at: devDir, withIntermediateDirectories: true)
        let ffmpeg = devDir.appendingPathComponent("ffmpeg")
        try createExecutable(at: ffmpeg)

        let resolved = BinaryBootstrap.resolveRuntimeFFmpegPath(
            bundledFFmpegPath: nil,
            environment: [
                "MACPARAKEET_FFMPEG_PATH": ffmpeg.path,
                "PATH": "/usr/bin:/bin"
            ],
            fileManager: .default
        )

        XCTAssertEqual(resolved, ffmpeg.path)
    }

    func testResolveRuntimeFFmpegPathUsesPATHFallback() throws {
        let pathDir = rootDir.appendingPathComponent("path-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: pathDir, withIntermediateDirectories: true)
        let ffmpeg = pathDir.appendingPathComponent("ffmpeg")
        try createExecutable(at: ffmpeg)

        let resolved = BinaryBootstrap.resolveRuntimeFFmpegPath(
            bundledFFmpegPath: nil,
            environment: ["PATH": pathDir.path],
            fileManager: .default
        )

        XCTAssertEqual(resolved, ffmpeg.path)
    }

    func testResolveRuntimeFFmpegPathReturnsNilWhenNothingAvailable() throws {
        // Use a FileManager that reports no executable files, isolating from
        // the host system (which may have /opt/homebrew/bin/ffmpeg).
        let noExecFM = NoExecutableFileManager()
        let resolved = BinaryBootstrap.resolveRuntimeFFmpegPath(
            bundledFFmpegPath: nil,
            environment: ["PATH": rootDir.path],
            fileManager: noExecFM
        )

        XCTAssertNil(resolved)
    }

    // MARK: - Helpers

    private func createExecutable(at url: URL) throws {
        try Data("fake-executable".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

/// FileManager subclass that always returns false for isExecutableFile,
/// isolating tests from whatever is installed on the host system.
private class NoExecutableFileManager: FileManager {
    override func isExecutableFile(atPath path: String) -> Bool { false }
}
