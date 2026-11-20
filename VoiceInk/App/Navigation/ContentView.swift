import OSLog
import SwiftUI

enum ViewType: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case modes = "Modes"
    case models = "AI Models"
    case transcribeAudio = "Transcribe Audio"
    case history = "History"
    case audio = "Audio"
    case dictionary = "Dictionary"
    case settings = "Settings"
    case license = "VoiceInk Pro"

    var id: String { rawValue }
}

final class MainWindowNavigation: ObservableObject {
    static let shared = MainWindowNavigation()

    @Published var selectedView: ViewType = .dashboard
    @Published var dictionarySettingsRequested = false

    private init() {}

    func navigate(to destination: String) {
        guard let viewType = ViewType(rawValue: destination) else {
            return
        }

        navigate(to: viewType)
    }

    func navigate(to destination: ViewType) {
        selectedView = Self.reachableDestination(for: destination)
    }

    /// Organisation build: removed sections (Dashboard, Modes, Models, License) are never shown;
    /// requests for them land on the closest remaining section.
    static func reachableDestination(for destination: ViewType) -> ViewType {
        guard OrgEdition.isEnabled else { return destination }
        switch destination {
        case .dashboard, .license:
            return .dashboard  // org: "Übersicht" (OrgHomeView)
        case .modes, .models:
            return .settings
        default:
            return destination
        }
    }

    func openDictionarySettings() {
        dictionarySettingsRequested = true
        navigate(to: .dictionary)
    }
}

struct ContentView: View {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ContentView")
    private static let detailBackgroundTintOpacity = 0.50
    @EnvironmentObject private var navigation: MainWindowNavigation

    var body: some View {
        HStack(spacing: 0) {
            AppSidebar(selectedView: $navigation.selectedView)

            detailContent
        }
        .frame(width: AppWindowLayout.width)
        .frame(minHeight: AppWindowLayout.minimumHeight)
        .preferredColorScheme(OrgEdition.isEnabled ? .dark : nil)
        .onAppear {
            logger.notice("ContentView appeared")
        }
        .onDisappear {
            logger.notice("ContentView disappeared")
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDestination)) { notification in
            if let destination = notification.userInfo?["destination"] as? String {
                logger.notice("navigateToDestination received: \(destination, privacy: .public)")
                navigation.navigate(to: destination)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if OrgEdition.isEnabled {
            let destination = MainWindowNavigation.reachableDestination(for: navigation.selectedView)
            VStack(alignment: .leading, spacing: 0) {
                OrgPageTopBar(title: orgPageTitle(destination))
                detailView(for: destination)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OrgStyle.windowBackground.ignoresSafeArea(.container, edges: .top))
        } else {
            detailView(for: navigation.selectedView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(detailBackground)
        }
    }

    private func orgPageTitle(_ destination: ViewType) -> String {
        switch destination {
        case .dashboard: return "Übersicht"
        case .history: return "Verlauf"
        case .transcribeAudio: return "Audio transkribieren"
        case .dictionary: return "Wörterbuch"
        case .settings: return "Einstellungen"
        case .audio: return "Mikrofon"
        default: return ""
        }
    }

    private var detailBackground: some View {
        ZStack {
            VisualEffectView(
                material: .sidebar,
                blendingMode: .behindWindow
            )

            AppTheme.Surface.window
                .opacity(Self.detailBackgroundTintOpacity)
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder
    private func detailView(for viewType: ViewType) -> some View {
        switch MainWindowNavigation.reachableDestination(for: viewType) {
        case .dashboard:
            if OrgEdition.isEnabled {
                OrgHomeView()
            } else {
                DashboardView()
            }
        case .models:
            ModelManagementView()
        case .transcribeAudio:
            AudioTranscribeView()
        case .history:
            HistoryView()
        case .audio:
            AudioSetupView()
        case .dictionary:
            DictionarySettingsView()
        case .modes:
            ModeView()
        case .settings:
            if OrgEdition.isEnabled {
                OrgSettingsView()
            } else {
                SettingsView()
            }
        case .license:
            LicenseManagementView()
        }
    }
}
