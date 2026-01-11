import Foundation
import Combine

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
    @Published var currentPlayer: MAPlayer?
    @Published var requiresAuth: Bool = false
    @Published var serverInfo: ServerInfo?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var serverURL: URL?
    private var pendingCallbacks: [String: (Result<Data, Error>) -> Void] = [:]
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var accessToken: String?
    private let authMessageId = "auth-handshake"
    private var pingTimer: Timer?
    private var connectionTimeoutTask: Task<Void, Never>?
    private let connectionTimeout: TimeInterval = 5.0

    static let shared = XonoraClient()

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        // Bypass proxy for local network connections (fixes iCloud Private Relay issues)
        config.connectionProxyDictionary = [:]
        config.waitsForConnectivity = true
        // Use a background queue for delegate callbacks to keep main thread free
        self.urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: .init())
    }

    var baseURL: URL? {
        return serverURL
    }

    // MARK: - Connection Management

    func connect(to serverURLString: String, accessToken: String? = nil) {
        // Don't reconnect if already connected or in progress
        switch connectionState {
        case .connected, .connecting, .authenticating:
            debugLog("Already connected or connecting, skipping connect call")
            return
        default:
            break
        }

        guard let url = URL(string: serverURLString) else {
            connectionState = .error("Invalid server URL")
            return
        }

        self.serverURL = url
        self.accessToken = accessToken

        // Reset reconnection counter for fresh connection attempt
        reconnectAttempts = 0

        connectionState = .connecting
        debugLog("Connecting to: \(serverURLString)")

        var wsComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        wsComponents?.scheme = url.scheme == "https" ? "wss" : "ws"
        wsComponents?.path = "/ws"

        guard let wsURL = wsComponents?.url else {
            connectionState = .error("Failed to create WebSocket URL")
            return
        }

        debugLog("WebSocket URL: \(wsURL)")

        var request = URLRequest(url: wsURL)
        // Add Origin header to satisfy server security requirements
        if let scheme = url.scheme, let host = url.host {
            let portString = url.port.map { ":\($0)" } ?? ""
            let origin = "\(scheme)://\(host)\(portString)"
            request.addValue(origin, forHTTPHeaderField: "Origin")
            debugLog("Setting Origin header: \(origin)")
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

    // MARK: - Connection Timeout

    private func startConnectionTimeout() {
        cancelConnectionTimeout()
        connectionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(5.0 * 1_000_000_000))
            guard let self = self, !Task.isCancelled else { return }

            // Only timeout if we're still in connecting state (haven't received server info)
            if self.connectionState == .connecting {
                self.debugLog("Connection timeout after 5 seconds")
                self.webSocketTask?.cancel(with: .goingAway, reason: nil)
                self.connectionState = .error("Connection timed out. Please check the server address and ensure the server is running.")
            }
        }
    }

    private func cancelConnectionTimeout() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
    }

    func disconnect() {
        stopReconnecting()
        stopPingTimer()
        cancelConnectionTimeout()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
        serverInfo = nil
    }

    /// Stop all reconnection attempts and reset state - allows user to change settings
    func stopReconnecting() {
        reconnectAttempts = maxReconnectAttempts // Prevent further reconnects
        debugLog("Stopped reconnection attempts")
    }

    /// Reset reconnection counter (call before a fresh connection attempt)
    func resetReconnectionAttempts() {
        reconnectAttempts = 0
    }

    private func reconnect() {
        guard reconnectAttempts < maxReconnectAttempts,
              let serverURL = serverURL else {
            connectionState = .error("Failed to reconnect after \(maxReconnectAttempts) attempts")
            return
        }

        reconnectAttempts += 1
        connectionState = .connecting
        debugLog("Reconnecting attempt \(reconnectAttempts)...")

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(reconnectAttempts) * 2) { [weak self] in
            guard let self = self else { return }
            self.connect(to: serverURL.absoluteString,
                        accessToken: self.accessToken)
        }
    }

    // MARK: - WebSocket Communication

    private func startPingTimer() {
        stopPingTimer()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendPing()
            }
        }
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func sendPing() {
        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                self?.debugLog("WebSocket ping failed: \(error.localizedDescription)")
            } else {
                // self?.debugLog("WebSocket ping sent")
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage()
            case .failure(let error):
                Task { @MainActor in
                    self.debugLog("WebSocket error: \(error.localizedDescription)")
                    self.connectionState = .error(error.localizedDescription)
                    self.reconnect()
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        // debugLog("Received: \(text.prefix(500))...")

        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            debugLog("Failed to parse message")
            return
        }

        Task { @MainActor in
            // Handle authentication response
            if let messageId = json["message_id"] as? String, messageId == authMessageId {
                if let result = json["result"] as? [String: Any], let authenticated = result["authenticated"] as? Bool, authenticated {
                    debugLog("Authentication successful")
                    connectionState = .connected
                    reconnectAttempts = 0
                    await fetchPlayers()
                } else {
                    let error = json["error"] as? String ?? "Authentication failed"
                    debugLog("Authentication failed: \(error)")
                    connectionState = .error("Authentication failed: Invalid access token.")
                }
                return
            }

            // Handle server info (first message after connect)
            if let serverVersion = json["server_version"] as? String {
                cancelConnectionTimeout()  // Connection successful, cancel timeout
                debugLog("Server version: \(serverVersion)")
                serverInfo = ServerInfo(
                    serverVersion: serverVersion,
                    schemaVersion: json["schema_version"] as? Int ?? 0,
                    minSchemaVersion: json["min_supported_schema_version"] as? Int ?? 0,
                    serverID: json["server_id"] as? String ?? ""
                )

                if (serverInfo?.schemaVersion ?? 0) >= 28 {
                    if accessToken != nil {
                        debugLog("New server schema, authenticating...")
                        connectionState = .authenticating
                        await authenticate()
                    } else {
                        debugLog("New server schema, but no access token provided.")
                        connectionState = .error("Authentication required. Please provide an access token in Settings.")
                    }
                } else {
                    debugLog("Old server schema, no authentication needed.")
                    connectionState = .connected
                    reconnectAttempts = 0
                    await fetchPlayers()
                }
                return
            }

            // Handle command responses
            if let messageId = json["message_id"] as? String,
               let callback = pendingCallbacks.removeValue(forKey: messageId) {
                callback(.success(data))
            }

            // Handle event messages
            if let event = json["event"] as? String {
                handleEvent(event, data: json)
            }

            // Handle errors
            if let errorCode = json["error_code"] as? Int {
                let errorMsg = json["details"] as? String ?? "Unknown error (code: \(errorCode))"
                debugLog("Error from server: \(errorMsg)")

                // Error code 20 = authentication required
                if errorCode == 20 {
                    requiresAuth = true
                    if accessToken == nil {
                        connectionState = .error("Authentication required. Please provide an access token in Settings.")
                    }
                }
            }
        }
    }

    private func authenticate() async {
        guard let token = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            debugLog("No access token provided for authentication")
            connectionState = .error("Authentication required. Please provide an access token.")
            return
        }

        // According to API docs, the auth command uses this specific format:
        let authPayload: [String: Any] = [
            "message_id": authMessageId,
            "command": "auth",
            "args": [
                "token": token
            ]
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: authPayload)
            let text = String(data: data, encoding: .utf8) ?? ""
            debugLog("Sending auth request...")

            guard let task = webSocketTask else {
                debugLog("WebSocket task is nil!")
                connectionState = .error("Connection lost. Please try again.")
                return
            }

            task.send(.string(text)) { [weak self] error in
                if let error = error {
                    Task { @MainActor in
                        self?.debugLog("Auth send error: \(error)")
                        self?.connectionState = .error("Failed to send authentication request: \(error.localizedDescription)")
                    }
                } else {
                    Task { @MainActor in
                        self?.debugLog("Auth request sent successfully")
                    }
                }
            }
        } catch {
            debugLog("Auth error: \(error)")
            connectionState = .error("Failed to create auth request")
        }
    }

    private func handleEvent(_ event: String, data: [String: Any]) {
        debugLog("Event: \(event)")
        switch event {
        case "player_updated", "players_updated":
            Task { await fetchPlayers() }
        case "queue_updated":
            if let eventData = data["data"] as? [String: Any] {
                NotificationCenter.default.post(name: .queueUpdated, object: nil, userInfo: eventData)
            }
        default:
            break
        }
    }

        private func sendCommand(_ command: String, args: [String: Any] = [:]) async throws -> Data {

            guard connectionState == .connected else {

                throw NSError(domain: "MusicAssistant", code: -1,

                    userInfo: [NSLocalizedDescriptionKey: "Not connected to server"])

            }

    

            let messageId = UUID().uuidString

    

            let payload: [String: Any] = [

                "message_id": messageId,

                "command": command,

                "args": args

            ]

    

            let data = try JSONSerialization.data(withJSONObject: payload)

            let text = String(data: data, encoding: .utf8) ?? ""

    

            debugLog("Sending command: \(command) (ID: \(messageId))")

    

            return try await withCheckedThrowingContinuation { continuation in

                pendingCallbacks[messageId] = { result in

                    switch result {

                    case .success(let data):

                        self.debugLog("Response received for \(command) (ID: \(messageId))")

                        continuation.resume(returning: data)

                    case .failure(let error):

                        self.debugLog("Error for \(command) (ID: \(messageId)): \(error)")

                        continuation.resume(throwing: error)

                    }

                }

    

                webSocketTask?.send(.string(text)) { error in

                    if let error = error {

                        Task { @MainActor in

                            self.pendingCallbacks.removeValue(forKey: messageId)

                            self.debugLog("Send error: \(error)")

                        }

                        continuation.resume(throwing: error)

                    }

                }

    

                // Timeout after 30 seconds

                DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in

                    if let callback = self?.pendingCallbacks.removeValue(forKey: messageId) {

                        self?.debugLog("Command timed out: \(command) (ID: \(messageId))")

                        callback(.failure(NSError(domain: "MusicAssistant", code: -1,

                            userInfo: [NSLocalizedDescriptionKey: "Request timeout"])))

                    }

                }

            }

        }

    

        // MARK: - API Methods

    

        func fetchPlayers() async {

            do {

                let data = try await sendCommand("players/all")

                debugLog("Players response received")



                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],

                   let result = json["result"] as? [[String: Any]] {

                    let playersData = try JSONSerialization.data(withJSONObject: result)

                    let decoder = JSONDecoder()

                    self.players = (try? decoder.decode([MAPlayer].self, from: playersData)) ?? []

                    debugLog("Found \(players.count) players")


                    // Check if current player is still valid and available
                    if let current = currentPlayer {
                        if let updatedPlayer = players.first(where: { $0.playerId == current.playerId }) {
                            if updatedPlayer.available {
                                currentPlayer = updatedPlayer
                            } else {
                                debugLog("Current player '\(current.name)' is no longer available")
                                currentPlayer = nil
                            }
                        } else {
                            debugLog("Current player '\(current.name)' no longer exists")
                            currentPlayer = nil
                        }
                    }

                    // Auto-select logic
                    let sendspinPlayer = players.first(where: {
                        $0.available && $0.provider == "sendspin" && !$0.name.contains("Web")
                    })
                    
                    // If no player selected, OR current is Web and we have a better one
                    if currentPlayer == nil || 
                       (currentPlayer?.name.contains("Web") == true && sendspinPlayer != nil) {
                        
                        if let bestPlayer = sendspinPlayer {
                            currentPlayer = bestPlayer
                            debugLog("Auto-selected Sendspin player: \(bestPlayer.name)")
                        } else if currentPlayer == nil, let firstAvailable = players.first(where: { $0.available }) {
                            currentPlayer = firstAvailable
                            debugLog("Auto-selected player: \(firstAvailable.name)")
                        }
                    }

                }

            } catch {

                debugLog("Failed to fetch players: \(error)")

            }

        }

    

        func fetchAlbums() async throws -> [Album] {

            debugLog("Fetching albums...")

            let data = try await sendCommand("music/albums/library_items")

    

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {

                debugLog("Failed to parse albums response")

                return []

            }

    

            debugLog("Albums response: \(String(describing: json.keys))")

    

            // Try different response structures

            var items: [[String: Any]]?

    

            if let result = json["result"] as? [String: Any] {

                items = result["items"] as? [[String: Any]]

            } else if let result = json["result"] as? [[String: Any]] {

                items = result

            }

    

            guard let albumItems = items else {

                debugLog("No album items found in response")

                return []

            }

    

            debugLog("Found \(albumItems.count) albums")

            let itemsData = try JSONSerialization.data(withJSONObject: albumItems)

            let decoder = JSONDecoder()

                        return (try? decoder.decode([Album].self, from: itemsData)) ?? []

                    }

            

                    func fetchPlaylists() async throws -> [Playlist] {

            
            debugLog("Fetching playlists...")
            let data = try await sendCommand("music/playlists/library_items")

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                debugLog("Failed to parse playlists response")
                return []
            }

            var items: [[String: Any]]?

            if let result = json["result"] as? [String: Any] {
                items = result["items"] as? [[String: Any]]
            } else if let result = json["result"] as? [[String: Any]] {
                items = result
            }

            guard let playlistItems = items else {
                debugLog("No playlist items found in response")
                return []
            }

            debugLog("Found \(playlistItems.count) playlists")
            let itemsData = try JSONSerialization.data(withJSONObject: playlistItems)
            let decoder = JSONDecoder()
            return (try? decoder.decode([Playlist].self, from: itemsData)) ?? []
        }

        func fetchArtists() async throws -> [Artist] {

            debugLog("Fetching artists...")

            let data = try await sendCommand("music/artists/library_items")

    

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {

                return []

            }

    

            var items: [[String: Any]]?

            if let result = json["result"] as? [String: Any] {

                items = result["items"] as? [[String: Any]]

            }

            else if let result = json["result"] as? [[String: Any]] {

                items = result

            }

    

            guard let artistItems = items else {

                return []

            }

    

            debugLog("Found \(artistItems.count) artists")

            let itemsData = try JSONSerialization.data(withJSONObject: artistItems)

            let decoder = JSONDecoder()

            return (try? decoder.decode([Artist].self, from: itemsData)) ?? []

        }

        func fetchTracks() async throws -> [Track] {
            debugLog("Fetching library tracks...")

            let data = try await sendCommand("music/tracks/library_items")

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return []
            }

            var items: [[String: Any]]?

            if let result = json["result"] as? [String: Any] {
                items = result["items"] as? [[String: Any]]
            }
            else if let result = json["result"] as? [[String: Any]] {
                items = result
            }

            guard let trackItems = items else {
                return []
            }

            debugLog("Found \(trackItems.count) library tracks")
            let itemsData = try JSONSerialization.data(withJSONObject: trackItems)
            let decoder = JSONDecoder()
            return (try? decoder.decode([Track].self, from: itemsData)) ?? []
        }



        func fetchAlbumTracks(albumId: String, provider: String) async throws -> [Track] {

            debugLog("Fetching tracks for album: \(albumId)")

            let data = try await sendCommand("music/albums/album_tracks", args: [

                "item_id": albumId,

                "provider_instance_id_or_domain": provider

            ])

    

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],

                  let result = json["result"] as? [[String: Any]] else {

                return []

            }

    

            debugLog("Found \(result.count) tracks")

            let resultData = try JSONSerialization.data(withJSONObject: result)

            let decoder = JSONDecoder()

                        return (try? decoder.decode([Track].self, from: resultData)) ?? []

                    }

            

                    func fetchPlaylistTracks(playlistId: String, provider: String) async throws -> [Track] {

            
            debugLog("Fetching tracks for playlist: \(playlistId)")
            let data = try await sendCommand("music/playlists/playlist_tracks", args: [
                "item_id": playlistId,
                "provider_instance_id_or_domain": provider
            ])

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? [[String: Any]] else {
                return []
            }

            debugLog("Found \(result.count) playlist tracks")
            let resultData = try JSONSerialization.data(withJSONObject: result)
            let decoder = JSONDecoder()
            return (try? decoder.decode([Track].self, from: resultData)) ?? []
        }

    

        func search(query: String) async throws -> (albums: [Album], artists: [Artist], tracks: [Track]) {

            let data = try await sendCommand("music/search", args: [

                "search_query": query,

                "media_types": ["album", "artist", "track"],

                "limit": 20

            ])

    

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],

                  let result = json["result"] as? [String: Any] else {

                return ([], [], [])

            }

    

            let decoder = JSONDecoder()

            var albums: [Album] = []

            var artists: [Artist] = []

            var tracks: [Track] = []

    

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

    

            debugLog("Search results - Albums: \(albums.count), Artists: \(artists.count), Tracks: \(tracks.count)")
            return (albums, artists, tracks)

        }

    

        func fetchQueue(queueId: String) async throws -> [QueueItem] {

            let data = try await sendCommand("player_queues/items", args: [

                "queue_id": queueId

            ])

    

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],

                  let result = json["result"] as? [[String: Any]] else {

                return []

            }

    

            let resultData = try JSONSerialization.data(withJSONObject: result)

            let decoder = JSONDecoder()

            return (try? decoder.decode([QueueItem].self, from: resultData)) ?? []

        }

        func addToLibrary(itemId: String, provider: String) async throws {
            debugLog("Adding to library: \(itemId) from \(provider)")
            // Construct a track URI in the format provider://track/item_id
            let trackUri = "\(provider)://track/\(itemId)"
            _ = try await sendCommand("music/library/add_item", args: [
                "item": trackUri
            ])
        }

        // MARK: - Playback Commands

    

    func playMedia(uris: [String], queueOption: String = "replace") async throws {
        guard var player = currentPlayer else {
            throw NSError(domain: "MusicAssistant", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No player selected"])
        }

        // Check if the current player is still available
        if !player.available {
            debugLog("Current player '\(player.name)' is not available, refreshing players...")
            await fetchPlayers()

            // Try to find the same player in updated list
            if let updatedPlayer = players.first(where: { $0.playerId == player.playerId && $0.available }) {
                player = updatedPlayer
                currentPlayer = updatedPlayer
            } else if let availablePlayer = players.first(where: { $0.available }) {
                // Fall back to any available player
                player = availablePlayer
                currentPlayer = availablePlayer
                debugLog("Switched to available player: \(player.name)")
            } else {
                throw NSError(domain: "MusicAssistant", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No available players. Check that a player is connected to your server."])
            }
        }

        let playerId = player.playerId
        debugLog("Playing media - URIs: \(uris.count) items, Queue ID: \(playerId)")

        guard !uris.isEmpty else {
            debugLog("ERROR: Empty URI list provided to playMedia")
            throw NSError(domain: "MusicAssistant", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Empty media URI list"])
        }

        // Use 'media' parameter with URI array
        _ = try await sendCommand("player_queues/play_media", args: [
            "queue_id": playerId,
            "media": uris,
            "option": queueOption
        ])
    }

    

            func playPause() async throws {

    

                guard let playerId = currentPlayer?.playerId else { return }

    

                _ = try await sendCommand("player_queues/play_pause", args: [

    

                    "queue_id": playerId

    

                ])

    

            }

    

        

    

            func play() async throws {

    

                guard let playerId = currentPlayer?.playerId else { return }

    

                _ = try await sendCommand("players/cmd/play", args: [

    

                    "player_id": playerId

    

                ])

    

            }

    

        

    

            func pause() async throws {

    

                guard let playerId = currentPlayer?.playerId else { return }

    

                _ = try await sendCommand("players/cmd/pause", args: [

    

                    "player_id": playerId

    

                ])

    

            }

    

        func next() async throws {

            guard let playerId = currentPlayer?.playerId else { return }

            _ = try await sendCommand("player_queues/next", args: [

                "queue_id": playerId

            ])

        }

    

        func previous() async throws {

            guard let playerId = currentPlayer?.playerId else { return }

            _ = try await sendCommand("player_queues/previous", args: [

                "queue_id": playerId

            ])

        }

    

        func stop() async throws {

            guard let playerId = currentPlayer?.playerId else { return }

            _ = try await sendCommand("player_queues/stop", args: [

                "queue_id": playerId

            ])

        }

    

        func seek(position: TimeInterval) async throws {

            guard let playerId = currentPlayer?.playerId else { return }

            _ = try await sendCommand("player_queues/seek", args: [

                "queue_id": playerId,

                "position": Int(position)

            ])

        }

    

        func setVolume(_ volume: Int) async throws {

            guard let playerId = currentPlayer?.playerId else { return }

            _ = try await sendCommand("players/cmd/volume_set", args: [

                "player_id": playerId,

                "volume_level": volume

            ])

        }

        func setShuffle(enabled: Bool) async throws {
            guard let playerId = currentPlayer?.playerId else { return }
            _ = try await sendCommand("player_queues/shuffle", args: [
                "queue_id": playerId,
                "shuffle_enabled": enabled
            ])
        }

        func setRepeat(mode: String) async throws {
            guard let playerId = currentPlayer?.playerId else { return }
            _ = try await sendCommand("player_queues/repeat", args: [
                "queue_id": playerId,
                "repeat_mode": mode
            ])
        }

        func toggleItemFavorite(uri: String, favorite: Bool) async throws {
            let command = favorite ? "music/favorites/add_item" : "music/favorites/remove_item"
            _ = try await sendCommand(command, args: [
                "item": uri
            ])
        }

    /// Image size presets for different contexts
    enum ImageSize: Int {
        case thumbnail = 150    // For small thumbnails (queue, lists)
        case small = 300        // For medium displays (grid items, CarPlay)
        case medium = 600       // For larger displays (album detail)
        case large = 1200       // For full-screen (now playing)
    }

    func getImageURL(for urlString: String?, size: ImageSize = .medium) -> URL? {
        guard let urlString = urlString, !urlString.isEmpty else { return nil }

        // If it's already a full HTTP URL, optimize it
        if urlString.hasPrefix("http") {
            return optimizeImageURL(urlString, size: size)
        }

        // For URIs (library://) or relative paths, use the imageproxy endpoint
        guard let baseURL = serverURL else { return nil }

        var components = URLComponents(url: baseURL.appendingPathComponent("api/imageproxy"), resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "path", value: urlString),
            URLQueryItem(name: "size", value: "\(size.rawValue)")
        ]

        if let token = accessToken {
            queryItems.append(URLQueryItem(name: "token", value: token))
        }

        components?.queryItems = queryItems

        return components?.url
    }

    /// Optimize image URLs for Apple Music CDN and other sources
    private func optimizeImageURL(_ urlString: String, size: ImageSize) -> URL? {
        var optimizedString = urlString

        // Apple Music CDN URLs (mzstatic.com) use format: {size}x{size}bb.jpg
        // Replace 3000x3000, 1200x1200, etc. with requested size
        if urlString.contains("mzstatic.com") {
            // Pattern: digits followed by 'x' followed by digits followed by 'bb'
            let pattern = "\\d+x\\d+bb"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(urlString.startIndex..., in: urlString)
                optimizedString = regex.stringByReplacingMatches(
                    in: urlString,
                    options: [],
                    range: range,
                    withTemplate: "\(size.rawValue)x\(size.rawValue)bb"
                )
            }
        }

        return URL(string: optimizedString)
    }

    // MARK: - Debug Logging

    private func debugLog(_ message: String) {
        #if DEBUG
        // Only log critical connection events to reduce noise
        let criticalKeywords = ["Connecting", "Error", "Handshake", "authenticated", "timeout", "command: player_queues/play_media"]
        if criticalKeywords.contains(where: { message.contains($0) }) {
            print("[MusicAssistant] \(message)")
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

extension Notification.Name {
    static let queueUpdated = Notification.Name("queueUpdated")
}
