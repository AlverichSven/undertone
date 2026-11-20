import SwiftUI

/// Recorder panel of the organisation build (Undertone).
///
/// Wide, dark glass panel: live text on top (larger type, grows up to about five lines),
/// a darker bar below with mode label, a small gradient waveform and Stop / Cancel hints.
/// Only used when `OrgEdition.isEnabled`; the upstream mini recorder stays unchanged.
struct OrgRecorderView: View {
    let recordingState: RecordingState
    let partialTranscript: String
    let showLiveTranscript: Bool
    let audioMeterProvider: () -> AudioMeter
    let onStop: () -> Void

    static let panelWidth: CGFloat = 640
    /// About 300 pt wide waveform in the bottom bar.
    private static let waveBarCount = 56
    private let cornerRadius: CGFloat = 18
    private let barHeight: CGFloat = 54

    private var hasText: Bool {
        showLiveTranscript && !partialTranscript.isEmpty
            && (recordingState == .recording || recordingState == .transcribing)
    }

    private var placeholder: String {
        switch recordingState {
        case .starting:
            return "Einen Moment …"
        case .recording:
            return "Ich höre zu …"
        case .transcribing, .enhancing, .busy:
            return "Wird verarbeitet …"
        case .idle:
            return "Bereit"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            textArea
            bottomBar
        }
        .frame(width: Self.panelWidth)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(red: 0.05, green: 0.05, blue: 0.09).opacity(0.72)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.24), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 22, y: 10)
        .padding(.bottom, 6)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Text

    @ViewBuilder
    private var textArea: some View {
        if hasText {
            LiveTranscriptView(text: partialTranscript, revealsGradually: recordingState == .recording)
        } else {
            Text(placeholder)
                .font(.system(size: 15, weight: .light))
                .foregroundColor(.white.opacity(0.42))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.75))
                Text("Diktat")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.85))
            }

            Spacer(minLength: 8)

            statusIndicator
                .frame(height: 38)

            Spacer(minLength: 8)

            Button(action: onStop) {
                Text("Stopp")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(recordingState != .recording)

            HStack(spacing: 6) {
                Text("Abbrechen")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.9))
                KeyCap(label: "esc")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: barHeight)
        .background(Color.black.opacity(0.28))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch recordingState {
        case .recording:
            OrgWaveformView(
                audioMeterProvider: audioMeterProvider,
                barCount: Self.waveBarCount,
                barWidth: 3,
                barSpacing: 2.5,
                maxHeight: 38
            )
        case .transcribing:
            ProcessingStatusDisplay(mode: .transcribing, color: .white)
        case .enhancing:
            ProcessingStatusDisplay(mode: .enhancing, color: .white)
        default:
            StaticVisualizer(barCount: Self.waveBarCount, barWidth: 3, barSpacing: 2.5, color: .white)
        }
    }
}

private struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.16))
            )
    }
}
