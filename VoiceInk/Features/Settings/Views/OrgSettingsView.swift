import Carbon.HIToolbox
import SwiftUI

/// Reduced settings of the organisation build ("Undertone"): shortcut, language, a few
/// everyday options and the license notice. Model, AI, cloud, updates, backup and diagnostics
/// are intentionally absent; the transcription model is set centrally by the administrator.
@MainActor
struct OrgSettingsView: View {
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @ObservedObject private var launchAtLoginManager = LaunchAtLoginManager.shared
    @ObservedObject private var mediaController = MediaController.shared
    @AppStorage(OrgVoiceCommands.commandsEnabledKey) private var voiceCommandsEnabled = true
    @AppStorage(OrgVoiceCommands.smileysEnabledKey) private var smileysEnabled = true
    @AppStorage(OrgFillerWords.enabledKey) private var fillerWordsEnabled = true
    @AppStorage(OrgCompanyDictionary.enabledKey) private var companyDictionaryEnabled = true
    @AppStorage(AudioDeviceManager.orgBluetoothProtectionKey) private var bluetoothProtectionEnabled = true
    @ObservedObject private var companyDictionary = OrgCompanyDictionary.shared
    @ObservedObject private var modeManager = ModeManager.shared
    @AppStorage(RecorderDisplaySettingsKeys.showLiveTranscript) private var showLiveTranscript = true
    @AppStorage("restoreClipboardAfterPaste") private var restoreClipboardAfterPaste = true
    @State private var cancelRecordingShortcutRecorderResetID = 0

    private static let defaultCancelRecordingShortcut = Shortcut.key(
        keyCode: UInt16(kVK_Escape),
        modifierFlags: []
    )

    private var configuredModel: (any TranscriptionModel)? {
        TranscriptionModelRegistry.models.first { $0.name == OrgEdition.configuredTranscriptionModelName }
    }

    /// Deutsch, Englisch, Automatisch (if the model can); a different language chosen in an
    /// earlier version stays visible until the user picks one of these.
    private var languageOptions: [(code: String, name: String)] {
        var options = OrgEdition.dictationLanguageOptions()
        let current = languageBinding.wrappedValue
        if !options.contains(where: { $0.code == current }) {
            options.append((current, OrgEdition.dictationLanguageName(current)))
        }
        return options
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: {
                let stored = modeManager.getConfiguration(with: OrgEdition.dictationModeID)?.selectedLanguage
                    ?? OrgEdition.defaultLanguage
                guard let model = configuredModel else { return stored }
                return TranscriptionLanguageSupport.validLanguageOrFallback(stored, for: model)
            },
            set: { newValue in
                OrgEdition.updateDictationMode { $0.selectedLanguage = newValue }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
            OrgSettingsCard(
                title: "Tastenkürzel",
                footer:
                    "Standard: fn-/Globus-Taste gedrückt halten, sprechen, loslassen. Falls macOS beim Drücken der Globus-Taste Emojis oder das eigene Diktat öffnet: Systemeinstellungen > Tastatur > „Globus-Taste drücken für“ auf „Keine Aktion“ stellen."
            ) {
                LabeledContent("Aufnahme-Taste") {
                    HStack(spacing: 8) {
                        Spacer()
                        Picker("", selection: $recordingShortcutManager.primaryRecordingShortcutMode) {
                            ForEach(RecordingShortcutManager.Mode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()

                        ShortcutRecorder(action: .primaryRecording) {
                            recordingShortcutManager.primaryRecordingShortcut = .custom
                            recordingShortcutManager.updateShortcutStatus()
                        }
                        .controlSize(.small)
                    }
                }

                LabeledContent("Letztes Diktat erneut einfügen") {
                    ShortcutRecorder(action: .pasteLastTranscription) {
                        recordingShortcutManager.updateShortcutStatus()
                    }
                    .controlSize(.small)
                }

                LabeledContent("Aufnahme abbrechen") {
                    HStack(spacing: 8) {
                        ShortcutRecorder(
                            action: .cancelRecorder,
                            defaultShortcut: Self.defaultCancelRecordingShortcut
                        )
                        .id(cancelRecordingShortcutRecorderResetID)
                        .controlSize(.small)

                        Button {
                            RecorderPanelShortcutManager.resetEscapeConfirmationHint()
                            ShortcutStore.setShortcut(nil, for: .cancelRecorder)
                            cancelRecordingShortcutRecorderResetID += 1
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.plain)
                        .help("Auf Standard zurücksetzen (zweimal Esc)")
                    }
                }
            }

            OrgSettingsCard(title: "Diktat") {
                Picker("Sprache", selection: languageBinding) {
                    ForEach(languageOptions, id: \.code) { option in
                        Text(option.name).tag(option.code)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Sprachmodell") {
                    Text(configuredModel?.displayName ?? OrgEdition.configuredTranscriptionModelName)
                        .foregroundColor(.secondary)
                }
                .help("Das Sprachmodell wird zentral von der IT festgelegt.")

                Toggle("Live-Text während der Aufnahme anzeigen", isOn: $showLiveTranscript)

                Toggle("Zwischenablage nach dem Einfügen wiederherstellen", isOn: $restoreClipboardAfterPaste)

                Text("Englisch: Sprachbefehle und Smileys sind dann aus. Automatisch: Das Modell erkennt die Sprache selbst. Die Sprache lässt sich auch im Menü der Menüleiste umschalten.")
                    .settingsDescription()
            }

            OrgSettingsCard(title: "Text") {
                Toggle("Füllwörter entfernen", isOn: $fillerWordsEnabled)
                Text("„äh“, „ähm“, „öh“, „hm“, „mhm“ fallen weg, ebenso direkt doppelte Wörter („das das“ wird zu „das“). Bewusste Dopplungen wie „so so“ oder „sehr sehr“ bleiben. Bei Englisch auch „uh“ und „um“.")
                    .settingsDescription()
            }

            OrgSettingsCard(
                title: "Firmenwörterbuch",
                footer: "Undertone sucht beim Start und einmal täglich nach der Datei \(OrgCompanyDictionary.fileName) in OneDrive/SharePoint und in Downloads und lädt die neueste. Ihre eigenen Einträge im Wörterbuch bleiben unberührt."
            ) {
                Toggle("Firmenwörterbuch verwenden", isOn: $companyDictionaryEnabled)

                if let content = companyDictionary.content {
                    LabeledContent("Stand") {
                        Text(content.version ?? "ohne Angabe").foregroundColor(.secondary)
                    }
                    LabeledContent("Inhalt") {
                        Text("\(content.cleanedWords.count) Wörter, \(content.jiraSchluessel.count) Projektschlüssel, \(content.ersetzungen.count) Ersetzungen")
                            .foregroundColor(.secondary)
                    }
                    if let path = companyDictionary.sourcePath {
                        LabeledContent("Quelle") {
                            Text((path as NSString).abbreviatingWithTildeInPath)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(path)
                        }
                    }
                } else {
                    Text("Kein Firmenwörterbuch geladen.")
                        .settingsDescription()
                }

                HStack(spacing: 8) {
                    Button("Firmenwörterbuch importieren …") { companyDictionary.showImportPanel() }
                    Button(companyDictionary.isSearching ? "Suche läuft …" : "Jetzt suchen") {
                        companyDictionary.search()
                    }
                    .disabled(companyDictionary.isSearching)
                    Spacer()
                    if companyDictionary.content != nil {
                        Button("Entfernen") { companyDictionary.remove() }
                    }
                }
                .controlSize(.small)

                if let message = companyDictionary.lastMessage {
                    Text(message).settingsDescription()
                }

                if !companyDictionary.placeholders.isEmpty {
                    Text("Diese Datei liegt nur in OneDrive und ist noch nicht auf diesem Mac: \(companyDictionary.placeholders.map(\.displayPath).joined(separator: ", ")). Bitte im Finder per Rechtsklick „Immer auf diesem Gerät behalten“ wählen, danach „Jetzt suchen“.")
                        .settingsDescription()
                        .textSelection(.enabled)
                }
            }

            OrgSettingsCard(title: "Mikrofon") {
                Toggle("Bluetooth-Headset nicht zum Diktieren verwenden", isOn: $bluetoothProtectionEnabled)
                Text("Wäre ein Bluetooth-Gerät (z. B. AirPods oder Headset) das Mikrofon, nimmt Undertone stattdessen das eingebaute Mikrofon des Mac. So wechselt das Headset in Teams-Besprechungen nicht in den schlechteren Telefonmodus. Das gilt auch, wenn Sie auf der Seite Mikrofon ein Bluetooth-Gerät gewählt haben. Ohne eingebautes Mikrofon (z. B. Mac mini) wird das Bluetooth-Gerät normal verwendet. Das Standardmikrofon des Systems bleibt unverändert.")
                    .settingsDescription()
            }

            OrgSettingsCard(title: "Sprachbefehle") {
                Toggle("Satzzeichen und Zeilen per Sprache", isOn: $voiceCommandsEnabled)
                Text("„neue Zeile“, „neuer Absatz“, „Doppelpunkt“, „Semikolon“, „Ausrufezeichen“, „Fragezeichen“, „Anführungszeichen“ (auf/zu), „Klammer auf/zu“, „Bindestrich“, „Schrägstrich“")
                    .settingsDescription()

                Toggle("Smileys per Sprache", isOn: $smileysEnabled)
                Text("„Smiley“ und der Name, z. B. „Smiley LOL“ 😂, „Smiley Daumen hoch“ 👍, „Smiley Zwinkern“ 😉, „Smiley Herz“ ❤️, „Smiley Haken“ ✅, „Smiley Party“ 🥳")
                    .settingsDescription()
            }

            OrgSettingsCard(title: "Allgemein") {
                Toggle(
                    "Beim Anmelden starten",
                    isOn: Binding(
                        get: { launchAtLoginManager.isEnabled },
                        set: { OrgEdition.setLaunchAtLogin($0) }
                    )
                )
                .disabled(launchAtLoginManager.isUpdating)

                Toggle("Dock-Symbol ausblenden", isOn: $menuBarManager.isMenuBarOnly)

                Toggle("Andere Töne während des Diktierens stummschalten", isOn: $mediaController.isSystemMuteEnabled)
            }

            OrgSettingsCard(
                title: "Updates",
                footer: "Undertone prüft einmal täglich, ob es eine neue Version gibt, und fragt vor der Installation. Es wird nie automatisch installiert."
            ) {
                Toggle(
                    "Automatisch nach Updates suchen",
                    isOn: Binding(
                        get: { updaterViewModel.automaticallyChecksForUpdates },
                        set: { updaterViewModel.setAutomaticallyChecksForUpdates($0) }
                    )
                )

                LabeledContent("Installierte Version") {
                    HStack(spacing: 12) {
                        Text(OrgEdition.versionDescription).foregroundColor(.secondary)
                        Button("Jetzt prüfen") { updaterViewModel.checkForUpdates() }
                            .disabled(!updaterViewModel.canCheckForUpdates)
                    }
                }
            }

            OrgSettingsCard(title: "Über Undertone") {
                Link("Häufige Fragen (FAQ)", destination: URL(string: "https://github.com/AlverichSven/undertone/blob/main/docs/FAQ.md")!)

                Text(OrgEdition.attributionText)
                    .settingsDescription()
                    .textSelection(.enabled)

                Text("Alle Aufnahmen und Texte bleiben auf diesem Mac. Das Sprachmodell ist in der App enthalten. Netzwerk wird nur für die Update-Prüfung beim internen Server genutzt.")
                    .settingsDescription()

                LabeledContent("Version") {
                    Text(OrgEdition.versionDescription).foregroundColor(.secondary)
                }
            }
            }
            .toggleStyle(OrgRowToggleStyle())
            .labeledContentStyle(OrgRowLabeledContentStyle())
            .padding(.horizontal, 26)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
    }
}

/// Dark card with a section title (organisation build).
struct OrgSettingsCard<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(OrgStyle.sectionTitleFont)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .font(.system(size: 13, weight: .regular))
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OrgCardBackground())

            if let footer {
                Text(footer)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(OrgStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// Label left, switch right (organisation build cards).
struct OrgRowToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Toggle("", isOn: configuration.$isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

/// Label left, value right (organisation build cards).
struct OrgRowLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            configuration.content
        }
    }
}
