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
    private var timePitch: AVAudioUnitTimePitch?

    // Decoder
    private var decoder: AudioDecoder?
    private var currentFormat: AudioFormatSpec?
    private let decoderLock = NSLock()

    // Playback state
    private var _isPlaying: Bool = false
    private var _volume: Float = 1.0
    private var _muted: Bool = false
    private var _playbackRate: Float = 1.0

    // Buffering system (PCM data)
    private var pcmChunks: [Data] = []
    private var totalBufferedBytes: Int = 0
    private let bufferLock = NSLock()
    
    private var chunksInNode = 0
    private var isPlaybackStarted = false

    // Dynamic max chunks based on playback rate
    // 30s buffer (30 / 0.4s per chunk = 75 chunks) to match official app behavior
    private var maxChunksInNode: Int {
        // Base of 75 chunks (~30s), scale up with playback rate
        return max(75, Int(75.0 * Double(_playbackRate)))
    }

    // Scheduling
    private var scheduleTimer: DispatchSourceTimer?

    // Configuration - Optimized for fast startup while maintaining stability
    private let scheduleChunkSeconds: Double = 0.4  // 400ms chunks
    private let initialBufferSeconds: Double = 1.0  // 1s initial buffer before start (reduced from 3.0s for faster startup)
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

    public var playbackRate: Float {
        audioThread.sync { _playbackRate }
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

    private func setupAudioSession(sampleRate: Double = 48000) {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            
            // .playback category with .longFormAudio policy
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            
            try session.setPreferredSampleRate(sampleRate)
            try session.setPreferredIOBufferDuration(0.01) // 10ms
            try session.setActive(true)
            print("[AudioPlayer] Audio session active (playback) @ \(session.sampleRate)Hz")
        } catch {
             print("[AudioPlayer] Audio session error: \(error)")
        }
        #endif
    }

    private func setupEngine(format: AudioFormatSpec) {
        guard engine == nil else { return }

        let newEngine = AVAudioEngine()
        let newPlayerNode = AVAudioPlayerNode()
        newPlayerNode.volume = _volume

        // Create time pitch node for playback rate control
        let newTimePitch = AVAudioUnitTimePitch()
        newTimePitch.rate = _playbackRate
        print("[AudioPlayer] Setting up engine with playback rate: \(_playbackRate)")

        newEngine.attach(newPlayerNode)
        newEngine.attach(newTimePitch)

        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(format.sampleRate),
            channels: AVAudioChannelCount(format.channels),
            interleaved: false
        )

        if let inputFormat = inputFormat {
            // Connect: playerNode -> timePitch -> mainMixerNode
            // Use our format throughout to ensure correct sample rate interpretation
            newEngine.connect(newPlayerNode, to: newTimePitch, format: inputFormat)
            newEngine.connect(newTimePitch, to: newEngine.mainMixerNode, format: inputFormat)
            print("[AudioPlayer] Audio chain connected: playerNode -> timePitch(rate=\(newTimePitch.rate)) -> mixer @ \(format.sampleRate)Hz")
        }

        // Prepare the engine to allocate resources before starting
        newEngine.prepare()

        engine = newEngine
        playerNode = newPlayerNode
        timePitch = newTimePitch
    }

    private func startEngine() {
        guard let engine = engine else { return }
        
        if !engine.isRunning {
            do {
                print("[AudioPlayer] Starting engine...")
                try engine.start()
                print("[AudioPlayer] Engine started")
            } catch {
                 print("[AudioPlayer] Engine start error: \(error)")
            }
        }
        
        if let playerNode = playerNode, !playerNode.isPlaying {
            playerNode.play()
            print("[AudioPlayer] PlayerNode started")
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
        timePitch = nil
        
        decoderLock.lock()
        decoder = nil
        decoderLock.unlock()
        
        currentFormat = nil
    }

    // MARK: - Public Interface

    public func start(format: AudioFormatSpec, codecHeader: Data?) throws {
        try audioThread.sync {
            // Always stop and reset - don't skip even if same format
            // Skipping caused stale buffer data issues on track changes
            stopInternal()

            let newDecoder = try AudioDecoderFactory.create(
                codec: format.codec,
                sampleRate: format.sampleRate,
                channels: format.channels,
                bitDepth: format.bitDepth,
                header: codecHeader
            )
            
            decoderLock.lock()
            decoder = newDecoder
            decoderLock.unlock()
            
            currentFormat = format

            setupAudioSession(sampleRate: Double(format.sampleRate))
            setupEngine(format: format)
            startEngine()
            startScheduleTimer()

            _isPlaying = true
        }
    }

    public func decode(_ data: Data) throws -> Data {
        // Decoding happens on the calling thread (usually Kit's message loop task)
        // Ensure only one decoder is used at a time (sequential message loop handles this)
        decoderLock.lock()
        guard let decoder = decoder else {
            decoderLock.unlock()
            throw AudioPlayerError.notStarted
        }
        decoderLock.unlock()
        
        // Note: We use the local reference which is safe to use outside lock
        // Assuming AudioDecoder implementations are thread-safe or only used sequentially
        // The decoder instance itself isn't shared/modified by other threads, just the property.
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

    public func setPlaybackRate(_ rate: Float) {
        audioThread.async { [weak self] in
            guard let self = self else { return }
            // AVAudioUnitTimePitch supports rates from 0.25 to 4.0
            let clamped = max(0.25, min(4.0, rate))
            print("[AudioPlayer] Setting playback rate from \(self._playbackRate) to \(clamped)")

            self._playbackRate = clamped
            if let timePitch = self.timePitch {
                timePitch.rate = clamped
                print("[AudioPlayer] TimePitch rate set to \(timePitch.rate)")
                print("[AudioPlayer] Buffer will now scale to \(1.0 * Double(clamped)) seconds of real-time audio")
            } else {
                print("[AudioPlayer] WARNING: timePitch is nil, rate will apply when engine starts")
            }

            // Trigger immediate buffer check to schedule more chunks if needed
            self.scheduleBufferedAudio()
        }
    }

    public func pause() {
        audioThread.async { [weak self] in
            guard let self = self else { return }
            self.playerNode?.pause()
            // Stop scheduling during pause to prevent buffer corruption on resume
            self.scheduleTimer?.cancel()
            self.scheduleTimer = nil

            // Reset playback started flag so resume will wait for fresh buffer
            bufferLock.lock()
            self.isPlaybackStarted = false
            bufferLock.unlock()
        }
    }

    public func resume() {
        audioThread.async { [weak self] in
            guard let self = self else { return }
            if let engine = self.engine, !engine.isRunning {
                self.startEngine()
            }
            self.playerNode?.play()
            // Restart scheduling when resuming
            self.startScheduleTimer()
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

        // Scale buffer requirement by playback rate
        // At 2.0x speed, we need 2x the buffer to maintain the same real-time duration
        let rateAdjustedBufferSeconds = initialBufferSeconds * Double(_playbackRate)
        let initialBufferBytes = Int(rateAdjustedBufferSeconds * Double(bytesPerSecond))

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
        guard bytesPerFrame > 0 else { return }
        let remainder = data.count % bytesPerFrame
        if remainder != 0 {
            print("[AudioPlayer] Warning: data size \(data.count) not aligned to frame boundary (\(bytesPerFrame) bytes/frame), \(remainder) bytes truncated")
        }
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
        // Safe conversion using intermediate array to avoid alignment issues
        let sampleCount = frameCount * channels
        var samples = [Int16](repeating: 0, count: sampleCount)
        _ = samples.withUnsafeMutableBytes { data.copyBytes(to: $0) }

        if channels == 2 {
            guard samples.count >= frameCount * 2 else { return }
            var leftInt16 = [Int16](repeating: 0, count: frameCount)
            var rightInt16 = [Int16](repeating: 0, count: frameCount)

            // Deinterleave manually (safer than striding on potentially unaligned memory)
            for i in 0..<frameCount {
                leftInt16[i] = samples[i * 2]
                rightInt16[i] = samples[i * 2 + 1]
            }

            var scale: Float = 1.0 / 32768.0
            vDSP_vflt16(leftInt16, 1, floatChannelData[0], 1, vDSP_Length(frameCount))
            vDSP_vflt16(rightInt16, 1, floatChannelData[1], 1, vDSP_Length(frameCount))
            vDSP_vsmul(floatChannelData[0], 1, &scale, floatChannelData[0], 1, vDSP_Length(frameCount))
            vDSP_vsmul(floatChannelData[1], 1, &scale, floatChannelData[1], 1, vDSP_Length(frameCount))
        } else {
            var scale: Float = 1.0 / 32768.0
            vDSP_vflt16(samples, 1, floatChannelData[0], 1, vDSP_Length(frameCount))
            vDSP_vsmul(floatChannelData[0], 1, &scale, floatChannelData[0], 1, vDSP_Length(frameCount))
        }
    }

    private func convertInt32ToFloat32(
        _ data: Data,
        into floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameCount: Int,
        channels: Int
    ) {
        // Safe conversion using intermediate array to avoid alignment issues
        let sampleCount = frameCount * channels
        var samples = [Int32](repeating: 0, count: sampleCount)
        _ = samples.withUnsafeMutableBytes { data.copyBytes(to: $0) }

        if channels == 2 {
            guard samples.count >= frameCount * 2 else { return }
            var leftInt32 = [Int32](repeating: 0, count: frameCount)
            var rightInt32 = [Int32](repeating: 0, count: frameCount)

            for i in 0..<frameCount {
                leftInt32[i] = samples[i * 2]
                rightInt32[i] = samples[i * 2 + 1]
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
            vDSP_vflt32(samples, 1, &floatBuffer, 1, vDSP_Length(frameCount))

            var scale: Float = 1.0 / Float(Int32.max)
            vDSP_vsmul(floatBuffer, 1, &scale, floatChannelData[0], 1, vDSP_Length(frameCount))
        }
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
        
        // We need to capture the decoder but we can't share it between old/new really
        // The decoder might have internal state.
        // For now, let's just attempt to restore it if possible, or recreate it.
        // Usually recreating is safer for media reset.
        
        teardownEngine()

        if wasPlaying, let format = savedFormat {
            do {
                // Re-create decoder
                let newDecoder = try AudioDecoderFactory.create(
                     codec: format.codec,
                     sampleRate: format.sampleRate,
                     channels: format.channels,
                     bitDepth: format.bitDepth,
                     header: nil // We might lose header here if we don't store it.
                     // TODO: Store codec header for resets
                )
                
                decoderLock.lock()
                decoder = newDecoder
                decoderLock.unlock()
                
                currentFormat = format
                setupEngine(format: format)
                startEngine()
                startScheduleTimer()
                _isPlaying = true
            } catch {
                print("[AudioPlayer] Failed to restore after media services reset: \(error)")
            }
        }
    }
}

public enum AudioPlayerError: Error {
    case notStarted
    case decodingFailed
    case bufferCreationFailed
    case unsupportedFormat
}
