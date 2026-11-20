import SwiftUI

struct MiniRecorderView<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject var assistantSession: AssistantSession
    let onRecordButtonTapped: () -> Void
    let onCloseTapped: () -> Void
    let onAssistantFollowUp: (String) -> Void
    @AppStorage(RecorderDisplaySettingsKeys.showLiveTranscript) private var showLiveTranscript = true

    // MARK: - Layout Constants

    // Organisation build (Undertone): wider glass panel, see `background`.
    private let controlBarHeight: CGFloat = OrgEdition.isEnabled ? 46 : 40
    private let compactWidth: CGFloat = OrgEdition.isEnabled ? 220 : 184
    private let expandedWidth: CGFloat = OrgEdition.isEnabled ? 600 : 300
    private let assistantWidth: CGFloat = 520
    private let compactCornerRadius: CGFloat = OrgEdition.isEnabled ? 23 : 20
    private let expandedCornerRadius: CGFloat = OrgEdition.isEnabled ? 20 : 14

    private var currentCornerRadius: CGFloat {
        hasLiveTranscript || hasAssistantResponse ? expandedCornerRadius : compactCornerRadius
    }

    @ViewBuilder
    private var panelBackground: some View {
        if OrgEdition.isEnabled {
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(red: 0.04, green: 0.04, blue: 0.08).opacity(0.62)
            }
        } else {
            Color.black
        }
    }

    // true when live transcript is streaming in during recording
    private var hasLiveTranscript: Bool {
        showLiveTranscript
            && stateProvider.recordingState == .recording
            && !stateProvider.partialTranscript.isEmpty
    }

    private var hasAssistantResponse: Bool {
        assistantSession.isVisible
    }

    private var shouldShowCloseButton: Bool {
        hasAssistantResponse && stateProvider.recordingState == .idle && !assistantSession.isBusy
    }

    private var liveAssistantFollowUpText: String {
        guard showLiveTranscript, stateProvider.recordingState == .recording else { return "" }
        return stateProvider.partialTranscript
    }

    private var controlBar: some View {
        HStack(spacing: 0) {
            Group {
                if shouldShowCloseButton {
                    RecorderCloseButton(action: onCloseTapped)
                } else {
                    RecorderRecordButton(
                        recordingState: stateProvider.recordingState,
                        action: onRecordButtonTapped
                    )
                }
            }
            .padding(.leading, 10)

            Spacer(minLength: 0)

            RecorderStatusDisplay(
                currentState: stateProvider.recordingState,
                audioMeterProvider: recorder.audioMeterSnapshot
            )

            Spacer(minLength: 0)

            RecorderModeButton(
                buttonSize: 22,
                padding: EdgeInsets()
            )
            .padding(.trailing, 12)
        }
        .frame(height: controlBarHeight)
    }

    private var transcriptSection: some View {
        VStack(spacing: 0) {
            if hasLiveTranscript {
                LiveTranscriptView(text: stateProvider.partialTranscript)
                Divider().background(Color.white.opacity(OrgEdition.isEnabled ? 0.08 : 0.15))
            }
        }
    }

    var body: some View {
        if OrgEdition.isEnabled && !hasAssistantResponse {
            OrgRecorderView(
                recordingState: stateProvider.recordingState,
                partialTranscript: stateProvider.partialTranscript,
                showLiveTranscript: showLiveTranscript,
                audioMeterProvider: recorder.audioMeterSnapshot,
                onStop: onRecordButtonTapped
            )
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        } else {
            upstreamBody
        }
    }

    private var upstreamBody: some View {
        VStack(spacing: 0) {
            if hasAssistantResponse {
                AssistantPanelView(
                    session: assistantSession,
                    liveFollowUpText: liveAssistantFollowUpText,
                    onSend: onAssistantFollowUp
                )
                Divider().background(Color.white.opacity(0.15))
            } else {
                transcriptSection
            }
            controlBar
        }
        .frame(width: hasAssistantResponse ? assistantWidth : (hasLiveTranscript ? expandedWidth : compactWidth))
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous))
        .overlay {
            if OrgEdition.isEnabled {
                RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
        }
        .shadow(color: .black.opacity(OrgEdition.isEnabled ? 0.35 : 0), radius: 18, y: 8)
        .padding(.bottom, OrgEdition.isEnabled ? 6 : 0)
        .animation(.easeInOut(duration: 0.3), value: hasLiveTranscript)
        .animation(.easeInOut(duration: 0.3), value: hasAssistantResponse)
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
