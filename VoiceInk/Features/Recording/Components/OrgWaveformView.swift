import SwiftUI

/// Waveform of the organisation build (Undertone).
///
/// Unlike the upstream visualizer (all bars follow the current level with a sine wobble), this
/// keeps a short history of the voice level. The newest value sits in the middle and older values
/// move outwards to both sides, so speech draws a real, symmetric "voice shape" that flows
/// outwards. Edges taper off like the README artwork; colours run violet, blue, teal.
struct OrgWaveformView: View {
    let audioMeterProvider: () -> AudioMeter
    var barCount: Int = 56
    var barWidth: CGFloat = 3
    var barSpacing: CGFloat = 2.5
    var maxHeight: CGFloat = 36
    var minHeight: CGFloat = 3

    @StateObject private var history = OrgWaveHistory()

    private static let colors: [(Double, Double, Double)] = [
        (0.43, 0.36, 1.0),
        (0.25, 0.67, 1.0),
        (0.16, 0.88, 0.82),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            // Sample the level on every frame the timeline renders (like the upstream
            // visualizer does); `levels` is plain storage, so this does not invalidate the view.
            let levels = history.tick(audioMeterProvider(), at: context.date, slots: barCount / 2 + 1)
            Canvas { graphics, size in
                let half = barCount / 2
                let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
                let originX = (size.width - totalWidth) / 2
                let midY = size.height / 2

                for index in 0..<barCount {
                    // Distance from the centre picks the history slot: centre = newest.
                    let distance = abs(index - half + (index >= half ? 0 : 1))
                    let level = distance < levels.count ? levels[distance] : 0
                    let t = Double(index) / Double(max(barCount - 1, 1))
                    let taper = pow(sin(Double.pi * t), 0.6)
                    let height = max(minHeight, minHeight + CGFloat(level * taper) * (maxHeight - minHeight))
                    let x = originX + CGFloat(index) * (barWidth + barSpacing)
                    let rect = CGRect(x: x, y: midY - height / 2, width: barWidth, height: height)
                    graphics.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .color(Self.color(at: t).opacity(level > 0.02 ? 1.0 : 0.55))
                    )
                }
            }
        }
        .frame(
            width: CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing,
            height: maxHeight
        )
    }

    private static func color(at t: Double) -> Color {
        let segment = t < 0.5 ? 0 : 1
        let local = t < 0.5 ? t / 0.5 : (t - 0.5) / 0.5
        let a = colors[segment], b = colors[segment + 1]
        return Color(
            red: a.0 + (b.0 - a.0) * local,
            green: a.1 + (b.1 - a.1) * local,
            blue: a.2 + (b.2 - a.2) * local
        )
    }
}

/// Short, smoothed history of the voice level (0...1), newest first.
@MainActor
final class OrgWaveHistory: ObservableObject {
    private(set) var levels: [Double] = []
    private var smoothed: Double = 0

    private var lastSample = Date.distantPast

    /// Adds a sample at most ~30 times per second and returns the current history.
    func tick(_ meter: AudioMeter, at date: Date, slots: Int) -> [Double] {
        if date.timeIntervalSince(lastSample) >= 1.0 / 32.0 {
            lastSample = date
            push(meter, slots: slots)
        }
        return levels
    }

    func push(_ meter: AudioMeter, slots: Int) {
        // Same boost as the upstream visualizer, plus a little peak for livelier shape.
        let raw = max(0, min(1, pow(meter.averagePower, 0.7) * 0.8 + meter.peakPower * 0.2))
        // Fast attack, slower release: words pop up, pauses settle smoothly.
        let factor = raw > smoothed ? 0.6 : 0.25
        smoothed += (raw - smoothed) * factor
        // Small natural variation so neighbouring bars are not identical.
        let jitter = Double.random(in: 0.85...1.0)
        levels.insert(smoothed * jitter, at: 0)
        if levels.count > slots { levels.removeLast(levels.count - slots) }
    }
}
