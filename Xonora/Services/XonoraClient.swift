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
    @Published var currentPlayer: MAPlayer? {
        didSet {
            if let old = oldValue, let new = currentPlayer {
                if old.playerId != new.playerId {
                    print("[XonoraClient] Player changed: '\(old.name)' -> '\(new.name)' (id: \(new.playerId))")
                    NotificationCenter.default.post(
                        name: .playerChanged,
                        object: nil,
                        userInfo: ["playerName": new.name, "provider": new.provider]
                    )
                }
            } else if let new = currentPlayer {
                print("[XonoraClient] Player set: '\(new.name)' (id: \(new.playerId))")
            } else {
                print("[XonoraClient] Player cleared (was: \(oldValue?.name ?? "nil"))")
            }
        }
    }
    /// Tracks if the user manually selected a player (prevents auto-selection from overriding)
    var userSelectedPlayer: Bool = false
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
        config.timeoutIntervalForRequest = 86400 
        config.timeoutIntervalForResource = 604800 
        config.connectionProxyDictionary = [:]
        config.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: .init())
    }

    var baseURL: URL? {
        return serverURL
    }

    // MARK: - Connection Management

    func connect(to serverURLString: String, accessToken: String? = nil) {
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
        self.accessToken = accessToken
        reconnectAttempts = 0
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
            try? await Task.sleep(nanoseconds: UInt64(5.0 * 1_000_000_000))
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

    private func reconnect() {
        guard reconnectAttempts < maxReconnectAttempts, let serverURL = serverURL else {
            connectionState = .error("Failed to reconnect.")
            return
        }

        reconnectAttempts += 1
        connectionState = .connecting

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(reconnectAttempts) * 2) { [weak self] in
            guard let self = self, self.reconnectAttempts < self.maxReconnectAttempts else { return }
            self.connect(to: serverURL.absoluteString, accessToken: self.accessToken)
        }
    }

    // MARK: - WebSocket Communication

    private func startPingTimer() {
        stopPingTimer()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendPing() }
        }
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func sendPing() {
        webSocketTask?.sendPing { _ in }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
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
                Task { @MainActor in
                    self.connectionState = .error(error.localizedDescription)
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
                if let result = json["result"] as? [String: Any], let authenticated = result["authenticated"] as? Bool, authenticated {
                    connectionState = .connected
                    reconnectAttempts = 0
                    await fetchPlayers()
                } else {
                    connectionState = .error("Authentication failed.")
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
                    await fetchPlayers()
                }
                return
            }

            if let messageId = json["message_id"] as? String,
               let callback = pendingCallbacks.removeValue(forKey: messageId) {
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
        guard let token = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        let authPayload: [String: Any] = [
            "message_id": authMessageId,
            "command": "auth",
            "args": ["token": token]
        ]
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
                let queueId = eventData["queue_id"] as? String ?? "unknown"
                let state = eventData["state"] as? String ?? "unknown"
                let currentPlayerId = currentPlayer?.playerId ?? "none"
                print("[XonoraClient] Queue event for '\(queueId)' (current player: '\(currentPlayerId)') - state: \(state)")

                // Only forward queue events for the current player
                if queueId == currentPlayerId {
                    NotificationCenter.default.post(name: .queueUpdated, object: nil, userInfo: eventData)
                } else {
                    print("[XonoraClient] Ignoring queue event from different player")
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
            pendingCallbacks[messageId] = { result in
                switch result {
                case .success(let data): continuation.resume(returning: data)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            webSocketTask?.send(.string(text)) { error in
                if let error = error {
                    self.pendingCallbacks.removeValue(forKey: messageId)
                    continuation.resume(throwing: error)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                if let callback = self?.pendingCallbacks.removeValue(forKey: messageId) {
                    callback(.failure(NSError(domain: "MusicAssistant", code: -1, userInfo: [NSLocalizedDescriptionKey: "Timeout"])))
                }
            }
        }
    }

    // MARK: - API Methods

    func fetchPlayers() async {
        do {
            let data = try await sendCommand("players/all")
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [[String: Any]] {
                print("[XonoraClient] Received \(result.count) players from API")
                let playersData = try JSONSerialization.data(withJSONObject: result)
                let decoder = JSONDecoder()
                do {
                    self.players = try decoder.decode([MAPlayer].self, from: playersData)
                    print("[XonoraClient] Decoded \(self.players.count) players")
                    for player in self.players {
                        print("[XonoraClient] Player: '\(player.name)' available=\(player.available) state=\(player.state?.rawValue ?? "nil") hasMedia=\(player.currentMedia?.title != nil)")
                    }
                } catch {
                    print("[XonoraClient] Failed to decode players: \(error)")
                    self.players = []
                }

                // Update current player if it still exists in the list
                if let current = currentPlayer {
                    if let updated = players.first(where: { $0.playerId == current.playerId }) {
                        if updated.available {
                            currentPlayer = updated
                        } else {
                            print("[XonoraClient] Current player '\(current.name)' became unavailable")
                            currentPlayer = nil
                            userSelectedPlayer = false // Allow auto-selection again
                        }
                    } else {
                        print("[XonoraClient] Current player '\(current.name)' no longer exists")
                        currentPlayer = nil
                        userSelectedPlayer = false // Allow auto-selection again
                    }
                }

                // Only auto-select if user hasn't manually selected a player
                if !userSelectedPlayer && currentPlayer == nil {
                    let sendspinPlayer = players.first(where: { $0.available && $0.provider == "sendspin" && !$0.name.contains("Web") })
                    if let best = sendspinPlayer {
                        print("[XonoraClient] Auto-selecting Sendspin player: '\(best.name)'")
                        currentPlayer = best
                    } else if let first = players.first(where: { $0.available }) {
                        print("[XonoraClient] Auto-selecting first available player: '\(first.name)'")
                        currentPlayer = first
                    }
                }
            }
        } catch {}
    }

    func fetchAlbums() async throws -> [Album] {
        let data = try await sendCommand("music/albums/library_items")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = (json["result"] as? [String: Any])?["items"] as? [[String: Any]] ?? json["result"] as? [[String: Any]] else { return [] }

        return await Task.detached(priority: .userInitiated) {
            let itemsData = (try? JSONSerialization.data(withJSONObject: items)) ?? Data()
            return (try? JSONDecoder().decode([Album].self, from: itemsData)) ?? []
        }.value
    }

    func fetchPlaylists() async throws -> [Playlist] {
        let data = try await sendCommand("music/playlists/library_items")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = (json["result"] as? [String: Any])?["items"] as? [[String: Any]] ?? json["result"] as? [[String: Any]] else { return [] }

        return await Task.detached(priority: .userInitiated) {
            let itemsData = (try? JSONSerialization.data(withJSONObject: items)) ?? Data()
            return (try? JSONDecoder().decode([Playlist].self, from: itemsData)) ?? []
        }.value
    }

    func fetchArtists() async throws -> [Artist] {
        let data = try await sendCommand("music/artists/library_items")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = (json["result"] as? [String: Any])?["items"] as? [[String: Any]] ?? json["result"] as? [[String: Any]] else { return [] }

        return await Task.detached(priority: .userInitiated) {
            let itemsData = (try? JSONSerialization.data(withJSONObject: items)) ?? Data()
            return (try? JSONDecoder().decode([Artist].self, from: itemsData)) ?? []
        }.value
    }

    func fetchTracks() async throws -> [Track] {
        let data = try await sendCommand("music/tracks/library_items")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = (json["result"] as? [String: Any])?["items"] as? [[String: Any]] ?? json["result"] as? [[String: Any]] else { return [] }

        return await Task.detached(priority: .userInitiated) {
            let itemsData = (try? JSONSerialization.data(withJSONObject: items)) ?? Data()
            return (try? JSONDecoder().decode([Track].self, from: itemsData)) ?? []
        }.value
    }

    /// Fetches recently played items from the server
    /// - Parameters:
    ///   - limit: Maximum number of items to return (default: 20)
    ///   - mediaTypes: Optional array of media types to filter (e.g., ["track", "album"])
    /// - Returns: Array of RecentlyPlayedItem
    func fetchRecentlyPlayed(limit: Int = 20, mediaTypes: [String]? = nil) async throws -> [RecentlyPlayedItem] {
        var args: [String: Any] = ["limit": limit]
        if let types = mediaTypes {
            args["media_types"] = types
        }

        let data = try await sendCommand("music/recently_played_items", args: args)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [[String: Any]] else {
            print("[XonoraClient] No recently played items in response")
            return []
        }

        print("[XonoraClient] Received \(result.count) recently played items")

        // Debug: Dump first item structure
        if let firstItem = result.first {
            print("[XonoraClient] First item keys: \(firstItem.keys.sorted())")
            if let metadata = firstItem["metadata"] as? [String: Any] {
                print("[XonoraClient] metadata keys: \(metadata.keys.sorted())")
                if let images = metadata["images"] as? [[String: Any]], !images.isEmpty {
                    print("[XonoraClient] metadata.images[\(images.count)]: \(images.first ?? [:])")
                }
            }
            if let image = firstItem["image"] {
                print("[XonoraClient] direct image: \(image)")
            }
        }

        let resultData = try JSONSerialization.data(withJSONObject: result)
        do {
            let items = try JSONDecoder().decode([RecentlyPlayedItem].self, from: resultData)
            if let firstParsed = items.first {
                print("[XonoraClient] Parsed \(items.count) items, first imageUrl: \(firstParsed.imageUrl ?? "nil")")
            }
            return items
        } catch {
            print("[XonoraClient] Decode error: \(error)")
            return []
        }
    }

    func fetchAlbumTracks(albumId: String, provider: String) async throws -> [Track] {
        let data = try await sendCommand("music/albums/album_tracks", args: ["item_id": albumId, "provider_instance_id_or_domain": provider])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let result = json["result"] as? [[String: Any]] else { return [] }
        let resultData = try JSONSerialization.data(withJSONObject: result)
        return (try? JSONDecoder().decode([Track].self, from: resultData)) ?? []
    }

    func fetchPlaylistTracks(playlistId: String, provider: String) async throws -> [Track] {
        let data = try await sendCommand("music/playlists/playlist_tracks", args: ["item_id": playlistId, "provider_instance_id_or_domain": provider])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let result = json["result"] as? [[String: Any]] else { return [] }
        let resultData = try JSONSerialization.data(withJSONObject: result)
        return (try? JSONDecoder().decode([Track].self, from: resultData)) ?? []
    }

    func fetchArtistAlbums(artistId: String, provider: String) async throws -> [Album] {
        let data = try await sendCommand("music/artists/artist_albums", args: ["item_id": artistId, "provider_instance_id_or_domain": provider])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let result = json["result"] as? [[String: Any]] else { return [] }
        let resultData = try JSONSerialization.data(withJSONObject: result)
        return (try? JSONDecoder().decode([Album].self, from: resultData)) ?? []
    }

    func fetchArtistTracks(artistId: String, provider: String) async throws -> [Track] {
        let data = try await sendCommand("music/artists/artist_tracks", args: ["item_id": artistId, "provider_instance_id_or_domain": provider])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let result = json["result"] as? [[String: Any]] else { return [] }
        let resultData = try JSONSerialization.data(withJSONObject: result)
        return (try? JSONDecoder().decode([Track].self, from: resultData)) ?? []
    }

    func search(query: String) async throws -> (albums: [Album], artists: [Artist], tracks: [Track], playlists: [Playlist]) {
        let data = try await sendCommand("music/search", args: ["search_query": query, "media_types": ["album", "artist", "track", "playlist"], "limit": 20])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let result = json["result"] as? [String: Any] else { return ([], [], [], []) }
        let decoder = JSONDecoder()
        var albums: [Album] = []
        var artists: [Artist] = []
        var tracks: [Track] = []
        var playlists: [Playlist] = []

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
        return (albums, artists, tracks, playlists)
    }

    func addToLibrary(itemId: String, provider: String) async throws {
        let trackUri = "\(provider)://track/\(itemId)"
        _ = try await sendCommand("music/library/add_item", args: ["item": trackUri])
    }

    func playMedia(uris: [String], queueOption: String = "replace") async throws {
        guard let player = currentPlayer else {
            print("[XonoraClient] playMedia FAILED: No player selected")
            throw NSError(domain: "MusicAssistant", code: -1, userInfo: [NSLocalizedDescriptionKey: "No player"])
        }
        print("[XonoraClient] playMedia on '\(player.name)' (id: \(player.playerId)) - \(uris.count) URI(s), option: \(queueOption)")
        if !uris.isEmpty {
            print("[XonoraClient] First URI: \(uris[0])")
        }
        let response = try await sendCommand("player_queues/play_media", args: ["queue_id": player.playerId, "media": uris, "option": queueOption])
        if let responseStr = String(data: response, encoding: .utf8) {
            let truncated = responseStr.count > 500 ? String(responseStr.prefix(500)) + "..." : responseStr
            print("[XonoraClient] playMedia response: \(truncated)")
        }
    }

    func playPause() async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/play_pause", args: ["queue_id": playerId])
    }

    func play() async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("players/cmd/play", args: ["player_id": playerId])
    }

    func pause() async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("players/cmd/pause", args: ["player_id": playerId])
    }

    func next() async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/next", args: ["queue_id": playerId])
    }

    func previous() async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/previous", args: ["queue_id": playerId])
    }

    func stop() async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/stop", args: ["queue_id": playerId])
    }

    func seek(position: TimeInterval) async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/seek", args: ["queue_id": playerId, "position": Int(position)])
    }

    func setVolume(_ volume: Int) async throws {
        guard let playerId = currentPlayer?.playerId else { return }
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

    /// Fetches the queue items for a specific player
    func fetchQueueItems(for playerId: String) async throws -> [Track] {
        print("[XonoraClient] Fetching queue items for player: \(playerId)")
        let data = try await sendCommand("player_queues/items", args: ["queue_id": playerId, "limit": 100])

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [[String: Any]] else {
            print("[XonoraClient] No queue items in response")
            return []
        }

        print("[XonoraClient] Received \(result.count) queue items")

        // Convert queue items to Track objects
        var tracks: [Track] = []
        for item in result {
            // Queue items have a nested "media_item" that contains the track
            if let mediaItem = item["media_item"] as? [String: Any] {
                if let trackData = try? JSONSerialization.data(withJSONObject: mediaItem),
                   let track = try? JSONDecoder().decode(Track.self, from: trackData) {
                    tracks.append(track)
                }
            }
        }

        print("[XonoraClient] Decoded \(tracks.count) tracks from queue")
        return tracks
    }

    /// Fetches the current queue state for a player (includes current_item, elapsed_time, etc.)
    func fetchQueueState(for playerId: String) async throws -> (currentIndex: Int, elapsedTime: TimeInterval, state: String) {
        let data = try await sendCommand("player_queues/get_queue", args: ["queue_id": playerId])

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any] else {
            return (0, 0, "idle")
        }

        let currentIndex = result["current_index"] as? Int ?? 0
        let elapsedTime = result["elapsed_time"] as? TimeInterval ?? 0
        let state = result["state"] as? String ?? "idle"

        print("[XonoraClient] Queue state: index=\(currentIndex), elapsed=\(elapsedTime), state=\(state)")
        return (currentIndex, elapsedTime, state)
    }

    func toggleItemFavorite(uri: String, favorite: Bool) async throws {
        let command = favorite ? "music/favorites/add_item" : "music/favorites/remove_item"
        _ = try await sendCommand(command, args: ["item": uri])
    }

    enum ImageSize: Int {
        case thumbnail = 150
        case small = 300
        case medium = 600
        case large = 1200
    }

    func getImageURL(for urlString: String?, size: ImageSize = .medium) -> URL? {
        guard let urlString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !urlString.isEmpty else { return nil }
        if urlString.hasPrefix("data:image") { return URL(string: urlString) }
        if urlString.contains("mzstatic.com") { return optimizeImageURL(urlString, size: size) }
        if let baseURL = serverURL, urlString.contains(baseURL.host ?? ""), (urlString.contains("/imageproxy") || urlString.contains("/api/imageproxy")) { return URL(string: urlString) }
        if urlString.hasPrefix("http") && !urlString.contains("localhost") && !urlString.contains("127.0.0.1") { return URL(string: urlString) }
        guard let baseURL = serverURL else { return nil }

        var components = URLComponents()
        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.port = baseURL.port
        let baseParams = baseURL.path.trimmingCharacters(in: .init(charactersIn: "/"))
        components.path = baseParams.isEmpty ? "/imageproxy" : "/\(baseParams)/imageproxy"
        components.queryItems = [URLQueryItem(name: "path", value: urlString), URLQueryItem(name: "size", value: "\(size.rawValue)")]
        if let token = accessToken { components.queryItems?.append(URLQueryItem(name: "token", value: token)) }
        return components.url
    }

    private func optimizeImageURL(_ urlString: String, size: ImageSize) -> URL? {
        var optimizedString = urlString
        if urlString.contains("mzstatic.com") {
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
        let criticalKeywords = ["Connecting", "Error", "Handshake", "authenticated", "timeout", "command: player_queues/play_media"]
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

extension Notification.Name {
    static let queueUpdated = Notification.Name("queueUpdated")
    static let playerChanged = Notification.Name("playerChanged")
}
