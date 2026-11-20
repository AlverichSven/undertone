import CryptoKit
import FluidAudio
import Foundation
import ZIPFoundation
import os

/// Organisation build: installs models from a plain file server ("archive mode", e.g. a Nexus raw
/// repository) instead of the Hugging Face API.
///
/// Layout on the server (`modelArchiveBaseURL`):
///   {base}/parakeet-tdt-0.6b-v3.zip, {base}/parakeet-ultra.zip, {base}/silero-vad.zip
///   (each ZIP has the FluidAudio cache folder as its root), and
///   {base}/cohere-transcribe-03-2026-Q4_K_M.gguf
///
/// Integrity: size and SHA-256 of every file come from the app bundle (Info.plist key
/// `UndertoneModelArchiveManifest`, generated at build time from `org/models.json`), never from the
/// server. Files are downloaded into a staging folder, verified, and only then unpacked/moved into
/// place. A missing manifest entry is an error; nothing unverified is installed.
@MainActor
final class OrgModelArchiveInstaller: ObservableObject {
    static let shared = OrgModelArchiveInstaller()

    /// Cloud folder searched first for a model package (Defaults/MDM `modelPackageFolderName`).
    nonisolated static var preferredFolderName: String {
        let configured = UserDefaults.standard.string(forKey: "modelPackageFolderName")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (configured?.isEmpty == false ? configured : nil) ?? "Undertone"
    }

    @Published private(set) var isRunning = false
    @Published private(set) var fractionCompleted: Double = 0
    @Published private(set) var message = ""
    @Published private(set) var lastError: String?

    private var task: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.undertone.app", category: "ModelArchive")

    static let vadArchiveName = "silero-vad.zip"

    private init() {}

    // MARK: - Public API

    func install(
        model: any TranscriptionModel,
        fluidAudioModelManager: FluidAudioModelManager,
        onFinished: @escaping @MainActor () -> Void
    ) {
        guard !isRunning else { return }
        guard let base = OrgEdition.modelArchiveBaseURL else {
            lastError = "Kein Modell-Archiv konfiguriert."
            return
        }

        let jobs: [Job]
        do {
            jobs = try Self.jobs(for: model)
        } catch {
            lastError = error.localizedDescription
            return
        }

        isRunning = true
        lastError = nil
        fractionCompleted = 0
        message = "Download wird vorbereitet …"

        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.run(jobs: jobs, base: base)
                self.message = "Fertig."
                self.fractionCompleted = 1
            } catch is CancellationError {
                self.lastError = "Download abgebrochen."
            } catch {
                self.logger.error("Archive install failed: \(error.localizedDescription, privacy: .public)")
                self.lastError = error.localizedDescription
            }
            self.isRunning = false
            self.task = nil
            self.fluidAudioModelManager = fluidAudioModelManager
            fluidAudioModelManager.refreshAfterExternalInstall()
            TranscribeCppModelManager.shared.onModelsChanged?()
            onFinished()
        }
    }

    func cancel() {
        task?.cancel()
    }

    func clearError() {
        lastError = nil
    }

    // MARK: - Model package from a local file (download or shared cloud folder)

    /// A package file found by the automatic search.
    struct FoundPackage: Equatable {
        let url: URL
        /// OneDrive/iCloud placeholder that is not on this Mac yet.
        let isPlaceholder: Bool
    }

    /// Set by the app so installs started from "Open with…" can refresh the model state.
    weak var fluidAudioModelManager: FluidAudioModelManager?

    @Published private(set) var isSearching = false
    @Published private(set) var foundPackages: [FoundPackage] = []
    @Published private(set) var didSearch = false

    /// Installs `Undertone-Sprachmodell-<model>.zip` from a local file after verifying size and
    /// SHA-256 against the manifest built into the app. The file is first copied into a staging
    /// folder and verified there, so it cannot change between check and unpacking.
    func installPackage(at sourceURL: URL, onFinished: @escaping @MainActor () -> Void = {}) {
        guard !isRunning else { return }
        guard let model = OrgModelSetup.configuredModel else {
            lastError = "Unbekanntes Sprachmodell."
            return
        }

        isRunning = true
        lastError = nil
        fractionCompleted = 0
        message = "Prüfe \(sourceURL.lastPathComponent) …"

        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.runPackage(source: sourceURL, model: model)
                self.message = "Fertig."
                self.fractionCompleted = 1
                self.foundPackages = []
            } catch is CancellationError {
                self.lastError = "Installation abgebrochen."
            } catch {
                self.logger.error("Package install failed: \(error.localizedDescription, privacy: .public)")
                self.lastError = error.localizedDescription
            }
            self.isRunning = false
            self.task = nil
            self.fluidAudioModelManager?.refreshAfterExternalInstall()
            TranscribeCppModelManager.shared.onModelsChanged?()
            onFinished()
        }
    }

    /// Looks for the package of the configured model in ~/Downloads and in the OneDrive/cloud folders
    /// below ~/Library/CloudStorage (max. depth 3, folders named like `preferredFolderName` first).
    func searchForPackage() {
        guard !isSearching, let model = OrgModelSetup.configuredModel else { return }
        isSearching = true
        let packageName = OrgEdition.modelPackageFileName(for: model.name)
        let expectedSize = OrgEdition.modelArchiveManifest[packageName]?.size

        Task { [weak self] in
            let results = await Task.detached(priority: .userInitiated) {
                Self.findPackages(named: packageName, expectedSize: expectedSize)
            }.value
            guard let self else { return }
            self.foundPackages = results
            self.isSearching = false
            self.didSearch = true
        }
    }

    nonisolated static func findPackages(named packageName: String, expectedSize: Int64?) -> [FoundPackage] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let stem = (packageName as NSString).deletingPathExtension.lowercased()

        func matches(_ url: URL) -> Bool {
            let name = url.lastPathComponent.lowercased()
            // Accept browser duplicates such as "… (1).zip".
            return name.hasSuffix(".zip") && name.hasPrefix(stem)
                && (name == stem + ".zip" || name.dropFirst(stem.count).hasPrefix(" ("))
        }

        func isPlaceholder(_ url: URL) -> Bool {
            var info = stat()
            if lstat(url.path, &info) == 0, info.st_flags & 0x4000_0000 != 0 {  // SF_DATALESS
                return true
            }
            if let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                .ubiquitousItemDownloadingStatus, status == .notDownloaded
            {
                return true
            }
            return false
        }

        func scan(_ directory: URL, depth: Int, into results: inout [URL]) {
            guard depth >= 0,
                let entries = try? fileManager.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                    options: [.skipsHiddenFiles])
            else { return }
            // Folders named like the preferred folder first.
            let sorted = entries.sorted { lhs, rhs in
                let l = lhs.lastPathComponent.contains(Self.preferredFolderName)
                let r = rhs.lastPathComponent.contains(Self.preferredFolderName)
                return l && !r
            }
            for entry in sorted {
                let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                if values?.isDirectory == true {
                    if values?.isPackage != true {
                        scan(entry, depth: depth - 1, into: &results)
                    }
                } else if matches(entry) {
                    results.append(entry)
                }
            }
        }

        var urls: [URL] = []
        let cloudRoot = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        // Preferred: a folder named like `preferredFolderName` inside the cloud providers.
        if let providers = try? fileManager.contentsOfDirectory(
            at: cloudRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        {
            for provider in providers {
                scan(provider, depth: 2, into: &urls)
            }
        }
        scan(home.appendingPathComponent("Downloads", isDirectory: true), depth: 2, into: &urls)

        var seen = Set<String>()
        let unique = urls.filter { seen.insert($0.standardizedFileURL.path).inserted }

        let packages = unique.map { url in
            FoundPackage(url: url, isPlaceholder: isPlaceholder(url))
        }
        .filter { package in
            // A local copy with the wrong size cannot be the package; placeholders are kept.
            guard !package.isPlaceholder, let expectedSize else { return true }
            let size = (try? package.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
            return size == expectedSize
        }

        // Community folder first, then local files before placeholders.
        return packages.sorted { lhs, rhs in
            let l = lhs.url.path.contains(Self.preferredFolderName)
            let r = rhs.url.path.contains(Self.preferredFolderName)
            if l != r { return l }
            return !lhs.isPlaceholder && rhs.isPlaceholder
        }
    }

    private func runPackage(source: URL, model: any TranscriptionModel) async throws {
        let packageName = OrgEdition.modelPackageFileName(for: model.name)
        let entry = try Self.manifestEntry(for: packageName)

        let modelsRoot = AsrModels.defaultCacheDirectory(for: .v3).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        let staging = modelsRoot.appendingPathComponent(".undertone-staging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        // 1. Private copy (APFS clone when on the same volume).
        message = "Kopiere \(source.lastPathComponent) …"
        fractionCompleted = 0.02
        let copy = staging.appendingPathComponent("package.zip")
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.copyItem(at: source, to: copy)
        }.value
        try Task.checkCancellation()

        // 2. Verify against the manifest before anything is unpacked.
        message = "Prüfe Prüfsumme …"
        fractionCompleted = 0.25
        let size = (try? copy.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1
        let hash = try await Task.detached(priority: .userInitiated) { try Self.sha256(of: copy) }.value
        guard size == entry.size, hash == entry.sha256 else {
            let otherPackage = OrgEdition.modelArchiveManifest.first { name, value in
                name != packageName && name.hasPrefix(OrgEdition.modelPackagePrefix)
                    && value.size == size && value.sha256 == hash
            }?.key
            logger.error(
                "Package check failed for \(source.path, privacy: .public): size \(size), sha256 \(hash, privacy: .public)")
            if let otherPackage {
                throw ArchiveError(
                    "„\(source.lastPathComponent)“ ist das Paket \(otherPackage), eingestellt ist aber \(packageName). Nichts installiert."
                )
            }
            throw ArchiveError(
                "Modelldatei beschädigt oder verändert: „\(source.lastPathComponent)“ stimmt nicht mit der erwarteten Prüfsumme überein. Nichts installiert. Bitte die Datei erneut herunterladen."
            )
        }
        try Task.checkCancellation()

        // 3. Unpack into the staging folder.
        message = "Entpacke …"
        fractionCompleted = 0.5
        let unpackDir = staging.appendingPathComponent("unpacked", isDirectory: true)
        let unzipProgress = Progress()
        let progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                self?.fractionCompleted = 0.5 + 0.45 * unzipProgress.fractionCompleted
            }
        }
        defer { progressTask.cancel() }
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: unpackDir, withIntermediateDirectories: true)
            try FileManager.default.unzipItem(at: copy, to: unpackDir, progress: unzipProgress)
        }.value
        progressTask.cancel()
        try Task.checkCancellation()

        // 4. Move the expected folders into place.
        message = "Installiere …"
        func requireFolder(_ name: String) throws -> URL {
            let folder = unpackDir.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue
            else {
                throw ArchiveError("Das Paket enthält den Ordner „\(name)“ nicht.")
            }
            return folder
        }

        switch model.provider {
        case .fluidAudio:
            let version = FluidAudioModelManager.asrVersion(for: model.name)
            let modelFolderName = AsrModels.defaultCacheDirectory(for: version).lastPathComponent
            let modelFolder = try requireFolder(modelFolderName)
            let vadFolder = try requireFolder(Repo.vad.folderName)
            if !Self.vadIsInstalled(modelsRoot: modelsRoot) {
                try Self.replaceItem(
                    at: modelsRoot.appendingPathComponent(Repo.vad.folderName, isDirectory: true),
                    with: vadFolder, staging: staging)
            }
            try Self.replaceItem(
                at: modelsRoot.appendingPathComponent(modelFolderName, isDirectory: true),
                with: modelFolder, staging: staging)

        case .transcribeCpp:
            guard let artifact = TranscribeCppModelCatalog.artifact(for: model.name) else {
                throw ArchiveError("Unbekanntes Modell \(model.name).")
            }
            let folder = try requireFolder(artifact.modelName)
            let file = folder.appendingPathComponent(artifact.fileName)
            let fileSize = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
            guard fileSize == artifact.expectedFileSize else {
                throw ArchiveError("Das Paket enthält eine unerwartete Version von \(artifact.fileName).")
            }
            try FileManager.default.createDirectory(at: artifact.modelDirectory, withIntermediateDirectories: true)
            try artifact.expectedSHA256.write(to: artifact.checksumFileURL, atomically: true, encoding: .utf8)
            try Self.replaceItem(at: artifact.modelFileURL, with: file, staging: staging)

        default:
            throw ArchiveError("Modell \(model.name) wird nicht unterstützt.")
        }

        logger.notice("Installed \(packageName, privacy: .public) from \(source.path, privacy: .public)")
    }

    // MARK: - Jobs

    private enum Destination {
        /// ZIP whose single root folder `folderName` is moved into `parent`.
        case folder(folderName: String, parent: URL)
        /// Plain file moved to `fileURL`; `checksumFile` receives the expected SHA-256 first.
        case file(fileURL: URL, checksumFile: URL?, checksum: String?)
    }

    private struct Job {
        let fileName: String
        let size: Int64
        let sha256: String
        let destination: Destination
    }

    private struct ArchiveError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private static func manifestEntry(for fileName: String) throws -> (size: Int64, sha256: String) {
        guard let entry = OrgEdition.modelArchiveManifest[fileName] else {
            throw ArchiveError(
                "Für „\(fileName)“ fehlt die Prüfsumme in dieser App (org/models.json beim Bau). Die Datei wird aus Sicherheitsgründen nicht geladen. Bitte die IT kontaktieren."
            )
        }
        return entry
    }

    private static func jobs(for model: any TranscriptionModel) throws -> [Job] {
        var jobs: [Job] = []

        switch model.provider {
        case .fluidAudio:
            let version = FluidAudioModelManager.asrVersion(for: model.name)
            let modelFolder = AsrModels.defaultCacheDirectory(for: version)
            let modelsRoot = modelFolder.deletingLastPathComponent()

            if !vadIsInstalled(modelsRoot: modelsRoot) {
                let entry = try manifestEntry(for: vadArchiveName)
                jobs.append(
                    Job(
                        fileName: vadArchiveName, size: entry.size, sha256: entry.sha256,
                        destination: .folder(folderName: Repo.vad.folderName, parent: modelsRoot)))
            }

            if !AsrModels.modelsExist(at: modelFolder, version: version) {
                let fileName = "\(model.name).zip"
                let entry = try manifestEntry(for: fileName)
                jobs.append(
                    Job(
                        fileName: fileName, size: entry.size, sha256: entry.sha256,
                        destination: .folder(folderName: modelFolder.lastPathComponent, parent: modelsRoot)))
            }

        case .transcribeCpp:
            guard let artifact = TranscribeCppModelCatalog.artifact(for: model.name) else {
                throw ArchiveError("Unbekanntes Modell \(model.name).")
            }
            if artifact.installedModelFileURL == nil {
                let entry = try manifestEntry(for: artifact.fileName)
                // The app's own catalog must agree with the build manifest, otherwise TranscribeCpp
                // would reject the installed file anyway.
                guard entry.size == artifact.expectedFileSize,
                    entry.sha256.lowercased() == artifact.expectedSHA256.lowercased()
                else {
                    throw ArchiveError(
                        "Die Prüfsumme für „\(artifact.fileName)“ in org/models.json passt nicht zur erwarteten Modellversion."
                    )
                }
                jobs.append(
                    Job(
                        fileName: artifact.fileName, size: entry.size, sha256: entry.sha256,
                        destination: .file(
                            fileURL: artifact.modelFileURL,
                            checksumFile: artifact.checksumFileURL,
                            checksum: artifact.expectedSHA256)))
            }

        default:
            throw ArchiveError("Modell \(model.name) wird im Archiv-Modus nicht unterstützt.")
        }

        return jobs
    }

    nonisolated private static func vadIsInstalled(modelsRoot: URL) -> Bool {
        let folder = modelsRoot.appendingPathComponent(Repo.vad.folderName, isDirectory: true)
        return ModelNames.VAD.requiredModels.allSatisfy { name in
            FileManager.default.fileExists(
                atPath: folder.appendingPathComponent(name).appendingPathComponent("coremldata.bin").path)
        }
    }

    // MARK: - Run

    private func run(jobs: [Job], base: String) async throws {
        let totalBytes = max(jobs.reduce(Int64(0)) { $0 + $1.size }, 1)
        var completedBytes: Int64 = 0

        for job in jobs {
            try Task.checkCancellation()
            guard let url = URL(string: "\(base)/\(job.fileName)") else {
                throw ArchiveError("Ungültige Archiv-URL: \(base)/\(job.fileName)")
            }

            let stagingParent: URL
            switch job.destination {
            case .folder(_, let parent):
                stagingParent = parent
            case .file(let fileURL, _, _):
                stagingParent = fileURL.deletingLastPathComponent()
            }
            let staging = stagingParent
                .appendingPathComponent(".undertone-staging-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }

            let downloadedFile = staging.appendingPathComponent(job.fileName)
            let baseBytes = completedBytes
            message = "Lade \(job.fileName) …"
            try await ArchiveDownload.run(url: url, to: downloadedFile) { [weak self] written in
                Task { @MainActor in
                    guard let self else { return }
                    let done = Double(baseBytes + min(written, job.size))
                    self.fractionCompleted = min(done / Double(totalBytes), 0.99)
                    self.message =
                        "Lade \(job.fileName) … \(ByteCountFormatter.string(fromByteCount: baseBytes + written, countStyle: .file)) von \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))"
                }
            }
            try Task.checkCancellation()

            message = "Prüfe \(job.fileName) …"
            let actualSize = (try? downloadedFile.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1
            let actualHash = try await Task.detached(priority: .utility) {
                try Self.sha256(of: downloadedFile)
            }.value
            guard actualSize == job.size, actualHash == job.sha256.lowercased() else {
                try? FileManager.default.removeItem(at: downloadedFile)
                logger.error(
                    "Integrity check failed for \(job.fileName, privacy: .public): size \(actualSize) (expected \(job.size)), sha256 \(actualHash, privacy: .public)"
                )
                throw ArchiveError(
                    "Modelldatei beschädigt oder verändert: „\(job.fileName)“ stimmt nicht mit der erwarteten Prüfsumme überein und wurde verworfen. Bitte die IT informieren."
                )
            }
            try Task.checkCancellation()

            switch job.destination {
            case .folder(let folderName, let parent):
                message = "Entpacke \(job.fileName) …"
                let unpackDir = staging.appendingPathComponent("unpacked", isDirectory: true)
                try await Task.detached(priority: .utility) {
                    try FileManager.default.createDirectory(at: unpackDir, withIntermediateDirectories: true)
                    try FileManager.default.unzipItem(at: downloadedFile, to: unpackDir)
                }.value
                let unpackedFolder = unpackDir.appendingPathComponent(folderName, isDirectory: true)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: unpackedFolder.path, isDirectory: &isDirectory),
                    isDirectory.boolValue
                else {
                    throw ArchiveError("„\(job.fileName)“ enthält nicht den erwarteten Ordner „\(folderName)“.")
                }
                try Self.replaceItem(at: parent.appendingPathComponent(folderName, isDirectory: true),
                                     with: unpackedFolder, staging: staging)

            case .file(let fileURL, let checksumFile, let checksum):
                if let checksumFile, let checksum {
                    try checksum.write(to: checksumFile, atomically: true, encoding: .utf8)
                }
                try Self.replaceItem(at: fileURL, with: downloadedFile, staging: staging)
            }

            completedBytes += job.size
            fractionCompleted = min(Double(completedBytes) / Double(totalBytes), 1)
            logger.notice("Installed \(job.fileName, privacy: .public) from archive")
        }
    }

    /// Moves `source` to `target` (same volume → rename). An existing (incomplete) target is moved
    /// aside first and removed afterwards.
    nonisolated private static func replaceItem(at target: URL, with source: URL, staging: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: target.path) {
            let aside = staging.appendingPathComponent("previous-\(UUID().uuidString)")
            try fileManager.moveItem(at: target, to: aside)
        }
        try fileManager.moveItem(at: source, to: target)
    }

    nonisolated private static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Single file download with progress into a fixed location.
private final class ArchiveDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var moveError: Error?
    private var statusCode: Int?

    private init(destination: URL, onProgress: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    static func run(url: URL, to destination: URL, onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        let operation = ArchiveDownload(destination: destination, onProgress: onProgress)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: configuration, delegate: operation, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let downloadTask = session.downloadTask(with: url)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.continuation = continuation
                downloadTask.resume()
            }
        } onCancel: {
            downloadTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode
        guard let statusCode, (200...299).contains(statusCode) else { return }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: Result<Void, Error>
        if let error {
            if (error as? URLError)?.code == .cancelled {
                result = .failure(CancellationError())
            } else {
                result = .failure(
                    NSError(
                        domain: "Undertone", code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Verbindung zu \(task.originalRequest?.url?.absoluteString ?? "Server") fehlgeschlagen: \(error.localizedDescription)"
                        ]))
            }
        } else if let moveError {
            result = .failure(moveError)
        } else if let statusCode = statusCode ?? (task.response as? HTTPURLResponse)?.statusCode,
            !(200...299).contains(statusCode)
        {
            result = .failure(
                NSError(
                    domain: "Undertone", code: statusCode,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Server antwortete mit HTTP \(statusCode) für \(task.originalRequest?.url?.absoluteString ?? "")."
                    ]))
        } else {
            result = .success(())
        }
        continuation?.resume(with: result)
        continuation = nil
    }
}
