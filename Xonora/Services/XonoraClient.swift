import Foundation
import Combine
import UIKit
import Network

// MARK: - Network Path Monitor

/// Monitors network path changes (WiFi/Cellular transitions, connectivity loss/restoration)
@MainActor
final class NetworkPathMonitor: ObservableObject {
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var status: NWPath.Status = .unsatisfied

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.xonora.network-monitor", qos: .userInitiated)
    private var lastStatus: NWPath.Status?

    init() {
        setupMonitoring()
    }

    private func setupMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.updatePath(path)
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    private func updatePath(_ path: NWPath) {
        let oldStatus = self.status
        self.status = path.status
        self.isConnected = path.status == .satisfied

        // Log significant status changes
        if oldStatus != path.status {
            print("[NetworkMonitor] Path status changed: \(oldStatus.description) → \(path.status.description)")

            // Notify about connectivity restoration (may need reconnection)
            if oldStatus != .satisfied && path.status == .satisfied {
                print("[NetworkMonitor] Network restored - services should reconnect")
                NotificationCenter.default.post(name: NSNotification.Name("NetworkPathRestored"), object: nil)
            } else if oldStatus == .satisfied && path.status != .satisfied {
                print("[NetworkMonitor] Network lost")
            }
        }
    }

    deinit {
        pathMonitor.cancel()
    }
}

// MARK: - NWPath.Status Description Helper

extension NWPath.Status: CustomStringConvertible {
    public var description: String {
        switch self {
        case .satisfied:
            return "satisfied"
        case .unsatisfied:
            return "unsatisfied"
        case .requiresConnection:
            return "requiresConnection"
        @unknown default:
            return "unknown"
        }
    }
}

// MARK: - Auth Mode & Connection State

enum AuthMode: String {
    case credentials
    case token
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case authenticating
    case connected
    case error(String)
}

@MainActor
class XonoraClient: NSObject, ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var players: [MAPlayer] = []
    @Published var userSelectedPlayer: Bool = false
    @Published var currentPlayer: MAPlayer? {
        didSet {
            // Bug 9 Fix: Suppress side effects (like clearing playback state) if this is a silent update
            guard !suppressPlayerChangeSideEffects else { return }

            // REMOVED: Don't auto-save preferred player from didSet.
            // preferredPlayerId is only set explicitly via setPreferredPlayer().
            // Auto-selections must not persist as user preferences.

            // Notify PlayerManager that the player changed
            // This clears Now Playing state to avoid confusion when switching between players
            PlayerManager.shared.handlePlayerChanged(to: currentPlayer, from: oldValue)

            // Post playerChanged notification for UI (like toast)
            if let player = currentPlayer, oldValue?.playerId != player.playerId {
                NotificationCenter.default.post(
                    name: .playerChanged,
                    object: nil,
                    userInfo: [
                        "playerName": player.name,
                        "provider": player.provider
                    ]
                )
            }
        }
    }

    /// Explicitly set the preferred player (called when user manually selects a player)
    func setPreferredPlayer(_ player: MAPlayer) {
        preferredPlayerId = player.playerId
        userSelectedPlayer = true
        currentPlayer = player
    }
    @Published var requiresAuth: Bool = false
    @Published var serverInfo: ServerInfo?
    @Published var currentUser: UserInfo?
    @Published var providers: [ProviderInstance] = []

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var serverURL: URL?
    private var pendingCallbacks: [String: (Result<Data, Error>) -> Void] = [:]
    private var consumedMessageIds: Set<String> = [] // Track message IDs that have already been processed to prevent double-resume
    var reconnectAttempts = 0
    private let maxReconnectAttempts = 20 // Bug 8 Fix: Increased from 5 to 20
    private var accessToken: String?
    private var sessionToken: String?
    private var authMode: AuthMode = .credentials
    private var username: String?
    private var password: String?
    var onSessionTokenReceived: ((String) -> Void)?
    private let authMessageId = "auth-handshake"
    private var pingTask: Task<Void, Never>? // Bug 8 Fix: Task instead of Timer
    private var suppressPlayerChangeSideEffects = false // Bug 9 Fix
    private var connectionTimeoutTask: Task<Void, Never>?
    private let connectionTimeout: TimeInterval = 5.0
    private var userInitiatedDisconnect = false // Track manual disconnections to prevent auto-reconnect

    /// Public accessor to check if disconnect was user-initiated
    var wasUserInitiatedDisconnect: Bool {
        return userInitiatedDisconnect
    }

    // Player preference storage
    private let preferredPlayerIdKey = "XonoraPreferredPlayerId"
    private var preferredPlayerId: String? {
        get { UserDefaults.standard.string(forKey: preferredPlayerIdKey) }
        set {
            if let newValue = newValue {
                UserDefaults.standard.set(newValue, forKey: preferredPlayerIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: preferredPlayerIdKey)
            }
        }
    }

    // Debouncing for fetchPlayers() to prevent race conditions
    private var fetchPlayersTask: Task<Void, Never>?
    private var lastFetchPlayersTime: Date?
    private let fetchPlayersDebounceInterval: TimeInterval = 0.5

    // Network path monitoring for zombie connection detection
    private let networkMonitor = NetworkPathMonitor()

    static let shared = XonoraClient()

    override init() {
        super.init()
        // Use default configuration instead of ephemeral to support background audio
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 86400 
        config.timeoutIntervalForResource = 604800 
        config.connectionProxyDictionary = [:]
        config.waitsForConnectivity = true
        // Allow connections to remain open during background audio playback
        config.sessionSendsLaunchEvents = true
        self.urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: .init())

        #if os(iOS)
        // Monitor network path restoration to reconnect if zombie connection detected
        NotificationCenter.default.addObserver(forName: NSNotification.Name("NetworkPathRestored"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.debugLog("[XonoraClient] Network path restored, checking connection health...")

                // Don't reconnect if user manually disconnected
                guard !self.userInitiatedDisconnect else { return }
                guard self.serverURL != nil else { return }

                // If connected, send ping to verify socket is alive (not zombie)
                if case .connected = self.connectionState {
                    self.debugLog("[XonoraClient] Already connected, sending ping to verify socket health...")
                    self.sendPing()
                } else if case .disconnected = self.connectionState {
                    // Network restored but we're not connected yet, trigger reconnection
                    self.debugLog("[XonoraClient] Network restored and disconnected, triggering reconnect...")
                    self.reconnectAttempts = 0
                    self.reconnect()
                }
            }
        }

        // Monitor app backgrounding to prepare WebSocket for suspension
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.debugLog("[XonoraClient] App entering background, preparing for suspension...")
                // Don't disconnect, but stop ping timer to reduce background activity
                // iOS will suspend the socket but we'll reconnect on foreground
            }
        }

        // Monitor app foregrounding to force reconnection or liveliness check
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.debugLog("[XonoraClient] App entering foreground, checking connection...")

                // Don't auto-reconnect if user manually disconnected
                guard !self.userInitiatedDisconnect else {
                    self.debugLog("[XonoraClient] Skipping foreground reconnect: user manually disconnected")
                    return
                }

                guard self.serverURL != nil else { return }

                switch self.connectionState {
                case .connected:
                    // Send ping to verify socket is alive - if it fails, reconnect will be triggered
                    self.sendPing()
                    await self.fetchPlayers(isSilent: true)

                case .connecting, .authenticating:
                    // Give it a moment, then check if still stuck
                    try? await Task.sleep(for: .seconds(2))
                    if self.connectionState == .connecting || self.connectionState == .authenticating {
                        self.debugLog("[XonoraClient] Still in \(self.connectionState) state, forcing fresh connection...")
                        self.webSocketTask?.cancel(with: .goingAway, reason: nil)
                        self.connectionState = .disconnected
                        self.reconnectAttempts = 0
                        self.reconnect()
                    }

                case .disconnected, .error:
                    self.debugLog("[XonoraClient] Not connected, triggering reconnect...")
                    self.reconnectAttempts = 0
                    self.reconnect()
                }
            }
        }
        #endif
    }

    deinit {
        #if os(iOS)
        NotificationCenter.default.removeObserver(self)
        #endif
    }

    var baseURL: URL? {
        return serverURL
    }

    // MARK: - Connection Management

    func connect(to serverURLString: String, authMode: AuthMode = .credentials, username: String? = nil, password: String? = nil, accessToken: String? = nil, sessionToken: String? = nil) {
        switch connectionState {
        case .connected, .connecting, .authenticating:
            return
        default:
            break
        }

        guard let url = URL(string: serverURLString) else {
            connectionState = .error("Invalid server URL")
            return
        }

        self.serverURL = url
        self.authMode = authMode
        self.username = username
        self.password = password
        self.accessToken = accessToken
        self.sessionToken = sessionToken
        reconnectAttempts = 0
        userInitiatedDisconnect = false // User is manually connecting
        connectionState = .connecting
        
        var wsComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        wsComponents?.scheme = url.scheme == "https" ? "wss" : "ws"
        wsComponents?.path = "/ws"

        guard let wsURL = wsComponents?.url else {
            connectionState = .error("Failed to create WebSocket URL")
            return
        }

        var request = URLRequest(url: wsURL)
        if let scheme = url.scheme, let host = url.host {
            let portString = url.port.map { ":\($0)" } ?? ""
            let origin = "\(scheme)://\(host)\(portString)"
            request.addValue(origin, forHTTPHeaderField: "Origin")
        }

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        stopPingTimer()
        cancelConnectionTimeout()

        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()

        receiveMessage()
        startPingTimer()
        startConnectionTimeout()
    }

    private func startConnectionTimeout() {
        cancelConnectionTimeout()
        connectionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self = self, !Task.isCancelled else { return }
            if self.connectionState == .connecting {
                self.webSocketTask?.cancel(with: .goingAway, reason: nil)
                self.connectionState = .error("Connection timed out.")
            }
        }
    }

    private func cancelConnectionTimeout() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
    }

    func disconnect() {
        userInitiatedDisconnect = true // User manually disconnected - prevent auto-reconnect
        stopReconnecting()
        stopPingTimer()
        cancelConnectionTimeout()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
        serverInfo = nil
    }

    func stopReconnecting() {
        reconnectAttempts = maxReconnectAttempts
    }

    func resetReconnectionAttempts() {
        reconnectAttempts = 0
    }

    func reconnect() {
        guard !userInitiatedDisconnect, let serverURL = serverURL else {
            if !userInitiatedDisconnect {
                debugLog("[XonoraClient] Skipping auto-reconnect: no server URL configured")
            } else {
                debugLog("[XonoraClient] Skipping auto-reconnect: user manually disconnected")
            }
            return
        }

        reconnectAttempts += 1
        let delay = min(Double(reconnectAttempts) * 2, 60.0)  // cap at 60s, never give up

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.userInitiatedDisconnect else { return }
            self.connect(to: serverURL.absoluteString, authMode: self.authMode, username: self.username, password: self.password, accessToken: self.accessToken, sessionToken: self.sessionToken)
        }
    }

    // MARK: - WebSocket Communication

    private func startPingTimer() {
        stopPingTimer()
        // Bug 8 Fix: Use Task for background-reliable pinging
        pingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15 * 1_000_000_000) // 15 seconds
                guard !Task.isCancelled else { return }
                await self.sendPing()
            }
        }
    }

    private func stopPingTimer() {
        pingTask?.cancel()
        pingTask = nil
    }

    func sendPing() {
        // Only send ping if we're connected to avoid accessing unconnected socket
        guard connectionState == .connected, let task = webSocketTask else { return }

        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self = self, !Task.isCancelled, self.connectionState == .connected else { return }
            print("[XonoraClient] Ping timeout — no pong in 10s, forcing reconnect")
            self.connectionState = .error("Ping timeout")
            self.reconnect()
        }

        task.sendPing { [weak self] error in
            timeoutTask.cancel()   // pong received (or socket error) — cancel the timeout
            if let error {
                // Connection likely dropped, trigger reconnect
                Task { @MainActor in
                    guard let self = self else { return }
                    if self.connectionState == .connected && !self.userInitiatedDisconnect {
                        self.connectionState = .error("Connection lost: \(error.localizedDescription)")
                        self.reconnect()
                    }
                }
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text): self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) { self.handleMessage(text) }
                    @unknown default: break
                    }
                    self.receiveMessage()
                case .failure(let error):
                    self.stopPingTimer()
                    // Only set error state if not user-initiated disconnect
                    if !self.userInitiatedDisconnect {
                        self.connectionState = .error(error.localizedDescription)
                    }
                    self.reconnect()
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        Task { @MainActor in
            if let messageId = json["message_id"] as? String, messageId == authMessageId {
                if let errorStr = json["error"] as? String {
                    if self.sessionToken != nil && self.authMode == .credentials {
                        self.sessionToken = nil
                        Task { await self.authenticate() }
                        return
                    }
                    connectionState = .error(errorStr)
                    return
                }

                if let result = json["result"] as? [String: Any] {
                    if let token = result["session_token"] as? String ?? result["access_token"] as? String {
                        self.sessionToken = token
                        self.onSessionTokenReceived?(token)
                        connectionState = .connected
                        reconnectAttempts = 0
                        await fetchAuthInfo()
                        await fetchPlayers()
                    } else if (result["authenticated"] as? Bool == true) || (result["success"] as? Bool == true) {
                        connectionState = .connected
                        reconnectAttempts = 0
                        await fetchAuthInfo()
                        await fetchPlayers()
                    } else {
                        if self.sessionToken != nil && self.authMode == .credentials {
                            self.sessionToken = nil
                            Task { await self.authenticate() }
                        } else {
                            if let data = try? JSONSerialization.data(withJSONObject: json), let str = String(data: data, encoding: .utf8) {
                                connectionState = .error("Auth result failed: \(str)")
                            } else {
                                connectionState = .error("Authentication failed.")
                            }
                        }
                    }
                } else if json["result"] as? Bool == true {
                    connectionState = .connected
                    reconnectAttempts = 0
                    await fetchAuthInfo()
                    await fetchPlayers()
                } else {
                    if self.sessionToken != nil && self.authMode == .credentials {
                        self.sessionToken = nil
                        Task { await self.authenticate() }
                    } else {
                        if let errorStr = json["error"] as? String ?? json["error_message"] as? String {
                            connectionState = .error(errorStr)
                        } else if let errorCode = json["error_code"] as? Int {
                            connectionState = .error("Authentication error code: \(errorCode)")
                        } else if let data = try? JSONSerialization.data(withJSONObject: json), let str = String(data: data, encoding: .utf8) {
                            connectionState = .error("Auth payload rejected: \(str)")
                        } else {
                            connectionState = .error("Authentication failed.")
                        }
                    }
                }
                return
            }

            if let serverVersion = json["server_version"] as? String {
                cancelConnectionTimeout()
                serverInfo = ServerInfo(
                    serverVersion: serverVersion,
                    schemaVersion: json["schema_version"] as? Int ?? 0,
                    minSchemaVersion: json["min_supported_schema_version"] as? Int ?? 0,
                    serverID: json["server_id"] as? String ?? ""
                )

                if (serverInfo?.schemaVersion ?? 0) >= 28 {
                    if accessToken != nil {
                        connectionState = .authenticating
                        await authenticate()
                    } else {
                        connectionState = .error("Authentication required.")
                    }
                } else {
                    connectionState = .connected
                    reconnectAttempts = 0
                    await fetchAuthInfo()
                    await fetchPlayers()
                }
                return
            }

            if let messageId = json["message_id"] as? String,
               !consumedMessageIds.contains(messageId),
               let callback = pendingCallbacks.removeValue(forKey: messageId) {
                consumedMessageIds.insert(messageId)
                callback(.success(data))
            }

            if let event = json["event"] as? String {
                handleEvent(event, data: json)
            }

            if let errorCode = json["error_code"] as? Int, errorCode == 20 {
                requiresAuth = true
                if accessToken == nil {
                    connectionState = .error("Authentication required.")
                }
            }
        }
    }

    private func authenticate() async {
        let authPayload: [String: Any]
        
        if let st = sessionToken, !st.isEmpty {
            authPayload = [
                "message_id": authMessageId,
                "command": "auth",
                "args": ["token": st]
            ]
        } else if authMode == .credentials {
            guard let un = username, let pwd = password, !un.isEmpty else {
                connectionState = .error("Credentials missing.")
                return
            }
            authPayload = [
                "message_id": authMessageId,
                "command": "auth/login",
                "args": [
                    "username": un,
                    "password": pwd,
                    "provider_id": "builtin",
                    "device_name": UIDevice.current.name,
                    "extra_credentials": [String: Any]()
                ]
            ]
        } else {
            guard let token = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
                connectionState = .error("Access token missing.")
                return
            }
            authPayload = [
                "message_id": authMessageId,
                "command": "auth",
                "args": ["token": token]
            ]
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: authPayload)
            let text = String(data: data, encoding: .utf8) ?? ""
            webSocketTask?.send(.string(text)) { _ in }
        } catch {}
    }

    private func handleEvent(_ event: String, data: [String: Any]) {
        switch event {
        case "player_updated", "players_updated":
            Task { await fetchPlayers() }
        case "queue_updated":
            if let eventData = data["data"] as? [String: Any] {
                let queueId = eventData["queue_id"] as? String
                let currentQueueId = currentPlayer?.playerId

                // Always post for MultiDeviceManager (tracks all players)
                NotificationCenter.default.post(name: .allQueuesUpdated, object: nil, userInfo: eventData)

                // Only post current-player events for PlayerManager
                if queueId == nil || currentQueueId == nil || queueId == currentQueueId {
                    NotificationCenter.default.post(name: .queueUpdated, object: nil, userInfo: eventData)
                }
            }
        default: break
        }
    }

    private func sendCommand(_ command: String, args: [String: Any] = [:]) async throws -> Data {
        guard connectionState == .connected else {
            throw NSError(domain: "MusicAssistant", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }
        let messageId = UUID().uuidString
        let payload: [String: Any] = ["message_id": messageId, "command": command, "args": args]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                pendingCallbacks[messageId] = { result in
                    switch result {
                    case .success(let data): continuation.resume(returning: data)
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
            }

            webSocketTask?.send(.string(text)) { error in
                if let error = error {
                    Task { @MainActor in
                        // Mark as consumed before removing to prevent timeout handler from also processing
                        guard !self.consumedMessageIds.contains(messageId) else { return }
                        self.consumedMessageIds.insert(messageId)
                        if self.pendingCallbacks.removeValue(forKey: messageId) != nil {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                Task { @MainActor in
                    guard let self = self else { return }
                    // Only process timeout if not already consumed by response or error handler
                    guard !self.consumedMessageIds.contains(messageId) else { return }
                    self.consumedMessageIds.insert(messageId)
                    if let callback = self.pendingCallbacks.removeValue(forKey: messageId) {
                        callback(.failure(NSError(domain: "MusicAssistant", code: -1, userInfo: [NSLocalizedDescriptionKey: "Timeout"])))
                    }
                }
            }
        }
    }

    // MARK: - Player Management Utilities

    /// Clears the user's preferred player selection
    /// Useful if you want to reset to automatic player selection
    func clearPreferredPlayer() {
        preferredPlayerId = nil
    }

    /// Forces the current player to the local Sendspin player, ignoring stored preferences.
    /// Used by CarPlay to ensure audio routes to the phone/car, not a remote speaker.
    func switchToLocalPlayer() async {
        guard let localId = await SendspinClient.shared.clientId else { return }
        if let localPlayer = players.first(where: { $0.playerId == localId && $0.available }) {
            setPreferredPlayer(localPlayer)
        }
        // If local player isn't in the list yet, the CarPlay delegate's subscriber will catch it.
    }

    /// Checks if the given player is this device's local Sendspin player
    func isLocalSendspinPlayer(_ player: MAPlayer) async -> Bool {
        guard player.provider == "sendspin" else { return false }
        guard let localId = await SendspinClient.shared.clientId else { return false }
        return player.playerId == localId
    }

    /// Fetches queue state for a player and posts it through the notification pipeline.
    /// Used as a fallback when queue_updated WebSocket events are missed (e.g., remote players).
    private func fetchAndPostQueueState(for playerId: String) async throws {
        let data = try await sendCommand("player_queues/get", args: ["queue_id": playerId])
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let result = json?["result"] as? [String: Any] else { return }
        NotificationCenter.default.post(name: .queueUpdated, object: nil, userInfo: result)
    }

    // MARK: - API Methods

    func fetchPlayers(isSilent: Bool = false) async {
        // Debounce: cancel any pending fetch and schedule a new one
        fetchPlayersTask?.cancel()

        // Check if we should debounce based on last fetch time
        let now = Date()
        if let lastFetch = lastFetchPlayersTime,
           now.timeIntervalSince(lastFetch) < fetchPlayersDebounceInterval {
            // Schedule a debounced fetch
            fetchPlayersTask = Task {
                try? await Task.sleep(for: .milliseconds(Int(fetchPlayersDebounceInterval * 1000)))
                guard !Task.isCancelled else { return }
                await performFetchPlayers(isSilent: isSilent)
            }
        } else {
            // Execute immediately
            await performFetchPlayers(isSilent: isSilent)
        }
    }

    func fetchAuthInfo() async {
        do {
            let meData = try await sendCommand("auth/me")
            if let json = try JSONSerialization.jsonObject(with: meData) as? [String: Any],
               let result = json["result"] as? [String: Any] {
                let decoder = JSONDecoder()
                let data = try JSONSerialization.data(withJSONObject: result)
                self.currentUser = try decoder.decode(UserInfo.self, from: data)
            }
        } catch {
            print("[XonoraClient] Failed to fetch auth/me: \(error)")
        }

        do {
            let providersData = try await sendCommand("providers")
            if let json = try JSONSerialization.jsonObject(with: providersData) as? [String: Any],
               let result = json["result"] as? [[String: Any]] {
                let decoder = JSONDecoder()
                let data = try JSONSerialization.data(withJSONObject: result)
                self.providers = try decoder.decode([ProviderInstance].self, from: data)
            }
        } catch {
            print("[XonoraClient] Failed to fetch providers: \(error)")
        }
    }

    private func performFetchPlayers(isSilent: Bool) async {
        lastFetchPlayersTime = Date()

        do {
            let data = try await sendCommand("players/all")

            let players = await Task.detached(priority: .userInitiated) {
                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    guard let result = json?["result"] as? [[String: Any]] else { return [MAPlayer]() }
                    let playersData = try JSONSerialization.data(withJSONObject: result)
                    return try JSONDecoder().decode([MAPlayer].self, from: playersData)
                } catch {
                    return [MAPlayer]()
                }
            }.value

            self.players = players

            // Populate MultiDeviceManager with initial state
            for player in players {
                 let existingState = MultiDeviceManager.shared.state(for: player.playerId)
                
                // Determine playback state
                let pbState: PlaybackState
                switch player.state {
                case .playing: pbState = .playing
                case .paused: pbState = .paused
                default: pbState = .stopped
                }
                
                // If we have an existing playing state and the new fetch says playing, 
                // trust our local timer/events for time, don't overwrite with potentially stale snapshot
                var finalTime = player.currentMedia?.position ?? 0
                if let existing = existingState, existing.playbackState == .playing, pbState == .playing {
                     // Keep existing time if it seems reasonable (within same track)
                     if existing.currentTrack?.uri == player.currentMedia?.uri {
                         finalTime = existing.currentTime
                     }
                }

                // Create minimal track from currentMedia if available
                var track: Track? = nil
                if let media = player.currentMedia, let title = media.title {
                    let albumRef: AlbumReference? = media.album.map { 
                        AlbumReference(
                            itemId: "", 
                            provider: "", 
                            name: $0, 
                            metadata: media.imageUrl.map { MediaItemMetadata(images: [MediaItemImage(type: "thumb", path: $0, provider: "")]) }
                        ) 
                    }
                    
                    track = Track(
                        itemId: "", // Placeholder
                        provider: "",
                        name: title,
                        version: nil,
                        duration: media.duration,
                        trackNumber: nil,
                        discNumber: nil,
                        uri: media.uri ?? "",
                        artists: media.artist.map { [ArtistReference(itemId: nil, provider: nil, name: $0)] } ?? [],
                        album: albumRef,
                        metadata: media.imageUrl.map { MediaItemMetadata(images: [MediaItemImage(type: "thumb", path: $0, provider: "")]) },
                        providerMappings: nil,
                        image: nil
                    )
                }

                // Update manager directly
                let state = MultiDeviceManager.PlayerState(
                    currentTrack: track,
                    playbackState: pbState,
                    currentTime: finalTime,
                    duration: player.currentMedia?.duration ?? 0,
                    volume: player.volume ?? 0,
                    queueId: player.playerId
                )
                
                MultiDeviceManager.shared.updateState(for: player.playerId, state: state)
            }

            // Player selection logic - only run when needed
            // We only auto-select a player when:
            // 1. No player is currently selected (initial play) AND user hasn't manually selected
            // 2. Current player is no longer available
            // 3. Local player is available but a different player is selected

            let currentPlayerStillValid = currentPlayer != nil &&
                players.contains(where: { $0.playerId == currentPlayer?.playerId && $0.available })

            // Reset userSelectedPlayer flag if current player becomes unavailable
            if !currentPlayerStillValid && currentPlayer != nil {
                userSelectedPlayer = false
            }

            // Get local sendspin ID early for auto-switch logic
            let localSendspinId = await SendspinClient.shared.clientId

            // If current player is still valid, check if we should auto-switch to local player
            if currentPlayerStillValid {
                // AUTO-SWITCH LOGIC: Prefer local Sendspin player when appropriate
                // This ensures that when you open the app on device B, it uses device B's player,
                // even if device A's player was previously active on the server.

                if let localId = localSendspinId,
                   let localPlayer = players.first(where: { $0.playerId == localId && $0.available }),
                   currentPlayer?.playerId != localId {

                    // Check if user has explicitly preferred a different player
                    // Only keep non-local player if user explicitly selected it via setPreferredPlayer().
                    // No longer requires currentPlayer to match — eliminates race conditions
                    // where a data refresh temporarily changes currentPlayer between selection and check.
                    let hasExplicitNonLocalPreference = preferredPlayerId != nil &&
                                                        preferredPlayerId != localId

                    if !hasExplicitNonLocalPreference {
                        // Auto-switch to local player
                        print("[XonoraClient] Auto-switching from '\(currentPlayer?.name ?? "unknown")' to local player '\(localPlayer.name)'")

                        if isSilent {
                            suppressPlayerChangeSideEffects = true
                            currentPlayer = localPlayer
                            suppressPlayerChangeSideEffects = false
                        } else {
                            currentPlayer = localPlayer
                        }
                        return
                    } else {
                        print("[XonoraClient] Keeping user-preferred player '\(currentPlayer?.name ?? "unknown")' instead of local '\(localPlayer.name)'")
                    }
                }

                // Update the current player object with fresh data
                if let newSnapshot = players.first(where: { $0.playerId == currentPlayer?.playerId }) {
                    let oldMedia = currentPlayer?.currentMedia
                    if currentPlayer?.state != newSnapshot.state ||
                       currentPlayer?.volume != newSnapshot.volume ||
                       currentPlayer?.currentMedia?.uri != newSnapshot.currentMedia?.uri {

                         // Fix Bug 9: Use suppress flag if this is a silent update
                         if isSilent {
                             suppressPlayerChangeSideEffects = true
                             currentPlayer = newSnapshot
                             suppressPlayerChangeSideEffects = false
                         } else {
                             currentPlayer = newSnapshot
                         }

                         // If the media URI changed, re-fetch the queue so Now Playing updates
                         if oldMedia?.uri != newSnapshot.currentMedia?.uri {
                             Task {
                                 try? await self.fetchAndPostQueueState(for: newSnapshot.playerId)
                             }
                         }
                    }
                }
                return
            }

            // If we get here, valid player is needed.
            // Only auto-select if user hasn't manually selected a player
            if userSelectedPlayer && currentPlayer != nil {
                // User has manually selected a player, don't auto-select
                return
            }

            var selectedPlayer: MAPlayer? = nil

            // Use localSendspinId already fetched above
            let isSendspinConnected = await SendspinClient.shared.isConnected

            // Step 1: ALWAYS prefer this device's local Sendspin player first
            // This makes the UI feel "local" by default
            if let localId = localSendspinId,
               let localPlayer = players.first(where: { $0.playerId == localId && $0.available }) {
                selectedPlayer = localPlayer
            }

            // Step 2: If local not available, check sticky preference
            if selectedPlayer == nil,
               let preferredId = preferredPlayerId,
               let preferred = players.first(where: { $0.playerId == preferredId && $0.available }) {
                selectedPlayer = preferred
            }

            // Step 3: Fall back to any available Sendspin player (excluding Web players)
            if selectedPlayer == nil {
                selectedPlayer = players.first(where: { $0.available && $0.provider == "sendspin" && !$0.name.contains("Web") })
            }

            // Step 4: Fall back to any available player (but be careful)
            if selectedPlayer == nil {
                // WAITING LOGIC:
                // If we are connected to local Sendspin socket, but the player hasn't appeared in the list yet,
                // DO NOT select a random player. Wait.
                // It usually takes ~1 second for the server to register the new connection and broadcast the player.
                
                let waitingForLocal: Bool
                if let localId = localSendspinId, isSendspinConnected {
                    waitingForLocal = !players.contains(where: { $0.playerId == localId })
                } else {
                    waitingForLocal = false
                }

                // Also wait if we have a preferred player set but it's not here yet (could be briefly offline)
                let waitingForPreferred: Bool
                if let prefId = preferredPlayerId {
                    waitingForPreferred = !players.contains(where: { $0.playerId == prefId })
                } else {
                    waitingForPreferred = false
                }
                
                if !waitingForLocal && !waitingForPreferred {
                    // Only fallback if we are NOT waiting for a specific better player
                    selectedPlayer = players.first(where: { $0.available })
                } else {
                    print("[XonoraClient] Waiting for preferred/local player to appear before auto-selecting...")
                }
            }

            if let selected = selectedPlayer {
                 print("[XonoraClient] Auto-selecting player: \(selected.name) (\(selected.playerId))")
                 currentPlayer = selected
            }
            // If selectedPlayer is nil, we leave currentPlayer as nil (or whatever it was)
        } catch {}
    }

    // MARK: - Player Grouping

    func groupPlayers(leaderId: String, memberIds: [String]) async throws {
        debugLog("[XonoraClient] Grouping players - Leader: \(leaderId), Members: \(memberIds)")
        let args: [String: Any] = [
            "target_player": leaderId,
            "player_ids_to_add": memberIds
        ]
        _ = try await sendCommand("players/cmd/set_members", args: args)
        debugLog("[XonoraClient] Group command completed successfully")

        // Auto-refresh players after grouping
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // Wait 500ms
            await fetchPlayers(isSilent: false)
        }
    }

    func ungroupPlayer(playerId: String) async throws {
        debugLog("[XonoraClient] Ungrouping player: \(playerId)")
        let args: [String: Any] = ["player_id": playerId]
        do {
            _ = try await sendCommand("players/cmd/ungroup", args: args)
            debugLog("[XonoraClient] Ungroup command completed successfully")
        } catch {
            debugLog("[XonoraClient] Ungroup failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    func createGroupPlayer(name: String, members: [String]) async throws {
        let args: [String: Any] = [
            "name": name,
            "members": members
        ]
        _ = try await sendCommand("players/create_group_player", args: args)
    }

    /// Fetches all library items by paginating until a partial page is returned.
    /// Skips the count call entirely - saves one round-trip per library type.
    /// Server already sorts by sort_name, so no client-side sorting needed.
    private func fetchAllLibraryItems<T: Decodable>(command: String, pageSize: Int = 500) async throws -> [T] {
        var allItems: [T] = []
        var offset = 0

        // First page
        let firstData = try await sendCommand(command, args: ["limit": pageSize, "offset": 0, "order_by": "sort_name"])
        let firstPage: [T] = try await Task.detached(priority: .userInitiated) {
            try Self.decodeLibraryPage(from: firstData)
        }.value
        allItems.append(contentsOf: firstPage)

        guard firstPage.count >= pageSize else { return allItems }

        // Fetch remaining pages concurrently
        offset = pageSize
        // Estimate: fetch up to 20 more pages concurrently (10,000 items max)
        var pageTasks: [Task<[T], Error>] = []
        for page in 1...20 {
            let pageOffset = page * pageSize
            pageTasks.append(Task {
                let data = try await self.sendCommand(command, args: ["limit": pageSize, "offset": pageOffset, "order_by": "sort_name"])
                return try await Task.detached(priority: .userInitiated) {
                    try Self.decodeLibraryPage(from: data) as [T]
                }.value
            })
        }

        for task in pageTasks {
            let items: [T] = try await task.value
            allItems.append(contentsOf: items)
            if items.count < pageSize { break } // Last page reached
        }

        return allItems
    }

    /// Decodes a page of library items directly from server response Data to model type.
    /// Avoids the intermediate [[String: Any]] -> Data -> Model double-serialization.
    nonisolated private static func decodeLibraryPage<T: Decodable>(from data: Data) throws -> [T] {
        let json = try JSONSerialization.jsonObject(with: data)

        var itemsJson: Any?
        if let dict = json as? [String: Any] {
            if let result = dict["result"] as? [String: Any], let items = result["items"] {
                itemsJson = items
            } else if let result = dict["result"] {
                itemsJson = result
            }
        } else {
            itemsJson = json
        }

        guard let items = itemsJson else {
            throw NSError(domain: "XonoraClient", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }

        let itemsData = try JSONSerialization.data(withJSONObject: items)
        return try JSONDecoder().decode([T].self, from: itemsData)
    }

    func fetchAlbums() async throws -> [Album] {
        try await fetchAllLibraryItems(command: "music/albums/library_items")
    }

    func fetchPlaylists() async throws -> [Playlist] {
        try await fetchAllLibraryItems(command: "music/playlists/library_items")
    }

    func fetchArtists() async throws -> [Artist] {
        try await fetchAllLibraryItems(command: "music/artists/library_items")
    }

    func fetchTracks() async throws -> [Track] {
        try await fetchAllLibraryItems(command: "music/tracks/library_items")
    }

    func fetchAudiobooks() async throws -> [Audiobook] {
        try await fetchAllLibraryItems(command: "music/audiobooks/library_items")
    }
    

    func fetchTrack(itemId: String, provider: String) async throws -> Track {
        let args = ["item_id": itemId, "provider_instance_id_or_domain": provider]
        let data = try await sendCommand("music/tracks/get", args: args)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard var result = json?["result"] as? [String: Any] else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid response format"))
        }
        
        // Ensure item_id and provider are present
        if result["item_id"] == nil { result["item_id"] = itemId }
        if result["provider"] == nil { result["provider"] = provider }
        
        let itemData = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(Track.self, from: itemData)
    }
    
    // MARK: - Specific Item Methods
    
    func fetchAlbum(itemId: String, provider: String) async throws -> Album {
        let args = ["item_id": itemId, "provider_instance_id_or_domain": provider]
        let data = try await sendCommand("music/albums/get", args: args)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard var result = json?["result"] as? [String: Any] else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid response format"))
        }
        
        // Ensure item_id and provider are present
        if result["item_id"] == nil { result["item_id"] = itemId }
        if result["provider"] == nil { result["provider"] = provider }
        
        let itemData = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(Album.self, from: itemData)
    }
    
    func fetchPlaylist(itemId: String, provider: String) async throws -> Playlist {
        let args = ["item_id": itemId, "provider_instance_id_or_domain": provider]
        let data = try await sendCommand("music/playlists/get", args: args)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard var result = json?["result"] as? [String: Any] else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid response format"))
        }
        
        // Ensure item_id and provider are present
        if result["item_id"] == nil { result["item_id"] = itemId }
        if result["provider"] == nil { result["provider"] = provider }
        
        let itemData = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(Playlist.self, from: itemData)
    }
    
    func fetchAudiobook(itemId: String, provider: String) async throws -> Audiobook {
        let args = ["item_id": itemId, "provider_instance_id_or_domain": provider]
        let data = try await sendCommand("music/audiobooks/get", args: args)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard var result = json?["result"] as? [String: Any] else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid response format"))
        }
        
        // Ensure item_id and provider are present
        if result["item_id"] == nil { result["item_id"] = itemId }
        if result["provider"] == nil { result["provider"] = provider }
        
        let itemData = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(Audiobook.self, from: itemData)
    }
    
    func fetchPodcast(itemId: String, provider: String) async throws -> Podcast {
        let args = ["item_id": itemId, "provider_instance_id_or_domain": provider]
        let data = try await sendCommand("music/podcasts/get", args: args)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard var result = json?["result"] as? [String: Any] else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid response format"))
        }
        
        // Ensure item_id and provider are present
        if result["item_id"] == nil { result["item_id"] = itemId }
        if result["provider"] == nil { result["provider"] = provider }
        
        let itemData = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(Podcast.self, from: itemData)
    }
    
    func fetchRadio(itemId: String, provider: String) async throws -> Radio {
        let args = ["item_id": itemId, "provider_instance_id_or_domain": provider]
        let data = try await sendCommand("music/radios/get", args: args)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard var result = json?["result"] as? [String: Any] else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid response format"))
        }
        
        // Ensure item_id and provider are present
        if result["item_id"] == nil { result["item_id"] = itemId }
        if result["provider"] == nil { result["provider"] = provider }
        
        let itemData = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(Radio.self, from: itemData)
    }

    func fetchPodcasts() async throws -> [Podcast] {
        try await fetchAllLibraryItems(command: "music/podcasts/library_items")
    }

    func fetchPodcastEpisodes(podcastId: String, provider: String) async throws -> [PodcastEpisode] {
        let data = try await sendCommand("music/podcasts/podcast_episodes", args: ["item_id": podcastId, "provider_instance_id_or_domain": provider])
        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let result = json?["result"] as? [[String: Any]] else { return [] }
                let resultData = try JSONSerialization.data(withJSONObject: result)
                return try JSONDecoder().decode([PodcastEpisode].self, from: resultData)
            } catch {
                print("[XonoraClient] Error decoding podcast episodes: \(error)")
                return []
            }
        }.value
    }

    func fetchRadios() async throws -> [Radio] {
        try await fetchAllLibraryItems(command: "music/radios/library_items")
    }

    func fetchSyncTasks() async throws -> [[String: Any]] {
        let data = try await sendCommand("music/synctasks")
        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let result = json?["result"] as? [[String: Any]] else { return [] }
                return result
            } catch {
                print("[XonoraClient] Error decoding sync tasks: \(error)")
                return []
            }
        }.value
    }

    func fetchAlbumTracks(albumId: String, provider: String) async throws -> [Track] {
        let data = try await sendCommand("music/albums/album_tracks", args: ["item_id": albumId, "provider_instance_id_or_domain": provider])
        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let result = json?["result"] as? [[String: Any]] else { return [] }
                let resultData = try JSONSerialization.data(withJSONObject: result)
                return try JSONDecoder().decode([Track].self, from: resultData)
            } catch {
                return []
            }
        }.value
    }

    func fetchPlaylistTracks(playlistId: String, provider: String) async throws -> [Track] {
        let data = try await sendCommand("music/playlists/playlist_tracks", args: ["item_id": playlistId, "provider_instance_id_or_domain": provider])
        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let result = json?["result"] as? [[String: Any]] else { return [] }
                let resultData = try JSONSerialization.data(withJSONObject: result)
                return try JSONDecoder().decode([Track].self, from: resultData)
            } catch {
                return []
            }
        }.value
    }

    func fetchAudiobookChapters(audiobookId: String, provider: String) async throws -> [Track] {
        let data = try await sendCommand("music/audiobooks/audiobook_tracks", args: ["item_id": audiobookId, "provider_instance_id_or_domain": provider])
        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let result = json?["result"] as? [[String: Any]] else { return [] }
                let resultData = try JSONSerialization.data(withJSONObject: result)
                return try JSONDecoder().decode([Track].self, from: resultData)
            } catch {
                return []
            }
        }.value
    }

    func fetchArtistAlbums(artistId: String, provider: String) async throws -> [Album] {
        let data = try await sendCommand("music/artists/artist_albums", args: ["item_id": artistId, "provider_instance_id_or_domain": provider])
        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let result = json?["result"] as? [[String: Any]] else { return [] }
                let resultData = try JSONSerialization.data(withJSONObject: result)
                return try JSONDecoder().decode([Album].self, from: resultData)
            } catch {
                return []
            }
        }.value
    }

    func fetchTrackAlbums(itemId: String, provider: String) async throws -> [Album] {
        let data = try await sendCommand("music/tracks/track_albums", args: [
            "item_id": itemId,
            "provider_instance_id_or_domain": provider
        ])
        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let result = json?["result"] as? [[String: Any]] else { return [] }
                let resultData = try JSONSerialization.data(withJSONObject: result)
                return try JSONDecoder().decode([Album].self, from: resultData)
            } catch {
                print("[XonoraClient] Error decoding track albums: \(error)")
                return []
            }
        }.value
    }
    
    func fetchRecentlyPlayed(limit: Int = 50) async throws -> [PlaybackHistoryItem] {
        let data = try await sendCommand("music/recently_played_items", args: ["limit": limit])
        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let result = json?["result"] as? [[String: Any]] else { return [] }
                
                // Convert MediaItem objects to PlaybackHistoryItem
                var historyItems: [PlaybackHistoryItem] = []
                for item in result {
                    guard let mediaType = item["media_type"] as? String,
                          let itemId = item["item_id"] as? String,
                          let name = item["name"] as? String,
                          let uri = item["uri"] as? String else {
                        continue
                    }
                    
                    // Determine content type from media_type
                    let contentType: PlaybackHistoryItem.ContentType
                    switch mediaType {
                    case "album": contentType = .album
                    case "track": contentType = .track
                    case "playlist": contentType = .playlist
                    case "audiobook": contentType = .audiobook
                    case "podcast": contentType = .podcast
                    case "podcast_episode": contentType = .podcast
                    case "radio": contentType = .radio
                    default: continue // Skip unknown types
                    }
                    
                    // Extract optional fields
                    let timestamp = Date() // MA doesn't provide timestamp, use current
                    let artistName = (item["artists"] as? [[String: Any]])?.first?["name"] as? String
                    
                    // Get image URL from metadata - construct provider URI
                    var imageUrl: String?
                    if let metadata = item["metadata"] as? [String: Any],
                       let images = metadata["images"] as? [[String: Any]],
                       let firstImage = images.first {
                        let path = firstImage["path"] as? String ?? ""
                        let provider = firstImage["provider"] as? String ?? ""
                        
                        // If path is already HTTP/HTTPS, use it directly
                        if path.hasPrefix("http://") || path.hasPrefix("https://") {
                            imageUrl = path
                        } else if !provider.isEmpty && !path.isEmpty {
                            // Construct provider URI: "provider://path"
                            imageUrl = "\(provider)://\(path)"
                        } else if !path.isEmpty {
                            imageUrl = path
                        }
                    }
                    
                    // Fallback: Check for top-level "image" object (common for non-library items)
                    if imageUrl == nil, let image = item["image"] as? [String: Any] {
                        let path = image["path"] as? String ?? ""
                        let provider = image["provider"] as? String ?? ""
                        
                        if path.hasPrefix("http://") || path.hasPrefix("https://") {
                            imageUrl = path
                        } else if !provider.isEmpty && !path.isEmpty {
                            imageUrl = "\(provider)://\(path)"
                        } else if !path.isEmpty {
                            imageUrl = path
                        }
                    }
                    
                    // Fallback: Direct image URL string
                    if imageUrl == nil, let directImage = item["image"] as? String, !directImage.isEmpty {
                        imageUrl = directImage
                    }
                    
                    // Don't use library:// URIs as fallback - they don't work with imageproxy
                    // (imageproxy needs actual file paths, not library IDs like library://track/43)
                    // Items without artwork will show placeholder icons instead
                    
                    // Extract progress/duration for audiobooks and podcasts
                    let progress: TimeInterval? = item["current_position"] as? TimeInterval
                    let duration: TimeInterval? = item["duration"] as? TimeInterval
                    
                    let historyItem = PlaybackHistoryItem(
                        timestamp: timestamp,
                        contentType: contentType,
                        itemId: itemId,
                        itemName: name,
                        itemUri: uri,
                        artistName: artistName,
                        imageUrl: imageUrl,
                        progress: progress,
                        duration: duration
                    )
                    historyItems.append(historyItem)
                }
                
                return historyItems
            } catch {
                print("[XonoraClient] Error decoding recently played: \(error)")
                return []
            }
        }.value
    }
    
    func fetchRecommendations() async throws -> [[String: Any]] {
        let data = try await sendCommand("music/recommendations")
        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let result = json?["result"] as? [[String: Any]] else { return [] }

                // Result is array of RecommendationFolder objects
                // Each folder has: name, items (array of media items), subtitle, image
                return result
            } catch {
                print("[XonoraClient] Error decoding recommendations: \(error)")
                return []
            }
        }.value
    }

    func fetchRecentlyAddedTracks(limit: Int = 50) async throws -> [Track] {
        let data = try await sendCommand("music/recently_added_tracks", args: ["limit": limit])
        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let result = json?["result"] as? [[String: Any]] else { return [] }
                let resultData = try JSONSerialization.data(withJSONObject: result)
                return try JSONDecoder().decode([Track].self, from: resultData)
            } catch {
                print("[XonoraClient] Error decoding recently added tracks: \(error)")
                return []
            }
        }.value
    }

    func fetchInProgressItems(limit: Int = 50) async throws -> [PlaybackHistoryItem] {
        let data = try await sendCommand("music/in_progress_items", args: ["limit": limit])
        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let result = json?["result"] as? [[String: Any]] else { return [] }

                // Convert ItemMapping objects to PlaybackHistoryItem
                var historyItems: [PlaybackHistoryItem] = []
                for item in result {
                    guard let mediaItem = item["item"] as? [String: Any],
                          let mediaType = mediaItem["media_type"] as? String,
                          let itemId = mediaItem["item_id"] as? String,
                          let name = mediaItem["name"] as? String,
                          let uri = mediaItem["uri"] as? String else {
                        continue
                    }

                    // Determine content type from media_type
                    let contentType: PlaybackHistoryItem.ContentType
                    switch mediaType {
                    case "audiobook": contentType = .audiobook
                    case "podcast_episode": contentType = .podcast
                    default: continue // Only show audiobooks and podcasts
                    }

                    let timestamp = Date()
                    let artistName = (mediaItem["artists"] as? [[String: Any]])?.first?["name"] as? String

                    // Get image URL from metadata
                    var imageUrl: String?
                    if let metadata = mediaItem["metadata"] as? [String: Any],
                       let images = metadata["images"] as? [[String: Any]],
                       let firstImage = images.first {
                        let path = firstImage["path"] as? String ?? ""
                        let provider = firstImage["provider"] as? String ?? ""

                        if path.hasPrefix("http://") || path.hasPrefix("https://") {
                            imageUrl = path
                        } else if !provider.isEmpty && !path.isEmpty {
                            imageUrl = "\(provider)://\(path)"
                        } else if !path.isEmpty {
                            imageUrl = path
                        }
                    }

                    // Extract progress/duration
                    let progress: TimeInterval? = item["position"] as? TimeInterval
                    let duration: TimeInterval? = mediaItem["duration"] as? TimeInterval

                    let historyItem = PlaybackHistoryItem(
                        timestamp: timestamp,
                        contentType: contentType,
                        itemId: itemId,
                        itemName: name,
                        itemUri: uri,
                        artistName: artistName,
                        imageUrl: imageUrl,
                        progress: progress,
                        duration: duration
                    )
                    historyItems.append(historyItem)
                }

                return historyItems
            } catch {
                print("[XonoraClient] Error decoding in progress items: \(error)")
                return []
            }
        }.value
    }

    func fetchSimilarTracks(for track: Track, limit: Int = 25) async throws -> [Track] {
        let data = try await sendCommand("music/tracks/similar_tracks", args: [
            "item_id": track.itemId,
            "provider_instance_id_or_domain": track.provider,
            "limit": limit
        ])

        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let result = json?["result"] as? [[String: Any]] else { return [] }
                let resultData = try JSONSerialization.data(withJSONObject: result)
                return try JSONDecoder().decode([Track].self, from: resultData)
            } catch {
                print("[XonoraClient] Error decoding similar tracks: \(error)")
                return []
            }
        }.value
    }

    func fetchTrackVersions(itemId: String, provider: String) async throws -> [Track] {
        let data = try await sendCommand("music/tracks/track_versions", args: [
            "item_id": itemId,
            "provider_instance_id_or_domain": provider
        ])

        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let result = json?["result"] as? [[String: Any]] else { return [] }
                let resultData = try JSONSerialization.data(withJSONObject: result)
                return try JSONDecoder().decode([Track].self, from: resultData)
            } catch {
                print("[XonoraClient] Error decoding track versions: \(error)")
                return []
            }
        }.value
    }

    func fetchAlbumVersions(itemId: String, provider: String) async throws -> [Album] {
        let data = try await sendCommand("music/albums/album_versions", args: [
            "item_id": itemId,
            "provider_instance_id_or_domain": provider
        ])

        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let result = json?["result"] as? [[String: Any]] else { return [] }
                let resultData = try JSONSerialization.data(withJSONObject: result)
                return try JSONDecoder().decode([Album].self, from: resultData)
            } catch {
                print("[XonoraClient] Error decoding album versions: \(error)")
                return []
            }
        }.value
    }

    /// Fetch lyrics for a track from metadata providers
    /// Returns a tuple of (plain lyrics, synced LRC lyrics)
    func fetchLyrics(for track: Track) async throws -> (lyrics: String?, lrcLyrics: String?) {
        // Bug 3 Fix: If provider mappings are missing (common for non-library tracks),
        // fetch full track details from server first to get them.
        // Server needs mappings to find lyrics across providers.
        var targetTrack = track
        
        if track.providerMappings == nil || track.providerMappings?.isEmpty == true {
            print("[XonoraClient] Track '\(track.name)' missing provider mappings, fetching full details...")
            // Try to fetch full track details
            do {
                let fetchedTrack = try await fetchTrack(itemId: track.itemId, provider: track.provider)
                targetTrack = fetchedTrack
                print("[XonoraClient] Successfully fetched track details with \(fetchedTrack.providerMappings?.count ?? 0) provider mappings")
            } catch {
                print("[XonoraClient] Failed to fetch track details: \(error.localizedDescription)")
                // Continue with original track - server will do its best
            }
        }
        
        // Build track dictionary matching the server's expected Track schema
        var trackDict: [String: Any] = [
            "item_id": targetTrack.itemId,
            "provider": targetTrack.provider,
            "name": targetTrack.name,
            "uri": targetTrack.uri,
            "provider_mappings": []
        ]
        
        if let mappings = targetTrack.providerMappings {
            trackDict["provider_mappings"] = mappings.map { mapping in
                return [
                    "item_id": mapping.itemId,
                    "provider_domain": mapping.providerDomain,
                    "provider_instance": mapping.providerInstance
                ]
            }
        }
        
        if let duration = targetTrack.duration {
            trackDict["duration"] = duration
        }

        if let version = targetTrack.version {
            trackDict["version"] = version
        }

        if let trackNumber = targetTrack.trackNumber {
            trackDict["track_number"] = trackNumber
        }

        if let discNumber = targetTrack.discNumber {
            trackDict["disc_number"] = discNumber
        }

        if let artists = targetTrack.artists {
            let artistsArray = artists.map { artist -> [String: Any] in
                var artistDict: [String: Any] = ["name": artist.name]
                if let itemId = artist.itemId { artistDict["item_id"] = itemId }
                if let provider = artist.provider { artistDict["provider"] = provider }
                return artistDict
            }
            trackDict["artists"] = artistsArray
        }
        
        if let album = targetTrack.album {
            trackDict["album"] = [
                "item_id": album.itemId,
                "provider": album.provider,
                "name": album.name
            ]
        }
        
        print("[XonoraClient] Fetching lyrics for '\(targetTrack.name)' by '\(targetTrack.artistNames)' \(targetTrack.version.map { "(version: \($0))" } ?? "") (provider: \(targetTrack.provider), mappings: \(targetTrack.providerMappings?.count ?? 0))")
        
        let data = try await sendCommand("metadata/get_track_lyrics", args: ["track": trackDict])
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let result = json?["result"] as? [Any], result.count >= 2 else {
            print("[XonoraClient] No lyrics found in server response")
            return (nil, nil)
        }
        
        // Result is array of [lyrics, lrc_lyrics]
        let lyrics = result[0] as? String
        let lrcLyrics = result[1] as? String
        
        if lyrics != nil || lrcLyrics != nil {
            print("[XonoraClient] Successfully fetched lyrics (plain: \(lyrics != nil), synced: \(lrcLyrics != nil))")
        } else {
            print("[XonoraClient] Server returned empty lyrics for '\(targetTrack.name)'")
        }
        
        return (lyrics, lrcLyrics)
    }
    
    func fetchArtistTracks(artistId: String, provider: String) async throws -> [Track] {
        let data = try await sendCommand("music/artists/artist_tracks", args: ["item_id": artistId, "provider_instance_id_or_domain": provider])
        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let result = json?["result"] as? [[String: Any]] else { return [] }
                let resultData = try JSONSerialization.data(withJSONObject: result)
                return try JSONDecoder().decode([Track].self, from: resultData)
            } catch {
                return []
            }
        }.value
    }

    func search(query: String, mediaTypes: [String]? = nil, limit: Int = 20) async throws -> (albums: [Album], artists: [Artist], tracks: [Track], playlists: [Playlist], audiobooks: [Audiobook], podcasts: [Podcast], radios: [Radio]) {
        let types = mediaTypes ?? ["album", "artist", "track", "playlist", "audiobook", "podcast", "radio"]
        let data = try await sendCommand("music/search", args: ["search_query": query, "media_types": types, "limit": limit])

        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let result = json?["result"] as? [String: Any] else { return ([], [], [], [], [], [], []) }
                let decoder = JSONDecoder()
                var albums: [Album] = []
                var artists: [Artist] = []
                var tracks: [Track] = []
                var playlists: [Playlist] = []
                var audiobooks: [Audiobook] = []
                var podcasts: [Podcast] = []
                var radios: [Radio] = []

                if let albumsArray = result["albums"] as? [[String: Any]] {
                    let albumsData = try JSONSerialization.data(withJSONObject: albumsArray)
                    albums = (try? decoder.decode([Album].self, from: albumsData)) ?? []
                }
                if let artistsArray = result["artists"] as? [[String: Any]] {
                    let artistsData = try JSONSerialization.data(withJSONObject: artistsArray)
                    artists = (try? decoder.decode([Artist].self, from: artistsData)) ?? []
                }
                if let tracksArray = result["tracks"] as? [[String: Any]] {
                    let tracksData = try JSONSerialization.data(withJSONObject: tracksArray)
                    tracks = (try? decoder.decode([Track].self, from: tracksData)) ?? []
                }
                if let playlistsArray = result["playlists"] as? [[String: Any]] {
                    let playlistsData = try JSONSerialization.data(withJSONObject: playlistsArray)
                    playlists = (try? decoder.decode([Playlist].self, from: playlistsData)) ?? []
                }
                if let audiobooksArray = result["audiobooks"] as? [[String: Any]] {
                    let audiobooksData = try JSONSerialization.data(withJSONObject: audiobooksArray)
                    audiobooks = (try? decoder.decode([Audiobook].self, from: audiobooksData)) ?? []
                }
                if let podcastsArray = result["podcasts"] as? [[String: Any]] {
                    let podcastsData = try JSONSerialization.data(withJSONObject: podcastsArray)
                    podcasts = (try? decoder.decode([Podcast].self, from: podcastsData)) ?? []
                }
                if let radiosArray = result["radios"] as? [[String: Any]] {
                    let radiosData = try JSONSerialization.data(withJSONObject: radiosArray)
                    radios = (try? decoder.decode([Radio].self, from: radiosData)) ?? []
                }
                return (albums, artists, tracks, playlists, audiobooks, podcasts, radios)
            } catch {
                return ([], [], [], [], [], [], [])
            }
        }.value
    }

    func addToLibrary(itemId: String, provider: String) async throws {
        let trackUri = "\(provider)://track/\(itemId)"
        _ = try await sendCommand("music/library/add_item", args: ["item": trackUri])
    }

    func addToLibrary(uri: String) async throws {
        _ = try await sendCommand("music/library/add_item", args: ["item": uri])
    }

    func removeFromLibrary(itemId: String, mediaType: String) async throws {
        _ = try await sendCommand("music/library/remove_item", args: [
            "media_type": mediaType,
            "library_item_id": itemId
        ])
    }

    // MARK: - Playlist Management

    func createPlaylist(name: String) async throws -> Playlist {
        let data = try await sendCommand("music/playlists/create_playlist", args: ["name": name])
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let result = json?["result"] as? [String: Any] else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid response format"))
        }
        
        let itemData = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(Playlist.self, from: itemData)
    }

    func addToPlaylist(playlistId: String, provider: String, trackUris: [String]) async throws {
        // Bug 1 Fix: Music Assistant expects 'db_playlist_id' as int and 'provider_instance_id_or_domain'
        guard let dbId = Int(playlistId) else {
            print("[XonoraClient] Error: Playlist ID must be convertible to Int for DB playlist")
            throw NSError(domain: "XonoraClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Playlist ID"])
        }

        _ = try await sendCommand("music/playlists/add_playlist_tracks",
                                  args: ["db_playlist_id": dbId,
                                         "provider_instance_id_or_domain": provider,
                                         "uris": trackUris])
    }

    func removeFromPlaylist(playlistId: String, provider: String, trackUris: [String]) async throws {
        guard let dbId = Int(playlistId) else {
            print("[XonoraClient] Error: Playlist ID must be convertible to Int for DB playlist")
            throw NSError(domain: "XonoraClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Playlist ID"])
        }

        _ = try await sendCommand("music/playlists/remove_playlist_tracks",
                                  args: ["db_playlist_id": dbId,
                                         "provider_instance_id_or_domain": provider,
                                         "uris": trackUris])
    }

    func ensureConnection() async throws {
        if connectionState == .connected { return }

        debugLog("[XonoraClient] ensureConnection: not connected, connecting...")

        // User action (like playing media) implies intent to reconnect
        userInitiatedDisconnect = false

        // Trigger reconnect immediately
        reconnectAttempts = 0
        reconnect()

        // Wait for connection (max 10 seconds)
        // After long idle, DNS + TCP + WebSocket + auth can exceed 5s on slow networks
        for _ in 0..<100 {
            if connectionState == .connected { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        throw NSError(domain: "XonoraClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to reconnect to server"])
    }

    func playMedia(uris: [String], queueOption: String = "replace") async throws {
        try await ensureConnection()
        guard let player = currentPlayer else { throw NSError(domain: "MusicAssistant", code: -1, userInfo: [NSLocalizedDescriptionKey: "No player"]) }
        _ = try await sendCommand("player_queues/play_media", args: ["queue_id": player.playerId, "media": uris, "option": queueOption])
    }
    
    // MARK: - Specific Player Control
    
    func playPause(playerId: String) async throws {
        try await ensureConnection()
        _ = try await sendCommand("player_queues/play_pause", args: ["queue_id": playerId])
    }
    
    func next(playerId: String) async throws {
        try await ensureConnection()
        _ = try await sendCommand("player_queues/next", args: ["queue_id": playerId])
    }
    
    func previous(playerId: String) async throws {
        try await ensureConnection()
        _ = try await sendCommand("player_queues/previous", args: ["queue_id": playerId])
    }

    func playPause() async throws {
        try await ensureConnection()
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/play_pause", args: ["queue_id": playerId])
    }

    func play() async throws {
        try await ensureConnection()
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("players/cmd/play", args: ["player_id": playerId])
    }

    func pause() async throws {
        try await ensureConnection()
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("players/cmd/pause", args: ["player_id": playerId])
    }

    func next() async throws {
        try await ensureConnection()
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/next", args: ["queue_id": playerId])
    }

    func previous() async throws {
        try await ensureConnection()
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/previous", args: ["queue_id": playerId])
    }

    func stop() async throws {
        try await ensureConnection()
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/stop", args: ["queue_id": playerId])
    }

    func seek(position: TimeInterval) async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/seek", args: ["queue_id": playerId, "position": Int(position)])
    }

    func setVolume(_ volume: Int) async throws {
        try await ensureConnection()
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("players/cmd/volume_set", args: ["player_id": playerId, "volume_level": volume])
    }

    func setVolume(_ volume: Int, playerId: String) async throws {
        try await ensureConnection()
        _ = try await sendCommand("players/cmd/volume_set", args: ["player_id": playerId, "volume_level": volume])
    }

    func setShuffle(enabled: Bool) async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/shuffle", args: ["queue_id": playerId, "shuffle_enabled": enabled])
    }

    func setRepeat(mode: String) async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/repeat", args: ["queue_id": playerId, "repeat_mode": mode])
    }
    
    func setPlaybackRate(_ rate: Float) async throws {
        // Music Assistant doesn't have a native playback rate API
        // We handle this locally via Sendspin audio engine
        print("[XonoraClient] Setting playback rate to \(rate)x via Sendspin")
        SendspinClient.shared.setPlaybackRate(rate)
    }

    func toggleItemFavorite(uri: String, favorite: Bool) async throws {
        let command = favorite ? "music/favorites/add_item" : "music/favorites/remove_item"
        _ = try await sendCommand(command, args: ["item": uri])
    }

    func markAsPlayed(track: Track, fullyPlayed: Bool = true) async throws {
        // Build media_item dictionary
        var mediaItem: [String: Any] = [
            "item_id": track.itemId,
            "provider": track.provider,
            "name": track.name,
            "uri": track.uri,
            "media_type": "track"
        ]

        if let duration = track.duration {
            mediaItem["duration"] = duration
        }

        _ = try await sendCommand("music/mark_played", args: [
            "media_item": mediaItem,
            "fully_played": fullyPlayed
        ])
    }

    func markAsUnplayed(track: Track) async throws {
        // Build media_item dictionary
        let mediaItem: [String: Any] = [
            "item_id": track.itemId,
            "provider": track.provider,
            "name": track.name,
            "uri": track.uri,
            "media_type": "track"
        ]

        _ = try await sendCommand("music/mark_unplayed", args: [
            "media_item": mediaItem
        ])
    }
    
    // MARK: - Queue Management
    /// Fetches the current queue for the given player
    func fetchQueue() async throws -> PlayerQueue? {
        guard let playerId = currentPlayer?.playerId else { return nil }

        // Fetch queue items
        let itemsData = try await sendCommand("player_queues/items", args: ["queue_id": playerId, "limit": 500])

        // Fetch queue state for metadata (currentIndex, shuffle, repeat)
        let stateData = try await sendCommand("player_queues/get", args: ["queue_id": playerId])

        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: itemsData) as? [String: Any]
                guard let result = json?["result"] as? [[String: Any]] else {
                    return PlayerQueue(queueId: playerId, currentIndex: nil, items: [], shuffleEnabled: nil, repeatMode: nil)
                }

                var queueItems: [QueueItem] = []
                for item in result {
                    guard let queueItemId = item["queue_item_id"] as? String,
                          let name = item["name"] as? String else {
                        continue
                    }
                    
                    let duration = item["duration"] as? TimeInterval
                    let uri = item["uri"] as? String
                    
                    // Extract artist name from media_item if available
                    var artistName: String? = nil
                    var albumName: String? = nil
                    var imageUrl: String? = nil
                    
                    if let mediaDict = item["media_item"] as? [String: Any] {
                        // Get artist — for audiobooks, prefer narrators then authors
                        if let artistsArray = mediaDict["artists"] as? [[String: Any]],
                           let firstArtist = artistsArray.first,
                           let artistNameVal = firstArtist["name"] as? String {
                            artistName = artistNameVal
                        }
                        if artistName == nil,
                           let mediaType = mediaDict["media_type"] as? String,
                           mediaType == "audiobook" {
                            if let narrators = mediaDict["narrators"] as? [String], !narrators.isEmpty {
                                artistName = narrators.joined(separator: ", ")
                            } else if let authors = mediaDict["authors"] as? [String], !authors.isEmpty {
                                artistName = authors.joined(separator: ", ")
                            }
                        }

                        // Get album name
                        if let albumDict = mediaDict["album"] as? [String: Any],
                           let albumNameVal = albumDict["name"] as? String {
                            albumName = albumNameVal
                        }
                        
                        // Get image from metadata
                        if let metadata = mediaDict["metadata"] as? [String: Any],
                           let images = metadata["images"] as? [[String: Any]],
                           let firstImage = images.first {
                            let path = firstImage["path"] as? String ?? ""
                            let provider = firstImage["provider"] as? String ?? ""
                            if path.hasPrefix("http") {
                                imageUrl = path
                            } else if !provider.isEmpty && !path.isEmpty {
                                imageUrl = "\(provider)://\(path)"
                            }
                        }
                    }
                    
                    // Simple QueueMediaItem for metadata only
                    var mediaItem: QueueMediaItem? = nil
                    if let mediaDict = item["media_item"] as? [String: Any] {
                        var metadata: MediaItemMetadata? = nil
                        if let metaDict = mediaDict["metadata"] as? [String: Any] {
                             // Images
                             var images: [MediaItemImage]? = nil
                             if let imagesArray = metaDict["images"] as? [[String: Any]] {
                                images = imagesArray.compactMap { imgDict -> MediaItemImage? in
                                    guard let path = imgDict["path"] as? String else { return nil }
                                    let type = imgDict["type"] as? String ?? "thumb"
                                    let provider = imgDict["provider"] as? String ?? ""
                                    return MediaItemImage(type: type, path: path, provider: provider)
                                }
                             }
                             
                             // Parse lyrics from queue metadata
                             let lyrics = metaDict["lyrics"] as? String
                             let lrcLyrics = metaDict["lrc_lyrics"] as? String
                            
                             metadata = MediaItemMetadata(images: images, lyrics: lyrics, lrcLyrics: lrcLyrics)
                        }
                        mediaItem = QueueMediaItem(
                            itemId: mediaDict["item_id"] as? String,
                            provider: mediaDict["provider"] as? String,
                            name: mediaDict["name"] as? String,
                            metadata: metadata
                        )
                    }
                    
                    // Extract clean track name from media_item if available
                    // The queue's "name" field often includes artists, so prefer media_item.name
                    let cleanName = mediaItem?.name ?? name

                    let queueItem = QueueItem(
                        queueItemId: queueItemId,
                        name: cleanName,
                        artist: artistName,
                        album: albumName,
                        imageUrl: imageUrl,
                        duration: duration,
                        uri: uri,
                        mediaItem: mediaItem
                    )
                    queueItems.append(queueItem)
                }

                // Parse state for metadata
                var currentIndex: Int? = nil
                var shuffleEnabled: Bool? = nil
                var repeatMode: String? = nil

                if let stateJson = try? JSONSerialization.jsonObject(with: stateData) as? [String: Any],
                   let stateResult = stateJson["result"] as? [String: Any] {
                    currentIndex = stateResult["current_index"] as? Int
                    shuffleEnabled = stateResult["shuffle_enabled"] as? Bool
                    repeatMode = stateResult["repeat_mode"] as? String
                }

                return PlayerQueue(
                    queueId: playerId,
                    currentIndex: currentIndex,
                    items: queueItems,
                    shuffleEnabled: shuffleEnabled,
                    repeatMode: repeatMode
                )
            } catch {
                print("[XonoraClient] Error parsing queue: \(error)")
                return PlayerQueue(queueId: playerId, currentIndex: nil, items: [], shuffleEnabled: nil, repeatMode: nil)
            }
        }.value
    }
    
    /// Clears the entire queue
    func clearQueue() async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/clear", args: ["queue_id": playerId])
    }
    
    /// Clears upcoming items from the queue, keeping the current track playing
    func clearUpcomingQueue() async throws {
        guard (currentPlayer?.playerId) != nil else {
            print("[XonoraClient] clearUpcomingQueue: No player ID")
            return
        }

        guard let queue = try await fetchQueue() else {
            print("[XonoraClient] clearUpcomingQueue: Failed to fetch queue")
            return
        }

        print("[XonoraClient] clearUpcomingQueue: Queue has \(queue.items.count) items")

        // Use currentIndex to determine which items to delete
        // If no currentIndex, use URI comparison as fallback
        let currentUri = await PlayerManager.shared.currentTrack?.uri
        print("[XonoraClient] clearUpcomingQueue: Current track URI: \(currentUri ?? "nil")")

        // Debug: Print first few queue URIs for comparison
        if queue.items.count > 0 {
            print("[XonoraClient] clearUpcomingQueue: Queue URIs: \(queue.items.prefix(3).compactMap { $0.uri }.joined(separator: ", "))")
        }

        // Find the current track index in the queue by matching queue_item_id
        var currentIndex: Int? = queue.currentIndex

        if currentIndex == nil {
            // Try to find by URI match
            if let uri = currentUri {
                currentIndex = queue.items.firstIndex(where: { $0.uri == uri })
                print("[XonoraClient] clearUpcomingQueue: Found current index by URI match: \(currentIndex ?? -1)")
            }

            // Also try matching with PlayerManager's current track by name
            if currentIndex == nil, let currentTrack = await PlayerManager.shared.currentTrack {
                // Try to find by comparing track names (case-insensitive)
                let currentName = currentTrack.name.lowercased()
                for (idx, item) in queue.items.enumerated() {
                    // Check if queue item name contains or matches the current track name
                    let itemName = item.name.lowercased()
                    let mediaItemName = item.mediaItem?.name?.lowercased()

                    if itemName.contains(currentName) || currentName.contains(itemName) ||
                       mediaItemName == currentName {
                        currentIndex = idx
                        print("[XonoraClient] clearUpcomingQueue: Found current index by name match at: \(idx)")
                        break
                    }
                }
            }
        } else {
            print("[XonoraClient] clearUpcomingQueue: Using server currentIndex: \(currentIndex ?? -1)")
        }

        guard let currentIdx = currentIndex else {
            // Can't determine current track - DON'T clear, safer to do nothing
            print("[XonoraClient] clearUpcomingQueue: ERROR - Can't determine current index, aborting to prevent stopping playback")
            return
        }

        // Safety check: Don't delete if only 1 item in queue (it must be the current one)
        if queue.items.count <= 1 {
            print("[XonoraClient] clearUpcomingQueue: Only 1 item in queue, nothing to clear")
            return
        }

        // Delete all items AFTER the current index
        var deletedCount = 0
        var failedCount = 0

        for (index, item) in queue.items.enumerated() {
            if index > currentIdx {
                do {
                    print("[XonoraClient] clearUpcomingQueue: Deleting upcoming item at index \(index): \(item.name)")
                    try await deleteQueueItem(itemId: item.queueItemId)
                    deletedCount += 1
                    // Small delay to avoid overwhelming the server
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                } catch {
                    print("[XonoraClient] clearUpcomingQueue: Failed to delete item \(item.queueItemId): \(error)")
                    failedCount += 1
                }
            }
        }

        print("[XonoraClient] clearUpcomingQueue: Deleted \(deletedCount) items, \(failedCount) failures")
    }
    
    /// Deletes a specific item from the queue
    func deleteQueueItem(itemId: String) async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/delete_item", args: ["queue_id": playerId, "queue_item_id": itemId])
    }
    
    /// Moves an item to a new position in the queue
    func moveQueueItem(itemId: String, toPosition: Int) async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/move_item", args: ["queue_id": playerId, "queue_item_id": itemId, "new_index": toPosition])
    }

    /// Fetches recently played items from the server (duplicate removed - use fetchRecentlyPlayed(limit:) instead)

    /// Fetches queue items for a specific player
    func fetchQueueItems(for playerId: String) async throws -> [Track] {
        let data = try await sendCommand("player_queues/items", args: ["queue_id": playerId, "limit": 500])

        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let result = json?["result"] as? [[String: Any]] else { return [] }

                var tracks: [Track] = []
                for item in result {
                    // Extract media_item if available
                    guard let mediaItem = item["media_item"] as? [String: Any],
                          let itemId = mediaItem["item_id"] as? String,
                          let provider = mediaItem["provider"] as? String,
                          let name = mediaItem["name"] as? String,
                          let uri = mediaItem["uri"] as? String else {
                        continue
                    }

                    let duration = mediaItem["duration"] as? TimeInterval
                    let trackNumber = mediaItem["track_number"] as? Int
                    let discNumber = mediaItem["disc_number"] as? Int
                    let version = mediaItem["version"] as? String

                    // Parse artists — for audiobooks, prefer narrators then authors
                    var artists: [ArtistReference]? = nil
                    if let artistsArray = mediaItem["artists"] as? [[String: Any]], !artistsArray.isEmpty {
                        artists = artistsArray.compactMap { artistDict -> ArtistReference? in
                            guard let artistName = artistDict["name"] as? String else { return nil }
                            return ArtistReference(
                                itemId: artistDict["item_id"] as? String,
                                provider: artistDict["provider"] as? String,
                                name: artistName
                            )
                        }
                    }
                    if (artists == nil || artists?.isEmpty == true),
                       let mediaType = mediaItem["media_type"] as? String,
                       mediaType == "audiobook" {
                        if let narrators = mediaItem["narrators"] as? [String], !narrators.isEmpty {
                            artists = narrators.map { ArtistReference(itemId: nil, provider: nil, name: $0) }
                        } else if let authors = mediaItem["authors"] as? [String], !authors.isEmpty {
                            artists = authors.map { ArtistReference(itemId: nil, provider: nil, name: $0) }
                        }
                    }

                    // Parse album
                    var album: AlbumReference? = nil
                    if let albumDict = mediaItem["album"] as? [String: Any],
                       let albumId = albumDict["item_id"] as? String,
                       let albumProvider = albumDict["provider"] as? String,
                       let albumName = albumDict["name"] as? String {
                        album = AlbumReference(
                            itemId: albumId,
                            provider: albumProvider,
                            name: albumName,
                            metadata: nil
                        )
                    }

                    let track = Track(
                        itemId: itemId,
                        provider: provider,
                        name: name,
                        version: version,
                        duration: duration,
                        trackNumber: trackNumber,
                        discNumber: discNumber,
                        uri: uri,
                        artists: artists,
                        album: album,
                        metadata: nil,
                        providerMappings: nil,
                        image: nil
                    )
                    tracks.append(track)
                }
                return tracks
            } catch {
                print("[XonoraClient] Error parsing queue items: \(error)")
                return []
            }
        }.value
    }

    /// Fetches queue state for a specific player
    func fetchQueueState(for playerId: String) async throws -> (currentIndex: Int, elapsedTime: Double, state: String) {
        let data = try await sendCommand("player_queues/get", args: ["queue_id": playerId])

        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let result = json?["result"] as? [String: Any] else {
                    return (0, 0.0, "idle")
                }

                let currentIndex = result["current_index"] as? Int ?? 0
                let elapsedTime = result["elapsed_time"] as? Double ?? 0.0
                let state = result["state"] as? String ?? "idle"

                return (currentIndex, elapsedTime, state)
            } catch {
                print("[XonoraClient] Error parsing queue state: \(error)")
                return (0, 0.0, "idle")
            }
        }.value
    }

    /// Plays the item at a specific index in the queue
    func playQueueIndex(_ index: Int) async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/play_index", args: ["queue_id": playerId, "index": index])
    }

    /// Fetches recently played items for the current queue
    func fetchRecentlyPlayedItems(limit: Int = 20) async throws -> [QueueItem] {
        guard let playerId = currentPlayer?.playerId else {
            print("[XonoraClient] fetchRecentlyPlayedItems: No player ID")
            return []
        }

        let args: [String: Any] = [
            "limit": limit,
            "queue_id": playerId,
            "fully_played_only": false
        ]

        let data = try await sendCommand("music/recently_played_items", args: args)

        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let resultArray = json?["result"] as? [[String: Any]] else {
                    print("[XonoraClient] fetchRecentlyPlayedItems: No result array in response")
                    return []
                }

                var playedItems: [QueueItem] = []

                for (index, item) in resultArray.enumerated() {
                    // The items ARE the media items directly (not wrapped in media_item)
                    guard let name = item["name"] as? String,
                          let provider = item["provider"] as? String else {
                        continue
                    }

                    // item_id might be Int or String
                    let itemId: String
                    if let intId = item["item_id"] as? Int {
                        itemId = String(intId)
                    } else if let strId = item["item_id"] as? String {
                        itemId = strId
                    } else {
                        continue
                    }

                    let uri = item["uri"] as? String

                    // Try to get artist/album/duration from library cache
                    var artistName: String? = nil
                    var albumName: String? = nil
                    var duration: TimeInterval? = item["duration"] as? TimeInterval

                    // For library tracks, look up in cache
                    if provider == "library" {
                        if let cachedTracks = await MetadataCache.shared.getTracks() {
                            // Find matching track by item_id
                            if let cachedTrack = cachedTracks.first(where: { $0.itemId == itemId }) {
                                artistName = cachedTrack.artistNames
                                albumName = cachedTrack.album?.name
                                duration = cachedTrack.duration
                            }
                        }
                    }

                    // Fallback to parsing from response if available
                    if artistName == nil {
                        if let artistsArray = item["artists"] as? [[String: Any]],
                           let firstArtist = artistsArray.first,
                           let artistNameVal = firstArtist["name"] as? String {
                            artistName = artistNameVal
                        }
                    }

                    if albumName == nil {
                        if let albumDict = item["album"] as? [String: Any],
                           let albumNameVal = albumDict["name"] as? String {
                            albumName = albumNameVal
                        }
                    }

                    // Extract image URL from image field
                    var imageUrl: String? = nil
                    if let imageDict = item["image"] as? [String: Any],
                       let path = imageDict["path"] as? String {
                        if path.hasPrefix("http") {
                            imageUrl = path
                        } else if let imgProvider = imageDict["provider"] as? String, !imgProvider.isEmpty {
                            imageUrl = "\(imgProvider)://\(path)"
                        }
                    }

                    // Create QueueMediaItem for metadata
                    var queueMediaItem: QueueMediaItem? = nil
                    if let metaDict = item["metadata"] as? [String: Any] {
                        var images: [MediaItemImage]? = nil
                        if let imagesArray = metaDict["images"] as? [[String: Any]] {
                            images = imagesArray.compactMap { imgDict -> MediaItemImage? in
                                guard let path = imgDict["path"] as? String else { return nil }
                                let type = imgDict["type"] as? String ?? "thumb"
                                let imgProvider = imgDict["provider"] as? String ?? ""
                                return MediaItemImage(type: type, path: path, provider: imgProvider)
                            }
                        }
                        let metadata = MediaItemMetadata(images: images)
                        queueMediaItem = QueueMediaItem(
                            itemId: itemId,
                            provider: provider,
                            name: name,
                            metadata: metadata
                        )
                    }

                    // Use a unique ID for played items (index-based since no timestamp in response)
                    let queueItemId = "played_\(index)_\(itemId)"

                    let queueItem = QueueItem(
                        queueItemId: queueItemId,
                        name: name,
                        artist: artistName,
                        album: albumName,
                        imageUrl: imageUrl,
                        duration: duration,
                        uri: uri,
                        mediaItem: queueMediaItem
                    )
                    playedItems.append(queueItem)
                }

                print("[XonoraClient] fetchRecentlyPlayedItems: Parsed \(playedItems.count) valid items")
                return playedItems
            } catch {
                print("[XonoraClient] Error parsing recently played items: \(error)")
                return []
            }
        }.value
    }

    enum ImageSize: Int {
        case thumbnail = 150
        case small = 300
        case medium = 600
        case large = 1200
    }

    func getImageURL(for urlString: String?, size: ImageSize = .medium, provider: String? = nil) -> URL? {
        guard let urlString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !urlString.isEmpty else {
            return nil
        }



        // Attempt to unwrap proxy URLs if they contain a remote HTTP path
        // This avoids local network proxy issues (e.g. iCloud Private Relay blocking 192.168.x.x)
        if urlString.contains("imageproxy") {
            if let components = URLComponents(string: urlString),
               let queryItems = components.queryItems,
               var pathValue = queryItems.first(where: { $0.name == "path" })?.value {

                // Handle double encoding if present (common in some MA providers)
                if pathValue.hasPrefix("http%3A") || pathValue.hasPrefix("https%3A") {
                    pathValue = pathValue.removingPercentEncoding ?? pathValue
                }

                // Only unwrap remote web URLs
                if (pathValue.hasPrefix("http://") || pathValue.hasPrefix("https://")) &&
                   !pathValue.contains("localhost") && !pathValue.contains("127.0.0.1") {

                    if pathValue.localizedCaseInsensitiveContains("mzstatic.com") {
                        return optimizeImageURL(pathValue, size: size)
                    }

                    return URL(string: pathValue)
                }
            }
        }

        if urlString.hasPrefix("data:image") {
            return URL(string: urlString)
        }
        if urlString.localizedCaseInsensitiveContains("mzstatic.com") {
            return optimizeImageURL(urlString, size: size)
        }
        if let baseURL = serverURL, urlString.contains(baseURL.host ?? ""), (urlString.contains("/imageproxy") || urlString.contains("/api/imageproxy")) {
            return URL(string: urlString)
        }
        if urlString.hasPrefix("http") && !urlString.contains("localhost") && !urlString.contains("127.0.0.1") {
            return URL(string: urlString)
        }

        // If it looks like a provider URI (contains ://)
        if urlString.contains("://") {
            guard let baseURL = serverURL else {
                return nil
            }

            // Parse the provider URI format: "provider://path"
            // Examples: 
            //   - "library://album/12" -> provider="library", path="album/12"
            //   - "filesystem_local--vi9QWfzW://album/1998 - 3rd Eye Vision" -> provider="filesystem_local--vi9QWfzW", path="album/1998 - 3rd Eye Vision"
            guard let separatorRange = urlString.range(of: "://") else {
                return nil
            }
            
            let providerPart = String(urlString[..<separatorRange.lowerBound])
            let pathPart = String(urlString[separatorRange.upperBound...])

            var components = URLComponents()
            components.scheme = baseURL.scheme
            components.host = baseURL.host
            components.port = baseURL.port
            let baseParams = baseURL.path.trimmingCharacters(in: .init(charactersIn: "/"))
            components.path = baseParams.isEmpty ? "/imageproxy" : "/\(baseParams)/imageproxy"
            
            // Send provider and path as separate parameters as required by MA imageproxy API
            components.queryItems = [
                URLQueryItem(name: "provider", value: providerPart),
                URLQueryItem(name: "path", value: pathPart),
                URLQueryItem(name: "size", value: "\(size.rawValue)")
            ]
            if let token = accessToken { components.queryItems?.append(URLQueryItem(name: "token", value: token)) }
            return components.url
        }

        guard let baseURL = serverURL else {
            return nil
        }

        var components = URLComponents()
        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.port = baseURL.port
        let baseParams = baseURL.path.trimmingCharacters(in: .init(charactersIn: "/"))
        components.path = baseParams.isEmpty ? "/imageproxy" : "/\(baseParams)/imageproxy"
        
        // URLQueryItem automatically handles percent-encoding, no need to pre-encode
        components.queryItems = [URLQueryItem(name: "path", value: urlString), URLQueryItem(name: "size", value: "\(size.rawValue)")]
        if let token = accessToken { components.queryItems?.append(URLQueryItem(name: "token", value: token)) }
        return components.url
    }

    private func optimizeImageURL(_ urlString: String, size: ImageSize) -> URL? {
        var optimizedString = urlString
        if urlString.localizedCaseInsensitiveContains("mzstatic.com") {
            let pattern = "\\d+x\\d+bb"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(urlString.startIndex..., in: urlString)
                optimizedString = regex.stringByReplacingMatches(in: urlString, options: [], range: range, withTemplate: "\(size.rawValue)x\(size.rawValue)bb")
            }
        }
        return URL(string: optimizedString)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        let criticalKeywords = ["Connecting", "Error", "Handshake", "authenticated", "timeout", "command: player_queues/play_media", "set_members", "group", "Grouping players"]
        if criticalKeywords.contains(where: { message.contains($0) }) {
            let logMessage = message.count > 1000 ? String(message.prefix(1000)) + "... (truncated)" : message
            print("[MusicAssistant] \(logMessage)")
        }
        #endif
    }
}

struct ServerInfo {
    let serverVersion: String
    let schemaVersion: Int
    let minSchemaVersion: Int
    let serverID: String
}

struct UserInfo: Codable {
    let userId: String
    let username: String
    let role: String
    let enabled: Bool
    let displayName: String?
    let avatarUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case role
        case enabled
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
    }
}

struct ProviderInstance: Codable, Identifiable {
    let type: String
    let domain: String
    let name: String
    let instanceNamePostfix: String?
    let instanceId: String
    let available: Bool
    let isStreamingProvider: Bool?
    
    var id: String { instanceId }
    
    var displayName: String {
        if let postfix = instanceNamePostfix, !postfix.isEmpty {
            return "\(name) (\(postfix))"
        }
        return name
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case domain
        case name
        case instanceNamePostfix = "instance_name_postfix"
        case instanceId = "instance_id"
        case available
        case isStreamingProvider = "is_streaming_provider"
    }
}

extension Notification.Name {
    static let queueUpdated = Notification.Name("queueUpdated")
    static let allQueuesUpdated = Notification.Name("allQueuesUpdated")
    static let playerChanged = Notification.Name("playerChanged")
}
