import SwiftUI

// MARK: - Icon Toggle Button

struct RecorderToggleButton: View {
    let isEnabled: Bool
    let icon: String
    let disabled: Bool
    let action: () -> Void

    init(isEnabled: Bool, icon: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.icon = icon
        self.disabled = disabled
        self.action = action
    }

    private var isEmoji: Bool {
        !icon.contains(".") && !icon.contains("-") && icon.unicodeScalars.contains { !$0.isASCII }
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isEmoji {
                    Text(icon).font(.system(size: 14))
                } else {
                    Image(systemName: icon).font(.system(size: 13))
                }
            }
            .foregroundColor(disabled ? .white.opacity(0.3) : (isEnabled ? .white : .white.opacity(0.6)))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(disabled)
    }
}

// MARK: - Record Button

struct RecorderRecordButton: View {
    let recordingState: RecordingState
    let action: () -> Void

    private var visualState: VisualState {
        switch recordingState {
        case .idle, .starting, .busy:
            return .ready
        case .recording:
            return .recording
        case .transcribing, .enhancing:
            return .processing
        }
    }

    private var isDisabled: Bool {
        switch recordingState {
        case .idle, .recording:
            return false
        case .starting, .transcribing, .enhancing, .busy:
            return true
        }
    }

    var body: some View {
        Button(action: action) {
            buttonFace
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(accessibilityLabel)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var buttonFace: some View {
        ZStack {
            Circle()
                .fill(colors.surface)
                .overlay(
                    Circle()
                        .strokeBorder(colors.border, lineWidth: 0.6)
                )

            stateMark
        }
        .frame(width: 21, height: 21)
        .contentShape(Circle())
        .animation(.easeOut(duration: 0.16), value: visualState)
    }

    private var colors: StateColors {
        switch visualState {
        case .ready:
            return StateColors(
                surface: Color(red: 0.30, green: 0.30, blue: 0.32),
                border: Color(red: 0.42, green: 0.42, blue: 0.44),
                mark: Color(red: 0.78, green: 0.78, blue: 0.80)
            )
        case .recording:
            let red = AppTheme.Status.error
            return StateColors(
                surface: red.opacity(0.92),
                border: red.opacity(0.98),
                mark: .white
            )
        case .processing:
            return StateColors(
                surface: Color.white.opacity(0.13),
                border: Color.white.opacity(0.18),
                mark: Color.white.opacity(0.86)
            )
        }
    }

    @ViewBuilder
    private var stateMark: some View {
        switch visualState {
        case .ready, .recording:
            RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                .fill(colors.mark)
                .frame(width: 8, height: 8)
        case .processing:
            ProcessingIndicator(color: colors.mark)
        }
    }

    private var accessibilityLabel: String {
        switch recordingState {
        case .idle:
            return String(localized: "Start recording")
        case .starting:
            return String(localized: "Starting recording")
        case .recording:
            return String(localized: "Stop recording")
        case .transcribing:
            return String(localized: "Transcribing recording")
        case .enhancing:
            return String(localized: "Enhancing recording")
        case .busy:
            return String(localized: "Recorder unavailable")
        }
    }

    private enum VisualState: Equatable {
        case ready
        case recording
        case processing
    }

    private struct StateColors {
        let surface: Color
        let border: Color
        let mark: Color
    }
}

// MARK: - Close Button

struct RecorderCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.13))
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                    )

                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.86))
            }
            .frame(width: 21, height: 21)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Close")
    }
}

// MARK: - Processing Indicator

struct ProcessingIndicator: View {
    @State private var rotation: Double = 0
    let color: Color

    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.9)
            .stroke(color, lineWidth: 1.5)
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Progress Dot Animation

struct ProgressAnimation: View {
    let color: Color
    let animationSpeed: Double

    private let dotCount = 5
    private let dotSize: CGFloat = 3
    private let dotSpacing: CGFloat = 2

    @State private var currentDot = 0
    @State private var timer: Timer?

    init(color: Color = .white, animationSpeed: Double = 0.3) {
        self.color = color
        self.animationSpeed = animationSpeed
    }

    var body: some View {
        HStack(spacing: dotSpacing) {
            ForEach(0..<dotCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: dotSize / 2)
                    .fill(color.opacity(index <= currentDot ? 0.85 : 0.25))
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .onAppear { startAnimation() }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func startAnimation() {
        timer?.invalidate()
        currentDot = 0
        timer = Timer.scheduledTimer(withTimeInterval: animationSpeed, repeats: true) { _ in
            currentDot = (currentDot + 1) % (dotCount + 2)
            if currentDot > dotCount { currentDot = -1 }
        }
    }
}

// MARK: - Mode Button

struct RecorderModeButton: View {
    @ObservedObject private var modeManager = ModeManager.shared
    let buttonSize: CGFloat
    let padding: EdgeInsets

    @State private var isPopoverPresented = false
    @State private var isHoveringButton: Bool = false
    @State private var isHoveringPopover: Bool = false
    @State private var dismissWorkItem: DispatchWorkItem?

    init(buttonSize: CGFloat = 28, padding: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 7)) {
        self.buttonSize = buttonSize
        self.padding = padding
    }

    var body: some View {
        if OrgEdition.isEnabled {
            // Organisation build has a single fixed mode; keep the layout slot empty.
            Color.clear.frame(width: buttonSize, height: 1).padding(padding)
        } else {
            modeToggleButton
        }
    }

    private var modeToggleButton: some View {
        RecorderToggleButton(
            isEnabled: !modeManager.enabledConfigurations.isEmpty,
            icon: modeManager.enabledConfigurations.isEmpty
                ? "square.grid.2x2" : (modeManager.currentEffectiveConfiguration?.icon.value ?? "square.grid.2x2"),
            disabled: modeManager.enabledConfigurations.isEmpty
        ) {
            isPopoverPresented.toggle()
        }
        .frame(width: buttonSize)
        .padding(padding)
        .onHover {
            isHoveringButton = $0
            syncPopoverVisibility()
        }
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            ModePopover()
                .onHover {
                    isHoveringPopover = $0
                    syncPopoverVisibility()
                }
        }
    }

    private func syncPopoverVisibility() {
        if isHoveringButton || isHoveringPopover {
            dismissWorkItem?.cancel()
            dismissWorkItem = nil
            isPopoverPresented = true
        } else {
            dismissWorkItem?.cancel()
            let work = DispatchWorkItem { [isPopoverPresentedBinding = $isPopoverPresented] in
                isPopoverPresentedBinding.wrappedValue = false
            }
            dismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
}

// MARK: - Live Transcript View

private struct LiveTranscriptHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Organisation build: reveals newly arrived words one after another so streaming text flows
/// instead of jumping in blocks. Display only; the transcript itself is untouched.
@MainActor
final class OrgWordRevealModel: ObservableObject {
    /// Words currently shown (fully revealed).
    @Published private(set) var shownText = ""
    /// Most recently revealed word, drawn slightly dimmer until the next one arrives.
    @Published private(set) var trailingWord = ""

    private var targetWords: [Substring] = []
    private var shownCount = 0
    private var timer: Timer?
    private var settleWork: DispatchWorkItem?

    private static let fastestInterval: TimeInterval = 0.035
    private static let slowestInterval: TimeInterval = 0.06
    /// Streaming passes arrive about once per second; reveal a block within this time.
    private static let blockBudget: TimeInterval = 0.85

    func update(target text: String, gradual: Bool) {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard gradual else {
            showAll(words)
            return
        }

        // Words already on screen that the model kept stay; corrected words are replaced in place
        // immediately (no shrinking, no flicker).
        let common = zip(targetWords.prefix(shownCount), words).prefix { $0 == $1 }.count
        let previousTargetCount = targetWords.count
        targetWords = words
        // Never fall more than about one block behind: finish the previous block at once.
        shownCount = min(words.count, max(shownCount, min(previousTargetCount, words.count), common))
        if shownCount < common { shownCount = common }

        publish()
        scheduleReveal()
    }

    func finish() {
        showAll(targetWords)
    }

    private func showAll(_ words: [Substring]) {
        timer?.invalidate()
        timer = nil
        targetWords = words
        shownCount = words.count
        publish(dimLast: false)
    }

    private func scheduleReveal() {
        timer?.invalidate()
        timer = nil
        let backlog = targetWords.count - shownCount
        guard backlog > 0 else {
            settle()
            return
        }
        let interval = min(Self.slowestInterval, max(Self.fastestInterval, Self.blockBudget / Double(backlog)))
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                guard self.shownCount < self.targetWords.count else {
                    timer.invalidate()
                    self.timer = nil
                    self.settle()
                    return
                }
                self.shownCount += 1
                self.publish()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func publish(dimLast: Bool = true) {
        let visible = targetWords.prefix(shownCount)
        if dimLast, let last = visible.last, shownCount > 0 {
            shownText = visible.dropLast().joined(separator: " ")
            trailingWord = String(last)
        } else {
            shownText = visible.joined(separator: " ")
            trailingWord = ""
        }
    }

    /// Brighten the last word shortly after the reveal stops.
    private func settle() {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.timer == nil else { return }
            self.publish(dimLast: false)
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
}

struct LiveTranscriptView: View {
    let text: String
    /// Organisation build: reveal new words gradually (only while recording).
    var revealsGradually: Bool = false

    // Organisation build: larger type, panel grows with the text up to about five lines.
    @State private var contentHeight: CGFloat = 0
    @StateObject private var reveal = OrgWordRevealModel()
    private let orgMinHeight: CGFloat = 48
    private let orgMaxHeight: CGFloat = 150

    /// Upstream always fades the top edge; the org build only fades once the text scrolls.
    private var fadesTop: Bool {
        !OrgEdition.isEnabled || contentHeight > orgMaxHeight
    }

    private var viewportHeight: CGFloat {
        guard OrgEdition.isEnabled else { return 56 }
        return min(max(contentHeight, orgMinHeight), orgMaxHeight)
    }

    private var usesReveal: Bool { OrgEdition.isEnabled }

    private var textOpacity: Double { OrgEdition.isEnabled ? 0.86 : 0.8 }

    private var displayedText: Text {
        guard usesReveal else { return Text(text) }
        let shown = reveal.shownText
        let trailing = reveal.trailingWord
        guard !trailing.isEmpty else { return Text(shown) }
        let separator = shown.isEmpty ? "" : " "
        return Text(shown + separator)
            + Text(trailing).foregroundColor(.white.opacity(0.55))
    }

    private var fadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: fadesTop ? .clear : .black, location: 0.0),
                .init(color: .black, location: fadesTop ? 0.18 : 0.0),
                .init(color: .black, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        if OrgEdition.isEnabled {
            orgBody
        } else {
            upstreamBody
        }
    }

    /// Organisation build: no ScrollView. The text is pinned to the bottom edge and simply
    /// grows upwards; overflow is clipped at the top (with a fade). This avoids the scroll view
    /// jumping back to the top and re-scrolling while long text streams in.
    private var orgBody: some View {
        displayedText
            .font(.system(size: 15, weight: .light))
            .lineSpacing(3)
            .foregroundColor(.white.opacity(textOpacity))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(key: LiveTranscriptHeightKey.self, value: geometry.size.height)
                }
            )
            .onPreferenceChange(LiveTranscriptHeightKey.self) { height in
                contentHeight = height
            }
            .frame(height: viewportHeight, alignment: .bottom)
            .clipped()
            .mask(fadeMask)
            .onAppear {
                reveal.update(target: text, gradual: revealsGradually)
            }
            .onChange(of: text) {
                reveal.update(target: text, gradual: revealsGradually)
            }
            .onChange(of: revealsGradually) { _, gradual in
                // Stop / processing: show the full text right away.
                if !gradual { reveal.finish() }
            }
            .transaction { $0.disablesAnimations = true }
    }

    private var upstreamBody: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                displayedText
                    .font(.system(size: OrgEdition.isEnabled ? 17 : 12, weight: OrgEdition.isEnabled ? .light : .regular))
                    .lineSpacing(OrgEdition.isEnabled ? 4 : 0)
                    .foregroundColor(.white.opacity(textOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OrgEdition.isEnabled ? 22 : 16)
                    .padding(.vertical, OrgEdition.isEnabled ? 14 : 6)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(key: LiveTranscriptHeightKey.self, value: geometry.size.height)
                        }
                    )
                    .id("bottom")
            }
            .onPreferenceChange(LiveTranscriptHeightKey.self) { height in
                contentHeight = height
            }
            .frame(height: viewportHeight)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: fadesTop ? .clear : .black, location: 0.0),
                        .init(color: .black, location: fadesTop ? 0.18 : 0.0),
                        .init(color: .black, location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onAppear {
                if usesReveal { reveal.update(target: text, gradual: revealsGradually) }
            }
            .onChange(of: text) {
                if usesReveal { reveal.update(target: text, gradual: revealsGradually) }
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: revealsGradually) { _, gradual in
                // Stop / processing: show the full text right away.
                if usesReveal && !gradual { reveal.finish() }
            }
            .onChange(of: reveal.shownText) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
        .transaction { $0.disablesAnimations = true }
    }
}

// MARK: - Recorder Status Display

struct RecorderStatusDisplay: View {
    let currentState: RecordingState
    let audioMeterProvider: () -> AudioMeter
    let menuBarHeight: CGFloat?

    init(
        currentState: RecordingState,
        audioMeterProvider: @escaping () -> AudioMeter,
        menuBarHeight: CGFloat? = nil
    ) {
        self.currentState = currentState
        self.audioMeterProvider = audioMeterProvider
        self.menuBarHeight = menuBarHeight
    }

    var body: some View {
        Group {
            if currentState == .enhancing {
                ProcessingStatusDisplay(mode: .enhancing, color: .white).transition(.opacity)
            } else if currentState == .transcribing {
                ProcessingStatusDisplay(mode: .transcribing, color: .white).transition(.opacity)
            } else if currentState == .recording && OrgEdition.isEnabled {
                // Undertone: waveform in the icon's gradient (violet, blue, teal).
                AudioVisualizer(
                    audioMeterProvider: audioMeterProvider,
                    color: .white,
                    isActive: true
                )
                .overlay(
                    LinearGradient(
                        colors: [
                            Color(red: 0.43, green: 0.36, blue: 1.0),
                            Color(red: 0.25, green: 0.67, blue: 1.0),
                            Color(red: 0.16, green: 0.88, blue: 0.82),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .blendMode(BlendMode.sourceAtop)
                )
                .compositingGroup()
                .scaleEffect(y: menuBarHeight != nil ? min(1.0, (menuBarHeight! - 8) / 25) : 1.0, anchor: .center)
                .transition(.opacity)
            } else if currentState == .recording {
                AudioVisualizer(
                    audioMeterProvider: audioMeterProvider,
                    color: .white,
                    isActive: true
                )
                    .scaleEffect(y: menuBarHeight != nil ? min(1.0, (menuBarHeight! - 8) / 25) : 1.0, anchor: .center)
                    .transition(.opacity)
            } else {
                StaticVisualizer(color: .white)
                    .scaleEffect(y: menuBarHeight != nil ? min(1.0, (menuBarHeight! - 8) / 25) : 1.0, anchor: .center)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentState)
    }
}

// MARK: - Assistant Response Panel

struct AssistantPanelView: View {
    @ObservedObject var session: AssistantSession
    let liveFollowUpText: String
    let onSend: (String) -> Void

    @State private var draftMessage = ""
    @FocusState private var isFollowUpFieldFocused: Bool

    private let horizontalPadding: CGFloat = 20
    private let followUpTextColor = Color.white.opacity(0.9)

    private var statusText: String? {
        switch session.phase {
        case .responding, .sendingFollowUp:
            return String(localized: "Thinking")
        case .failed(let message):
            return message
        case .inactive, .ready:
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            messageList
            followUpRow
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 10)
        .frame(height: 320)
        .onAppear(perform: focusFollowUpFieldIfAvailable)
        .onChange(of: session.phase) {
            focusFollowUpFieldIfAvailable()
        }
    }

    private var fullConversationText: String {
        session.messages.map { msg in
            let prefix = msg.role == .user ? "You" : "Assistant"
            return "\(prefix): \(msg.content)"
        }.joined(separator: "\n\n")
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(session.messages) { message in
                        AssistantMessageBubble(message: message)
                            .id(message.id)
                    }

                    if let statusText {
                        Text(statusText)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.62))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("status")
                    }
                }
                .padding(.vertical, 2)
                .overlay(alignment: .topLeading) {
                    if !session.messages.isEmpty {
                        CopyIconButton(textToCopy: fullConversationText)
                            .scaleEffect(0.72)
                    }
                }
            }
            .onChange(of: session.messages.count) {
                scrollToBottom(proxy)
            }
            .onChange(of: session.phase) {
                scrollToBottom(proxy)
            }
        }
    }

    private var followUpRow: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                if shouldShowLiveFollowUpText {
                    Text(liveFollowUpText)
                        .font(.system(size: 12))
                        .foregroundStyle(followUpTextColor)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .allowsHitTesting(false)
                }

                TextField("", text: $draftMessage)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(followUpTextColor)
                    .tint(followUpTextColor)
                    .disabled(!session.canSendFollowUp)
                    .focused($isFollowUpFieldFocused)
                    .onSubmit(sendDraftMessage)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button(action: sendDraftMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(canSendDraft ? .black : .white.opacity(0.35))
                    .frame(width: 24, height: 24)
                    .background(canSendDraft ? Color.white.opacity(0.88) : Color.white.opacity(0.10))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSendDraft)
            .help("Send follow up")
        }
    }

    private var shouldShowLiveFollowUpText: Bool {
        draftMessage.isEmpty && !liveFollowUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSendDraft: Bool {
        session.canSendFollowUp && !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraftMessage() {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard session.canSendFollowUp, !trimmed.isEmpty else { return }
        draftMessage = ""
        onSend(trimmed)
        focusFollowUpFieldIfAvailable()
    }

    private func focusFollowUpFieldIfAvailable() {
        guard session.canSendFollowUp else { return }
        DispatchQueue.main.async {
            isFollowUpFieldFocused = true
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                if let last = session.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                } else {
                    proxy.scrollTo("status", anchor: .bottom)
                }
            }
        }
    }
}

private struct AssistantMessageBubble: View {
    let message: AssistantDisplayMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 36)
            }

            MarkdownContentView(
                message.content,
                fontSize: 12,
                foregroundColor: .white.opacity(isUser ? 0.92 : 0.86),
                alignment: .leading
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isUser ? Color.white.opacity(0.16) : Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if !isUser {
                    CopyIconButton(textToCopy: message.content)
                        .scaleEffect(0.72)
                        .padding(0)
                }
            }
            .help(isUser ? message.content : "")

            if !isUser {
                Spacer(minLength: 36)
            }
        }
    }
}
