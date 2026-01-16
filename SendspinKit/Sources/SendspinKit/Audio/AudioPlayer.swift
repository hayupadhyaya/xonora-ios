// ABOUTME: AVAudioEngine-based audio player with simple buffer scheduling
// ABOUTME: Replaces AudioQueue with modern AVAudioEngine for reliable playback

import AVFoundation
import Accelerate
import Foundation

/// Audio player using AVAudioEngine for playback
/// Thread-safe using dedicated DispatchQueue (AVAudioEngine is not Sendable)
public final class AudioPlayer: @unchecked Sendable {
    // Audio engine components (accessed only on audioThread)
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    // Decoder
    private var decoder: AudioDecoder?
    private var currentFormat: AudioFormatSpec?

    // Playback state
    private var _isPlaying: Bool = false
    private var _volume: Float = 1.0
    private var _muted: Bool = false

    // Buffering system (PCM data)
    private var pcmChunks: [Data] = []
    private var totalBufferedBytes: Int = 0
    private let bufferLock = NSLock()
    
    private var chunksInNode = 0
    private let maxChunksInNode = 12
    private var isPlaybackStarted = false

    // Scheduling
    private var scheduleTimer: DispatchSourceTimer?

    // Configuration - Optimized for stability and throughput
    private let scheduleChunkSeconds: Double = 0.4  // 400ms chunks
    private let initialBufferSeconds: Double = 1.0  // 1s initial buffer before start
    private let schedulerInterval: Double = 0.1     // 100ms check

    // Dedicated threads
    private let audioThread: DispatchQueue
    private let decodingQueue: DispatchQueue

    public var isPlaying: Bool {
        audioThread.sync { _isPlaying }
    }

    public var volume: Float {
        audioThread.sync { _volume }
    }

    public var muted: Bool {
        audioThread.sync { _muted }
    }

    public init() {
        audioThread = DispatchQueue(
            label: "com.sendspinkit.audiothread",
            qos: .userInteractive
        )
        decodingQueue = DispatchQueue(
            label: "com.sendspinkit.decoding",
            qos: .userInitiated
        )
        setupNotifications()
    }

    deinit {
        scheduleTimer?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupNotifications() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.audioThread.async {
                self?.handleInterruption(notification)
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.audioThread.async {
                self?.handleRouteChange(notification)
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.audioThread.async {
                self?.handleMediaServicesReset()
            }
        }
        #endif
    }

    private func setupAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            // Only set category if it changed to avoid overhead
            if session.category != .playback {
                try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            }
            try session.setPreferredIOBufferDuration(0.01) // 10ms
            try session.setActive(true)
        } catch {
            // print("[AudioPlayer] Audio session error: \(error)")
        }
        #endif
    }

    private func setupEngine(format: AudioFormatSpec) {
        guard engine == nil else { return }

        let newEngine = AVAudioEngine()
        let newPlayerNode = AVAudioPlayerNode()
        newPlayerNode.volume = _volume

        newEngine.attach(newPlayerNode)

        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(format.sampleRate),
            channels: AVAudioChannelCount(format.channels),
            interleaved: false
        )
        
        if let inputFormat = inputFormat {
            newEngine.connect(newPlayerNode, to: newEngine.mainMixerNode, format: inputFormat)
        }

        engine = newEngine
        playerNode = newPlayerNode
    }

    private func startEngine() {
        guard let engine = engine else { return }
        
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                // print("[AudioPlayer] Engine start error: \(error)")
            }
        }
        
        if let playerNode = playerNode, !playerNode.isPlaying {
            playerNode.play()
        }
    }

    private func stopEngine() {
        playerNode?.stop()
        engine?.stop()
    }

    private func teardownEngine() {
        stopEngine()
        engine = nil
        playerNode = nil
        decoder = nil
        currentFormat = nil
    }

    // MARK: - Public Interface

    public func start(format: AudioFormatSpec, codecHeader: Data?) throws {
        try audioThread.sync {
            if _isPlaying, currentFormat == format {
                return
            }

            stopInternal()

            decoder = try AudioDecoderFactory.create(
                codec: format.codec,
                sampleRate: format.sampleRate,
                channels: format.channels,
                bitDepth: format.bitDepth,
                header: codecHeader
            )
            currentFormat = format

            setupAudioSession()
            setupEngine(format: format)
            startEngine()
            startScheduleTimer()

            _isPlaying = true
        }
    }

    public func decode(_ data: Data) throws -> Data {
        // Decoding happens on the calling thread (usually Kit's message loop task)
        // Ensure only one decoder is used at a time (sequential message loop handles this)
        guard let decoder = decoder else {
            throw AudioPlayerError.notStarted
        }
        return try decoder.decode(data)
    }

    public func playPCM(_ pcmData: Data) {
        bufferLock.lock()
        pcmChunks.append(pcmData)
        totalBufferedBytes += pcmData.count
        bufferLock.unlock()
    }

    public func stop() {
        audioThread.async { [weak self] in
            self?.stopInternal()
        }
    }

    private func stopInternal() {
        scheduleTimer?.cancel()
        scheduleTimer = nil

        teardownEngine()

        bufferLock.lock()
        pcmChunks.removeAll(keepingCapacity: true)
        totalBufferedBytes = 0
        chunksInNode = 0
        isPlaybackStarted = false
        bufferLock.unlock()

        _isPlaying = false
        // Don't deactivate session here to avoid -50 errors on immediate restart
    }

    public func setVolume(_ volume: Float) {
        audioThread.async { [weak self] in
            guard let self = self else { return }
            let clamped = max(0.0, min(1.0, volume))
            self._volume = clamped
            self.playerNode?.volume = self._muted ? 0.0 : clamped
        }
    }

    public func setMute(_ muted: Bool) {
        audioThread.async { [weak self] in
            guard let self = self else { return }
            self._muted = muted
            self.playerNode?.volume = muted ? 0.0 : self._volume
        }
    }

    public func pause() {
        audioThread.async { [weak self] in
            self?.playerNode?.pause()
        }
    }

    public func resume() {
        audioThread.async { [weak self] in
            guard let self = self else { return }
            if let engine = self.engine, !engine.isRunning {
                self.startEngine()
            }
            self.playerNode?.play()
        }
    }
    
    public func getCurrentTime() -> TimeInterval {
        audioThread.sync {
            guard let node = playerNode,
                  let lastRenderTime = node.lastRenderTime,
                  let playerTime = node.playerTime(forNodeTime: lastRenderTime) else {
                return 0
            }
            return Double(playerTime.sampleTime) / playerTime.sampleRate
        }
    }

    // MARK: - Scheduling

    private func startScheduleTimer() {
        scheduleTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: audioThread)
        timer.schedule(deadline: .now() + 0.1, repeating: schedulerInterval)
        timer.setEventHandler { [weak self] in
            self?.scheduleBufferedAudio()
        }
        timer.resume()
        scheduleTimer = timer
    }

    private func scheduleBufferedAudio() {
        guard let format = currentFormat else { return }

        let effectiveBitDepth = self.effectiveBitDepth(for: format)
        let bytesPerFrame = format.channels * (effectiveBitDepth / 8)
        let bytesPerSecond = format.sampleRate * bytesPerFrame
        let chunkBytes = Int(scheduleChunkSeconds * Double(bytesPerSecond))
        let initialBufferBytes = Int(initialBufferSeconds * Double(bytesPerSecond))

        bufferLock.lock()

        // Wait for initial buffer
        if !isPlaybackStarted {
            if totalBufferedBytes >= initialBufferBytes {
                isPlaybackStarted = true
            } else {
                bufferLock.unlock()
                return
            }
        }

        // Schedule chunks
        while totalBufferedBytes >= chunkBytes && chunksInNode < maxChunksInNode {
            // Aggregate chunks into a single Data block for the requested chunk size
            var dataToSchedule = Data(capacity: chunkBytes)
            while dataToSchedule.count < chunkBytes && !pcmChunks.isEmpty {
                let first = pcmChunks.removeFirst()
                let needed = chunkBytes - dataToSchedule.count
                
                if first.count <= needed {
                    dataToSchedule.append(first)
                    totalBufferedBytes -= first.count
                } else {
                    // Split the chunk
                    dataToSchedule.append(first.prefix(needed))
                    let remaining = first.dropFirst(needed)
                    pcmChunks.insert(Data(remaining), at: 0)
                    totalBufferedBytes -= needed
                }
            }
            
            chunksInNode += 1
            bufferLock.unlock()

            scheduleChunk(dataToSchedule, format: format)

            bufferLock.lock()
        }

        bufferLock.unlock()
    }

    private func scheduleChunk(_ data: Data, format: AudioFormatSpec) {
        guard let playerNode = playerNode else { return }
        
        guard let bufferFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(format.sampleRate),
            channels: AVAudioChannelCount(format.channels),
            interleaved: false
        ) else {
            return
        }

        let effectiveBitDepth = self.effectiveBitDepth(for: format)
        let bytesPerFrame = format.channels * (effectiveBitDepth / 8)
        let frameCount = data.count / bytesPerFrame

        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: bufferFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let floatChannelData = buffer.floatChannelData else { return }

        if effectiveBitDepth == 16 {
            convertInt16ToFloat32(data, into: floatChannelData, frameCount: frameCount, channels: format.channels)
        } else {
            convertInt32ToFloat32(data, into: floatChannelData, frameCount: frameCount, channels: format.channels)
        }
        
        if let engine = engine, !engine.isRunning {
            startEngine()
        } else if !playerNode.isPlaying {
            playerNode.play()
        }

        playerNode.scheduleBuffer(buffer) { [weak self] in
            self?.bufferLock.lock()
            self?.chunksInNode = max(0, (self?.chunksInNode ?? 1) - 1)
            self?.bufferLock.unlock()
        }
    }

    private func effectiveBitDepth(for format: AudioFormatSpec) -> Int {
        switch format.codec {
        case .flac, .opus: return 32
        case .pcm: return format.bitDepth == 24 ? 32 : format.bitDepth
        }
    }

    private func convertInt16ToFloat32(
        _ data: Data,
        into floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameCount: Int,
        channels: Int
    ) {
        data.withUnsafeBytes { rawBuffer in
            guard let int16Ptr = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }

            if channels == 2 {
                var leftInt16 = [Int16](repeating: 0, count: frameCount)
                var rightInt16 = [Int16](repeating: 0, count: frameCount)

                for i in 0..<frameCount {
                    leftInt16[i] = int16Ptr[i * 2]
                    rightInt16[i] = int16Ptr[i * 2 + 1]
                }

                var scale: Float = 1.0 / 32768.0
                vDSP_vflt16(leftInt16, 1, floatChannelData[0], 1, vDSP_Length(frameCount))
                vDSP_vflt16(rightInt16, 1, floatChannelData[1], 1, vDSP_Length(frameCount))
                vDSP_vsmul(floatChannelData[0], 1, &scale, floatChannelData[0], 1, vDSP_Length(frameCount))
                vDSP_vsmul(floatChannelData[1], 1, &scale, floatChannelData[1], 1, vDSP_Length(frameCount))
            } else {
                var scale: Float = 1.0 / 32768.0
                vDSP_vflt16(int16Ptr, 1, floatChannelData[0], 1, vDSP_Length(frameCount))
                vDSP_vsmul(floatChannelData[0], 1, &scale, floatChannelData[0], 1, vDSP_Length(frameCount))
            }
        }
    }

    private func convertInt32ToFloat32(
        _ data: Data,
        into floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameCount: Int,
        channels: Int
    ) {
        data.withUnsafeBytes { rawBuffer in
            guard let int32Ptr = rawBuffer.bindMemory(to: Int32.self).baseAddress else { return }

            if channels == 2 {
                var leftInt32 = [Int32](repeating: 0, count: frameCount)
                var rightInt32 = [Int32](repeating: 0, count: frameCount)

                for i in 0..<frameCount {
                    leftInt32[i] = int32Ptr[i * 2]
                    rightInt32[i] = int32Ptr[i * 2 + 1]
                }

                var leftFloat = [Float](repeating: 0, count: frameCount)
                var rightFloat = [Float](repeating: 0, count: frameCount)

                vDSP_vflt32(leftInt32, 1, &leftFloat, 1, vDSP_Length(frameCount))
                vDSP_vflt32(rightInt32, 1, &rightFloat, 1, vDSP_Length(frameCount))

                var scale: Float = 1.0 / Float(Int32.max)
                vDSP_vsmul(leftFloat, 1, &scale, floatChannelData[0], 1, vDSP_Length(frameCount))
                vDSP_vsmul(rightFloat, 1, &scale, floatChannelData[1], 1, vDSP_Length(frameCount))
            } else {
                var floatBuffer = [Float](repeating: 0, count: frameCount)
                vDSP_vflt32(int32Ptr, 1, &floatBuffer, 1, vDSP_Length(frameCount))

                var scale: Float = 1.0 / Float(Int32.max)
                vDSP_vsmul(floatBuffer, 1, &scale, floatChannelData[0], 1, vDSP_Length(frameCount))
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        #if os(iOS)
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            playerNode?.pause()
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    do {
                        try AVAudioSession.sharedInstance().setActive(true)
                        if engine?.isRunning == false { try engine?.start() }
                        playerNode?.play()
                    } catch {}
                }
            }
        @unknown default: break
        }
        #endif
    }

    private func handleRouteChange(_ notification: Notification) {
        #if os(iOS)
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        if reason == .oldDeviceUnavailable {
            playerNode?.pause()
        }
        #endif
    }

    private func handleMediaServicesReset() {
        let wasPlaying = _isPlaying
        let savedFormat = currentFormat
        let savedDecoder = decoder

        teardownEngine()

        if wasPlaying, let format = savedFormat {
            decoder = savedDecoder
            currentFormat = savedFormat
            setupEngine(format: format)
            startEngine()
            startScheduleTimer()
            _isPlaying = true
        }
    }
}

public enum AudioPlayerError: Error {
    case notStarted
    case decodingFailed
    case bufferCreationFailed
    case unsupportedFormat
}
