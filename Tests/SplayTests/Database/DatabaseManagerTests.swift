import XCTest
import GRDB
@testable import SplayCore

final class DatabaseManagerTests: XCTestCase {
    private let prePromptLibraryMigrationIDs = [
        "v0.1-dictations",
        "v0.1-transcriptions",
        "v0.2-custom-words",
        "v0.2-text-snippets",
        "v0.3-transcription-source-url",
        "v0.4-transcription-diarization-segments",
        "v0.4-transcription-llm-content",
        "v0.5-private-dictation",
        "v0.5-chat-conversations",
        "v0.5-drop-unused-fts",
        "v0.5-transcription-video-metadata",
        "v0.6-transcription-source-type",
        "v0.7-snippet-key-action",
    ]

    func testInMemoryDatabaseCreates() throws {
        let manager = try DatabaseManager()
        XCTAssertNotNil(manager.dbQueue)
    }

    func testFileBackedConnectionsWaitForShortWriteLock() throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("macparakeet-lock-wait-\(UUID().uuidString).db")
            .path
        defer { cleanupDatabaseFiles(atPath: dbPath) }

        let first = try DatabaseManager(path: dbPath)
        let second = try DatabaseManager(path: dbPath)
        let lockAcquired = DispatchSemaphore(value: 0)
        let releaseLock = DispatchSemaphore(value: 0)
        let firstFinished = expectation(description: "first write finishes")
        let secondFinished = expectation(description: "second write finishes")
        let resultLock = NSLock()
        var firstError: Error?
        var secondError: Error?

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try first.dbQueue.write { db in
                    try db.execute(sql: "SELECT 1")
                    lockAcquired.signal()
                    _ = releaseLock.wait(timeout: .now() + 2)
                }
            } catch {
                resultLock.lock()
                firstError = error
                resultLock.unlock()
            }
            firstFinished.fulfill()
        }

        XCTAssertEqual(lockAcquired.wait(timeout: .now() + 1), .success)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try second.dbQueue.write { db in
                    try db.execute(sql: "SELECT 1")
                }
            } catch {
                resultLock.lock()
                secondError = error
                resultLock.unlock()
            }
            secondFinished.fulfill()
        }

        Thread.sleep(forTimeInterval: 0.1)
        releaseLock.signal()

        wait(for: [firstFinished, secondFinished], timeout: 3)
        resultLock.lock()
        let capturedFirstError = firstError
        let capturedSecondError = secondError
        resultLock.unlock()

        XCTAssertNil(capturedFirstError)
        XCTAssertNil(capturedSecondError)
    }

    func testConcurrentFileBackedManagersSerializeInitialMigration() throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("macparakeet-concurrent-migration-\(UUID().uuidString).db")
            .path
        defer { cleanupDatabaseFiles(atPath: dbPath) }

        let start = DispatchSemaphore(value: 0)
        let finished = DispatchGroup()
        let resultLock = NSLock()
        var errors: [Error] = []

        for _ in 0..<4 {
            finished.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                start.wait()
                do {
                    let manager = try DatabaseManager(path: dbPath)
                    try manager.dbQueue.read { db in
                        XCTAssertTrue(try db.tableExists("dictations"))
                        XCTAssertTrue(try db.tableExists("transcriptions"))
                        XCTAssertTrue(try db.tableExists("quick_prompts"))
                    }
                } catch {
                    resultLock.lock()
                    errors.append(error)
                    resultLock.unlock()
                }
                finished.leave()
            }
        }

        for _ in 0..<4 {
            start.signal()
        }

        XCTAssertEqual(finished.wait(timeout: .now() + 5), .success)
        resultLock.lock()
        let capturedErrors = errors
        resultLock.unlock()
        XCTAssertTrue(capturedErrors.isEmpty, "Unexpected migration errors: \(capturedErrors)")
    }

    func testMigrationsCreateTables() throws {
        let manager = try DatabaseManager()
        try manager.dbQueue.read { db in
            XCTAssertTrue(try db.tableExists("dictations"))
            XCTAssertTrue(try db.tableExists("transcriptions"))
            XCTAssertTrue(try db.tableExists("prompts"))
            XCTAssertTrue(try db.tableExists("summaries"))
            // dictations_fts was dropped in v0.5-drop-unused-fts (never queried, wasted write overhead)
            XCTAssertFalse(try db.tableExists("dictations_fts"))
        }
    }

    func testMigrationsCreateIndexes() throws {
        let manager = try DatabaseManager()
        try manager.dbQueue.read { db in
            let dictationIndexes = try db.indexes(on: "dictations")
            XCTAssertTrue(dictationIndexes.contains { $0.name == "idx_dictations_created_at" })

            let transcriptionIndexes = try db.indexes(on: "transcriptions")
            XCTAssertTrue(transcriptionIndexes.contains { $0.name == "idx_transcriptions_created_at" })
            XCTAssertTrue(transcriptionIndexes.contains { $0.name == "idx_transcriptions_source_type_created_at" })
            XCTAssertTrue(transcriptionIndexes.contains { $0.name == "idx_transcriptions_favorite_created_at" })
            XCTAssertTrue(transcriptionIndexes.contains { $0.name == "idx_transcriptions_status_created_at" })

            let promptIndexes = try db.indexes(on: "prompts")
            XCTAssertTrue(promptIndexes.contains { $0.name == "idx_prompts_name" })

            let summaryIndexes = try db.indexes(on: "summaries")
            XCTAssertTrue(summaryIndexes.contains { $0.name == "idx_summaries_transcription_id" })
        }
    }

    func testSourceURLColumnExists() throws {
        let manager = try DatabaseManager()
        try manager.dbQueue.read { db in
            let columns = try db.columns(in: "transcriptions")
            let columnNames = columns.map(\.name)
            XCTAssertTrue(columnNames.contains("sourceURL"), "transcriptions should have sourceURL column")
        }
    }

    func testVideoMetadataColumnsExist() throws {
        let manager = try DatabaseManager()
        try manager.dbQueue.read { db in
            let columns = try db.columns(in: "transcriptions").map(\.name)
            XCTAssertTrue(columns.contains("thumbnailURL"), "transcriptions should have thumbnailURL column")
            XCTAssertTrue(columns.contains("channelName"), "transcriptions should have channelName column")
            XCTAssertTrue(columns.contains("videoDescription"), "transcriptions should have videoDescription column")
            XCTAssertTrue(columns.contains("isFavorite"), "transcriptions should have isFavorite column")
            XCTAssertTrue(columns.contains("sourceType"), "transcriptions should have sourceType column")
            XCTAssertTrue(columns.contains("recoveredFromCrash"), "transcriptions should have recoveredFromCrash column")
        }
    }

    // MARK: - ADR-020 v0.8 schema additions

    func testUserNotesColumnExistsOnTranscriptions() throws {
        let manager = try DatabaseManager()
        try manager.dbQueue.read { db in
            let columns = try db.columns(in: "transcriptions").map(\.name)
            XCTAssertTrue(columns.contains("userNotes"), "transcriptions should have userNotes column (ADR-020 §3)")
        }
    }

    func testUserNotesSnapshotColumnExistsOnSummaries() throws {
        let manager = try DatabaseManager()
        try manager.dbQueue.read { db in
            let columns = try db.columns(in: "summaries").map(\.name)
            XCTAssertTrue(columns.contains("userNotesSnapshot"), "summaries should have userNotesSnapshot column (ADR-020 §6)")
        }
    }

    func testTranscriptionUserNotesRoundTrips() throws {
        let manager = try DatabaseManager()
        let transcriptionID = UUID()

        let transcription = Transcription(
            id: transcriptionID,
            fileName: "meeting.m4a",
            sourceType: .meeting,
            userNotes: "key decision: ship Friday\nfollow up with QA"
        )
        try manager.dbQueue.write { db in
            try transcription.insert(db)
        }

        let loaded = try manager.dbQueue.read { db in
            try Transcription.fetchOne(db, key: transcriptionID)
        }
        XCTAssertEqual(loaded?.userNotes, "key decision: ship Friday\nfollow up with QA")
    }

    func testTranscriptionUserNotesNilByDefault() throws {
        let manager = try DatabaseManager()
        let transcriptionID = UUID()

        let transcription = Transcription(id: transcriptionID, fileName: "no-notes.m4a")
        try manager.dbQueue.write { db in
            try transcription.insert(db)
        }

        let loaded = try manager.dbQueue.read { db in
            try Transcription.fetchOne(db, key: transcriptionID)
        }
        XCTAssertNil(loaded?.userNotes)
    }

    func testSourceTypeMigrationRemapsLegacyURLRowsToFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("source_type_migration_\(UUID().uuidString).db").path

        let seedQueue = try DatabaseQueue(path: dbPath)
        try seedQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE grdb_migrations (
                    identifier TEXT NOT NULL PRIMARY KEY
                )
            """)
            for migrationID in [
                "v0.1-dictations",
                "v0.1-transcriptions",
                "v0.2-custom-words",
                "v0.2-text-snippets",
                "v0.3-transcription-source-url",
                "v0.4-transcription-diarization-segments",
                "v0.4-transcription-llm-content",
                "v0.5-private-dictation",
                "v0.5-chat-conversations",
                "v0.5-drop-unused-fts",
                "v0.5-transcription-video-metadata",
            ] {
                try db.execute(
                    sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
                    arguments: [migrationID]
                )
            }

            try db.execute(sql: """
                CREATE TABLE transcriptions (
                    id TEXT PRIMARY KEY,
                    createdAt TEXT NOT NULL,
                    fileName TEXT NOT NULL,
                    filePath TEXT,
                    fileSizeBytes INTEGER,
                    durationMs INTEGER,
                    rawTranscript TEXT,
                    cleanTranscript TEXT,
                    wordTimestamps TEXT,
                    language TEXT DEFAULT 'en',
                    speakerCount INTEGER,
                    speakers TEXT,
                    status TEXT NOT NULL DEFAULT 'processing',
                    errorMessage TEXT,
                    exportPath TEXT,
                    updatedAt TEXT NOT NULL,
                    sourceURL TEXT,
                    diarizationSegments TEXT,
                    summary TEXT,
                    chatMessages TEXT,
                    thumbnailURL TEXT,
                    channelName TEXT,
                    videoDescription TEXT,
                    isFavorite INTEGER NOT NULL DEFAULT 0
                )
            """)

            // dictations table is required by the v0.7.4 lifetime stats backfill.
            try Self.createV05DictationsTable(db: db)
            try Self.createV05ChatConversationsTable(db: db)

            try db.execute(sql: """
                CREATE TABLE text_snippets (
                    id TEXT PRIMARY KEY,
                    trigger TEXT NOT NULL,
                    expansion TEXT NOT NULL,
                    isEnabled INTEGER NOT NULL DEFAULT 1,
                    useCount INTEGER NOT NULL DEFAULT 0,
                    createdAt TEXT NOT NULL,
                    updatedAt TEXT NOT NULL
                )
            """)

            let now = Date()
            try db.execute(
                sql: """
                    INSERT INTO transcriptions (id, createdAt, fileName, updatedAt, sourceURL)
                    VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [UUID(), now, "legacy-url.mp3", now, "https://example.com/watch?v=test"]
            )
        }

        // The v0.6 migration backfilled URL-bearing rows as `youtube`; the later
        // v0.21 migration (YouTube support removed) remaps every such row to
        // `file`, which is the end state after all migrations run.
        let manager = try DatabaseManager(path: dbPath)
        try manager.dbQueue.read { db in
            let sourceType = try String.fetchOne(db, sql: "SELECT sourceType FROM transcriptions LIMIT 1")
            XCTAssertEqual(sourceType, Transcription.SourceType.file.rawValue)
        }

        try? FileManager.default.removeItem(atPath: dbPath)
    }

    func testSummariesTableIncludesUpdatedAtColumn() throws {
        let manager = try DatabaseManager()
        try manager.dbQueue.read { db in
            let columns = try db.columns(in: "summaries").map(\.name)
            XCTAssertTrue(columns.contains("updatedAt"), "summaries should have updatedAt column")
        }
    }

    func testPromptSummaryMigrationMovesLegacySummaryAndDropsColumn() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("prompt_summary_migration_\(UUID().uuidString).db").path
        let transcriptionID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_712_345_678)
        let legacySummary = "Existing migrated summary"

        let seedQueue = try DatabaseQueue(path: dbPath)
        try seedQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE grdb_migrations (
                    identifier TEXT NOT NULL PRIMARY KEY
                )
            """)
            for migrationID in prePromptLibraryMigrationIDs {
                try db.execute(
                    sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
                    arguments: [migrationID]
                )
            }

            try db.execute(sql: """
                CREATE TABLE text_snippets (
                    id TEXT PRIMARY KEY,
                    trigger TEXT NOT NULL,
                    expansion TEXT NOT NULL,
                    isEnabled INTEGER NOT NULL DEFAULT 1,
                    useCount INTEGER NOT NULL DEFAULT 0,
                    createdAt TEXT NOT NULL,
                    updatedAt TEXT NOT NULL,
                    action TEXT
                )
            """)

            try db.execute(sql: """
                CREATE TABLE transcriptions (
                    id TEXT PRIMARY KEY,
                    createdAt TEXT NOT NULL,
                    fileName TEXT NOT NULL,
                    filePath TEXT,
                    fileSizeBytes INTEGER,
                    durationMs INTEGER,
                    rawTranscript TEXT,
                    cleanTranscript TEXT,
                    wordTimestamps TEXT,
                    language TEXT DEFAULT 'en',
                    speakerCount INTEGER,
                    speakers TEXT,
                    status TEXT NOT NULL DEFAULT 'processing',
                    errorMessage TEXT,
                    exportPath TEXT,
                    updatedAt TEXT NOT NULL,
                    sourceURL TEXT,
                    diarizationSegments TEXT,
                    summary TEXT,
                    chatMessages TEXT,
                    thumbnailURL TEXT,
                    channelName TEXT,
                    videoDescription TEXT,
                    isFavorite INTEGER NOT NULL DEFAULT 0,
                    sourceType TEXT NOT NULL DEFAULT 'file'
                )
            """)

            // dictations table is required by the v0.7.4 lifetime stats backfill.
            try Self.createV05DictationsTable(db: db)
            try Self.createV05ChatConversationsTable(db: db)

            try db.execute(
                sql: """
                    INSERT INTO transcriptions (
                        id, createdAt, fileName, updatedAt, summary
                    ) VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [transcriptionID, createdAt, "fixture.wav", createdAt, legacySummary]
            )
        }

        let manager = try DatabaseManager(path: dbPath)
        try manager.dbQueue.read { db in
            let migratedSummaryCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM summaries WHERE transcriptionId = ?",
                arguments: [transcriptionID]
            )
            let migratedSummaryContent = try String.fetchOne(
                db,
                sql: "SELECT content FROM summaries WHERE transcriptionId = ?",
                arguments: [transcriptionID]
            )
            let migratedPromptName = try String.fetchOne(
                db,
                sql: "SELECT promptName FROM summaries WHERE transcriptionId = ?",
                arguments: [transcriptionID]
            )
            let migratedPromptContent = try String.fetchOne(
                db,
                sql: "SELECT promptContent FROM summaries WHERE transcriptionId = ?",
                arguments: [transcriptionID]
            )
            let transcriptionColumns = try db.columns(in: "transcriptions").map(\.name)

            XCTAssertEqual(migratedSummaryCount, 1)
            XCTAssertEqual(migratedSummaryContent, legacySummary)
            XCTAssertEqual(migratedPromptName, "Summary")
            XCTAssertEqual(migratedPromptContent, Prompt.classicSummaryPrompt().content)
            XCTAssertFalse(transcriptionColumns.contains("summary"))
        }

        try? FileManager.default.removeItem(atPath: dbPath)
    }

    func testMigrationsAreIdempotent() throws {
        // Running migrations twice on the SAME database file should not error
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("idempotent_test_\(UUID().uuidString).db").path

        // First run — creates tables and indexes
        let manager1 = try DatabaseManager(path: dbPath)
        try manager1.dbQueue.read { db in
            XCTAssertTrue(try db.tableExists("dictations"))
            XCTAssertTrue(try db.tableExists("transcriptions"))
        }

        // Second run on the SAME file — migrations should be skipped gracefully
        let manager2 = try DatabaseManager(path: dbPath)
        try manager2.dbQueue.read { db in
            XCTAssertTrue(try db.tableExists("dictations"))
            XCTAssertTrue(try db.tableExists("transcriptions"))
        }

        // Clean up
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    func testTransformWorkbenchCleanupMigrationPreservesRestoredHistoryWhenRerun() throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("transform_workbench_cleanup_\(UUID().uuidString).db")
            .path
        defer { cleanupDatabaseFiles(atPath: dbPath) }

        do {
            let manager = try DatabaseManager(path: dbPath)
            try manager.dbQueue.write { db in
                try db.execute(sql: """
                    CREATE TABLE IF NOT EXISTS transform_history (
                        id TEXT PRIMARY KEY,
                        inputText TEXT NOT NULL,
                        outputText TEXT NOT NULL
                    )
                """)
                try db.execute(sql: """
                    CREATE TABLE IF NOT EXISTS transform_profiles (
                        promptId TEXT PRIMARY KEY,
                        customInstructions TEXT
                    )
                """)
                try db.execute(sql: """
                    CREATE TABLE IF NOT EXISTS writing_samples (
                        id TEXT PRIMARY KEY,
                        text TEXT NOT NULL
                    )
                """)
                try db.execute(
                    sql: "DELETE FROM grdb_migrations WHERE identifier = ?",
                    arguments: ["v0.16-drop-transform-workbench-tables"]
                )
            }
        }

        let manager = try DatabaseManager(path: dbPath)
        try manager.dbQueue.read { db in
            XCTAssertTrue(try db.tableExists("transform_history"))
            XCTAssertFalse(try db.tableExists("transform_profiles"))
            XCTAssertFalse(try db.tableExists("writing_samples"))

            let historyColumns = try db.columns(in: "transform_history").map(\.name)
            XCTAssertTrue(historyColumns.contains("transformName"))
            XCTAssertTrue(historyColumns.contains("sourceAppBundleID"))
            XCTAssertTrue(historyColumns.contains("totalElapsedMs"))

            let appliedMigrationIDs = try String.fetchAll(
                db,
                sql: """
                    SELECT identifier FROM grdb_migrations
                    WHERE identifier IN (?, ?, ?, ?)
                """,
                arguments: [
                    "v0.14-transform-history",
                    "v0.15-transform-workbench",
                    "v0.16-drop-transform-workbench-tables",
                    "v0.17-recreate-transform-history",
                ]
            )
            XCTAssertEqual(
                Set(appliedMigrationIDs),
                [
                    "v0.14-transform-history",
                    "v0.15-transform-workbench",
                    "v0.16-drop-transform-workbench-tables",
                    "v0.17-recreate-transform-history",
                ]
            )
        }
    }

    func testEngineAttributionMigrationToleratesExistingColumnsWhenMigrationMarkerIsMissing() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("engine_attribution_rerun_\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let manager1 = try DatabaseManager(path: dbPath)
        try manager1.dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM grdb_migrations WHERE identifier = ?",
                arguments: ["v0.8-engine-attribution"]
            )
        }

        let manager2 = try DatabaseManager(path: dbPath)
        try manager2.dbQueue.read { db in
            let transcriptionColumns = try db.columns(in: "transcriptions").map(\.name)
            let dictationColumns = try db.columns(in: "dictations").map(\.name)
            XCTAssertTrue(transcriptionColumns.contains("engine"))
            XCTAssertTrue(transcriptionColumns.contains("engineVariant"))
            XCTAssertTrue(dictationColumns.contains("engine"))
            XCTAssertTrue(dictationColumns.contains("engineVariant"))

            let migrationRecorded = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM grdb_migrations WHERE identifier = ?)",
                arguments: ["v0.8-engine-attribution"]
            ) ?? false
            XCTAssertTrue(migrationRecorded)
        }
    }

    func testDictationLanguageMigrationToleratesExistingColumnWhenMigrationMarkerIsMissing() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("dictation_language_rerun_\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let manager1 = try DatabaseManager(path: dbPath)
        try manager1.dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM grdb_migrations WHERE identifier = ?",
                arguments: ["v0.19-dictation-language"]
            )
        }

        let manager2 = try DatabaseManager(path: dbPath)
        try manager2.dbQueue.read { db in
            let dictationColumns = try db.columns(in: "dictations").map(\.name)
            XCTAssertTrue(dictationColumns.contains("language"))

            let migrationRecorded = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM grdb_migrations WHERE identifier = ?)",
                arguments: ["v0.19-dictation-language"]
            ) ?? false
            XCTAssertTrue(migrationRecorded)
        }
    }

    /// Recreates the dictations table at its v0.5 shape (after `v0.5-private-dictation`
    /// added `hidden` and `wordCount`). Used by partial-migration test fixtures so the
    /// v0.7.4 lifetime-stats backfill has a real table to read from.
    static func createV05DictationsTable(db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE dictations (
                id TEXT PRIMARY KEY,
                createdAt TEXT NOT NULL,
                durationMs INTEGER NOT NULL,
                rawTranscript TEXT NOT NULL,
                cleanTranscript TEXT,
                audioPath TEXT,
                pastedToApp TEXT,
                processingMode TEXT NOT NULL DEFAULT 'raw',
                status TEXT NOT NULL DEFAULT 'completed',
                errorMessage TEXT,
                updatedAt TEXT NOT NULL,
                hidden INTEGER NOT NULL DEFAULT 0,
                wordCount INTEGER NOT NULL DEFAULT 0
            )
        """)
    }

    static func createV05ChatConversationsTable(db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE chat_conversations (
                id TEXT PRIMARY KEY,
                transcriptionId TEXT NOT NULL REFERENCES transcriptions(id) ON DELETE CASCADE,
                title TEXT NOT NULL DEFAULT '',
                messages TEXT,
                createdAt TEXT NOT NULL,
                updatedAt TEXT NOT NULL
            )
        """)
        try db.execute(sql: """
            CREATE INDEX idx_chat_conversations_transcription_id
            ON chat_conversations(transcriptionId)
        """)
    }

    private func cleanupDatabaseFiles(atPath path: String) {
        for suffix in ["", "-shm", "-wal", ".migration.lock"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }
}
