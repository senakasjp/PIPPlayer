import SwiftUI

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
    var videoZoom: Binding<Double>? = nil

    @State private var showsOptions = false

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
            let wide = geometry.size.width >= (videoZoom == nil ? 600 : 700)
            HStack(spacing: 8) {
                if wide { queueNavigation }
                Button(action: onToggle) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 32, height: 32)
                        .background(.white, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
                .help(isPlaying ? "Pause" : "Play")
                if geometry.size.width >= 360 { timeLabel(safeTime) }
                Slider(value: seekValue, in: 0...max(safeDuration, 1), onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing { onSeek() }
                })
                .frame(minWidth: 0, maxWidth: .infinity)
                .disabled(safeDuration <= 0)
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(formattedTime(safeTime)) of \(formattedTime(safeDuration))")
                .help("Seek through the video")
                if wide {
                    timeLabel(safeDuration)
                    separator
                    volumeSlider
                }
                if !wide || videoZoom != nil {
                    control("slider.horizontal.3", "Playback options") { showsOptions.toggle() }
                        .popover(isPresented: $showsOptions, arrowEdge: .bottom) { options }
                }
                separator
                control("list.bullet", "Playlist", action: onPlaylist)
            }
            .padding(.horizontal, 12)
            .frame(width: geometry.size.width, height: 56)
            .background(.black.opacity(0.70))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
        .frame(height: 56)
        .foregroundStyle(.white)
        .tint(.white)
        .environment(\.colorScheme, .dark)
    }

    private var separator: some View {
        Rectangle().fill(.white.opacity(0.16)).frame(width: 1, height: 18)
            .accessibilityHidden(true)
    }

    private var queueNavigation: some View {
        HStack(spacing: 4) {
            control("backward.end.fill", "Previous item") { onPrevious?() }.disabled(onPrevious == nil)
            control("forward.end.fill", "Next item") { onNext?() }.disabled(onNext == nil)
        }
    }

    private var volumeSlider: some View {
        HStack(spacing: 4) {
            Image(systemName: volume <= 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 13)).accessibilityHidden(true)
            Slider(value: volumeValue, in: 0...1)
                .frame(width: 96)
                .accessibilityLabel("Volume")
                .accessibilityValue("\(Int(volumeValue.wrappedValue * 100)) percent")
                .help("Adjust volume")
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Playback").font(.headline)
                Spacer()
                Text("\(formattedTime(safeTime)) / \(formattedTime(safeDuration))")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack {
                Text("Volume")
                Spacer()
                volumeSlider
            }
            HStack {
                Text("Playlist")
                Spacer()
                queueNavigation
            }
            if let videoZoom {
                Divider()
                HStack {
                    Text("Video zoom")
                    Spacer()
                    Text("\(Int(videoZoom.wrappedValue * 100))%")
                        .monospacedDigit()
                }
                Slider(value: videoZoom, in: 1...3, step: 0.05)
                    .accessibilityLabel("Video zoom")
                    .accessibilityValue("\(Int(videoZoom.wrappedValue * 100)) percent")
                Button("Reset to 100%") { videoZoom.wrappedValue = 1 }
                    .disabled(videoZoom.wrappedValue == 1)
            }
        }
        .padding(16)
        .frame(width: 220)
        .foregroundStyle(.white)
        .tint(.white)
    }

    private func control(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .help(label)
    }

    private func timeLabel(_ time: Double) -> some View {
        Text(formattedTime(time))
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.white.opacity(0.75))
            .fixedSize()
    }

    private func formattedTime(_ time: Double) -> String {
        let seconds = Int(min(max(time, 0), 359_999))
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
