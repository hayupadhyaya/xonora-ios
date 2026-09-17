import Foundation
import Combine
import SendspinKit
import UIKit
import AVFoundation

// Facade for SendspinKit to match the app's expectation
// Adapts the modern SendspinKit actor-based client to the app's ObservableObject requirements

@MainActor
class SendspinClient: ObservableObject {
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var isBuffering = false
    @Published var bufferProgress: Double = 0.0
    @Published var connectionError: String?
    @Published var playerName: String = {
        let base = UIDevice.current.name
        let suffix = UIDevice.current.identifierForVendor?.uuidString.suffix(4).uppercased() ?? "0000"
        return "\(base)-\(suffix)"
    }()
    @Published var clientId: String?

    private let playerNameKey = "SendspinPlayerName"
    private var lastHost: String?
    private var lastPort: UInt16?
    private var lastScheme: String?
    private var lastAccessToken: String?

    // Reconnection logic
    private var reconnectAttempts = 0
    private var userInitiatedDisconnect = false  // true only when user explicitly disconnects
    private var reconnectTask: Task<Void, Never>?

    // Health check
    private var healthCheckTask: Task<Void, Never>?
    private let healthCheckInterval: TimeInterval = 30.0 // Check every 30 seconds

    // Connection completion tracking
    private var connectionContinuation: CheckedContinuation<Void, Never>?
    private var continuationResumed = false

    // Internal client from SendspinKit
    private var client: SendspinKit.SendspinClient?
    private var eventTask: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?

    static let shared = SendspinClient()
    
    private init() {
        if let savedName = UserDefaults.standard.string(forKey: playerNameKey) {
            self.playerName = savedName
        }
        
        // Auto-reconnect on foreground if needed
        foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                guard self.lastHost != nil else { return }

                self.safeLog("[SendspinClient] App foregrounded, isConnected: \(self.isConnected), isConnecting: \(self.isConnecting)")

                if !self.isConnected && !self.isConnecting {
                    self.safeLog("[SendspinClient] Not connected - deferring reconnection to PlayerViewModel coordination")
                } else if self.isConnecting {
                    self.safeLog("[SendspinClient] Connection already in progress, skipping")
                } else {
                    self.safeLog("[SendspinClient] Connection appears healthy, no reconnect needed")
                }
            }
        }
    }
    
    func updatePlayerName(_ name: String) {
        self.playerName = name
        UserDefaults.standard.set(name, forKey: playerNameKey)

        if let host = lastHost, let port = lastPort, let scheme = lastScheme {
            Task {
                await connect(to: host, port: port, scheme: scheme, accessToken: lastAccessToken)
                // Give server a moment to process the re-registration before refreshing the player list
                try? await Task.sleep(for: .seconds(1))
                await XonoraClient.shared.fetchPlayers()
            }
        }
    }
    
    func connect(to host: String, port: UInt16 = 8927, scheme: String = "ws", accessToken: String? = nil, isReconnecting: Bool = false) async {
        // Prevent concurrent connection attempts
        guard !isConnecting else {
            self.safeLog("[SendspinClient] Already connecting, ignoring duplicate request")
            return
        }

        self.lastHost = host
        self.lastPort = port
        self.lastScheme = scheme
        self.lastAccessToken = accessToken
        self.isConnecting = true

        // Only reset reconnection state for fresh manual connections, not reconnection attempts
        if !isReconnecting {
            self.reconnectAttempts = 0
            self.reconnectTask?.cancel()
        }

        // Bug 4 Fix: Omit port if standard http/https ports (implying reverse proxy)
        // to avoid issues with some proxies that dislike :443 in Host header
        var urlString = ""
        if (scheme == "wss" && port == 443) || (scheme == "ws" && port == 80) {
            urlString = "\(scheme)://\(host)/sendspin"
        } else {
            urlString = "\(scheme)://\(host):\(port)/sendspin"
        }
        self.safeLog("[SendspinClient] Connecting to: \(urlString)")
        self.safeLog("[SendspinClient] Access token provided: \(accessToken != nil)")
        self.safeLog("[SendspinClient] Access token length: \(accessToken?.count ?? 0)")

        guard let url = URL(string: urlString) else {
            self.connectionError = "Invalid URL: \(urlString)"
            self.safeLog("[SendspinClient] ERROR: Invalid URL")
            self.isConnecting = false
            return
        }

        // Resume any pending continuation before starting a new connection
        // This prevents continuation leaks when connect() is called multiple times
        resumeContinuationIfNeeded(reason: "new connection requested")

        // First disconnect old client before creating new one
        eventTask?.cancel()
        await client?.disconnect()

        // Wait for the connection to complete (handshake to finish)
        await withCheckedContinuation { continuation in
            connectionContinuation = continuation
            continuationResumed = false
            createAndConnectClient(url: url, accessToken: accessToken)
        }

        // Connection attempt finished (success or failure)
        self.isConnecting = false
    }

    private func createAndConnectClient(url: URL, accessToken: String?) {
        // Create configuration for the client
        // Only advertise 48kHz support to force server-side resampling if needed
        let playerConfig = PlayerConfiguration(
            bufferCapacity: 32 * 1024 * 1024, // 32MB buffer (increased to 32MB for high speed playback stability)
            supportedFormats: [
                AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 48000, bitDepth: 16),
                AudioFormatSpec(codec: .flac, channels: 2, sampleRate: 48000, bitDepth: 16)
            ]
        )

        let clientName = self.playerName
        let clientId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        self.clientId = clientId

        self.safeLog("[SendspinClient] Client ID: \(clientId)")
        self.safeLog("[SendspinClient] Client Name: \(clientName)")

        let client = SendspinKit.SendspinClient(
            clientId: clientId,
            name: clientName,
            roles: [.playerV1],
            playerConfig: playerConfig,
            accessToken: accessToken
        )

        self.client = client
        self.safeLog("[SendspinClient] Client created and assigned, client is nil: \(self.client == nil)")

        // Start listening to events
        eventTask = Task {
            for await event in client.events {
                handleEvent(event)
            }
        }

        Task {
            do {
                self.safeLog("[SendspinClient] Starting connection...")
                try await client.connect(to: url)
                self.safeLog("[SendspinClient] Connection initiated successfully, client is nil: \(self.client == nil)")
            } catch {
                self.safeLog("[SendspinClient] Connection error: \(error)")
                self.connectionError = "Connection failed: \(error.localizedDescription)"
                self.isConnected = false

                // Resume continuation if still waiting (connection failed before handshake)
                self.resumeContinuationIfNeeded(reason: "connection threw error")

                self.attemptReconnect()
            }
        }
    }
    
    func disconnect() {
        disconnectInternal(keepConfig: false)
    }
    
    private func disconnectInternal(keepConfig: Bool) {
        reconnectTask?.cancel()
        healthCheckTask?.cancel()
        if !keepConfig {
            userInitiatedDisconnect = true
        }

        // Resume any pending continuation to prevent leaks
        resumeContinuationIfNeeded(reason: "disconnect")

        eventTask?.cancel()
        Task {
            await client?.disconnect()
            self.client = nil
            print("[SendspinClient] Client disconnected and set to nil")
        }
        isConnected = false
        isConnecting = false
        isBuffering = false
    }
    
    private func attemptReconnect() {
        guard let host = lastHost, let port = lastPort, let scheme = lastScheme else { return }
        guard !userInitiatedDisconnect else { return }

        reconnectAttempts += 1
        let delay = min(Double(reconnectAttempts) * 2.0, 60.0)  // cap at 60s, never give up
        self.safeLog("[SendspinClient] Reconnection attempt \(reconnectAttempts), delay: \(delay)s")

        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }

            self.safeLog("[SendspinClient] Attempting reconnection...")
            await self.connect(to: host, port: port, scheme: scheme, accessToken: self.lastAccessToken, isReconnecting: true)
        }
    }

    private func startHealthCheck() {
        healthCheckTask?.cancel()
        healthCheckTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(healthCheckInterval))

                guard !Task.isCancelled else { break }
                await performHealthCheck()
            }
        }
    }

    private func performHealthCheck() async {
        guard isConnected else { return }
        guard let client = client else {
            safeLog("[SendspinClient] Health check failed - client is nil")
            isConnected = false
            safeLog("[SendspinClient] State: \(connectionStateDescription)")
            // PlayerViewModel observes isConnected and will coordinate reconnection
            return
        }

        // Check if transport is actually connected
        let transportConnected = await client.isTransportConnected()
        if !transportConnected {
            safeLog("[SendspinClient] Health check failed - transport disconnected")
            isConnected = false
            safeLog("[SendspinClient] State: \(connectionStateDescription)")
            // PlayerViewModel observes isConnected and will coordinate reconnection
        }
    }
    
    private func handleEvent(_ event: ClientEvent) {
        safeLog("[SendspinClient] Event received: \(event)")
        switch event {
        case .serverConnected:
            safeLog("[SendspinClient] Server connected event received")
            self.isConnected = true
            self.safeLog("[SendspinClient] State: \(connectionStateDescription)")
            self.connectionError = nil
            self.reconnectAttempts = 0 // Reset on success

            // Start health monitoring
            self.startHealthCheck()

            // Resume the connection continuation now that handshake is complete
            resumeContinuationIfNeeded(reason: "player registered")

        case .streamStarted:
            // safeLog("[SendspinClient] Stream started: \(format)")
            self.isBuffering = true
            // Track buffering progress - estimate based on AudioPlayer's 1s initial buffer
            // This provides visual feedback while actual buffering occurs
            Task {
                for i in 1...10 {
                    try? await Task.sleep(for: .milliseconds(100)) // 100ms each = 1s total
                    self.bufferProgress = Double(i) / 10.0
                }
                self.isBuffering = false
            }

        case .streamEnded:
            // safeLog("[SendspinClient] Stream ended")
            self.isBuffering = false
            self.bufferProgress = 0.0

        case .error(let msg):
            // safeLog("[SendspinClient] Error: \(msg)")
            self.connectionError = msg

            // Resume continuation if still waiting (connection failed)
            resumeContinuationIfNeeded(reason: "connection error")

            // Update connection state - PlayerViewModel will coordinate reconnection with XonoraClient
            let wasConnected = self.isConnected
            self.isConnected = false

            if wasConnected {
                self.safeLog("[SendspinClient] Connection lost - deferring reconnection to PlayerViewModel coordination")
            } else {
                self.safeLog("[SendspinClient] Reconnection attempt failed - deferring to PlayerViewModel coordination")
            }
            self.safeLog("[SendspinClient] State: \(connectionStateDescription)")

        default:
            // safeLog("[SendspinClient] Unhandled event: \(event)")
            break
        }
    }

    private func resumeContinuationIfNeeded(reason: String) {
        guard !continuationResumed, let continuation = connectionContinuation else { return }
        continuationResumed = true
        connectionContinuation = nil
        safeLog("[SendspinClient] Resuming continuation: \(reason)")
        continuation.resume()
    }

    private func safeLog(_ message: String) {
        // Truncate extremely long messages to avoid system logging issues
        let logMessage = message.count > 1000 ? String(message.prefix(1000)) + "... (truncated)" : message
        print(logMessage)
    }
    
    // Playback controls (proxied to client if supported, or handled via server commands)
    // Note: Sendspin is a passive player. "Resume" usually means "Unmute" or "Start Engine" locally.
    // The Kit handles the engine automatically on stream start.
    
    func pausePlayback() {
        Task {
            await client?.pausePlayback()
        }
    }
    
    func resumePlayback() {
        Task {
            // Ensure we are connected before trying to resume
            if !isConnected {
                print("[SendspinClient] Disconnected during resume request, attempting reconnect...")
                reconnectIfNeeded()

                // Wait up to 5 seconds for connection
                for _ in 0..<50 {
                    guard !Task.isCancelled else { return }
                    if isConnected && client != nil { break }
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                }
            }

            // Capture client reference atomically with isConnected check
            guard let activeClient = client, isConnected else {
                print("[SendspinClient] Failed to reconnect, cannot resume playback")
                return
            }
            print("[SendspinClient] Resuming playback on client")
            await activeClient.resumePlayback()
        }
    }

    func setPlaybackRate(_ rate: Float) {
        print("[SendspinClient] setPlaybackRate called with rate: \(rate)")
        print("[SendspinClient] client is nil: \(client == nil)")
        if let client = client {
            print("[SendspinClient] Calling SendspinKit client setPlaybackRate")
            client.setPlaybackRate(rate)
            print("[SendspinClient] setPlaybackRate call completed")
        } else {
            print("[SendspinClient] ERROR: client is nil, cannot set playback rate")
        }
    }

    func stopPlayback() {
        Task {
            await client?.stopPlayback()
        }
        isBuffering = false
        bufferProgress = 0.0
    }
    
    func getPlaybackTime() async -> TimeInterval {
        return client?.getPlaybackTime() ?? 0
    }

    func getPlaybackTimeSync() -> TimeInterval {
        return client?.getPlaybackTime() ?? 0
    }

    func reconnectIfNeeded() {
        guard !isConnected else { return }
        if lastHost != nil {
            userInitiatedDisconnect = false
            reconnectAttempts = 0
            attemptReconnect()
        }
    }

    var connectionStateDescription: String {
        if isConnected {
            return "Connected"
        } else if reconnectAttempts > 0 {
            return "Reconnecting (attempt \(reconnectAttempts))..."
        } else {
            return "Disconnected"
        }
    }
}
