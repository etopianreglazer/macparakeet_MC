import FluidAudio
import Foundation

/// Seeds FluidAudio's on-disk model cache from model folders shipped inside an
/// app bundle, so a first launch (or a launch after the data container was
/// wiped) needs no network before the first transcription.
///
/// The bundle carries a `Models/` folder laid out exactly like the cache
/// (`<repo folder>/<files…>`, e.g. `parakeet-tdt-0.6b-v3/Encoder.mlmodelc/…`);
/// each top-level folder is one FluidAudio repo. A repo is copied only when the
/// cache does not already hold a complete copy — every file in the bundled
/// folder present in the cache at the same size — so a normal launch costs one
/// directory walk and nothing else.
///
/// Copies are staged next to the destination and renamed into place, so an
/// interrupted copy never leaves a half folder that a later "does it exist"
/// check would trust. On APFS the copy is a clone (no extra disk, near-instant).
///
/// Decision and device history: `docs/plans/splay-ios-utility-layer.md`
/// § Model delivery (the Hugging Face download failed twice on the phone).
public enum BundledModelSeeder {
    public struct Report: Equatable, Sendable {
        /// Repo folders copied into the cache on this call.
        public var seeded: [String] = []
        /// Repo folders the cache already held completely; left untouched.
        public var alreadyComplete: [String] = []

        public init(seeded: [String] = [], alreadyComplete: [String] = []) {
            self.seeded = seeded
            self.alreadyComplete = alreadyComplete
        }
    }

    /// The folder-reference name the app targets ship the models under.
    public static let bundleFolderName = "Models"

    /// Where FluidAudio looks: `Application Support/FluidAudio/Models`.
    public static func defaultCacheDirectory() -> URL {
        MLModelConfigurationUtils.defaultModelsDirectory()
    }

    /// The bundled `Models` folder, if this build shipped one.
    public static func bundledModelsDirectory(in bundle: Bundle = .main) -> URL? {
        guard let url = bundle.url(forResource: bundleFolderName, withExtension: nil) else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return url
    }

    /// Copies every repo folder under `source` into `cache` unless the cache
    /// already holds a complete copy. A missing or empty `source` is a no-op.
    /// Throws on the first copy that fails; repos seeded before it stay seeded.
    @discardableResult
    public static func seed(from source: URL, into cache: URL) throws -> Report {
        let fileManager = FileManager.default
        var report = Report()
        guard let repoFolders = try? fileManager.contentsOfDirectory(
            at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else {
            return report
        }
        try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
        removeStaleStaging(in: cache)

        for repoFolder in repoFolders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? repoFolder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let name = repoFolder.lastPathComponent
            let destination = cache.appendingPathComponent(name, isDirectory: true)
            if isComplete(source: repoFolder, destination: destination) {
                report.alreadyComplete.append(name)
                continue
            }
            try replace(destination, withCopyOf: repoFolder, stagingIn: cache)
            report.seeded.append(name)
        }
        return report
    }

    /// `true` when every regular file under `source` exists under `destination`
    /// at the same relative path and size. Extra files in the destination are
    /// ignored (FluidAudio may add its own, e.g. compiled-model side files).
    static func isComplete(source: URL, destination: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: destination.path) else { return false }
        let root = source.resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard let walker = fileManager.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: []
        ) else { return false }

        for case let file as URL in walker {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            let filePath = file.resolvingSymlinksInPath().path
            guard filePath.hasPrefix(rootPath) else { return false }
            let relative = String(filePath.dropFirst(rootPath.count))
            let counterpart = destination.appendingPathComponent(relative)
            guard let counterpartValues = try? counterpart.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  counterpartValues.isRegularFile == true,
                  counterpartValues.fileSize == values.fileSize else {
                return false
            }
        }
        return true
    }

    static let stagingPrefix = ".seeding-"

    /// A process that died mid-copy leaves its staging folder behind (hidden,
    /// but up to the size of a model). Nothing else ever creates entries with
    /// this prefix in the cache, so they are safe to sweep on the next run.
    private static func removeStaleStaging(in cache: URL) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(atPath: cache.path) else { return }
        for entry in entries where entry.hasPrefix(stagingPrefix) {
            try? fileManager.removeItem(at: cache.appendingPathComponent(entry, isDirectory: true))
        }
    }

    /// Copy `source` to a hidden sibling of `destination`, then swap it in.
    private static func replace(_ destination: URL, withCopyOf source: URL, stagingIn cache: URL) throws {
        let fileManager = FileManager.default
        let staging = cache.appendingPathComponent(
            "\(stagingPrefix)\(destination.lastPathComponent)-\(UUID().uuidString)", isDirectory: true
        )
        do {
            try fileManager.copyItem(at: source, to: staging)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }
}
