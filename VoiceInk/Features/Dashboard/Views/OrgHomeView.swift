import AppKit
import SwiftData
import SwiftUI

// MARK: - Style (organisation build)

/// Look of the Undertone main window (dark, Superwhisper-like): cards slightly lighter than the
/// background with a fine border, system font in regular/medium weight.
enum OrgStyle {
    static let windowBackground = Color(red: 0.105, green: 0.105, blue: 0.115)
    static let cardFill = Color.white.opacity(0.045)
    static let cardBorder = Color.white.opacity(0.08)
    static let cardRadius: CGFloat = 14
    static let pageTitleFont = Font.system(size: 24, weight: .semibold)
    static let sectionTitleFont = Font.system(size: 15, weight: .semibold)
    static let secondaryText = Color.white.opacity(0.55)
}

struct OrgCardBackground: View {
    var radius: CGFloat = OrgStyle.cardRadius

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(OrgStyle.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(OrgStyle.cardBorder, lineWidth: 1)
            )
    }
}

/// Page title on the left, current microphone on the right.
struct OrgPageTopBar: View {
    let title: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(OrgStyle.pageTitleFont)
                .foregroundColor(.primary)
            Spacer(minLength: 12)
            OrgMicrophonePill()
        }
        .padding(.horizontal, 26)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }
}

/// Shows the current input device; click opens the microphone page.
struct OrgMicrophonePill: View {
    @ObservedObject private var audioDeviceManager = AudioDeviceManager.shared
    @EnvironmentObject private var navigation: MainWindowNavigation

    private var deviceName: String {
        let deviceID = audioDeviceManager.getCurrentDevice()
        guard deviceID != 0 else { return "Kein Mikrofon" }
        return audioDeviceManager.getDeviceName(deviceID: deviceID) ?? "Mikrofon"
    }

    var body: some View {
        Button {
            navigation.navigate(to: .audio)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "headphones")
                    .font(.system(size: 12, weight: .regular))
                Text(deviceName)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: 260)
            .background(
                Capsule().fill(Color.white.opacity(0.06))
                    .overlay(Capsule().strokeBorder(OrgStyle.cardBorder, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .help("Mikrofon wählen")
    }
}

// MARK: - App usage per transcription

/// Remembers in which app each dictation was made (bundle id + name), for "genutzte Apps" and the
/// app icon on the overview cards. Stored next to the app data, not in the SwiftData schema.
@MainActor
final class OrgAppUsageStore: ObservableObject {
    static let shared = OrgAppUsageStore()

    struct Entry: Codable, Equatable {
        let bundleID: String
        let name: String
    }

    @Published private(set) var entries: [String: Entry] = [:]
    private let maximumEntries = 5000

    private var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(OrgEdition.appSupportFolderName, isDirectory: true)
            .appendingPathComponent("org-app-usage.json")
    }

    private init() {
        if let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        {
            entries = decoded
        }
    }

    func record(transcriptionID: UUID, app: NSRunningApplication?) {
        guard OrgEdition.isEnabled, let app, let bundleID = app.bundleIdentifier,
            bundleID != Bundle.main.bundleIdentifier
        else { return }
        entries[transcriptionID.uuidString] = Entry(bundleID: bundleID, name: app.localizedName ?? bundleID)
        if entries.count > maximumEntries {
            // Keep the store small; old entries only matter for long periods.
            for key in entries.keys.prefix(entries.count - maximumEntries) {
                entries.removeValue(forKey: key)
            }
        }
        save()
    }

    func entry(for transcriptionID: UUID) -> Entry? {
        entries[transcriptionID.uuidString]
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            // Statistics only; ignore write errors.
        }
    }
}

// MARK: - Overview ("Übersicht")

struct OrgHomeView: View {
    @EnvironmentObject private var navigation: MainWindowNavigation
    @ObservedObject private var appUsage = OrgAppUsageStore.shared
    @Query(sort: \SessionMetric.timestamp, order: .reverse) private var metrics: [SessionMetric]
    @Query private var recentTranscriptions: [Transcription]
    @AppStorage("orgHomeStatsPeriod") private var periodRawValue = Period.all.rawValue
    @State private var copiedID: UUID?

    init() {
        var descriptor = FetchDescriptor<Transcription>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 5
        _recentTranscriptions = Query(descriptor)
    }

    enum Period: String, CaseIterable, Identifiable {
        case today, week, month, all
        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return "Heute"
            case .week: return "7 Tage"
            case .month: return "30 Tage"
            case .all: return "Gesamt"
            }
        }

        var startDate: Date? {
            let calendar = Calendar.current
            switch self {
            case .today: return calendar.startOfDay(for: Date())
            case .week: return calendar.date(byAdding: .day, value: -7, to: Date())
            case .month: return calendar.date(byAdding: .day, value: -30, to: Date())
            case .all: return nil
            }
        }
    }

    private var period: Period { Period(rawValue: periodRawValue) ?? .all }

    private struct Stats {
        var words = 0
        var duration: TimeInterval = 0
        var apps = 0
        var wordsPerMinute: Int? {
            guard duration > 5 else { return nil }
            return Int((Double(words) / (duration / 60)).rounded())
        }
        var saved: TimeInterval { DashboardTimeSaving.timeSaved(words: words, duration: duration) }
    }

    private var stats: Stats {
        let start = period.startDate
        var result = Stats()
        var bundleIDs = Set<String>()
        for metric in metrics {
            if let start, metric.timestamp < start { break }  // sorted newest first
            result.words += metric.wordCount
            result.duration += metric.audioDuration
            if let entry = appUsage.entry(for: metric.transcriptionId) {
                bundleIDs.insert(entry.bundleID)
            }
        }
        result.apps = bundleIDs.count
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                statsSection
                recentSection
            }
            .padding(.horizontal, 26)
            .padding(.top, 6)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Statistics

    private var statsSection: some View {
        let stats = stats
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Statistik")
                    .font(OrgStyle.sectionTitleFont)
                Spacer()
                Menu {
                    ForEach(Period.allCases) { option in
                        Button(option.title) { periodRawValue = option.rawValue }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(period.title)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .regular))
                    }
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.85))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            HStack(spacing: 12) {
                statTile(
                    value: stats.wordsPerMinute.map { Self.number($0) } ?? "–",
                    label: "Ø Wörter pro Minute", symbol: "speedometer", tint: .orange)
                statTile(value: Self.number(stats.words), label: "Wörter", symbol: "text.word.spacing", tint: .blue)
                statTile(value: Self.number(stats.apps), label: "Genutzte Apps", symbol: "square.grid.2x2", tint: .purple)
                statTile(
                    value: Self.duration(stats.saved), label: "Gesparte Zeit", symbol: "clock", tint: .green)
            }
        }
    }

    private func statTile(value: String, label: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(tint)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.16)))
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(OrgStyle.secondaryText)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OrgCardBackground())
    }

    // MARK: Recent recordings

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Letzte Aufnahmen")
                    .font(OrgStyle.sectionTitleFont)
                Spacer()
                Button("Alle anzeigen") { navigation.navigate(to: .history) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
            }

            if recentTranscriptions.isEmpty {
                Text("Noch keine Aufnahmen. Halten Sie die fn-Taste gedrückt, sprechen Sie und lassen Sie los.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(OrgStyle.secondaryText)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OrgCardBackground())
            } else {
                VStack(spacing: 8) {
                    ForEach(recentTranscriptions) { transcription in
                        recentCard(transcription)
                    }
                }
                Text("Klick auf eine Aufnahme kopiert den Text.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(OrgStyle.secondaryText)
            }
        }
    }

    private func recentCard(_ transcription: Transcription) -> some View {
        let text = transcription.preferredHistoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = TranscriptionStatus(rawValue: transcription.transcriptionStatus ?? "")
        let placeholder: String? = {
            switch status {
            case .canceled: return "Aufnahme abgebrochen"
            case .failed: return "Transkription fehlgeschlagen"
            case .pending: return text.isEmpty ? "Wird verarbeitet …" : nil
            default: return text.isEmpty ? "Keine Sprache erkannt" : nil
            }
        }()
        let entry = appUsage.entry(for: transcription.id)
        let isCopied = copiedID == transcription.id

        return Button {
            guard placeholder == nil else { return }
            _ = ClipboardManager.copyToClipboard(text)
            copiedID = transcription.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                if copiedID == transcription.id { copiedID = nil }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if let placeholder {
                        Text(placeholder).italic().foregroundColor(OrgStyle.secondaryText)
                    } else {
                        Text(text).foregroundColor(.primary)
                    }
                }
                .font(.system(size: 14, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    if let entry {
                        OrgAppIcon(bundleID: entry.bundleID)
                        Text(entry.name)
                    }
                    if entry != nil {
                        Text("·")
                    }
                    Text(Self.relative(transcription.timestamp))
                    Spacer()
                    if isCopied {
                        Label("Kopiert", systemImage: "checkmark")
                            .labelStyle(.titleAndIcon)
                            .foregroundColor(.green)
                    }
                }
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(OrgStyle.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(OrgCardBackground())
            .contentShape(RoundedRectangle(cornerRadius: OrgStyle.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(placeholder == nil ? "Text kopieren" : "")
    }

    // MARK: Formatting

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static func number(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return seconds > 0 ? "< 1 Min." : "0 Min." }
        if minutes < 60 { return "\(minutes) Min." }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) Std." : "\(hours) Std. \(rest) Min."
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .short
        return formatter
    }()

    private static func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "gerade eben" }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Icon of an app by bundle id (empty space if the app is not installed).
struct OrgAppIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "app")
                .frame(width: 16, height: 16)
        }
    }
}
