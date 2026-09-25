import XCTest
@testable import SplayCore

final class CrashReporterTests: XCTestCase {

    private var testDir: String!

    override func setUp() {
        super.setUp()
        testDir = NSTemporaryDirectory() + "CrashReporterTests-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: testDir)
        super.tearDown()
    }

    private var testCrashPath: String { testDir + "/crash_report.txt" }

    // MARK: - Signal Crash Parsing

    func testLoadPendingReportParsesValidSignalCrash() {
        let content = """
        crash_type: signal
        signal: 11
        name: SIGSEGV
        timestamp: 1711900000
        app_ver: 0.5.1
        os_ver: 15.3.1
        uuid: A1B2C3D4-E5F6-7890-ABCD-EF1234567890
        slide: 0x100000
        --- stack ---
        0x00000001a2f3b4c0
        0x00000001a2f3b4d8
        0x00000001a2f3b500
        """
        try! content.write(toFile: testCrashPath, atomically: true, encoding: .utf8)

        let report = CrashReporter.loadPendingReport(from: testCrashPath)
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.crashType, "signal")
        XCTAssertEqual(report?.signal, "11")
        XCTAssertEqual(report?.name, "SIGSEGV")
        XCTAssertEqual(report?.timestamp, "1711900000")
        XCTAssertEqual(report?.appVersion, "0.5.1")
        XCTAssertEqual(report?.osVersion, "15.3.1")
        XCTAssertEqual(report?.uuid, "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")
        XCTAssertEqual(report?.slide, "0x100000")
        XCTAssertNil(report?.reason)
        XCTAssertEqual(report?.stackTrace.count, 3)
        XCTAssertEqual(report?.stackTrace.first, "0x00000001a2f3b4c0")
    }

    // MARK: - Exception Crash Parsing

    func testLoadPendingReportParsesExceptionCrash() {
        let content = """
        crash_type: exception
        signal: exception
        name: NSInvalidArgumentException
        timestamp: 1711900000
        app_ver: 0.5.1
        os_ver: 15.3.1
        uuid: A1B2C3D4-E5F6-7890-ABCD-EF1234567890
        slide: 0x0
        reason: unrecognized selector sent to instance
        --- stack ---
        0x00000001a2f3b4c0
        0x00000001a2f3b4d8
        """
        try! content.write(toFile: testCrashPath, atomically: true, encoding: .utf8)

        let report = CrashReporter.loadPendingReport(from: testCrashPath)
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.crashType, "exception")
        XCTAssertEqual(report?.name, "NSInvalidArgumentException")
        XCTAssertEqual(report?.reason, "unrecognized selector sent to instance")
        XCTAssertEqual(report?.stackTrace.count, 2)
    }

    // MARK: - Edge Cases

    func testLoadPendingReportReturnsNilForMissingFile() {
        let report = CrashReporter.loadPendingReport(from: testDir + "/nonexistent.txt")
        XCTAssertNil(report)
    }

    func testLoadPendingReportReturnsNilForEmptyFile() {
        try! "".write(toFile: testCrashPath, atomically: true, encoding: .utf8)
        let report = CrashReporter.loadPendingReport(from: testCrashPath)
        XCTAssertNil(report)
    }

    func testLoadPendingReportHandlesMalformedFile() {
        try! "garbage data\nno structure here".write(toFile: testCrashPath, atomically: true, encoding: .utf8)
        let report = CrashReporter.loadPendingReport(from: testCrashPath)
        XCTAssertNil(report) // Missing required fields
    }

    func testLoadPendingReportHandlesPartialFile() {
        // Only some fields — simulates interrupted write
        let content = """
        crash_type: signal
        signal: 6
        name: SIGABRT
        timestamp: 1711900000
        app_ver: 0.5.1
        """
        try! content.write(toFile: testCrashPath, atomically: true, encoding: .utf8)

        let report = CrashReporter.loadPendingReport(from: testCrashPath)
        XCTAssertNotNil(report) // Has required fields
        XCTAssertEqual(report?.signal, "6")
        XCTAssertEqual(report?.name, "SIGABRT")
        XCTAssertTrue(report?.stackTrace.isEmpty ?? false)
    }

    // MARK: - Telemetry Integration

    func testKeepPendingReportLocallyMovesReportIntoArchive() throws {
        let content = "crash_type: signal\nsignal: 11\nname: SIGSEGV\ntimestamp: 1711900000\napp_ver: 0.1\nos_ver: 14.6\n--- stack ---\n0x1234\n"
        try content.write(toFile: testCrashPath, atomically: true, encoding: .utf8)
        let archive = testDir + "/archive"

        let kept = CrashReporter.keepPendingReportLocally(from: testCrashPath, archiveDirectory: archive)

        let keptPath = try XCTUnwrap(kept)
        XCTAssertFalse(FileManager.default.fileExists(atPath: testCrashPath))
        XCTAssertEqual(try String(contentsOfFile: keptPath, encoding: .utf8), content)
        XCTAssertTrue(keptPath.hasSuffix("crash-1711900000.txt"))
    }

    func testKeepPendingReportLocallyWithoutReportDoesNothing() {
        XCTAssertNil(CrashReporter.keepPendingReportLocally(
            from: testDir + "/nonexistent.txt",
            archiveDirectory: testDir + "/archive"
        ))
    }

    func testKeepPendingReportLocallyPrunesOldestBeyondLimit() throws {
        let archive = testDir + "/archive"
        try FileManager.default.createDirectory(atPath: archive, withIntermediateDirectories: true)
        for index in 0..<CrashReporter.maxArchivedReports {
            let name = String(format: "crash-10000000%02d.txt", index)
            try "old".write(toFile: archive + "/" + name, atomically: true, encoding: .utf8)
        }
        let content = "crash_type: signal\nsignal: 6\nname: SIGABRT\ntimestamp: 2000000000\napp_ver: 0.1\n"
        try content.write(toFile: testCrashPath, atomically: true, encoding: .utf8)

        CrashReporter.keepPendingReportLocally(from: testCrashPath, archiveDirectory: archive)

        let names = try FileManager.default.contentsOfDirectory(atPath: archive).sorted()
        XCTAssertEqual(names.count, CrashReporter.maxArchivedReports)
        XCTAssertFalse(names.contains("crash-1000000000.txt"), "the oldest report is pruned")
        XCTAssertTrue(names.contains("crash-2000000000.txt"))
    }

    // MARK: - Reviewer-Flagged Edge Cases

    func testReasonFieldWithColonsPreservesFullValue() {
        let content = """
        crash_type: exception
        signal: exception
        name: NSInvalidArgumentException
        timestamp: 1711900000
        app_ver: 0.5.1
        reason: Cannot decode: key "url": no such key
        --- stack ---
        0x1234
        """
        try! content.write(toFile: testCrashPath, atomically: true, encoding: .utf8)

        let report = CrashReporter.loadPendingReport(from: testCrashPath)
        XCTAssertEqual(report?.reason, "Cannot decode: key \"url\": no such key")
    }

    func testNoStackSectionReturnsEmptyStackTrace() {
        let content = """
        crash_type: signal
        signal: 11
        name: SIGSEGV
        timestamp: 1711900000
        app_ver: 0.5.1
        """
        try! content.write(toFile: testCrashPath, atomically: true, encoding: .utf8)

        let report = CrashReporter.loadPendingReport(from: testCrashPath)
        XCTAssertNotNil(report)
        XCTAssertTrue(report?.stackTrace.isEmpty ?? false)
    }

    func testNonHexLinesInStackSectionAreSkipped() {
        let content = """
        crash_type: signal
        signal: 11
        name: SIGSEGV
        timestamp: 1711900000
        app_ver: 0.5.1
        --- stack ---
        0x1234
        garbage line
        not a hex address
        0x5678
        """
        try! content.write(toFile: testCrashPath, atomically: true, encoding: .utf8)

        let report = CrashReporter.loadPendingReport(from: testCrashPath)
        XCTAssertEqual(report?.stackTrace, ["0x1234", "0x5678"])
    }

    func testStackTraceCappedAt256Frames() {
        var lines = [
            "crash_type: signal", "signal: 11", "name: SIGSEGV",
            "timestamp: 1711900000", "app_ver: 0.5.1", "--- stack ---"
        ]
        for i in 0..<300 {
            lines.append("0x\(String(i, radix: 16))")
        }
        let content = lines.joined(separator: "\n")
        try! content.write(toFile: testCrashPath, atomically: true, encoding: .utf8)

        let report = CrashReporter.loadPendingReport(from: testCrashPath)
        XCTAssertEqual(report?.stackTrace.count, 256)
    }

    func testMissingOptionalFieldsDefaultToEmptyString() {
        let content = "crash_type: signal\nsignal: 11\nname: SIGSEGV\ntimestamp: 0\napp_ver: 0.1\n"
        try! content.write(toFile: testCrashPath, atomically: true, encoding: .utf8)

        let report = CrashReporter.loadPendingReport(from: testCrashPath)
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.osVersion, "")
        XCTAssertEqual(report?.uuid, "")
        XCTAssertEqual(report?.slide, "")
        XCTAssertNil(report?.reason)
    }

    func testStackTraceMarkerWithTrailingWhitespace() {
        let content = "crash_type: signal\nsignal: 11\nname: SIGSEGV\ntimestamp: 0\napp_ver: 0.1\n--- stack ---  \n0xABCD\n"
        try! content.write(toFile: testCrashPath, atomically: true, encoding: .utf8)

        let report = CrashReporter.loadPendingReport(from: testCrashPath)
        XCTAssertEqual(report?.stackTrace, ["0xABCD"])
    }

    func testLoadPendingReportParsesAllFields() throws {
        let content = """
        crash_type: signal
        signal: 11
        name: SIGSEGV
        timestamp: 1711900000
        app_ver: 0.5.1
        os_ver: 15.3
        uuid: TEST-UUID
        slide: 0x100000
        --- stack ---
        0xAAAA
        0xBBBB
        0xCCCC
        """
        try content.write(toFile: testCrashPath, atomically: true, encoding: .utf8)

        let report = try XCTUnwrap(CrashReporter.loadPendingReport(from: testCrashPath))
        XCTAssertEqual(report.appVersion, "0.5.1")
        XCTAssertEqual(report.osVersion, "15.3")
        XCTAssertEqual(report.uuid, "TEST-UUID")
        XCTAssertEqual(report.slide, "0x100000")
        XCTAssertNil(report.reason)
        XCTAssertEqual(report.stackTrace, ["0xAAAA", "0xBBBB", "0xCCCC"])
    }

    func testExceptionReasonWithNewlinesIsPreserved() throws {
        let content = """
        crash_type: exception
        signal: exception
        name: NSRangeException
        timestamp: 1711900000
        app_ver: 0.5.1
        reason: index 5 beyond bounds [0..3]\\nmore context here
        --- stack ---
        0x1234
        """
        try content.write(toFile: testCrashPath, atomically: true, encoding: .utf8)

        let report = try XCTUnwrap(CrashReporter.loadPendingReport(from: testCrashPath))
        XCTAssertEqual(report.reason, "index 5 beyond bounds [0..3]\nmore context here")
    }
}

// NoOpTelemetryService is imported from SplayCore via @testable import
