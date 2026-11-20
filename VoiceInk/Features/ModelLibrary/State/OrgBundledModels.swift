import CryptoKit
import FluidAudio
import Foundation
import os

/// Organisation build: the configured model (plus VAD for Parakeet) ships inside the app bundle at
/// `Contents/Resources/Models/<folder>/`, sealed by the code signature. `Models/bundle.json`
/// (written at build time by scripts/org_bundle_model.py) lists a content id per folder.
///
/// On launch, `installIfNeeded()` makes sure the model folders exist where FluidAudio / TranscribeCpp
/// expect them. A folder that already carries the same content id (marker file
/// `.undertone-bundle-id`, or a one-time content check) is left untouched; otherwise the bundled copy
/// is cloned into a staging folder next to the target, verified, and renamed into place. No network.
enum OrgBundledModels {
    static let markerFileName = ".undertone-bundle-id"

    enum Outcome: Equatable {
        /// Bundle contains no model (built without one).
        case noBundledModel
        /// Everything was already in place.
        case upToDate
        /// Folders were installed from the bundle.
        case installed([String])
        case failed(String)
    }

    private struct BundleManifest: Decodable {
        let model: String
        let folders: [String: String]
    }

    private static let logger = Logger(subsystem: "com.undertone.app", category: "BundledModels")

    /// Result of the last `installIfNeeded()` (shown by the setup screen if something went wrong).
    nonisolated(unsafe) private(set) static var lastOutcome: Outcome = .noBundledModel

    static var bundledModelsDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Models", isDirectory: true)
    }

    /// Model name the bundle was built with, if any.
    static var bundledModelName: String? {
        loadManifest()?.model
    }

    private static func loadManifest() -> BundleManifest? {
        guard let directory = bundledModelsDirectory,
            let data = try? Data(contentsOf: directory.appendingPathComponent("bundle.json"))
        else { return nil }
        return try? JSONDecoder().decode(BundleManifest.self, from: data)
    }

    @discardableResult
    static func installIfNeeded() -> Outcome {
        let outcome = performInstall()
        lastOutcome = outcome
        switch outcome {
        case .installed(let folders):
            logger.notice("Installed bundled model folders: \(folders.joined(separator: ", "), privacy: .public)")
        case .failed(let message):
            logger.error("Bundled model install failed: \(message, privacy: .public)")
        default:
            break
        }
        return outcome
    }

    private static func performInstall() -> Outcome {
        guard let directory = bundledModelsDirectory, let manifest = loadManifest(), !manifest.folders.isEmpty else {
            return .noBundledModel
        }

        var installed: [String] = []
        for (folder, contentID) in manifest.folders.sorted(by: { $0.key < $1.key }) {
            let source = directory.appendingPathComponent(folder, isDirectory: true)
            guard let target = targetDirectory(forFolder: folder) else {
                return .failed("Unbekannter Modellordner „\(folder)“ in der App.")
            }
            do {
                if try installFolder(source: source, target: target, contentID: contentID, folder: folder) {
                    installed.append(folder)
                }
            } catch {
                return .failed(
                    "Das mitgelieferte Sprachmodell („\(folder)“) konnte nicht nach \(target.deletingLastPathComponent().path) kopiert werden: \(error.localizedDescription)"
                )
            }
        }
        return installed.isEmpty ? .upToDate : .installed(installed)
    }

    /// Where FluidAudio / TranscribeCpp look for a bundled folder.
    private static func targetDirectory(forFolder folder: String) -> URL? {
        if let artifact = TranscribeCppModelCatalog.artifact(for: folder) {
            return artifact.modelDirectory
        }
        let fluidAudioRoot = AsrModels.defaultCacheDirectory(for: .v3).deletingLastPathComponent()
        let known: Set<String> = [
            Repo.vad.folderName,
            AsrModels.defaultCacheDirectory(for: .v3).lastPathComponent,
            AsrModels.defaultCacheDirectory(for: .ultra).lastPathComponent,
        ]
        guard known.contains(folder) else { return nil }
        return fluidAudioRoot.appendingPathComponent(folder, isDirectory: true)
    }

    /// Returns true if the folder was (re)installed.
    private static func installFolder(source: URL, target: URL, contentID: String, folder: String) throws -> Bool {
        let fileManager = FileManager.default
        let marker = target.appendingPathComponent(markerFileName)

        if fileManager.fileExists(atPath: target.path) {
            if let existing = try? String(contentsOf: marker, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), existing == contentID
            {
                return false
            }
            // Folder from an earlier install (Hugging Face, package, VoiceInk): compare once by content.
            if (try? contentIdentifier(of: target)) == contentID {
                try? contentID.write(to: marker, atomically: true, encoding: .utf8)
                return false
            }
        }

        let parent = target.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".undertone-staging-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        // Clone (APFS) or copy out of the signed bundle, then check the copy before it goes live.
        let staged = staging.appendingPathComponent(folder, isDirectory: true)
        try fileManager.copyItem(at: source, to: staged)
        let stagedID = try contentIdentifier(of: staged)
        guard stagedID == contentID else {
            throw NSError(
                domain: "Undertone", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Die Kopie stimmt nicht mit der App überein (App beschädigt?)."])
        }
        if let artifact = TranscribeCppModelCatalog.artifact(for: folder) {
            try artifact.expectedSHA256.write(
                to: staged.appendingPathComponent(".\(artifact.fileName).sha256"), atomically: true, encoding: .utf8)
        }
        try contentID.write(to: staged.appendingPathComponent(markerFileName), atomically: true, encoding: .utf8)

        if fileManager.fileExists(atPath: target.path) {
            try fileManager.moveItem(at: target, to: staging.appendingPathComponent("previous", isDirectory: true))
        }
        try fileManager.moveItem(at: staged, to: target)
        return true
    }

    /// Content id of a model folder: SHA-256 over "<relative path>\0<size>\0<sha256>\n" for every
    /// regular file, sorted by path, ignoring hidden files and folders. Must match
    /// scripts/org_bundle_model.py.
    static func contentIdentifier(of directory: URL) throws -> String {
        let fileManager = FileManager.default
        let basePath = directory.standardizedFileURL.resolvingSymlinksInPath().path
        guard
            let enumerator = fileManager.enumerator(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles])
        else {
            throw CocoaError(.fileReadUnknown)
        }

        var entries: [(path: String, url: URL, size: Int)] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let fullPath = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard fullPath.hasPrefix(basePath + "/") else { continue }
            let relative = String(fullPath.dropFirst(basePath.count + 1))
            entries.append((relative, url, values.fileSize ?? 0))
        }
        entries.sort { Array($0.path.utf8).lexicographicallyPrecedes(Array($1.path.utf8)) }

        var outer = SHA256()
        for entry in entries {
            let fileHash = try sha256Hex(of: entry.url)
            outer.update(data: Data("\(entry.path)\u{0}\(entry.size)\u{0}\(fileHash)\n".utf8))
        }
        return outer.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 8 * 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
