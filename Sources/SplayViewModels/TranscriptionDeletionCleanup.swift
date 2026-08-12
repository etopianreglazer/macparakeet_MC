import Foundation
import SplayCore

enum TranscriptionDeletionCleanup {
    static func removeOwnedAssets(for transcription: Transcription) throws {
        try TranscriptionAssetCleanup.removeOwnedAssets(for: transcription)
    }
}
