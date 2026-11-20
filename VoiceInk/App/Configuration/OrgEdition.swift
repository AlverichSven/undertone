import Carbon.HIToolbox
import AppKit
import Foundation

#if ORG_EDITION
    import FluidAudio
#endif

/// Central switches and constants for the organisation build ("Undertone").
///
/// The organisation build is compiled with the `ORG_EDITION` flag (`make org`). In the normal
/// VoiceInk build every value here resolves to the upstream behaviour, so call sites can use
/// `OrgEdition.isEnabled` / `OrgEdition.appName` without changing upstream behaviour.
enum OrgEdition {
    #if ORG_EDITION
        static let isEnabled = true
    #else
        static let isEnabled = false
    #endif

    /// Visible product name.
    static let appName = isEnabled ? "Undertone" : "VoiceInk"

    /// Folder below ~/Library/Application Support for SwiftData stores and app-managed models.
    /// The organisation build keeps its own data so it never shares stores with VoiceInk.
    static let appSupportFolderName = isEnabled ? "com.undertone.app" : "com.prakashjoshipax.VoiceInk"

    /// The only transcription models offered in the organisation build (order = display order).
    static let allowedTranscriptionModelNames: [String] = [
        "parakeet-tdt-0.6b-v3",
        "parakeet-ultra",
        "cohere-transcribe",
    ]

    static let defaultTranscriptionModelName = "parakeet-tdt-0.6b-v3"

    static let transcriptionModelDefaultsKey = "transcriptionModel"
    static let transcriptionModelInfoPlistKey = "UndertoneTranscriptionModel"

    /// Model chosen centrally by the administrator. Users cannot change it.
    /// Priority: UserDefaults/MDM key `transcriptionModel` → Info.plist `UndertoneTranscriptionModel`
    /// → Parakeet V3. Values outside `allowedTranscriptionModelNames` fall back to Parakeet V3.
    static var configuredTranscriptionModelName: String {
        let candidates: [String?] = [
            UserDefaults.standard.string(forKey: transcriptionModelDefaultsKey),
            Bundle.main.object(forInfoDictionaryKey: transcriptionModelInfoPlistKey) as? String,
        ]

        for candidate in candidates {
            guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                continue
            }
            return allowedTranscriptionModelNames.contains(value) ? value : defaultTranscriptionModelName
        }

        return defaultTranscriptionModelName
    }
    static let defaultLanguage = "de"

    /// Same id as the upstream "Dictation" starter mode, so existing helpers recognise it.
    static let dictationModeID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

    static let attributionText =
        "Undertone basiert auf VoiceInk von Prakash Joshi Pax (https://github.com/Beingpax/VoiceInk), Lizenz GPLv3. Quellcode von Undertone: https://github.com/AlverichSven/undertone"
    static let sourceCodeURL = URL(string: "https://github.com/AlverichSven/undertone")!

    // MARK: - Model server

    static let modelServerDefaultsKey = "modelServerBaseURL"
    static let modelServerInfoPlistKey = "UndertoneModelServerBaseURL"
    static let fallbackModelServerBaseURL = "https://huggingface.co"

    /// Base URL for all model downloads (`{base}/{repo}/resolve/{revision}/{file}`).
    /// Priority: UserDefaults/MDM key `modelServerBaseURL` → Info.plist `UndertoneModelServerBaseURL`
    /// → upstream Hugging Face.
    static var modelServerBaseURL: String {
        let candidates: [String?] = [
            UserDefaults.standard.string(forKey: modelServerDefaultsKey),
            Bundle.main.object(forInfoDictionaryKey: modelServerInfoPlistKey) as? String,
        ]

        for candidate in candidates {
            if let normalized = normalizedBaseURL(candidate) {
                return normalized
            }
        }

        return fallbackModelServerBaseURL
    }

    // MARK: - Model archive (plain file server, e.g. Nexus raw repository)

    // MARK: - Updates (Sparkle; GitHub Releases or any static file server)

    static let updateFeedDefaultsKey = "updateFeedBaseURL"
    static let updateFeedInfoPlistKey = "UndertoneUpdateFeedBaseURL"

    /// appcast.xml below the update base URL. Priority: UserDefaults/MDM `updateFeedBaseURL`
    /// → Info.plist `UndertoneUpdateFeedBaseURL` (make org UPDATE_FEED_BASE=…). Nil = Info.plist SUFeedURL.
    static var updateFeedURLString: String? {
        let candidates: [String?] = [
            UserDefaults.standard.string(forKey: updateFeedDefaultsKey),
            Bundle.main.object(forInfoDictionaryKey: updateFeedInfoPlistKey) as? String,
        ]
        for candidate in candidates {
            if let base = normalizedBaseURL(candidate) {
                return base + "/appcast.xml"
            }
        }
        return nil
    }

    /// "1.0.0 (202611201530)"
    static var versionDescription: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    static let modelArchiveDefaultsKey = "modelArchiveBaseURL"
    static let modelArchiveInfoPlistKey = "UndertoneModelArchiveBaseURL"
    static let modelArchiveManifestInfoPlistKey = "UndertoneModelArchiveManifest"

    /// Base URL of the model archive. When set, models are downloaded as verified ZIP/GGUF files
    /// from `{base}/<file>` instead of the Hugging Face API.
    /// Priority: UserDefaults/MDM key `modelArchiveBaseURL` → Info.plist `UndertoneModelArchiveBaseURL`
    /// → none (Hugging Face path).
    static var modelArchiveBaseURL: String? {
        let candidates: [String?] = [
            UserDefaults.standard.string(forKey: modelArchiveDefaultsKey),
            Bundle.main.object(forInfoDictionaryKey: modelArchiveInfoPlistKey) as? String,
        ]
        for candidate in candidates {
            if let normalized = normalizedBaseURL(candidate) {
                return normalized
            }
        }
        return nil
    }

    static var isModelArchiveModeEnabled: Bool { modelArchiveBaseURL != nil }

    /// Model package distributed as a file (download or shared folder): contains the model
    /// folder and, for Parakeet, `silero-vad/` (FluidAudio layout) or `cohere-transcribe/<gguf>`.
    static let modelPackagePrefix = "Undertone-Sprachmodell-"
    /// Set to true (defaults/MDM) to let the setup screen search ~/Downloads and OneDrive by itself.
    static let modelPackageAutoSearchDefaultsKey = "modelPackageAutoSearch"

    static func modelPackageFileName(for modelName: String) -> String {
        "\(modelPackagePrefix)\(modelName).zip"
    }

    /// Expected size and SHA-256 per archive file, embedded at build time from `org/models.json`.
    /// Never taken from the server.
    static var modelArchiveManifest: [String: (size: Int64, sha256: String)] {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: modelArchiveManifestInfoPlistKey) as? [String: Any]
        else { return [:] }
        var result: [String: (size: Int64, sha256: String)] = [:]
        for (fileName, value) in raw {
            guard let entry = value as? [String: Any],
                let sha = entry["sha256"] as? String, sha.count == 64,
                let size = (entry["size"] as? NSNumber)?.int64Value, size > 0
            else { continue }
            result[fileName] = (size, sha.lowercased())
        }
        return result
    }

    /// Builds a Hugging Face style file URL below `modelServerBaseURL`.
    static func modelFileURL(repository: String, revision: String, fileName: String) -> URL? {
        URL(string: "\(modelServerBaseURL)/\(repository)/resolve/\(revision)/\(fileName)")
    }

    private static func normalizedBaseURL(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        while value.hasSuffix("/") {
            value.removeLast()
        }

        guard let url = URL(string: value),
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            url.host != nil
        else {
            return nil
        }

        return value
    }

    // MARK: - Startup

    /// Called from `AppDefaults.registerDefaults()` before any manager reads its settings.
    static func applyStartupConfiguration() {
        #if ORG_EDITION
            UserDefaults.standard.register(defaults: [
                "SelectedLanguage": defaultLanguage,
                "enableAnnouncements": false,
                AutoLearnSettings.isEnabledKey: false,
                "primaryRecordingShortcutMode": RecordingShortcutManager.Mode.pushToTalk.rawValue,
                RecorderDisplaySettingsKeys.showLiveTranscript: true,
                "restoreClipboardAfterPaste": true,
            ])

            // Features that must stay off even if a value was written earlier.
            UserDefaults.standard.set(false, forKey: "enableAnnouncements")
            UserDefaults.standard.set(false, forKey: AutoLearnSettings.isEnabledKey)

            // Push-to-talk on the fn/Globe key unless the user picked another shortcut.
            ShortcutStore.seedShortcut(
                .modifierOnly(keyCode: UInt16(kVK_Function), modifierFlags: [.function]),
                for: .primaryRecording
            )

            // In archive mode FluidAudio must never fall back to Hugging Face: point its registry
            // at the archive (which has no HF API), so a stray download fails instead.
            ModelRegistry.baseURL = modelArchiveBaseURL ?? modelServerBaseURL
        #endif
    }

    /// Ensures exactly one enabled, AI-free dictation mode exists and keeps it within the
    /// organisation limits (allowed models, no enhancement, no context capture, paste output).
    // MARK: - Menu bar icon

    /// Menu bar symbol of the organisation build: the centre of the Undertone waveform
    /// (seven rounded bars), drawn as a template image so macOS tints it for light/dark menu bars.
    static func menuBarIcon() -> NSImage {
        let heights: [CGFloat] = [0.36, 0.26, 0.62, 1.0, 0.62, 0.40, 0.48]
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let barWidth: CGFloat = 1.8
            let spacing: CGFloat = (rect.width - CGFloat(heights.count) * barWidth) / CGFloat(heights.count - 1)
            NSColor.black.setFill()
            for (index, value) in heights.enumerated() {
                let height = max(barWidth, rect.height * value)
                let x = CGFloat(index) * (barWidth + spacing)
                let bar = NSRect(x: x, y: (rect.height - height) / 2, width: barWidth, height: height)
                NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Launch at login

    /// Set when the user switches "Beim Anmelden starten" off in the settings.
    static let launchAtLoginOptOutKey = "orgLaunchAtLoginOptOut"

    /// Undertone starts at login on every Mac: on each launch the login item is (re)registered,
    /// unless the user deliberately switched it off in the settings.
    @MainActor
    static func ensureLaunchAtLogin() {
        #if ORG_EDITION
            guard !UserDefaults.standard.bool(forKey: launchAtLoginOptOutKey) else { return }
            Task { @MainActor in
                let manager = LaunchAtLoginManager.shared
                if await !manager.currentEnabledStatus() {
                    manager.setEnabled(true)
                }
            }
        #endif
    }

    /// Settings toggle: remembers an explicit opt-out so `ensureLaunchAtLogin` respects it.
    @MainActor
    static func setLaunchAtLogin(_ enabled: Bool) {
        UserDefaults.standard.set(!enabled, forKey: launchAtLoginOptOutKey)
        LaunchAtLoginManager.shared.setEnabled(enabled)
    }

    @MainActor
    static func ensureDictationMode() {
        #if ORG_EDITION
            let manager = ModeManager.shared
            let existing = manager.configurations.first { $0.id == dictationModeID }

            var config =
                existing
                ?? ModeConfig(
                    id: dictationModeID,
                    name: "Diktat",
                    icon: .symbol("mic.fill"),
                    isAIEnhancementEnabled: false,
                    selectedTranscriptionModelName: configuredTranscriptionModelName,
                    isRealtimeTranscriptionEnabled: true,
                    selectedLanguage: defaultLanguage,
                    useClipboardContext: false,
                    useSelectedTextContext: false,
                    useScreenCapture: false,
                    isTextFormattingEnabled: true,
                    outputMode: .paste,
                    isEnabled: true,
                    isDefault: true
                )

            config.name = "Diktat"
            config.appConfigs = nil
            config.urlConfigs = nil
            config.triggerGroups = nil
            config.triggerWords = []
            config.isAIEnhancementEnabled = false
            config.selectedPrompt = nil
            config.selectedAIProvider = nil
            config.selectedAIModel = nil
            config.useClipboardContext = false
            config.useSelectedTextContext = false
            config.useScreenCapture = false
            config.outputMode = .paste
            config.customCommand = nil
            config.isEnabled = true
            config.isDefault = true
            // The administrator's model always wins; re-evaluated on every launch.
            config.selectedTranscriptionModelName = configuredTranscriptionModelName
            // Live text is used whenever the model supports streaming (Cohere does not; the
            // runtime then silently records without live text).
            config.isRealtimeTranscriptionEnabled = true
            if (config.selectedLanguage ?? "").isEmpty {
                config.selectedLanguage = defaultLanguage
            }

            // ModeConfig equality only compares ids, so always write the normalized config.
            manager.replaceConfigurations([config])
            manager.setActiveConfiguration(config)
        #endif
    }

    /// Updates the dictation mode (model, language, live text) from the organisation settings.
    @MainActor
    static func updateDictationMode(_ update: (inout ModeConfig) -> Void) {
        guard var config = ModeManager.shared.getConfiguration(with: dictationModeID) else { return }
        update(&config)
        ModeManager.shared.updateConfiguration(config)
        ModeManager.shared.setActiveConfiguration(config)
    }
}
