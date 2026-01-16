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
                NotificationCenter.default.post(name: .queueUpdated, object: nil, userInfo: eventData)
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
                let playersData = try JSONSerialization.data(withJSONObject: result)
                let decoder = JSONDecoder()
                self.players = (try? decoder.decode([MAPlayer].self, from: playersData)) ?? []

                if let current = currentPlayer {
                    if let updated = players.first(where: { $0.playerId == current.playerId }) {
                        if updated.available { currentPlayer = updated } else { currentPlayer = nil }
                    } else { currentPlayer = nil }
                }

                let sendspinPlayer = players.first(where: { $0.available && $0.provider == "sendspin" && !$0.name.contains("Web") })
                if let best = sendspinPlayer {
                    if currentPlayer == nil || currentPlayer?.playerId != best.playerId { currentPlayer = best }
                } else if currentPlayer == nil, let first = players.first(where: { $0.available }) {
                    currentPlayer = first
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

    func search(query: String) async throws -> (albums: [Album], artists: [Artist], tracks: [Track]) {
        let data = try await sendCommand("music/search", args: ["search_query": query, "media_types": ["album", "artist", "track"], "limit": 20])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let result = json["result"] as? [String: Any] else { return ([], [], []) }
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
        return (albums, artists, tracks)
    }

    func addToLibrary(itemId: String, provider: String) async throws {
        let trackUri = "\(provider)://track/\(itemId)"
        _ = try await sendCommand("music/library/add_item", args: ["item": trackUri])
    }

    func playMedia(uris: [String], queueOption: String = "replace") async throws {
        guard let player = currentPlayer else { throw NSError(domain: "MusicAssistant", code: -1, userInfo: [NSLocalizedDescriptionKey: "No player"]) }
        _ = try await sendCommand("player_queues/play_media", args: ["queue_id": player.playerId, "media": uris, "option": queueOption])
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
}
