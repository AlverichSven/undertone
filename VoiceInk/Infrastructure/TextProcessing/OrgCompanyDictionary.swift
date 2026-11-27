import AppKit
import Foundation
import os

/// Company dictionary of the organisation build (Undertone): vocabulary, project keys and
/// replacements from a shared JSON file (`Undertone-Woerterbuch.json`, format: `OrgCompanyDictionaryContent`).
///
/// - Sources: automatically at launch and once a day the newest file of that name below
///   `~/Library/CloudStorage/*/` (depth 4, OneDrive/SharePoint sync) and `~/Downloads` (depth 2);
///   OneDrive placeholders (not on this Mac) are skipped and listed in the settings. By hand:
///   „Firmenwörterbuch importieren …“ or „Öffnen mit > Undertone“.
/// - The loaded file is copied to `~/Library/Application Support/com.undertone.app/Firmenwoerterbuch.json`
///   and kept apart from the user's own dictionary entries (SwiftData), so a newer company file
///   simply replaces the old one and „Entfernen“ leaves the user's entries alone.
/// - Defaults keys: `orgCompanyDictionaryEnabled` (default on), `orgCompanyDictionaryAutoSearch`
///   (default on), `orgCompanyDictionarySource`, `orgCompanyDictionarySourceDate`,
///   `orgCompanyDictionaryRemovedDate`.
@MainActor
final class OrgCompanyDictionary: ObservableObject {
    static let shared = OrgCompanyDictionary()

    static let enabledKey = "orgCompanyDictionaryEnabled"
    static let autoSearchKey = "orgCompanyDictionaryAutoSearch"
    static let sourceKey = "orgCompanyDictionarySource"
    static let sourceDateKey = "orgCompanyDictionarySourceDate"
    static let removedDateKey = "orgCompanyDictionaryRemovedDate"
    nonisolated static let fileName = "Undertone-Woerterbuch.json"
    private static let storedFileName = "Firmenwoerterbuch.json"

    struct Placeholder: Identifiable, Equatable {
        let path: String
        var id: String { path }
        var displayPath: String { (path as NSString).abbreviatingWithTildeInPath }
    }

    @Published private(set) var content: OrgCompanyDictionaryContent?
    @Published private(set) var sourcePath: String?
    @Published private(set) var sourceDate: Date?
    @Published private(set) var placeholders: [Placeholder] = []
    @Published private(set) var isSearching = false
    @Published private(set) var lastMessage: String?

    private var terms = OrgCompanyTerms(keys: [], replacements: [])
    private var dailyTimer: Timer?
    private let logger = Logger(subsystem: "com.undertone.app", category: "OrgCompanyDictionary")

    private init() {
        loadStoredCopy()
    }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    private var isActive: Bool { OrgEdition.isEnabled && isEnabled && content != nil }

    // MARK: - Use in the text pipeline

    /// Company words for VoiceInk's vocabulary correction (added to the user's own words).
    var vocabularyWords: [String] {
        guard isActive, let content else { return [] }
        return content.cleanedWords
    }

    func applyProjectKeys(_ text: String) -> String {
        guard isActive else { return text }
        return terms.applyProjectKeys(to: text)
    }

    func applyReplacements(_ text: String) -> String {
        guard isActive else { return text }
        return terms.applyReplacements(to: text)
    }

    // MARK: - Storage

    private static var storedFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(OrgEdition.appSupportFolderName, isDirectory: true)
        return base.appendingPathComponent(storedFileName)
    }

    private func loadStoredCopy() {
        guard OrgEdition.isEnabled,
            let data = try? Data(contentsOf: Self.storedFileURL),
            let decoded = try? OrgCompanyDictionaryContent.decode(data)
        else { return }
        apply(decoded)
        sourcePath = UserDefaults.standard.string(forKey: Self.sourceKey)
        sourceDate = UserDefaults.standard.object(forKey: Self.sourceDateKey) as? Date
    }

    private func apply(_ newContent: OrgCompanyDictionaryContent?) {
        content = newContent
        terms = newContent.map(OrgCompanyTerms.init(content:)) ?? OrgCompanyTerms(keys: [], replacements: [])
    }

    /// Loads a file and makes it the company dictionary (replaces the previous one).
    @discardableResult
    func importFile(at url: URL, automatic: Bool = false) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            let decoded = try OrgCompanyDictionaryContent.decode(data)
            let folder = Self.storedFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: Self.storedFileURL, options: .atomic)

            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            let defaults = UserDefaults.standard
            defaults.set(url.path, forKey: Self.sourceKey)
            defaults.set(modified, forKey: Self.sourceDateKey)
            if !automatic { defaults.removeObject(forKey: Self.removedDateKey) }
            apply(decoded)
            sourcePath = url.path
            sourceDate = modified
            lastMessage = nil
            logger.notice("Company dictionary loaded automatic=\(automatic, privacy: .public)")
            return true
        } catch {
            logger.error("Company dictionary not loaded: \(error.localizedDescription, privacy: .public)")
            if !automatic {
                lastMessage = "Die Datei konnte nicht gelesen werden. Erwartet wird ein Firmenwörterbuch im JSON-Format (woerter, jiraSchluessel, ersetzungen)."
            }
            return false
        }
    }

    /// „Entfernen“: drops the company dictionary; the automatic search only picks up a newer file.
    func remove() {
        try? FileManager.default.removeItem(at: Self.storedFileURL)
        let defaults = UserDefaults.standard
        defaults.set(sourceDate ?? Date(), forKey: Self.removedDateKey)
        defaults.removeObject(forKey: Self.sourceKey)
        defaults.removeObject(forKey: Self.sourceDateKey)
        apply(nil)
        sourcePath = nil
        sourceDate = nil
        lastMessage = nil
    }

    // MARK: - Import dialog

    func showImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Firmenwörterbuch importieren"
        panel.message = "Bitte wählen Sie die Datei \(Self.fileName) aus."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            importFile(at: url)
        }
    }

    /// „Öffnen mit > Undertone“ and drop on the Dock icon.
    nonisolated static func isDictionaryFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let stem = (fileName as NSString).deletingPathExtension.lowercased()
        guard name.hasSuffix(".json") else { return false }
        return name.hasPrefix(stem) || name.hasPrefix("undertone-wörterbuch")
    }

    // MARK: - Automatic search

    /// Called at launch: search now and then once a day.
    func startAutomaticUpdates() {
        guard OrgEdition.isEnabled else { return }
        searchAutomatically()
        dailyTimer?.invalidate()
        dailyTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { _ in
            Task { @MainActor in OrgCompanyDictionary.shared.searchAutomatically() }
        }
    }

    private func searchAutomatically() {
        guard UserDefaults.standard.object(forKey: Self.autoSearchKey) as? Bool ?? true else { return }
        search(automatic: true)
    }

    /// Looks for the newest `Undertone-Woerterbuch.json` and loads it if it is newer than the current one.
    func search(automatic: Bool = false) {
        guard !isSearching else { return }
        isSearching = true
        Task {
            let found = await Task.detached(priority: .utility) { Self.findFiles() }.value
            self.isSearching = false
            self.placeholders = found.placeholders.map { Placeholder(path: $0.path) }

            let defaults = UserDefaults.standard
            let removedDate = defaults.object(forKey: Self.removedDateKey) as? Date
            guard let newest = found.local.first else {
                if !automatic {
                    self.lastMessage = found.placeholders.isEmpty
                        ? "Kein Firmenwörterbuch gefunden (\(Self.fileName) in OneDrive/SharePoint oder Downloads)."
                        : "Das Firmenwörterbuch liegt nur in OneDrive und ist noch nicht auf diesem Mac."
                }
                return
            }
            let isNewer = self.sourceDate.map { newest.date > $0 } ?? true
            let isAfterRemoval = removedDate.map { newest.date > $0 } ?? true
            let changedSource = self.sourcePath != newest.url.path
            if self.content == nil ? isAfterRemoval || !automatic : (isNewer || (changedSource && !automatic)) {
                self.importFile(at: newest.url, automatic: automatic)
            } else if !automatic {
                self.lastMessage = "Das Firmenwörterbuch ist aktuell."
            }
        }
    }

    private struct FoundFiles: Sendable {
        var local: [(url: URL, date: Date)]
        var placeholders: [URL]
    }

    nonisolated private static func findFiles() -> FoundFiles {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        var candidates: [URL] = []

        func scan(_ directory: URL, depth: Int) {
            guard depth >= 0,
                let entries = try? fileManager.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                    options: [.skipsHiddenFiles])
            else { return }
            for entry in entries {
                let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                if values?.isDirectory == true {
                    if values?.isPackage != true { scan(entry, depth: depth - 1) }
                } else if isDictionaryFile(entry) {
                    candidates.append(entry)
                }
            }
        }

        let cloudRoot = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        if let providers = try? fileManager.contentsOfDirectory(
            at: cloudRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        {
            // ~/Library/CloudStorage/<Anbieter>/ + bis zu 4 Ebenen darunter.
            for provider in providers { scan(provider, depth: 4) }
        }
        scan(home.appendingPathComponent("Downloads", isDirectory: true), depth: 2)

        var local: [(url: URL, date: Date)] = []
        var placeholders: [URL] = []
        for url in candidates {
            if isPlaceholder(url) {
                placeholders.append(url)
            } else {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                local.append((url, date))
            }
        }
        local.sort { $0.date > $1.date }
        return FoundFiles(local: local, placeholders: placeholders)
    }

    /// OneDrive/iCloud file that is listed but not downloaded to this Mac.
    nonisolated private static func isPlaceholder(_ url: URL) -> Bool {
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
}
