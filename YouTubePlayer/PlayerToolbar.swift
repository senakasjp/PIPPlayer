import SwiftUI

// Shared tokens for the native player chrome; see DESIGN.md.
enum PlayerChrome {
    static let accent = Color(red: 1, green: 105 / 255, blue: 74 / 255)
    static let panel = Color(red: 39 / 255, green: 56 / 255, blue: 73 / 255)
    static let height: CGFloat = 72
    static let radius: CGFloat = 10
    static let inset: CGFloat = 8
    static let padding: CGFloat = 14
    static let titleSize: CGFloat = 24
    static let iconSize: CGFloat = 16
    static let timeSize: CGFloat = 11
}

struct PlayerToolbar: View {
    let isPlaying: Bool
    @Binding var currentTime: Double
    let duration: Double
    @Binding var volume: Double
    @Binding var isScrubbing: Bool
    let onToggle: () -> Void
    let onSeek: () -> Void
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    let onPlaylist: () -> Void
    var onFullscreen: () -> Void = {}
    var onAlwaysOnTop: () -> Void = {}
    var isAlwaysOnTop = false
    var videoZoom: Binding<Double>? = nil
    @State private var showsOptions = false
    @State private var volumeBeforeMute = 1.0

    private var safeDuration: Double { duration.isFinite ? max(duration, 0) : 0 }
    private var safeTime: Double { currentTime.isFinite ? max(currentTime, 0) : 0 }
    private var seekValue: Binding<Double> {
        Binding(get: { min(safeTime, safeDuration) }, set: { currentTime = $0 })
    }
    private var volumeValue: Binding<Double> {
        Binding(get: { volume.isFinite ? min(max(volume, 0), 1) : 1 }, set: { volume = $0 })
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 480
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    timeLabel(safeTime)
                    PlayerSlider(value: seekValue, maximum: max(safeDuration, 1), label: "Playback position", enabled: safeDuration > 0) { editing in
                        isScrubbing = editing
                        if !editing { onSeek() }
                    }
                    .frame(height: 20)
                    .help("Seek through the video")
                    timeLabel(safeDuration)
                }
                HStack(spacing: 0) {
                    Group {
                        if wide { volumeSlider }
                        else { control(volume <= 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", "Mute / unmute", action: toggleMute) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    transport
                    HStack(spacing: 4) {
                        if wide {
                            control("arrow.up.left.and.arrow.down.right", "Toggle fullscreen", action: onFullscreen)
                            control(isAlwaysOnTop ? "pin.fill" : "pin", "Always on top", action: onAlwaysOnTop)
                                .foregroundStyle(isAlwaysOnTop ? PlayerChrome.accent : .white)
                        }
                        control("gearshape.fill", "Playback options") { showsOptions.toggle() }
                            .popover(isPresented: $showsOptions, arrowEdge: .bottom) { options }
                        control("list.bullet", "Playlist", action: onPlaylist)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(height: 28)
            }
            .padding(.horizontal, PlayerChrome.padding)
            .padding(.vertical, 8)
            .frame(width: geometry.size.width, height: PlayerChrome.height)
            .background(PlayerChrome.panel.opacity(0.94))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: PlayerChrome.radius))
            .overlay(RoundedRectangle(cornerRadius: PlayerChrome.radius).strokeBorder(.white.opacity(0.06)))
            .shadow(color: .black.opacity(0.20), radius: 12, y: 4)
        }
        .frame(height: PlayerChrome.height)
        .foregroundStyle(.white)
        .tint(PlayerChrome.accent)
        .environment(\.colorScheme, .dark)
    }

    private var transport: some View {
        HStack(spacing: 8) {
            control("backward.end.fill", "Previous item") { onPrevious?() }.disabled(onPrevious == nil)
            Button(action: onToggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 36, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .help(isPlaying ? "Pause (Space)" : "Play (Space)")
            control("forward.end.fill", "Next item") { onNext?() }.disabled(onNext == nil)
        }
    }

    private var volumeSlider: some View {
        PlayerSlider(value: volumeValue, maximum: 1, label: "Volume", isVolume: true)
            .frame(width: 88, height: 26)
            .overlay(alignment: .leading) {
                Image(systemName: volume <= 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: PlayerChrome.iconSize))
                    .padding(.leading, 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .help("Adjust volume")
    }

    private func toggleMute() {
        if volume > 0 { volumeBeforeMute = volume; volume = 0 }
        else { volume = volumeBeforeMute }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playback").font(.headline)
            HStack { Text("Volume"); Spacer(); volumeSlider }
            Button("Toggle fullscreen", action: onFullscreen)
            Toggle("Always on top", isOn: Binding(get: { isAlwaysOnTop }, set: { _ in onAlwaysOnTop() }))
            if let videoZoom {
                Divider()
                HStack {
                    Text("Video zoom")
                    Spacer()
                    Text("\(Int(videoZoom.wrappedValue * 100))%").monospacedDigit()
                }
                Slider(value: videoZoom, in: 1...3, step: 0.05)
                    .accessibilityLabel("Video zoom")
                Button("Reset to 100%") { videoZoom.wrappedValue = 1 }
                    .disabled(videoZoom.wrappedValue == 1)
            }
        }
        .padding(16)
        .frame(width: 240)
    }

    private func control(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: PlayerChrome.iconSize, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .help(label)
    }

    private func timeLabel(_ time: Double) -> some View {
        Text(formattedTime(time))
            .font(.system(size: PlayerChrome.timeSize, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.85))
            .fixedSize()
    }

    private func formattedTime(_ time: Double) -> String {
        let seconds = Int(min(max(time, 0), 359_999))
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct PlayerSlider: NSViewRepresentable {
    @Binding var value: Double
    let maximum: Double
    let label: String
    var enabled = true
    var isVolume = false
    var onEditing: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        let cell = PlayerSliderCell()
        cell.isVolume = isVolume
        cell.onEditing = { context.coordinator.parent.onEditing($0) }
        slider.cell = cell
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.setAccessibilityLabel(label)
        return slider
    }
    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        slider.minValue = 0
        slider.maxValue = maximum
        slider.doubleValue = value
        slider.isEnabled = enabled
    }
    final class Coordinator: NSObject {
        var parent: PlayerSlider
        init(_ parent: PlayerSlider) { self.parent = parent }
        @objc func changed(_ sender: NSSlider) {
            parent.value = sender.doubleValue
            if NSApp.currentEvent?.type == .keyDown { parent.onEditing(false) }
        }
    }
}

private final class PlayerSliderCell: NSSliderCell {
    var isVolume = false
    var onEditing: (Bool) -> Void = { _ in }
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let bounds = controlView?.bounds ?? rect
        let track = isVolume ? bounds : NSRect(x: 6, y: bounds.midY - 1.5, width: max(0, bounds.width - 12), height: 3)
        let radius: CGFloat = isVolume ? 6 : 2
        NSColor.white.withAlphaComponent(isEnabled ? 0.35 : 0.15).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
        let fraction = maxValue > minValue ? (doubleValue - minValue) / (maxValue - minValue) : 0
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).addClip()
        (isVolume ? NSColor.white.withAlphaComponent(0.35) : NSColor(PlayerChrome.accent)).setFill()
        NSRect(x: track.minX, y: track.minY, width: track.width * fraction, height: track.height).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    override func drawKnob(_ knobRect: NSRect) {
        guard !isVolume else { return }
        NSColor.white.withAlphaComponent(isEnabled ? 1 : 0.35).setFill()
        NSBezierPath(ovalIn: NSRect(x: knobRect.midX - 6, y: knobRect.midY - 6, width: 12, height: 12)).fill()
    }
    override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
        onEditing(true)
        return super.startTracking(at: startPoint, in: controlView)
    }
    override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView, mouseIsUp flag: Bool) {
        super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
        onEditing(false)
    }
}
