// ABOUTME: Main orchestrator for Sendspin protocol client
// ABOUTME: Manages WebSocket connection, message handling, clock sync, and audio playback

import Foundation
import Observation

/// Main Sendspin client
@Observable
@MainActor
public final class SendspinClient {
    // Configuration
    private let clientId: String
    private let name: String
    private let roles: Set<VersionedRole>
    private let playerConfig: PlayerConfiguration?
    private let accessToken: String?

    // State
    public private(set) var connectionState: ConnectionState = .disconnected
    private var playerState: PlayerStateValue = .synchronized
    private var isAutoStarting = false // Prevent multiple simultaneous auto-starts
    private var currentVolume: Float = 1.0
    private var currentMuted: Bool = false

    // Dependencies
    private var transport: WebSocketTransport?
    private var clockSync: ClockSynchronizer?
    private var audioPlayer: AudioPlayer?

    // Task management
    private var messageLoopTask: Task<Void, Never>?
    private var clockSyncTask: Task<Void, Never>?

    // Event stream
    private let eventsContinuation: AsyncStream<ClientEvent>.Continuation
    public let events: AsyncStream<ClientEvent>

    public init(
        clientId: String,
        name: String,
        roles: Set<VersionedRole>,
        playerConfig: PlayerConfiguration? = nil,
        accessToken: String? = nil
    ) {
        self.clientId = clientId
        self.name = name
        self.roles = roles
        self.playerConfig = playerConfig
        self.accessToken = accessToken

        (events, eventsContinuation) = AsyncStream.makeStream()

        // Validate configuration
        if roles.contains(.playerV1) {
            precondition(playerConfig != nil, "Player role requires playerConfig")
        }
    }

    deinit {
        eventsContinuation.finish()
    }

    /// Discover Sendspin servers on the local network
    /// - Parameter timeout: How long to search for servers (default: 3 seconds)
    /// - Returns: Array of discovered servers
    public nonisolated static func discoverServers(timeout: Duration = .seconds(3)) async -> [DiscoveredServer] {
        let discovery = ServerDiscovery()
        await discovery.startDiscovery()

        return await withTaskGroup(of: [DiscoveredServer].self) { group in
            var latestServers: [DiscoveredServer] = []

            // Collect servers for the timeout period
            group.addTask {
                var collected: [DiscoveredServer] = []
                for await discoveredServers in discovery.servers {
                    collected = discoveredServers
                }
                return collected
            }

            // Timeout task
            group.addTask {
                try? await Task.sleep(for: timeout)
                await discovery.stopDiscovery()
                return []
            }

            // Wait for all tasks and collect results
            for await result in group where !result.isEmpty {
                latestServers = result
            }

            return latestServers
        }
    }

    /// Connect to Sendspin server
    @MainActor
    public func connect(to url: URL) async throws {
        // Prevent multiple connections
        guard connectionState == .disconnected else {
            return
        }

        connectionState = .connecting
        // print("[SendspinKit] Connection state: connecting")

        // Create dependencies
        let transport = WebSocketTransport(url: url)
        let clockSync = ClockSynchronizer()

        self.transport = transport
        self.clockSync = clockSync

        // Create audio player if player role
        if roles.contains(.playerV1) {
            let audioPlayer = AudioPlayer()
            self.audioPlayer = audioPlayer
            currentVolume = audioPlayer.volume
            currentMuted = audioPlayer.muted
            // print("[SendspinKit] Player role initialized")
        }

        // Connect WebSocket
        // print("[SendspinKit] Connecting WebSocket to \(url)...")
        try await transport.connect()
        // print("[SendspinKit] WebSocket connected successfully")

        // Capture streams before detaching (they're nonisolated)
        let textStream = transport.textMessages
        let binaryStream = transport.binaryMessages

        // Start message loop (detached from MainActor)
        messageLoopTask = Task.detached { [weak self] in
            await self?.runMessageLoop(textStream: textStream, binaryStream: binaryStream)
        }

        // Authenticate if token is present, otherwise send hello directly
        if let token = accessToken {
            // print("[SendspinKit] Sending auth token...")
            let authMessage = AuthMessage(token: token, clientId: clientId)
            try await transport.send(authMessage)
            // print("[SendspinKit] Auth message sent successfully")
        } else {
            // print("[SendspinKit] No token, sending hello directly...")
            try await sendClientHello()
        }

        // Start timeout handler to detect if server doesn't respond with server/hello
        Task {
            try? await Task.sleep(for: .seconds(10))
            if await connectionState == .connecting {
                // print("[SendspinKit] ⚠️ Connection timeout - no server/hello received after 10 seconds")
                await MainActor.run {
                    connectionState = .error("Connection timeout: Server did not respond with server/hello")
                    eventsContinuation.yield(.error("Connection timeout: Server did not respond"))
                }
            }
        }
    }

    /// Perform initial clock synchronization
    /// Does multiple sync rounds to establish offset and drift before audio starts
    @MainActor
    private func performInitialSync() async throws {
        guard let transport = transport, let clockSync = clockSync else {
            throw SendspinClientError.notConnected
        }

        // Do 5 quick sync rounds to establish offset and drift
        for _ in 0 ..< 5 {
            let now = getCurrentMicroseconds()
            let payload = ClientTimePayload(clientTransmitted: now)
            let message = ClientTimeMessage(payload: payload)
            try await transport.send(message)
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Wait a bit more to ensure last responses are processed
        try? await Task.sleep(for: .milliseconds(200))
    }

    /// Disconnect from server
    @MainActor
    public func disconnect() async {
        // Cancel all tasks
        messageLoopTask?.cancel()
        clockSyncTask?.cancel()
        messageLoopTask = nil
        clockSyncTask = nil

        // Stop audio
        audioPlayer?.stop()

        // Disconnect transport
        await transport?.disconnect()

        // Clean up
        transport = nil
        clockSync = nil
        audioPlayer = nil

        // Reset player state
        playerState = .synchronized
        currentVolume = 1.0
        currentMuted = false

        connectionState = .disconnected
    }

    @MainActor
    private func sendClientHello() async throws {
        guard let transport = transport else {
            throw SendspinClientError.notConnected
        }

        // Build player support if player role
        var playerV1Support: PlayerSupport?
        if roles.contains(.playerV1), let playerConfig = playerConfig {
            playerV1Support = PlayerSupport(
                supportedFormats: playerConfig.supportedFormats,
                bufferCapacity: playerConfig.bufferCapacity,
                supportedCommands: [.volume, .mute]
            )
        }

        let payload = ClientHelloPayload(
            clientId: clientId,
            name: name,
            deviceInfo: DeviceInfo.current,
            version: 1,
            supportedRoles: Array(roles),
            playerV1Support: playerV1Support,
            metadataV1Support: roles.contains(.metadataV1) ? MetadataSupport() : nil,
            artworkV1Support: roles.contains(.artworkV1) ? ArtworkSupport() : nil,
            visualizerV1Support: roles.contains(.visualizerV1) ? VisualizerSupport() : nil
        )

        let message = ClientHelloMessage(payload: payload)
        try await transport.send(message)
    }

    private func sendClientState() async throws {
        guard let transport = transport else {
            throw SendspinClientError.notConnected
        }

        // Only send if we have player role
        guard roles.contains(.playerV1) else {
            return
        }

        // Convert volume from 0.0-1.0 to 0-100 (with rounding)
        let volumeInt = Int((currentVolume * 100).rounded())

        let playerStateObject = PlayerStateObject(
            state: playerState,
            volume: volumeInt,
            muted: currentMuted
        )

        let payload = ClientStatePayload(player: playerStateObject)
        let message = ClientStateMessage(payload: payload)

        try await transport.send(message)
    }

    private nonisolated func runMessageLoop(
        textStream: AsyncStream<String>,
        binaryStream: AsyncStream<Data>
    ) async {
        await withTaskGroup(of: Void.self) { group in
            // Text message handler
            group.addTask { [weak self] in
                guard let self = self else { return }
                for await text in textStream {
                    await self.handleTextMessage(text)
                }
            }

            // Binary message handler
            group.addTask { [weak self] in
                guard let self = self else { return }
                for await data in binaryStream {
                    await self.handleBinaryMessage(data)
                }
            }
        }
    }

    private nonisolated func runClockSync() async {
        guard let transport = await transport else {
            return
        }

        while !Task.isCancelled {
            do {
                let now = getCurrentMicroseconds()
                let payload = ClientTimePayload(clientTransmitted: now)
                let message = ClientTimeMessage(payload: payload)
                try await transport.send(message)
            } catch {
                break
            }

            try? await Task.sleep(for: .seconds(5))
        }
    }

    private nonisolated func handleTextMessage(_ text: String) async {
        let decoder = JSONDecoder()

        guard let data = text.data(using: .utf8) else {
            return
        }

        // Extract message type for logging
        var msgType = "unknown"
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = json["type"] as? String {
            msgType = type
            // fputs("[RX] \(msgType)\n", stderr)
        }

        // Try to decode message type
        if let message = try? decoder.decode(ServerHelloMessage.self, from: data), message.type == msgType {
            await handleServerHello(message)
        } else if let message = try? decoder.decode(AuthOKMessage.self, from: data), message.type == msgType {
            // print("[SendspinKit] Auth OK received, sending hello...")
            try? await sendClientHello()

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                if connectionState == .connecting {
                    // print("[SendspinKit] ⚠️ Server did not send server/hello")
                    // print("[SendspinKit] Treating connection as established (Music Assistant compatibility mode)")
                    connectionState = .connected
                    let info = ServerInfo(
                        serverId: "music-assistant",
                        name: "Music Assistant Sendspin",
                        version: 1
                    )
                    eventsContinuation.yield(.serverConnected(info))

                    try? await sendClientState()
                }
            }
        } else if let message = try? decoder.decode(ServerTimeMessage.self, from: data), message.type == msgType {
            await handleServerTime(message)
        } else if let message = try? decoder.decode(StreamStartMessage.self, from: data), message.type == msgType {
            await handleStreamStart(message)
        } else if let message = try? decoder.decode(StreamEndMessage.self, from: data), message.type == msgType {
            await handleStreamEnd(message)
        } else if let message = try? decoder.decode(StreamMetadataMessage.self, from: data), message.type == msgType {
            await handleStreamMetadata(message)
        } else if let message = try? decoder.decode(GroupUpdateMessage.self, from: data), message.type == msgType {
            await handleGroupUpdate(message)
        } else if let message = try? decoder.decode(SessionUpdateMessage.self, from: data), message.type == msgType {
            await handleSessionUpdate(message)
        } else if msgType == "server/command" {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let payload = json["payload"] as? [String: Any],
               let player = payload["player"] as? [String: Any],
               let command = player["command"] as? String {
                // print("[SendspinKit] Received server command: \(command)")

                if command == "volume", let volume = player["volume"] as? Int {
                    // print("[SendspinKit] Setting volume to \(volume)")
                    await setVolume(Float(volume) / 100.0)
                } else if command == "mute", let muted = player["muted"] as? Bool {
                    // print("[SendspinKit] Setting mute to \(muted)")
                    await setMute(muted)
                }
            }
        } else {
            // let preview = text.prefix(500)
            // fputs("[CLIENT] ❌ Failed to decode message type '\(msgType)': \(preview)\n", stderr)
        }
    }

    private nonisolated func handleBinaryMessage(_ data: Data) async {
        // print("[SendspinKit] 📦 Received binary message: \(data.count) bytes")

        guard let message = BinaryMessage(data: data) else {
            // print("[SendspinKit] ❌ Failed to parse binary message")
            return
        }

        // print("[SendspinKit] Binary message type: \(message.type), timestamp: \(message.timestamp)")

        switch message.type {
        case .audioChunk:
            await handleAudioChunk(message)

        case .artworkChannel0, .artworkChannel1, .artworkChannel2, .artworkChannel3:
            let channel = Int(message.type.rawValue - 8)
            eventsContinuation.yield(.artworkReceived(channel: channel, data: message.data))

        case .visualizerData:
            eventsContinuation.yield(.visualizerData(message.data))
        }
    }

    private func handleServerHello(_ message: ServerHelloMessage) async {
        // print("[SendspinKit] ✅ Received server/hello from \(message.payload.name)")
        connectionState = .connected

        let info = ServerInfo(
            serverId: message.payload.serverId,
            name: message.payload.name,
            version: message.payload.version
        )

        eventsContinuation.yield(.serverConnected(info))

        // Send initial client state after receiving server hello (required by spec)
        try? await sendClientState()

        // Now that handshake is complete, start clock synchronization
        // print("[SendspinKit] Starting initial clock sync...")
        try? await performInitialSync()

        // Start continuous clock sync loop
        // print("[SendspinKit] Starting continuous clock sync...")
        clockSyncTask = Task.detached { [weak self] in
            await self?.runClockSync()
        }
        // print("[SendspinKit] Connection fully established")
    }
    
    // ... (rest of methods)

    private func handleServerTime(_ message: ServerTimeMessage) async {
        guard let clockSync = clockSync else {
            return
        }

        let now = getCurrentMicroseconds()

        await clockSync.processServerTime(
            clientTransmitted: message.payload.clientTransmitted,
            serverReceived: message.payload.serverReceived,
            serverTransmitted: message.payload.serverTransmitted,
            clientReceived: now
        )
    }

    private func handleStreamEnd(_: StreamEndMessage) async {
        audioPlayer?.stop()
        playerState = .synchronized
        eventsContinuation.yield(.streamEnded)
    }

    private func handleGroupUpdate(_ message: GroupUpdateMessage) async {
        if let groupId = message.payload.groupId,
           let groupName = message.payload.groupName {
            let info = GroupInfo(
                groupId: groupId,
                groupName: groupName,
                playbackState: message.payload.playbackState
            )

            eventsContinuation.yield(.groupUpdated(info))
        }
    }

    private func handleStreamMetadata(_ message: StreamMetadataMessage) async {
        let metadata = TrackMetadata(
            title: message.payload.title,
            artist: message.payload.artist,
            album: message.payload.album,
            albumArtist: nil,
            track: nil,
            duration: nil,
            year: nil,
            artworkUrl: message.payload.artworkUrl
        )
        eventsContinuation.yield(.metadataReceived(metadata))
    }

    private func handleSessionUpdate(_ message: SessionUpdateMessage) async {
        if let sessionMetadata = message.payload.metadata {
            let metadata = TrackMetadata(
                title: sessionMetadata.title,
                artist: sessionMetadata.artist,
                album: sessionMetadata.album,
                albumArtist: sessionMetadata.albumArtist,
                track: sessionMetadata.track,
                duration: sessionMetadata.trackDuration,
                year: sessionMetadata.year,
                artworkUrl: sessionMetadata.artworkUrl
            )
            eventsContinuation.yield(.metadataReceived(metadata))
        }
    }

    private func handleStreamStart(_ message: StreamStartMessage) async {
        // print("[SendspinKit] 📡 Received stream/start message")

        guard let playerInfo = message.payload.player else {
            // print("[SendspinKit] ❌ No player info in stream/start")
            return
        }

        // print("[SendspinKit] Stream format: \(playerInfo.codec) \(playerInfo.sampleRate)Hz \(playerInfo.channels)ch \(playerInfo.bitDepth)bit")

        guard let audioPlayer = audioPlayer else {
            // print("[SendspinKit] ❌ No audio player available")
            return
        }

        // Parse codec
        guard let codec = AudioCodec(rawValue: playerInfo.codec) else {
            // print("[SendspinKit] ❌ Unsupported codec: \(playerInfo.codec)")
            connectionState = .error("Unsupported codec: \(playerInfo.codec)")
            playerState = .error
            try? await sendClientState()
            return
        }

        let format = AudioFormatSpec(
            codec: codec,
            channels: playerInfo.channels,
            sampleRate: playerInfo.sampleRate,
            bitDepth: playerInfo.bitDepth
        )

        // Decode codec header if present
        var codecHeader: Data?
        if let headerBase64 = playerInfo.codecHeader {
            codecHeader = Data(base64Encoded: headerBase64)
            // print("[SendspinKit] Codec header: \(codecHeader?.count ?? 0) bytes")
        }

        // Check if already playing to avoid duplicate events
        let wasPlaying = audioPlayer.isPlaying

        do {
            // print("[SendspinKit] 🚀 Starting audio player...")
            try audioPlayer.start(format: format, codecHeader: codecHeader)
            playerState = .synchronized

            if !wasPlaying {
                eventsContinuation.yield(.streamStarted(format))
            }
            try? await sendClientState()
            // print("[SendspinKit] ✅ Audio player started successfully")
        } catch {
            // print("[SendspinKit] ❌ Failed to start audio: \(error)")
            connectionState = .error("Failed to start audio: \(error.localizedDescription)")
            playerState = .error
            try? await sendClientState()
        }
    }

    private func handleAudioChunk(_ message: BinaryMessage) async {
        // print("[SendspinKit] 🎵 Received audio chunk: \(message.data.count) bytes, timestamp: \(message.timestamp)")

        guard let audioPlayer = audioPlayer else { return }

        // Ensure playback is started if receiving chunks
        let isPlaying = audioPlayer.isPlaying
        // print("[SendspinKit] Audio player isPlaying: \(isPlaying), isAutoStarting: \(isAutoStarting)")

        if !isPlaying && !isAutoStarting {
            isAutoStarting = true
            // print("[SendspinKit] Auto-starting because chunks received but not playing.")

            // Use highest priority format if we haven't received stream/start yet
            if let defaultFormat = playerConfig?.supportedFormats.first {
                do {
                    // print("[SendspinKit] 🚀 Auto-starting audio engine with format: \(defaultFormat)")
                    try audioPlayer.start(format: defaultFormat, codecHeader: nil)
                    playerState = .synchronized
                    eventsContinuation.yield(.streamStarted(defaultFormat))
                    try? await sendClientState()
                    // print("[SendspinKit] ✅ Audio engine started successfully")
                } catch {
                    // print("[SendspinKit] ❌ Failed to auto-start: \(error)")
                    isAutoStarting = false
                }
            } else {
                 // print("[SendspinKit] ❌ No default format available to auto-start")
            }
        }

        do {
            // Decode chunk
            let pcmData = try audioPlayer.decode(message.data)
            // print("[SendspinKit] ✅ Decoded \(pcmData.count) bytes of PCM data")

            // Pass directly to player for buffering and playback
            audioPlayer.playPCM(pcmData)
            // print("[SendspinKit] ✅ Queued PCM data for playback")
        } catch {
            // print("[SendspinKit] ❌ Failed to decode chunk: \(error)")
        }
    }

    // Process start time for relative clock (nonisolated for use in getCurrentMicroseconds)
    private nonisolated static let processStartTime = Date()

    private nonisolated func getCurrentMicroseconds() -> Int64 {
        let elapsed = Date().timeIntervalSince(SendspinClient.processStartTime)
        return Int64(elapsed * 1_000_000)
    }

    /// Set playback volume (0.0 to 1.0)
    @MainActor
    public func setVolume(_ volume: Float) async {
        guard let audioPlayer = audioPlayer else { return }

        let clampedVolume = max(0.0, min(1.0, volume))
        audioPlayer.setVolume(clampedVolume)
        currentVolume = audioPlayer.volume

        try? await sendClientState()
    }

    /// Set mute state
    @MainActor
    public func setMute(_ muted: Bool) async {
        guard let audioPlayer = audioPlayer else { return }

        audioPlayer.setMute(muted)
        currentMuted = audioPlayer.muted

        try? await sendClientState()
    }

    /// Pause playback
    @MainActor
    public func pausePlayback() async {
        audioPlayer?.pause()
        try? await sendClientState()
    }

    /// Resume playback
    @MainActor
    public func resumePlayback() async {
        audioPlayer?.resume()
        try? await sendClientState()
    }
    
    /// Get current audio playback time in seconds
    @MainActor
    public func getPlaybackTime() -> TimeInterval {
        return audioPlayer?.getCurrentTime() ?? 0
    }
}

public enum ClientEvent: Sendable {
    case serverConnected(ServerInfo)
    case streamStarted(AudioFormatSpec)
    case streamEnded
    case groupUpdated(GroupInfo)
    case metadataReceived(TrackMetadata)
    case artworkReceived(channel: Int, data: Data)
    case visualizerData(Data)
    case error(String)
}

public struct ServerInfo: Sendable {
    public let serverId: String
    public let name: String
    public let version: Int
}

public struct GroupInfo: Sendable {
    public let groupId: String
    public let groupName: String
    public let playbackState: String?
}

public struct TrackMetadata: Sendable {
    public let title: String?
    public let artist: String?
    public let album: String?
    public let albumArtist: String?
    public let track: Int?
    public let duration: Int? // Duration in seconds
    public let year: Int?
    public let artworkUrl: String?
}

public enum SendspinClientError: Error {
    case notConnected
    case unsupportedCodec(String)
    case audioSetupFailed
    case authenticationFailed
}
