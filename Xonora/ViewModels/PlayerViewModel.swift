import Foundation
import Combine
import SendspinKit
import UIKit

@MainActor
class PlayerViewModel: ObservableObject {
    @Published var isNowPlayingPresented = false
    @Published var serverURL: String = ""
    @Published var username: String = ""
    @Published var accessToken: String = ""
    @Published var authMode: AuthMode = .credentials
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var isAuthenticating = false
    @Published var connectionError: String?
    @Published var showingServerSetup = false
    @Published var requiresAuth = false
    @Published var playbackError: String?
    @Published var sendspinEnabled: Bool = false
    @Published var sendspinConnected: Bool = false
    @Published var currentTrack: Track?
    @Published var currentSource: String?
    @Published var discoveredServers: [DiscoveredServer] = []

    private let client = XonoraClient.shared
    private let sendspinClient = SendspinClient.shared
    private let discovery = ServerDiscovery()
    let playerManager = PlayerManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var notificationObservers: [NSObjectProtocol] = []
    private var discoveryTask: Task<Void, Never>?

    private let serverURLKey = "MusicAssistantServerURL"
    private let accessTokenKey = "MusicAssistantAccessToken"
    private let authModeKey = "MusicAssistantAuthMode"
    private let sendspinEnabledKey = "MusicAssistantSendspinEnabled"
    private var sessionToken: String?

    init() {
        loadSavedCredentials()
        setupBindings()
        setupBackgroundHandling()
    }
    
    private func setupBackgroundHandling() {
        // Handle app lifecycle for better connection management
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                print("[PlayerViewModel] App foregrounded - checking connection health")

                // If we had a saved connection but now disconnected, try to reconnect
                // But skip if user manually disconnected
                // Sendspin will automatically reconnect when XonoraClient succeeds
                if !self.serverURL.isEmpty && !self.isConnected && !self.isConnecting && !self.client.wasUserInitiatedDisconnect {
                    print("[PlayerViewModel] Auto-reconnecting to saved server...")
                    self.connectToServer()
                }
            }
        })

        // Handle app becoming active again (includes after lock screen unlock)
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                print("[PlayerViewModel] App became active - verifying connection")

                // Check if we should be connected but aren't
                // Skip if user manually disconnected
                if !self.serverURL.isEmpty && !self.isConnected && !self.isConnecting && !self.client.wasUserInitiatedDisconnect {
                    print("[PlayerViewModel] Reconnecting after becoming active...")
                    self.connectToServer()
                }
                // NOTE: Sendspin reconnection now happens automatically via connectionState observer
            }
        })

        // Handle reconnection requests from PlayerManager (works on all platforms)
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .reconnectRequired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                print("[PlayerViewModel] Reconnection requested by PlayerManager")

                // PlayerManager requesting reconnect implies user action, so reset the flag
                if !self.serverURL.isEmpty && !self.isConnecting {
                    print("[PlayerViewModel] Attempting reconnection...")
                    self.connectToServer()
                }
            }
        })
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupBindings() {
        client.onSessionTokenReceived = { [weak self] token in
            self?.sessionToken = token
            KeychainHelper.shared.save(key: "ma_session_token", value: token)
        }

        // Listen for Playback Errors
        playerManager.$playbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if case .error(let message) = state {
                    self?.playbackError = message
                }
            }
            .store(in: &cancellables)

        client.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .connected:
                    self.isConnected = true
                    self.isConnecting = false
                    self.isAuthenticating = false
                    self.connectionError = nil
                    print("[PlayerViewModel] XonoraClient successfully connected")
                    
                    // CRITICAL: Only connect Sendspin AFTER XonoraClient is confirmed connected
                    // This prevents the state mismatch where Sendspin shows connected but XonoraClient is stuck
                    if self.sendspinEnabled {
                        Task { @MainActor in
                            print("[PlayerViewModel] XonoraClient connected, now connecting Sendspin...")
                            await self.connectSendspin()
                        }
                    }
                    
                case .connecting:
                    self.isConnecting = true
                    self.isAuthenticating = false
                    self.connectionError = nil
                    
                    // Disconnect Sendspin when main connection is lost
                    // This ensures state consistency
                    self.sendspinClient.disconnect()
                    
                case .authenticating:
                    self.isConnecting = false
                    self.isAuthenticating = true
                    self.connectionError = nil
                    
                case .disconnected:
                    self.isConnected = false
                    self.isConnecting = false
                    self.isAuthenticating = false

                    // Disconnect Sendspin when main connection is lost
                    self.sendspinClient.disconnect()

                    // Only auto-reconnect if this was NOT a user-initiated disconnect
                    // and we have saved credentials
                    if !self.serverURL.isEmpty {
                        // Check if user manually disconnected - if so, don't auto-reconnect
                        let wasUserInitiated = self.client.wasUserInitiatedDisconnect
                        if wasUserInitiated {
                            print("[PlayerViewModel] User-initiated disconnect - skipping auto-reconnect")
                        } else {
                            print("[PlayerViewModel] Unexpectedly disconnected - scheduling reconnection...")
                            Task { @MainActor in
                                // Wait a moment before reconnecting
                                try? await Task.sleep(for: .seconds(2))
                                if !self.isConnected && !self.isConnecting && !self.client.wasUserInitiatedDisconnect {
                                    print("[PlayerViewModel] Attempting auto-reconnection after disconnect...")
                                    self.connectToServer()
                                }
                            }
                        }
                    }
                    
                case .error(let message):
                    self.isConnected = false
                    self.isConnecting = false
                    self.isAuthenticating = false
                    self.connectionError = message
                    
                    // Disconnect Sendspin when main connection errors
                    self.sendspinClient.disconnect()
                    
                    print("[PlayerViewModel] Connection error: \(message)")
                    
                    // CRITICAL: Also auto-reconnect on error, not just disconnected
                    // The XonoraClient internal reconnection might have exhausted retries
                    // so we need to give it another chance at the PlayerViewModel level
                    // But skip if user manually disconnected
                    if !self.serverURL.isEmpty && message.contains("Failed to reconnect") && !self.client.wasUserInitiatedDisconnect {
                        print("[PlayerViewModel] Client exhausted reconnection attempts - resetting and trying again...")
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(3))
                            if !self.isConnected && !self.isConnecting && !self.client.wasUserInitiatedDisconnect {
                                print("[PlayerViewModel] Attempting manual reconnection after error...")
                                self.connectToServer()
                            }
                        }
                    }
                }
            }
            .store(in: &cancellables)

        client.$requiresAuth
            .receive(on: DispatchQueue.main)
            .assign(to: &$requiresAuth)

        // Sendspin connection state
        sendspinClient.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$sendspinConnected)

        // Sync current track
        playerManager.$currentTrack
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentTrack)

        // Sync current source
        playerManager.$currentSource
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentSource)
    }

    func startDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = Task {
            await discovery.startDiscovery()
            for await servers in await discovery.servers {
                self.discoveredServers = servers
            }
        }
    }

    func stopDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
        Task {
            await discovery.stopDiscovery()
            self.discoveredServers = []
        }
    }

    private func loadSavedCredentials() {
        if let savedURL = UserDefaults.standard.string(forKey: serverURLKey) {
            serverURL = savedURL
        }

        if let oldToken = UserDefaults.standard.string(forKey: accessTokenKey) {
            KeychainHelper.shared.save(key: "ma_access_token", value: oldToken)
            accessToken = oldToken
            authMode = .token
            UserDefaults.standard.set(AuthMode.token.rawValue, forKey: authModeKey)
            UserDefaults.standard.removeObject(forKey: accessTokenKey)
        } else {
            if let savedMode = UserDefaults.standard.string(forKey: authModeKey),
               let mode = AuthMode(rawValue: savedMode) {
                authMode = mode
            }
            username = KeychainHelper.shared.load(key: "ma_username") ?? ""
            accessToken = KeychainHelper.shared.load(key: "ma_access_token") ?? ""
            sessionToken = KeychainHelper.shared.load(key: "ma_session_token")
        }

        // If Sendspin enabled state hasn't been set yet, default to true
        if UserDefaults.standard.object(forKey: sendspinEnabledKey) == nil {
            sendspinEnabled = true
            UserDefaults.standard.set(true, forKey: sendspinEnabledKey)
        } else {
            sendspinEnabled = UserDefaults.standard.bool(forKey: sendspinEnabledKey)
        }
    }

    func connectToServer(password: String? = nil) {
        guard !serverURL.isEmpty else {
            showingServerSetup = true
            return
        }

        // Don't reconnect if already connected or connecting
        if isConnected || isConnecting || isAuthenticating {
            return
        }

        let url = normalizeServerURL(serverURL)
        UserDefaults.standard.set(url, forKey: serverURLKey)
        UserDefaults.standard.set(authMode.rawValue, forKey: authModeKey)

        serverURL = url

        if authMode == .credentials {
            KeychainHelper.shared.save(key: "ma_username", value: username)
            if let pwd = password, !pwd.isEmpty {
                KeychainHelper.shared.save(key: "ma_password", value: pwd)
            }
        } else if authMode == .token {
            KeychainHelper.shared.save(key: "ma_access_token", value: accessToken)
        }

        // Reset reconnection counter before connecting
        client.resetReconnectionAttempts()

        let pwd = password ?? KeychainHelper.shared.load(key: "ma_password")
        client.connect(to: url, authMode: authMode, username: username, password: pwd, accessToken: accessToken, sessionToken: sessionToken)

        // NOTE: Sendspin connection is now handled automatically in the connectionState observer
        // when XonoraClient transitions to .connected state. This ensures proper synchronization.
    }

    // MARK: - Sendspin

    func toggleSendspin(_ enabled: Bool) {
        sendspinEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: sendspinEnabledKey)

        if enabled {
            Task {
                await connectSendspin()
            }
        } else {
            sendspinClient.disconnect()
        }
    }

    func connectSendspin() async {
        guard !serverURL.isEmpty else { return }
        
        // CRITICAL: Only connect Sendspin if XonoraClient is actually connected
        // Sendspin requires a working server connection to function
        guard isConnected else {
            print("[PlayerViewModel] Skipping Sendspin connection - XonoraClient not connected yet")
            return
        }

        if let url = URL(string: serverURL), let host = url.host {
            let scheme = url.scheme == "https" ? "wss" : "ws"

            // Use the same port as the server URL - Sendspin is at /sendspin on the same server
            let targetPort: UInt16
            if let port = url.port {
                targetPort = UInt16(port)
            } else {
                // No explicit port means standard port for the scheme
                targetPort = (scheme == "wss") ? 443 : 80
            }

            let tokenToUse = (authMode == .credentials) ? (sessionToken ?? "") : accessToken
            print("[PlayerViewModel] Connecting Sendspin to \(host):\(targetPort) with token length: \(tokenToUse.count)")
            await sendspinClient.connect(to: host, port: targetPort, scheme: scheme, accessToken: tokenToUse)
            print("[PlayerViewModel] Sendspin connection completed - player is now registered on server")

            // Wait a moment for the server to register the player, then refresh the player list
            try? await Task.sleep(for: .seconds(1))
            print("[PlayerViewModel] Refreshing player list after Sendspin registration...")
            await client.fetchPlayers()
        }
    }

    func disconnect() {
        client.disconnect()
        sendspinClient.disconnect()
    }

    /// Stop all connection attempts and allow changing settings
    func stopAndShowSettings() {
        client.disconnect()
        sendspinClient.disconnect()
        showingServerSetup = true
    }

    func updateServerURL(_ url: String) {
        serverURL = normalizeServerURL(url)
        UserDefaults.standard.set(serverURL, forKey: serverURLKey)
    }

    func updateCredentials(accessToken: String) {
        let trimmedToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accessToken = trimmedToken
        KeychainHelper.shared.save(key: "ma_access_token", value: trimmedToken)
    }

    private func normalizeServerURL(_ url: String) -> String {
        var normalizedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)

        // Add http:// if no scheme provided
        if !normalizedURL.hasPrefix("http://") && !normalizedURL.hasPrefix("https://") {
            normalizedURL = "http://\(normalizedURL)"
        }

        // Remove trailing slash
        if normalizedURL.hasSuffix("/") {
            normalizedURL = String(normalizedURL.dropLast())
        }

        return normalizedURL
    }

    // MARK: - Playback Control

    func playTrack(_ track: Track, fromQueue tracks: [Track]? = nil, sourceName: String? = nil) {
        playerManager.playTrack(track, fromQueue: tracks, sourceName: sourceName)
    }

    func playAlbum(_ tracks: [Track], startingAt index: Int = 0) {
        playerManager.playAlbum(tracks, startingAt: index)
    }

    func playPlaylist(_ playlist: Playlist, tracks: [Track], startingAt index: Int = 0) {
        playerManager.playPlaylist(playlist, tracks: tracks, startingAt: index)
    }
    
    func playPodcast(_ podcast: Podcast, episode: PodcastEpisode) {
        playerManager.playPodcast(podcast, episode: episode)
    }

    func playRadio(_ radio: Radio) {
        playerManager.playRadio(radio)
    }

    func togglePlayPause() {
        playerManager.togglePlayPause()
    }

    func next() {
        playerManager.next()
    }

    func previous() {
        playerManager.previous()
    }

    func seek(to time: TimeInterval) {
        playerManager.seek(to: time)
    }

    func toggleShuffle() {
        playerManager.toggleShuffle()
    }

    func cycleRepeatMode() {
        playerManager.cycleRepeatMode()
    }

    // MARK: - Helper Properties

    var isPlaying: Bool {
        playerManager.isPlaying
    }

    var hasTrack: Bool {
        playerManager.currentTrack != nil
    }

    var progress: Double {
        playerManager.progress
    }

    var currentTime: TimeInterval {
        playerManager.currentTime
    }

    var duration: TimeInterval {
        playerManager.duration
    }

    var shuffleEnabled: Bool {
        playerManager.shuffleEnabled
    }

    var repeatMode: RepeatMode {
        playerManager.repeatMode
    }

    func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && !time.isNaN else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
