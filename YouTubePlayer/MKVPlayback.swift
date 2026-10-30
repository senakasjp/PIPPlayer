import AppKit
import Combine
import CoreAudio
import AudioToolbox
import VLCKit

private enum PlayerEQBands {
    static let frequencies: [Float] = [63, 250, 500, 1_500, 3_000, 5_000, 8_000]
    static let labels = ["63 Hz", "250 Hz", "500 Hz", "1.5 kHz", "3 kHz", "5 kHz", "8 kHz"]
}

final class MKVVideoSurface: NSView {
    let videoView = VLCVideoView()
    var zoom = 1.0 { didSet { needsLayout = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        videoView.fillScreen = false
        addSubview(videoView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let factor = min(3, max(1, zoom))
        videoView.frame = bounds.insetBy(dx: -bounds.width * (factor - 1) / 2,
                                        dy: -bounds.height * (factor - 1) / 2)
    }
}

final class MKVPlayback: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    struct Snapshot {
        let sessionID: UUID
        let mediaID: String
        let time: Double
        let duration: Double
        let state: Int
    }

    let updates = PassthroughSubject<Snapshot, Never>()
    private(set) var snapshot: Snapshot?
    private(set) var sessionID = UUID()
    let surface = MKVVideoSurface(frame: .zero)
    private static let library = VLCLibrary(options: ["--no-play-and-pause"])
    private var player = VLCMediaPlayer(library: MKVPlayback.library)
    private var currentMedia: StreamingMedia?
    private var timer: Timer?
    private var mediaID: String?
    private var pendingStart: Double?
    private var finished = false
    private var equalizerEnabled = false
    private var equalizerGains = Array(repeating: 0.0, count: PlayerEQBands.frequencies.count)

    override init() {
        super.init()
        player.drawable = surface.videoView
    }

    func play(_ media: StreamingMedia, startTime: Double, volume: Double) {
        stop()
        player = VLCMediaPlayer(library: MKVPlayback.library)
        player.drawable = surface.videoView
        player.delegate = self
        currentMedia = media
        mediaID = media.mediaID
        pendingStart = startTime.isFinite ? max(0, startTime) : 0
        finished = false
        player.media = VLCMedia(url: media.playbackURL)
        applyEqualizer()
        setVolume(volume)
        player.play()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
    }

    func stop() {
        sessionID = UUID()
        timer?.invalidate()
        timer = nil
        mediaID = nil
        currentMedia = nil
        player.delegate = nil
        player.stop()
        player.media = nil
        snapshot = nil
        pendingStart = nil
    }

    func togglePlayPause() {
        if finished, let media = currentMedia {
            play(media, startTime: 0, volume: Double(player.audio?.volume ?? 100))
            return
        }
        if player.isPlaying { player.pause() } else { player.play() }
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite, player.isSeekable else { return }
        let milliseconds = min(Double(Int32.max), max(0, seconds * 1000))
        player.time = VLCTime(int: Int32(milliseconds))
    }

    func setVolume(_ value: Double) {
        guard value.isFinite else { return }
        player.audio?.volume = Int32(min(100, max(0, value)))
    }

    func setEqualizer(enabled: Bool, gains: [Double]) {
        equalizerEnabled = enabled
        equalizerGains = gains
        applyEqualizer()
    }

    private func applyEqualizer() {
        guard equalizerEnabled, equalizerGains.count == PlayerEQBands.frequencies.count else {
            player.equalizer = nil
            return
        }
        let equalizer = VLCAudioEqualizer()
        for (frequency, gain) in zip(PlayerEQBands.frequencies, equalizerGains) {
            guard let band = equalizer.bands.min(by: { abs($0.frequency - frequency) < abs($1.frequency - frequency) }) else { continue }
            band.amplification = Float(min(12, max(-12, gain)))
        }
        player.equalizer = equalizer
    }

    func mediaPlayerStateChanged(_ notification: Notification) {
        guard let sender = notification.object as? VLCMediaPlayer else { return }
        let state = sender.state
        if Thread.isMainThread {
            guard sender === player else { return }
            poll(state: state)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self, sender === self.player else { return }
                self.poll(state: state)
            }
        }
    }

    private func poll(state reportedState: VLCMediaPlayerState? = nil) {
        guard let mediaID, !finished else { return }
        var state: Int
        switch reportedState ?? player.state {
        case .playing: state = 1
        case .paused: state = 2
        case .ended: state = 0
        case .error: state = -1
        default: state = player.isPlaying ? 1 : 3
        }
        if let start = pendingStart, player.isSeekable, state == 1 {
            pendingStart = nil
            if start > 0 { seek(to: start) }
        }
        let time = max(0, Double(player.time.intValue) / 1000)
        let duration = max(0, Double(player.media?.length.intValue ?? 0) / 1000)
        if state == 0 && time == 0 && duration == 0 { state = -1 }
        if state == 0 || state == -1 {
            finished = true
            timer?.invalidate()
            timer = nil
        }
        let value = Snapshot(sessionID: sessionID, mediaID: mediaID, time: time, duration: duration, state: state)
        snapshot = value
        updates.send(value)
    }

    deinit {
        player.delegate = nil
        timer?.invalidate()
        player.stop()
        player.drawable = nil
    }
}

@MainActor
final class PlayerEqualizer: ObservableObject {
    static let frequencies = PlayerEQBands.labels
    private static let webKitBundleID = "com.apple.WebKit.GPU"
    private static let gainsKey = "playerEqualizerGains"

    @Published var isEnabled = false {
        didSet { apply() }
    }
    @Published private(set) var gains: [Double] {
        didSet {
            UserDefaults.standard.set(gains, forKey: Self.gainsKey)
            apply()
        }
    }
    @Published private(set) var errorMessage: String?
    var isRoutingWebAudio: Bool { webAudio != nil }

    private weak var vlcPlayback: MKVPlayback?
    private var usesVLC = false
    private var isPlaying = false
    private var volume = 1.0
    private var webAudio: AnyObject?

    init() {
        let stored = UserDefaults.standard.array(forKey: Self.gainsKey) as? [Double] ?? []
        if stored.count == PlayerEQBands.frequencies.count {
            gains = stored
        } else if stored.count == 6 {
            let migrated = [
                stored[0], stored[1], (stored[1] + stored[2]) / 2, stored[2],
                stored[3], (stored[3] + stored[4]) / 2, stored[4]
            ]
            gains = migrated
            UserDefaults.standard.set(migrated, forKey: Self.gainsKey)
        } else {
            gains = Array(repeating: 0, count: PlayerEQBands.frequencies.count)
        }
    }

    func setGain(_ value: Double, at index: Int) {
        guard gains.indices.contains(index), value.isFinite else { return }
        var updated = gains
        updated[index] = min(12, max(-12, value))
        gains = updated
    }

    /// Returns every band to 0 dB, keeping the enabled state as-is.
    func resetGains() {
        guard gains.contains(where: { $0 != 0 }) else { return }
        gains = Array(repeating: 0, count: PlayerEQBands.frequencies.count)
    }

    func updatePlayback(vlcPlayback: MKVPlayback, usesVLC: Bool, isPlaying: Bool, volume: Double) {
        self.vlcPlayback = vlcPlayback
        self.usesVLC = usesVLC
        self.isPlaying = isPlaying
        self.volume = volume
        if !isEnabled {
            stopWebAudio()
            vlcPlayback.setEqualizer(enabled: false, gains: gains)
            errorMessage = nil
        } else if usesVLC {
            stopWebAudio()
            vlcPlayback.setEqualizer(enabled: true, gains: gains)
            errorMessage = nil
        } else if isPlaying {
            vlcPlayback.setEqualizer(enabled: false, gains: gains)
            if #available(macOS 14.2, *) {
                do {
                    if webAudio == nil {
                        webAudio = try WebProcessEqualizer(gains: gains, volume: volume)
                    } else {
                        (webAudio as? WebProcessEqualizer)?.set(gains: gains, volume: volume)
                    }
                    errorMessage = nil
                } catch {
                    stopWebAudio()
                    errorMessage = error.localizedDescription
                }
            } else {
                errorMessage = "YouTube audio EQ requires macOS 14.2 or later."
            }
        } else {
            stopWebAudio()
            vlcPlayback.setEqualizer(enabled: false, gains: gains)
            errorMessage = nil
        }
    }

    func setVolume(_ value: Double) {
        volume = value
        if #available(macOS 14.2, *) {
            (webAudio as? WebProcessEqualizer)?.setVolume(value)
        }
    }

    private func apply() {
        guard let vlcPlayback else { return }
        updatePlayback(vlcPlayback: vlcPlayback, usesVLC: usesVLC, isPlaying: isPlaying, volume: volume)
    }

    private func stopWebAudio() {
        if #available(macOS 14.2, *) {
            (webAudio as? WebProcessEqualizer)?.stop()
        }
        webAudio = nil
    }
}

@available(macOS 14.2, *)
private final class WebProcessEqualizer {
    private let tapID: AudioObjectID
    private let aggregateID: AudioObjectID
    private let ioProcID: AudioDeviceIOProcID
    private let dsp: EqualizerDSP

    init(gains: [Double], volume: Double) throws {
        let processes = try Self.activeWebKitProcessIDs()
        guard processes.count == 1, let process = processes.first else {
            throw PlayerEqualizerError.ambiguousWebAudio
        }
        let (outputDeviceUID, _) = try Self.defaultOutputDevice()

        let description = CATapDescription(__processes: [NSNumber(value: process)], andDeviceUID: outputDeviceUID, withStream: 0)
        description.name = "Floatplayer Audio EQ"
        description.muteBehavior = .muted
        description.isPrivate = true

        var createdTapID = AudioObjectID(kAudioObjectUnknown)
        try Self.check(AudioHardwareCreateProcessTap(description, &createdTapID))
        tapID = createdTapID

        var createdAggregateID = AudioObjectID(kAudioObjectUnknown)
        var createdIOProcID: AudioDeviceIOProcID?
        do {
            let tapUID = try Self.tapUID(for: tapID)
            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Floatplayer EQ",
                kAudioAggregateDeviceUIDKey: "com.example.FloatPlayer.eq.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID]],
                kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true
                ]],
                kAudioAggregateDeviceTapAutoStartKey: true
            ]
            try Self.check(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &createdAggregateID))
            aggregateID = createdAggregateID

            let inputFormat = try Self.streamFormat(deviceID: createdAggregateID, scope: kAudioDevicePropertyScopeInput)
            let outputFormat = try Self.streamFormat(deviceID: createdAggregateID, scope: kAudioDevicePropertyScopeOutput)
            guard Self.supportsProcessing(inputFormat), Self.supportsProcessing(outputFormat),
                  inputFormat.mSampleRate == outputFormat.mSampleRate else {
                throw PlayerEqualizerError.unsupportedAudioFormat
            }

            let processor = EqualizerDSP(sampleRate: inputFormat.mSampleRate, gains: gains, volume: volume)
            dsp = processor
            let callbackQueue = DispatchQueue(label: "com.example.FloatPlayer.equalizer-audio", qos: .userInteractive)
            try Self.check(AudioDeviceCreateIOProcIDWithBlock(&createdIOProcID, createdAggregateID, callbackQueue) {
                _, inputData, _, outputData, _ in
                _ = processor.process(inputData, outputData)
            })
            guard let createdIOProcID else { throw PlayerEqualizerError.audioIOProcUnavailable }
            ioProcID = createdIOProcID
            try Self.check(AudioDeviceStart(createdAggregateID, createdIOProcID))
        } catch {
            if let createdIOProcID {
                AudioDeviceStop(createdAggregateID, createdIOProcID)
                AudioDeviceDestroyIOProcID(createdAggregateID, createdIOProcID)
            }
            if createdAggregateID != AudioObjectID(kAudioObjectUnknown) {
                AudioHardwareDestroyAggregateDevice(createdAggregateID)
            }
            AudioHardwareDestroyProcessTap(tapID)
            throw error
        }
    }

    func set(gains: [Double], volume: Double) {
        dsp.update(gains: gains, volume: volume)
    }

    func setVolume(_ value: Double) {
        dsp.updateVolume(value)
    }

    func stop() {
        AudioDeviceStop(aggregateID, ioProcID)
        AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        AudioHardwareDestroyAggregateDevice(aggregateID)
        AudioHardwareDestroyProcessTap(tapID)
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else { throw PlayerEqualizerError.audioStatus(status) }
    }

    private static func activeWebKitProcessIDs() throws -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var byteCount: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(system, &address, 0, nil, &byteCount))
        guard byteCount > 0 else { return [] }
        var processIDs = [AudioObjectID](repeating: 0, count: Int(byteCount) / MemoryLayout<AudioObjectID>.size)
        let status = processIDs.withUnsafeMutableBufferPointer { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else { return kAudio_ParamError }
            return AudioObjectGetPropertyData(system, &address, 0, nil, &byteCount, baseAddress)
        }
        try check(status)
        return try processIDs.filter {
            try bundleID(for: $0) == "com.apple.WebKit.GPU" && isRunningOutput($0)
        }
    }

    private static func bundleID(for processID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var byteCount = UInt32(MemoryLayout<CFString>.size)
        var value: CFString = "" as CFString
        try check(withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(processID, &address, 0, nil, &byteCount, $0)
        })
        return value as String
    }

    private static func isRunningOutput(_ processID: AudioObjectID) throws -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var byteCount = UInt32(MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        try check(withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(processID, &address, 0, nil, &byteCount, $0)
        })
        return value != 0
    }

    private static func tapUID(for tapID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyUID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var byteCount = UInt32(MemoryLayout<CFString>.size)
        var value: CFString = "" as CFString
        try check(withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &byteCount, $0)
        })
        return value as String
    }

    private static func defaultOutputDevice() throws -> (uid: String, id: AudioObjectID) {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var byteCount = UInt32(MemoryLayout<AudioObjectID>.size)
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        try check(withUnsafeMutablePointer(to: &deviceID) {
            AudioObjectGetPropertyData(system, &address, 0, nil, &byteCount, $0)
        })

        address.mSelector = kAudioDevicePropertyDeviceUID
        byteCount = UInt32(MemoryLayout<CFString>.size)
        var value: CFString = "" as CFString
        try check(withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &byteCount, $0)
        })
        return (value as String, deviceID)
    }

    private static func streamFormat(deviceID: AudioObjectID, scope: AudioObjectPropertyScope) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamFormat,
                                                 mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var byteCount = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var format = AudioStreamBasicDescription()
        try check(withUnsafeMutablePointer(to: &format) {
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &byteCount, $0)
        })
        return format
    }

    private static func supportsProcessing(_ format: AudioStreamBasicDescription) -> Bool {
        format.mFormatID == kAudioFormatLinearPCM &&
        format.mFormatFlags & kAudioFormatFlagIsFloat != 0 &&
        format.mFormatFlags & kAudioFormatFlagIsPacked != 0 &&
        format.mBitsPerChannel == 32 &&
        format.mChannelsPerFrame == 2 &&
        format.mSampleRate > 0
    }
}

private final class EqualizerDSP: @unchecked Sendable {
    private struct Coefficients {
        let b0: Float
        let b1: Float
        let b2: Float
        let a1: Float
        let a2: Float
    }

    private let lock = NSLock()
    private let sampleRate: Double
    private var coefficients: [Coefficients]
    private var delays = Array(repeating: Float.zero, count: PlayerEQBands.frequencies.count * 4)
    private var volume: Float

    init(sampleRate: Double, gains: [Double], volume: Double) {
        self.sampleRate = sampleRate
        coefficients = Self.makeCoefficients(sampleRate: sampleRate, gains: gains)
        self.volume = Float(min(1, max(0, volume)))
    }

    func update(gains: [Double], volume: Double) {
        let nextCoefficients = Self.makeCoefficients(sampleRate: sampleRate, gains: gains)
        lock.lock()
        coefficients = nextCoefficients
        self.volume = Float(min(1, max(0, volume)))
        lock.unlock()
    }

    func updateVolume(_ value: Double) {
        lock.lock()
        volume = Float(min(1, max(0, value)))
        lock.unlock()
    }

    func process(_ input: UnsafePointer<AudioBufferList>, _ output: UnsafeMutablePointer<AudioBufferList>) -> Bool {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        guard inputs.count == outputs.count else { return false }

        lock.lock()
        defer { lock.unlock() }

        var channelOffset = 0
        for index in inputs.indices {
            guard let source = inputs[index].mData?.assumingMemoryBound(to: Float.self),
                  let destination = outputs[index].mData?.assumingMemoryBound(to: Float.self),
                  inputs[index].mNumberChannels == outputs[index].mNumberChannels else { return false }
            let channels = Int(inputs[index].mNumberChannels)
            guard channels > 0, channelOffset + channels <= 2 else { return false }
            let sampleCount = Int(min(inputs[index].mDataByteSize, outputs[index].mDataByteSize) / UInt32(MemoryLayout<Float>.size))
            let frameCount = sampleCount / channels
            for frame in 0..<frameCount {
                for channel in 0..<channels {
                    let sampleIndex = frame * channels + channel
                    var sample = source[sampleIndex]
                    for (bandIndex, coefficient) in coefficients.enumerated() {
                        let stateIndex = bandIndex * 4 + (channelOffset + channel) * 2
                        let filtered = coefficient.b0 * sample + delays[stateIndex]
                        delays[stateIndex] = coefficient.b1 * sample - coefficient.a1 * filtered + delays[stateIndex + 1]
                        delays[stateIndex + 1] = coefficient.b2 * sample - coefficient.a2 * filtered
                        sample = filtered
                    }
                    destination[sampleIndex] = sample * volume
                }
            }
            channelOffset += channels
        }
        return true
    }

    private static func makeCoefficients(sampleRate: Double, gains: [Double]) -> [Coefficients] {
        PlayerEQBands.frequencies.enumerated().map { index, frequency in
            let gain = Float(gains.indices.contains(index) ? min(12, max(-12, gains[index])) : 0)
            let amplitude = pow(10, Double(gain) / 40)
            let omega = 2 * Double.pi * min(Double(frequency), sampleRate * 0.45) / sampleRate
            let alpha = sin(omega) / 2 // Q = 1
            let cosine = cos(omega)
            let a0 = 1 + alpha / amplitude
            return Coefficients(
                b0: Float((1 + alpha * amplitude) / a0),
                b1: Float((-2 * cosine) / a0),
                b2: Float((1 - alpha * amplitude) / a0),
                a1: Float((-2 * cosine) / a0),
                a2: Float((1 - alpha / amplitude) / a0)
            )
        }
    }
}

private enum PlayerEqualizerError: LocalizedError {
    case ambiguousWebAudio
    case audioIOProcUnavailable
    case unsupportedAudioFormat
    case audioStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .ambiguousWebAudio:
            return "Pause audio in other WebKit apps to use Floatplayer’s EQ."
        case .audioIOProcUnavailable:
            return "Floatplayer couldn’t open the system audio route for EQ."
        case .unsupportedAudioFormat:
            return "The selected audio output format is not supported by EQ."
        case .audioStatus(let status):
            return "Floatplayer couldn’t start audio EQ (Core Audio error \(status))."
        }
    }
}
