import SwiftUI
import AppKit

// Shared tokens for the native player chrome; see DESIGN.md.
enum PlayerChrome {
    static let accent = Color(red: 1, green: 105 / 255, blue: 74 / 255)
    static let panel = Color(red: 39 / 255, green: 56 / 255, blue: 73 / 255)
    static let height: CGFloat = 72
    static let topBarHeight: CGFloat = 28
    static let windowButtonsWidth: CGFloat = 80
    static let radius: CGFloat = 4
    static let windowRadius: CGFloat = 6   // player window and playlist sheet corners
    static let smallRadius: CGFloat = 3   // fields, badges, thumbnails, buttons
    static let inset: CGFloat = 8
    static let padding: CGFloat = 14
    static let titleSize: CGFloat = 24
    static let iconSize: CGFloat = 18
    static let timeSize: CGFloat = 11
    static let eqPopoverWidth: CGFloat = 400
    static let eqPadding: CGFloat = 16
    static let contentPadding: CGFloat = 12
    static let eqSectionSpacing: CGFloat = 12
    static let eqHeaderSpacing: CGFloat = 2
    static let eqColumnSpacing: CGFloat = 8
    static let eqBandSpacing: CGFloat = 7
    static let eqBandWidth: CGFloat = 44
    static let eqSliderWidth: CGFloat = 28
    static let eqSliderHeight: CGFloat = 132
    static let eqValueSize: CGFloat = 10
    static let eqValueHeight: CGFloat = 14
    static let eqTrackOpacity = 0.20
    static let eqDisabledTrackOpacity = 0.10
    static let eqAccentOpacity = 0.90
    static let eqDisabledAccentOpacity = 0.25
    static let eqTickOpacity = 0.16
    static let eqZeroTickOpacity = 0.38
    static let eqDisabledTickOpacity = 0.08
    static let eqTrackInset: CGFloat = 8
    static let eqTrackWidth: CGFloat = 3
    static let eqTrackRadius: CGFloat = 1.5
    static let eqTickCount = 12
    static let eqTickInnerOffset: CGFloat = 4
    static let eqTickOuterOffset: CGFloat = 8
    static let eqKnobWidth: CGFloat = 26
    static let eqKnobHeight: CGFloat = 11
    static let eqKnobFill = NSColor(calibratedWhite: 0.82, alpha: 1)
    static let eqKnobDisabledOpacity = 0.58
    static let eqKnobStrokeOpacity = 0.50
    static let eqKnobDisabledStrokeOpacity = 0.18

    /// Borderless 28pt icon control shared by the toolbar and playlist.
    static func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        IconControlButton(symbol: symbol, label: label, action: action)
    }

    /// Vector SF Symbol control with a soft hover surface, so the icon set reads
    /// crisp on Retina displays and still gives pointer feedback in dark panels.
    private struct IconControlButton: View {
        let symbol: String
        let label: String
        let action: () -> Void
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: PlayerChrome.iconSize, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.white.opacity(hovering && isEnabled ? 0.10 : 0))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .onHover { hovering = $0 }
            .accessibilityLabel(label)
            .help(label)
        }
    }
}

extension NSWindow {
    /// macOS 26 rounds titled windows and sheets heavily and offers no public setting.
    /// ponytail: private AppKit setter, skipped when the method is missing; drop it if Apple adds an API.
    func setCornerRadius(_ radius: CGFloat) {
        let selector = NSSelectorFromString("_setCornerRadius:")
        guard let method = class_getInstanceMethod(NSWindow.self, selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, CGFloat) -> Void
        unsafeBitCast(method_getImplementation(method), to: Setter.self)(self, selector, radius)
    }

    /// Keeps the whole window inside the usable area of a screen. Tiling window
    /// managers (AeroSpace, Rectangle, …) and unplugged displays can leave a
    /// window partly or entirely off-screen; this pulls it back so its controls
    /// and content stay reachable.
    func clampToVisibleScreen(margin: CGFloat = 12, centerIfOffscreen: Bool = false) {
        guard let visible = (sheetParent?.screen ?? NSScreen.bestScreen(for: frame))?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        let margin = max(0, margin)
        let bounds = visible.insetBy(dx: min(margin, visible.width / 4), dy: min(margin, visible.height / 4))
        var frame = self.frame

        // Never keep a window larger than the space available on the display.
        frame.size.width = min(frame.width, bounds.width)
        frame.size.height = min(frame.height, bounds.height)

        let intersects = bounds.intersects(frame)
        if centerIfOffscreen, !intersects {
            frame.origin.x = bounds.midX - frame.width / 2
            frame.origin.y = bounds.midY - frame.height / 2
        }
        frame.origin.x = min(max(frame.origin.x, bounds.minX), bounds.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, bounds.minY), bounds.maxY - frame.height)

        if frame != self.frame {
            setFrame(frame, display: true)
        }
    }

    /// Centers the window on the screen it belongs to (or the main screen), fitting
    /// it inside the visible area first. Used when opening the playlist and when a
    /// saved frame no longer maps to any connected display.
    func centerOnVisibleScreen(margin: CGFloat = 12) {
        guard let visible = (sheetParent?.screen ?? NSScreen.bestScreen(for: frame))?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        let margin = max(0, margin)
        let bounds = visible.insetBy(dx: min(margin, visible.width / 4), dy: min(margin, visible.height / 4))
        var size = frame.size
        size.width = min(size.width, bounds.width)
        size.height = min(size.height, bounds.height)
        setFrame(NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                        width: size.width, height: size.height), display: true)
    }
}

extension NSScreen {
    /// The display a frame belongs to: the one with the largest overlap, or the main
    /// display when nothing overlaps (for example after a monitor was disconnected).
    static func bestScreen(for frame: NSRect) -> NSScreen? {
        let screens = NSScreen.screens
        let best = screens.max { a, b in
            a.visibleFrame.intersection(frame).area < b.visibleFrame.intersection(frame).area
        }
        if let best, best.visibleFrame.intersects(frame) { return best }
        return NSScreen.main ?? screens.first
    }
}

private extension NSRect {
    var area: CGFloat { isNull || isEmpty ? 0 : width * height }
}

/// Applies `PlayerChrome.windowRadius` to the window hosting this view (used for sheets).
struct WindowCornerRadius: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.setCornerRadius(PlayerChrome.windowRadius)
        }
    }
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {}
}

/// Centers the window hosting this view on its screen (used for sheets that shouldn't anchor under the title bar)
/// and keeps it fully visible after window managers or display changes move it.
struct CenterOnScreen: NSViewRepresentable {
    final class Probe: NSView {
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }

            // Center after the sheet has been sized, then once more after a tiling
            // window manager has had a chance to place it.
            DispatchQueue.main.async {
                window.centerOnVisibleScreen()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak window] in
                guard let window, window.isVisible else { return }
                window.clampToVisibleScreen()
            }

            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: window, queue: .main
            ) { [weak window] _ in
                window?.clampToVisibleScreen()
            })
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {}
}

extension View {
    /// The player's floating slate panel: tinted material, hairline border and soft shadow.
    func playerPanel(radius: CGFloat = PlayerChrome.radius) -> some View {
        background(PlayerChrome.panel.opacity(0.94))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.06)))
            .shadow(color: .black.opacity(0.20), radius: 12, y: 4)
    }
}

struct PlayerToolbar: View {
    let isPlaying: Bool
    @Binding var currentTime: Double
    let duration: Double
    @Binding var volume: Double
    @Binding var isScrubbing: Bool
    @ObservedObject var equalizer: PlayerEqualizer
    let onToggle: () -> Void
    let onSeek: () -> Void
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    let onPlaylist: () -> Void
    var onFullscreen: () -> Void = {}
    var onAlwaysOnTop: () -> Void = {}
    var isAlwaysOnTop = false
    var videoZoom: Binding<Double>? = nil
    var onDeleteFile: (() -> Void)? = nil
    @State private var showsOptions = false
    @State private var showsEqualizer = false
    @State private var volumeBeforeMute = 1.0
    @State private var hoveringTransport = false

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
                    HStack(spacing: 4) {
                        control(volume <= 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", "Mute / unmute", action: toggleMute)
                        control("waveform", "Equalizer") { showsEqualizer.toggle() }
                            .foregroundStyle(equalizer.isEnabled ? PlayerChrome.accent : .white)
                            .popover(isPresented: $showsEqualizer, arrowEdge: .bottom) { equalizerPopover }
                        if wide { volumeSlider }
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
            .playerPanel()
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
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 26, weight: .semibold))
                    .frame(width: 38, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.white.opacity(hoveringTransport ? 0.10 : 0))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringTransport = $0 }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .help(isPlaying ? "Pause (Space)" : "Play (Space)")
            control("forward.end.fill", "Next item") { onNext?() }.disabled(onNext == nil)
        }
    }

    private var volumeSlider: some View {
        PlayerSlider(value: volumeValue, maximum: 1, label: "Volume", isVolume: true)
            .frame(width: 88, height: 26)
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
            Divider()
            Button(action: onFullscreen) {
                Label("Toggle fullscreen", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Toggle(isOn: Binding(get: { isAlwaysOnTop }, set: { _ in onAlwaysOnTop() })) {
                Label("Always on top", systemImage: isAlwaysOnTop ? "pin.fill" : "pin")
            }
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
            if let onDeleteFile {
                Divider()
                Button("Stop & Delete File", role: .destructive, action: onDeleteFile)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var equalizerPopover: some View {
        VStack(alignment: .leading, spacing: PlayerChrome.eqSectionSpacing) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(PlayerChrome.accent.opacity(equalizer.isEnabled ? 0.20 : 0.10))
                    Image(systemName: "slider.vertical.3")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(equalizer.isEnabled ? PlayerChrome.accent : .white.opacity(0.55))
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Equalizer").font(.headline)
                    Text("7 bands · ±12 dB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Reset") { equalizer.resetGains() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(equalizer.gains.contains { $0 != 0 } ? 0.85 : 0.35))
                    .disabled(!equalizer.gains.contains { $0 != 0 })
                    .help("Reset every band to 0 dB")
                    .accessibilityLabel("Reset equalizer bands")
                Toggle(isOn: Binding(get: { equalizer.isEnabled }, set: { equalizer.isEnabled = $0 })) {
                    Text("On")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(PlayerChrome.accent)
                .accessibilityLabel("Enable equalizer")
                .accessibilityValue(equalizer.isEnabled ? "On" : "Off")
                .help("Enable equalizer")
            }
            Divider()
            HStack(alignment: .top, spacing: PlayerChrome.eqColumnSpacing) {
                ForEach(PlayerEqualizer.frequencies.indices, id: \.self) { index in
                    VStack(spacing: PlayerChrome.eqBandSpacing) {
                        gainLabel(equalizer.gains[index], isEnabled: equalizer.isEnabled)
                            .frame(height: PlayerChrome.eqValueHeight)
                        EqualizerBandSlider(
                            value: Binding(get: { equalizer.gains[index] }, set: { equalizer.setGain($0, at: index) }),
                            label: "\(PlayerEqualizer.frequencies[index]) gain in decibels",
                            enabled: equalizer.isEnabled
                        )
                        .frame(width: PlayerChrome.eqSliderWidth, height: PlayerChrome.eqSliderHeight)
                        Text(PlayerEqualizer.frequencies[index])
                            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.55))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(width: PlayerChrome.eqBandWidth)
                }
            }
            .frame(maxWidth: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Label("Floatplayer only; YouTube may ask for audio capture permission",
                      systemImage: "waveform")
                    .symbolRenderingMode(.monochrome)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = equalizer.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.monochrome)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: PlayerChrome.smallRadius))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(PlayerChrome.eqPadding)
        .frame(width: PlayerChrome.eqPopoverWidth)
        .background(PlayerChrome.panel)
    }

    private func gainLabel(_ value: Double, isEnabled: Bool) -> some View {
        let gain = Int(value.rounded())
        let color: Color = gain == 0
            ? .white.opacity(0.72)
            : (isEnabled ? PlayerChrome.accent : .white.opacity(0.58))
        return Text(gain == 0 ? "0" : String(format: "%+d", gain))
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(color)
            .accessibilityLabel(gain == 0 ? "0 decibels" : "\(gain) decibels")
    }

    private func control(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        PlayerChrome.iconButton(symbol, label, action: action)
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

private struct EqualizerBandSlider: NSViewRepresentable {
    @Binding var value: Double
    let label: String
    let enabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        slider.cell = EqualizerBandSliderCell()
        slider.isVertical = true
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.setAccessibilityLabel(label)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        slider.minValue = -12
        slider.maxValue = 12
        slider.doubleValue = value
        slider.isEnabled = enabled
        slider.isVertical = true
    }

    final class Coordinator: NSObject {
        var parent: EqualizerBandSlider

        init(_ parent: EqualizerBandSlider) { self.parent = parent }

        @objc func changed(_ sender: NSSlider) {
            parent.value = sender.doubleValue
        }
    }
}

private final class EqualizerBandSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        guard let bounds = controlView?.bounds else { return }
        let track = NSRect(x: bounds.midX - PlayerChrome.eqTrackWidth / 2,
                           y: bounds.minY + PlayerChrome.eqTrackInset,
                           width: PlayerChrome.eqTrackWidth,
                           height: max(0, bounds.height - PlayerChrome.eqTrackInset * 2))
        NSColor.white.withAlphaComponent(isEnabled ? PlayerChrome.eqTrackOpacity : PlayerChrome.eqDisabledTrackOpacity).setFill()
        NSBezierPath(roundedRect: track, xRadius: PlayerChrome.eqTrackRadius, yRadius: PlayerChrome.eqTrackRadius).fill()

        let fraction = maxValue > minValue ? (doubleValue - minValue) / (maxValue - minValue) : 0.5
        let zeroY = track.minY + track.height / 2
        let valueY = track.minY + track.height * CGFloat(flipped ? 1 - fraction : fraction)
        let fill = NSRect(x: track.minX, y: min(zeroY, valueY), width: track.width, height: max(1, abs(valueY - zeroY)))
        NSColor(PlayerChrome.accent).withAlphaComponent(isEnabled ? PlayerChrome.eqAccentOpacity : PlayerChrome.eqDisabledAccentOpacity).setFill()
        fill.fill()

        let ticks = NSBezierPath()
        for tick in 0...PlayerChrome.eqTickCount where tick != PlayerChrome.eqTickCount / 2 {
            let y = track.minY + track.height * CGFloat(tick) / CGFloat(PlayerChrome.eqTickCount)
            ticks.move(to: NSPoint(x: bounds.midX - PlayerChrome.eqTickOuterOffset, y: y))
            ticks.line(to: NSPoint(x: bounds.midX - PlayerChrome.eqTickInnerOffset, y: y))
            ticks.move(to: NSPoint(x: bounds.midX + PlayerChrome.eqTickInnerOffset, y: y))
            ticks.line(to: NSPoint(x: bounds.midX + PlayerChrome.eqTickOuterOffset, y: y))
        }
        ticks.lineWidth = 1
        NSColor.white.withAlphaComponent(isEnabled ? PlayerChrome.eqTickOpacity : PlayerChrome.eqDisabledTickOpacity).setStroke()
        ticks.stroke()

        // A stronger centre tick marks the 0 dB baseline without adding another label row.
        let baselineY = track.minY + track.height / 2
        let zeroTick = NSBezierPath()
        zeroTick.move(to: NSPoint(x: bounds.midX - PlayerChrome.eqTickOuterOffset - 1, y: baselineY))
        zeroTick.line(to: NSPoint(x: bounds.midX - PlayerChrome.eqTickInnerOffset, y: baselineY))
        zeroTick.move(to: NSPoint(x: bounds.midX + PlayerChrome.eqTickInnerOffset, y: baselineY))
        zeroTick.line(to: NSPoint(x: bounds.midX + PlayerChrome.eqTickOuterOffset + 1, y: baselineY))
        zeroTick.lineWidth = 1.5
        NSColor.white.withAlphaComponent(isEnabled ? PlayerChrome.eqZeroTickOpacity : PlayerChrome.eqDisabledTickOpacity).setStroke()
        zeroTick.stroke()
    }

    override func drawKnob(_ knobRect: NSRect) {
        let bounds = controlView?.bounds ?? knobRect
        let knob = NSRect(x: bounds.midX - PlayerChrome.eqKnobWidth / 2,
                          y: knobRect.midY - PlayerChrome.eqKnobHeight / 2,
                          width: PlayerChrome.eqKnobWidth,
                          height: PlayerChrome.eqKnobHeight)
        PlayerChrome.eqKnobFill.withAlphaComponent(isEnabled ? 1 : PlayerChrome.eqKnobDisabledOpacity).setFill()
        NSBezierPath(roundedRect: knob, xRadius: 3.5, yRadius: 3.5).fill()
        NSColor.white.withAlphaComponent(isEnabled ? PlayerChrome.eqKnobStrokeOpacity : PlayerChrome.eqKnobDisabledStrokeOpacity).setStroke()
        NSBezierPath(roundedRect: knob, xRadius: 3.5, yRadius: 3.5).stroke()
        let grip = NSBezierPath()
        grip.move(to: NSPoint(x: knob.minX + PlayerChrome.eqTickInnerOffset, y: knob.midY))
        grip.line(to: NSPoint(x: knob.maxX - PlayerChrome.eqTickInnerOffset, y: knob.midY))
        NSColor(PlayerChrome.panel).withAlphaComponent(isEnabled ? 1 : PlayerChrome.eqKnobDisabledOpacity).setStroke()
        grip.stroke()
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
        let radius: CGFloat = isVolume ? 3 : 1.5
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
