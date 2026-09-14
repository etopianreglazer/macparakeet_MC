import XCTest
@testable import SplayCore

/// `BundledModelSeeder` against temp directories standing in for the app
/// bundle's `Models/` folder and FluidAudio's cache. Pure file work: nothing
/// here touches the real cache or loads a model.
final class BundledModelSeederTests: XCTestCase {
    private var tempRoot: URL!
    private var bundleModels: URL!
    private var cache: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundledModelSeederTests-\(UUID().uuidString)", isDirectory: true)
        bundleModels = tempRoot.appendingPathComponent("Models", isDirectory: true)
        cache = tempRoot.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleModels, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
    }

    // MARK: - Helpers

    /// A repo folder shaped like FluidAudio's: nested `.mlmodelc` folders plus
    /// top-level json files.
    private func makeRepo(_ name: String, in root: URL, files: [String: String]) throws -> URL {
        let repo = root.appendingPathComponent(name, isDirectory: true)
        for (relative, contents) in files {
            let file = repo.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }
        return repo
    }

    private static let parakeetFiles = [
        "Encoder.mlmodelc/coremldata.bin": "encoder-weights",
        "Encoder.mlmodelc/weights/weight.bin": "0123456789",
        "Decoder.mlmodelc/coremldata.bin": "decoder",
        "config.json": "{}",
        "parakeet_v3_vocab.json": "{\"a\":1}",
    ]
    private static let vadFiles = [
        "silero-vad-unified-256ms-v6.0.0.mlmodelc/coremldata.bin": "vad",
        "config.json": "{}",
    ]

    private func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    // MARK: - Seeding

    func testSeedsEveryRepoIntoAnEmptyCacheRecursively() throws {
        _ = try makeRepo("parakeet-tdt-0.6b-v3", in: bundleModels, files: Self.parakeetFiles)
        _ = try makeRepo("silero-vad", in: bundleModels, files: Self.vadFiles)

        let report = try BundledModelSeeder.seed(from: bundleModels, into: cache)

        XCTAssertEqual(report.seeded, ["parakeet-tdt-0.6b-v3", "silero-vad"])
        XCTAssertEqual(report.alreadyComplete, [])
        for (relative, expected) in Self.parakeetFiles {
            let copied = cache.appendingPathComponent("parakeet-tdt-0.6b-v3/\(relative)")
            XCTAssertEqual(try contents(of: copied), expected, relative)
        }
        XCTAssertEqual(
            try contents(of: cache.appendingPathComponent("silero-vad/config.json")), "{}"
        )
    }

    func testCompleteCacheIsLeftUntouched() throws {
        _ = try makeRepo("parakeet-tdt-0.6b-v3", in: bundleModels, files: Self.parakeetFiles)
        let existing = try makeRepo("parakeet-tdt-0.6b-v3", in: cache, files: Self.parakeetFiles)
        // Something FluidAudio or the OS added on its own must survive.
        let extra = existing.appendingPathComponent("Encoder.mlmodelc/analytics/side-file")
        try FileManager.default.createDirectory(at: extra.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "keep me".write(to: extra, atomically: true, encoding: .utf8)

        let report = try BundledModelSeeder.seed(from: bundleModels, into: cache)

        XCTAssertEqual(report.seeded, [])
        XCTAssertEqual(report.alreadyComplete, ["parakeet-tdt-0.6b-v3"])
        XCTAssertEqual(try contents(of: extra), "keep me")
    }

    func testIncompleteCacheIsReplaced() throws {
        _ = try makeRepo("parakeet-tdt-0.6b-v3", in: bundleModels, files: Self.parakeetFiles)
        var partial = Self.parakeetFiles
        partial.removeValue(forKey: "Encoder.mlmodelc/weights/weight.bin")   // interrupted download
        let existing = try makeRepo("parakeet-tdt-0.6b-v3", in: cache, files: partial)
        let stale = existing.appendingPathComponent("stale.tmp")
        try "half".write(to: stale, atomically: true, encoding: .utf8)

        let report = try BundledModelSeeder.seed(from: bundleModels, into: cache)

        XCTAssertEqual(report.seeded, ["parakeet-tdt-0.6b-v3"])
        XCTAssertEqual(
            try contents(of: cache.appendingPathComponent("parakeet-tdt-0.6b-v3/Encoder.mlmodelc/weights/weight.bin")),
            "0123456789"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path), "the partial folder is replaced, not merged")
    }

    func testSizeMismatchCountsAsIncomplete() throws {
        _ = try makeRepo("silero-vad", in: bundleModels, files: Self.vadFiles)
        var truncated = Self.vadFiles
        truncated["silero-vad-unified-256ms-v6.0.0.mlmodelc/coremldata.bin"] = "v"
        _ = try makeRepo("silero-vad", in: cache, files: truncated)

        let report = try BundledModelSeeder.seed(from: bundleModels, into: cache)

        XCTAssertEqual(report.seeded, ["silero-vad"])
        XCTAssertEqual(
            try contents(of: cache.appendingPathComponent("silero-vad/silero-vad-unified-256ms-v6.0.0.mlmodelc/coremldata.bin")),
            "vad"
        )
    }

    func testLeavesNoStagingFoldersBehind() throws {
        _ = try makeRepo("parakeet-tdt-0.6b-v3", in: bundleModels, files: Self.parakeetFiles)
        _ = try makeRepo("silero-vad", in: bundleModels, files: Self.vadFiles)

        try BundledModelSeeder.seed(from: bundleModels, into: cache)

        let entries = try FileManager.default.contentsOfDirectory(atPath: cache.path).sorted()
        XCTAssertEqual(entries, ["parakeet-tdt-0.6b-v3", "silero-vad"])
    }

    func testStaleStagingFromAnInterruptedCopyIsSwept() throws {
        _ = try makeRepo("silero-vad", in: bundleModels, files: Self.vadFiles)
        _ = try makeRepo("silero-vad", in: cache, files: Self.vadFiles)   // complete: nothing to copy
        let stale = try makeRepo(
            "\(BundledModelSeeder.stagingPrefix)silero-vad-DEADBEEF", in: cache, files: ["config.json": "{"]
        )

        let report = try BundledModelSeeder.seed(from: bundleModels, into: cache)

        XCTAssertEqual(report.alreadyComplete, ["silero-vad"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cache.path), ["silero-vad"])
    }

    func testMissingOrEmptySourceIsANoOp() throws {
        let missing = tempRoot.appendingPathComponent("no-such-folder", isDirectory: true)
        XCTAssertEqual(try BundledModelSeeder.seed(from: missing, into: cache), BundledModelSeeder.Report())
        XCTAssertEqual(try BundledModelSeeder.seed(from: bundleModels, into: cache), BundledModelSeeder.Report())
    }

    func testLooseFilesInTheBundleFolderAreIgnored() throws {
        _ = try makeRepo("silero-vad", in: bundleModels, files: Self.vadFiles)
        try "notes".write(to: bundleModels.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)

        let report = try BundledModelSeeder.seed(from: bundleModels, into: cache)

        XCTAssertEqual(report.seeded, ["silero-vad"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.appendingPathComponent("README.txt").path))
    }

    // MARK: - Completeness check

    func testIsCompleteRequiresDestinationToExist() throws {
        let source = try makeRepo("silero-vad", in: bundleModels, files: Self.vadFiles)
        XCTAssertFalse(BundledModelSeeder.isComplete(
            source: source, destination: cache.appendingPathComponent("silero-vad")
        ))
    }
}
