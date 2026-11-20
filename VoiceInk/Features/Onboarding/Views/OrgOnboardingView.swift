import AVFoundation
import AppKit
import ApplicationServices
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Helpers for the administrator-configured transcription model of the organisation build.
@MainActor
enum OrgModelSetup {
    struct Progress {
        let fraction: Double
        let message: String
        let isIndeterminate: Bool
    }

    static var configuredModel: (any TranscriptionModel)? {
        TranscriptionModelRegistry.models.first { $0.name == OrgEdition.configuredTranscriptionModelName }
    }

    static var packageFileName: String {
        OrgEdition.modelPackageFileName(for: OrgEdition.configuredTranscriptionModelName)
    }

    static func isReady(fluidAudioModelManager: FluidAudioModelManager) -> Bool {
        guard let model = configuredModel else { return false }
        switch model.provider {
        case .fluidAudio:
            return fluidAudioModelManager.isFluidAudioModelDownloaded(named: model.name)
        case .transcribeCpp:
            return TranscribeCppModelManager.shared.isModelDownloaded(named: model.name)
        default:
            return false
        }
    }

    /// Package install, archive download or Hugging Face download in progress.
    static func isDownloading(fluidAudioModelManager: FluidAudioModelManager) -> Bool {
        if OrgModelArchiveInstaller.shared.isRunning {
            return true
        }
        if OrgEdition.isModelArchiveModeEnabled {
            return false
        }
        if let model = configuredModel as? FluidAudioModel {
            return fluidAudioModelManager.isFluidAudioModelDownloading(model)
        }
        if let model = configuredModel as? TranscribeCppModel {
            return TranscribeCppModelManager.shared.isModelDownloading(model)
        }
        return false
    }

    static func progress(fluidAudioModelManager: FluidAudioModelManager) -> Progress? {
        let installer = OrgModelArchiveInstaller.shared
        if installer.isRunning {
            return Progress(
                fraction: installer.fractionCompleted, message: installer.message, isIndeterminate: false)
        }
        if OrgEdition.isModelArchiveModeEnabled {
            return nil
        }
        if let model = configuredModel as? FluidAudioModel,
            let status = fluidAudioModelManager.downloadStatus(for: model)
        {
            return Progress(
                fraction: status.fractionCompleted, message: status.message, isIndeterminate: status.isIndeterminate)
        }
        if let model = configuredModel as? TranscribeCppModel,
            let status = TranscribeCppModelManager.shared.downloadStatus(for: model)
        {
            return Progress(
                fraction: status.fractionCompleted, message: status.message, isIndeterminate: status.isIndeterminate)
        }
        return nil
    }

    static func lastError(fluidAudioModelManager: FluidAudioModelManager) -> String? {
        if let error = OrgModelArchiveInstaller.shared.lastError {
            return error
        }
        let hfError: String? = {
            guard !OrgEdition.isModelArchiveModeEnabled, let model = configuredModel else { return nil }
            switch model.provider {
            case .fluidAudio:
                return fluidAudioModelManager.lastDownloadErrors[model.name].map {
                    "Download von \(OrgEdition.modelServerBaseURL) fehlgeschlagen: \($0)"
                }
            case .transcribeCpp:
                return TranscribeCppModelManager.shared.lastDownloadErrors[model.name].map {
                    "Download von \(OrgEdition.modelServerBaseURL) fehlgeschlagen: \($0)"
                }
            default:
                return nil
            }
        }()
        if let hfError {
            return hfError
        }
        switch OrgBundledModels.lastOutcome {
        case .failed(let message):
            return message
        case .noBundledModel:
            return "Diese App enthält kein Sprachmodell. Bitte die Modelldatei auswählen."
        default:
            break
        }
        if let bundled = OrgBundledModels.bundledModelName, bundled != OrgEdition.configuredTranscriptionModelName {
            return "Die App enthält das Modell \(bundled), eingestellt ist aber \(OrgEdition.configuredTranscriptionModelName)."
        }
        return nil
    }

    /// Secondary path: load from the internet (model archive URL if configured, else Hugging Face).
    static func startInternetDownload(fluidAudioModelManager: FluidAudioModelManager) {
        guard !isReady(fluidAudioModelManager: fluidAudioModelManager),
            !isDownloading(fluidAudioModelManager: fluidAudioModelManager)
        else { return }
        OrgModelArchiveInstaller.shared.clearError()

        if OrgEdition.isModelArchiveModeEnabled {
            guard let model = configuredModel else { return }
            OrgModelArchiveInstaller.shared.install(model: model, fluidAudioModelManager: fluidAudioModelManager) {}
            return
        }

        if let model = configuredModel as? FluidAudioModel {
            fluidAudioModelManager.startDownload(model)
        } else if let model = configuredModel as? TranscribeCppModel {
            TranscribeCppModelManager.shared.startDownload(model)
        }
    }
}

/// Minimal first-run setup of the organisation build: permissions and the automatic download of
/// the administrator-configured model. No choices, no AI, no license.
struct OrgOnboardingView: View {
    @Binding var hasCompletedOnboardingV2: Bool
    @EnvironmentObject private var fluidAudioModelManager: FluidAudioModelManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @ObservedObject private var transcribeCppModelManager = TranscribeCppModelManager.shared
    @ObservedObject private var archiveInstaller = OrgModelArchiveInstaller.shared

    @State private var microphoneGranted = false
    @State private var microphoneDenied = false
    @State private var accessibilityGranted = false
    @State private var showModelStep = false

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let contentMaxWidth: CGFloat = 560

    private var permissionsGranted: Bool { microphoneGranted && accessibilityGranted }
    private var modelReady: Bool { OrgModelSetup.isReady(fluidAudioModelManager: fluidAudioModelManager) }

    var body: some View {
        ZStack {
            OnboardingBackground()

            OnboardingStepScreen(
                systemImage: "mic.badge.plus",
                title: "Willkommen bei Undertone",
                subtitle: showModelStep
                    ? "Zwei Freigaben und das Sprachmodell, dann können Sie diktieren. Alles läuft lokal auf diesem Mac."
                    : "Zwei Freigaben, dann können Sie diktieren. Das Sprachmodell ist bereits eingerichtet, alles läuft lokal auf diesem Mac.",
                contentMaxWidth: contentMaxWidth
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    permissionRow(
                        number: 1,
                        title: "Mikrofon",
                        subtitle: "Damit Undertone Ihre Stimme aufnehmen kann.",
                        granted: microphoneGranted,
                        actionTitle: microphoneDenied ? "Einstellungen öffnen" : "Erlauben",
                        action: requestMicrophone
                    )
                    permissionRow(
                        number: 2,
                        title: "Bedienungshilfen",
                        subtitle: "Damit der Text direkt in das aktive Fenster eingefügt wird.",
                        granted: accessibilityGranted,
                        actionTitle: "Erlauben",
                        action: requestAccessibility
                    )
                    // The model ships inside the app; this step only appears as a fallback.
                    if showModelStep {
                        modelRow
                    }
                }
            } bottomBar: {
                OnboardingBottomBar(
                    leadingTitle: "Beenden",
                    primaryTitle: "Los geht's",
                    isPrimaryEnabled: permissionsGranted && modelReady,
                    onLeading: { NSApplication.shared.terminate(nil) },
                    onPrimary: finish
                )
            }
        }
        .onAppear {
            refreshPermissions()
            prepareModel()
        }
        .onReceive(refreshTimer) { _ in
            refreshPermissions()
        }
        .onChange(of: archiveInstaller.foundPackages) { _, packages in
            autoInstallIfUnambiguous(packages)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Rows

    private func permissionRow(
        number: Int,
        title: String,
        subtitle: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            stepBadge(number: number, done: granted)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.Text.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Text.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            if granted {
                statusBadge("Erteilt")
            } else {
                primaryButton(actionTitle, action: action)
            }
        }
        .padding(14)
        .background(AppMaterialCardBackground(isSelected: !granted, cornerRadius: 10))
    }

    private var modelRow: some View {
        let modelName = OrgModelSetup.configuredModel?.displayName ?? OrgEdition.configuredTranscriptionModelName
        let progress = OrgModelSetup.progress(fluidAudioModelManager: fluidAudioModelManager)
        let error = OrgModelSetup.lastError(fluidAudioModelManager: fluidAudioModelManager)
        let isBusy = OrgModelSetup.isDownloading(fluidAudioModelManager: fluidAudioModelManager)
        let localPackage = archiveInstaller.foundPackages.first { !$0.isPlaceholder }
        let placeholder = archiveInstaller.foundPackages.first { $0.isPlaceholder }
        // Re-read when the TranscribeCpp manager publishes.
        _ = transcribeCppModelManager.lastDownloadErrors

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                stepBadge(number: 3, done: modelReady)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Sprachmodell (\(modelName))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.Text.primary)
                    Text(
                        modelSubtitle(
                            isBusy: isBusy, error: error, localPackage: localPackage, placeholder: placeholder)
                    )
                    .font(.system(size: 12))
                    .foregroundColor(error == nil ? AppTheme.Text.muted : AppTheme.Status.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                }

                Spacer(minLength: 10)

                if modelReady {
                    statusBadge("Bereit")
                } else if isBusy || archiveInstaller.isSearching {
                    ProgressView().controlSize(.small)
                } else if let localPackage {
                    primaryButton("Installieren") { install(localPackage.url) }
                } else {
                    primaryButton("Modelldatei auswählen …", action: chooseModelFile)
                }
            }

            if let progress, !modelReady {
                VStack(alignment: .leading, spacing: 4) {
                    if progress.isIndeterminate {
                        ProgressView().progressViewStyle(.linear)
                    } else {
                        ProgressView(value: min(max(progress.fraction, 0), 1))
                            .progressViewStyle(.linear)
                    }
                    Text(progress.message)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.Text.muted)
                }
                .padding(.leading, 44)
            }

            if !modelReady && !isBusy {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        "Die Datei „\(OrgModelSetup.packageFileName)“ liegt bei den Undertone-Downloads. Sie können sie auch auf dieses Fenster ziehen."
                    )
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.Text.muted)
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 14) {
                        if localPackage != nil {
                            linkButton("Andere Datei auswählen …", action: chooseModelFile)
                        }
                        linkButton("In Downloads und OneDrive suchen") { archiveInstaller.searchForPackage() }
                        linkButton(
                            OrgEdition.isModelArchiveModeEnabled
                                ? "Stattdessen aus dem Internet laden"
                                : "Stattdessen aus dem Internet laden (Hugging Face)"
                        ) {
                            OrgModelSetup.startInternetDownload(fluidAudioModelManager: fluidAudioModelManager)
                        }
                    }
                }
                .padding(.leading, 44)
            }
        }
        .padding(14)
        .background(AppMaterialCardBackground(isSelected: !modelReady, cornerRadius: 10))
    }

    private func modelSubtitle(
        isBusy: Bool,
        error: String?,
        localPackage: OrgModelArchiveInstaller.FoundPackage?,
        placeholder: OrgModelArchiveInstaller.FoundPackage?
    ) -> String {
        if modelReady {
            return "Das Modell ist eingerichtet."
        }
        if let error {
            return error
        }
        if isBusy {
            return "Das Modell wird eingerichtet. Das kann einige Minuten dauern."
        }
        if archiveInstaller.isSearching {
            return "Suche die Modelldatei in Downloads und im OneDrive-Ordner …"
        }
        if let localPackage {
            return "Gefunden: \(localPackage.url.path(percentEncoded: false))"
        }
        if let placeholder {
            return
                "Gefunden in OneDrive, aber noch nicht auf diesem Mac: \(placeholder.url.lastPathComponent). Bitte im Finder per Doppelklick bzw. „Download“ laden und danach „Erneut suchen“."
        }
        return "Bitte die Modelldatei auswählen."
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .underline()
                .foregroundColor(AppTheme.Text.secondary)
        }
        .buttonStyle(.plain)
    }

    private func stepBadge(number: Int, done: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(done ? AppTheme.Selection.fill : AppTheme.Surface.controlActive)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.Text.primary)
            } else {
                Text("\(number)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.Text.primary)
            }
        }
        .frame(width: 30, height: 30)
    }

    private func statusBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(AppTheme.Text.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.Text.secondary.opacity(0.12))
            .clipShape(Capsule())
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.Action.primaryForeground)
                .frame(minWidth: 94)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                        .fill(AppTheme.Action.primaryFill)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func refreshPermissions() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        microphoneGranted = status == .authorized
        microphoneDenied = status == .denied || status == .restricted
        accessibilityGranted = AXIsProcessTrusted()
    }

    private func requestMicrophone() {
        if microphoneDenied {
            openPrivacyPane("Privacy_Microphone")
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { refreshPermissions() }
        }
    }

    private func requestAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
        openPrivacyPane("Privacy_Accessibility")
    }

    private func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Main path: model package file (shared cloud folder or Downloads). With a configured model
    /// archive URL the archive download starts directly instead.
    private func prepareModel() {
        archiveInstaller.fluidAudioModelManager = fluidAudioModelManager
        showModelStep = !modelReady
        guard !modelReady, !OrgModelSetup.isDownloading(fluidAudioModelManager: fluidAudioModelManager) else {
            return
        }
        if OrgEdition.isModelArchiveModeEnabled {
            OrgModelSetup.startInternetDownload(fluidAudioModelManager: fluidAudioModelManager)
        } else if UserDefaults.standard.bool(forKey: OrgEdition.modelPackageAutoSearchDefaultsKey) {
            // Off by default: scanning Downloads/OneDrive makes macOS ask for folder access.
            archiveInstaller.searchForPackage()
        }
    }

    /// Exactly one complete local package found: install without a click (the content is verified
    /// against the built-in checksum before anything is unpacked).
    private func autoInstallIfUnambiguous(_ packages: [OrgModelArchiveInstaller.FoundPackage]) {
        let local = packages.filter { !$0.isPlaceholder }
        guard local.count == 1, !modelReady, archiveInstaller.lastError == nil,
            !OrgModelSetup.isDownloading(fluidAudioModelManager: fluidAudioModelManager)
        else { return }
        install(local[0].url)
    }

    private func install(_ url: URL) {
        archiveInstaller.fluidAudioModelManager = fluidAudioModelManager
        archiveInstaller.installPackage(at: url) {
            transcriptionModelManager.refreshAllAvailableModels()
        }
    }

    private func chooseModelFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Modelldatei auswählen"
        panel.message = "Bitte „\(OrgModelSetup.packageFileName)“ aus den Undertone-Downloads auswählen."
        if panel.runModal() == .OK, let url = panel.url {
            install(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) })
        else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, url.pathExtension.lowercased() == "zip" else { return }
            DispatchQueue.main.async { install(url) }
        }
        return true
    }

    private func finish() {
        guard permissionsGranted, modelReady else { return }
        OrgEdition.ensureDictationMode()
        transcriptionModelManager.refreshAllAvailableModels()
        hasCompletedOnboardingV2 = true
    }
}
