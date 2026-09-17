//
//  WatchSessionManager.swift
//  Xonora
//
//  iPhone-side WatchConnectivity manager that bridges existing architecture to Apple Watch.
//  Observes state from XonoraClient, MultiDeviceManager, PlayerManager, and LibraryViewModel.
//

import Foundation
import WatchConnectivity
import Combine

@MainActor
class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    private var session: WCSession?
    private var cancellables = Set<AnyCancellable>()

    // Throttling for application context updates
    private var updateTask: Task<Void, Never>?
    private var lastUpdate: Date = .distantPast
    private let updateInterval: TimeInterval = 0.5  // Max 2 updates/sec

    // Dirty flags: only rebuild snapshots whose source data actually changed
    private var playersNeedsRebuild = true
    private var nowPlayingNeedsRebuild = true
    private var libraryNeedsRebuild = true

    // State snapshot caching (for change detection)
    private var lastPlayersSnapshot: WatchPlayersSnapshot?
    private var lastNowPlayingState: WatchNowPlayingState?
    private var lastLibrarySnapshot: WatchLibrarySnapshot?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            print("[WatchSessionManager] WatchConnectivity not supported on this device")
            return
        }

        session = WCSession.default
        session?.delegate = self
        session?.activate()

        setupObservers()
        print("[WatchSessionManager] Activated and ready")
    }

    // MARK: - Observers

    private func setupObservers() {
        // -- Players: only when player list, selection, or per-player state changes --
        XonoraClient.shared.$players
            .sink { [weak self] _ in
                self?.playersNeedsRebuild = true
                self?.scheduleUpdate()
            }
            .store(in: &cancellables)

        XonoraClient.shared.$currentPlayer
            .sink { [weak self] _ in
                self?.playersNeedsRebuild = true
                self?.scheduleUpdate()
            }
            .store(in: &cancellables)

        MultiDeviceManager.shared.$playerStates
            .sink { [weak self] _ in
                self?.playersNeedsRebuild = true
                self?.scheduleUpdate()
            }
            .store(in: &cancellables)

        // -- Now Playing: playback state, track, time, controls --
        Publishers.CombineLatest4(
            PlayerManager.shared.$playbackState,
            PlayerManager.shared.$currentTrack,
            PlayerManager.shared.$currentTime,
            PlayerManager.shared.$duration
        )
        .sink { [weak self] _ in
            // Only nowPlaying — do NOT rebuild players for every time tick
            self?.nowPlayingNeedsRebuild = true
            self?.scheduleUpdate()
        }
        .store(in: &cancellables)

        Publishers.CombineLatest3(
            PlayerManager.shared.$shuffleEnabled,
            PlayerManager.shared.$repeatMode,
            PlayerManager.shared.$volume
        )
        .sink { [weak self] _ in
            self?.nowPlayingNeedsRebuild = true
            self?.scheduleUpdate()
        }
        .store(in: &cancellables)

        XonoraClient.shared.$connectionState
            .sink { [weak self] _ in
                self?.nowPlayingNeedsRebuild = true
                self?.scheduleUpdate()
            }
            .store(in: &cancellables)

        // -- Library: debounced, changes infrequently --
        Publishers.CombineLatest3(
            LibraryViewModel.shared.$albums,
            LibraryViewModel.shared.$playlists,
            LibraryViewModel.shared.$artists
        )
        .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.libraryNeedsRebuild = true
            self?.scheduleUpdate()
        }
        .store(in: &cancellables)
    }

    // MARK: - Update Scheduling

    private func scheduleUpdate() {
        // Cancel pending update
        updateTask?.cancel()

        // Schedule new update with throttling
        updateTask = Task { @MainActor in
            let now = Date()
            let timeSinceLastUpdate = now.timeIntervalSince(lastUpdate)

            if timeSinceLastUpdate < updateInterval {
                // Wait for remaining time
                try? await Task.sleep(nanoseconds: UInt64((updateInterval - timeSinceLastUpdate) * 1_000_000_000))
            }

            await sendUpdate()
            lastUpdate = Date()
        }
    }

    // MARK: - Build DTOs

    private func buildPlayersSnapshot() -> WatchPlayersSnapshot {
        let players = XonoraClient.shared.players
        let currentPlayerId = XonoraClient.shared.currentPlayer?.playerId
        let playerStates = MultiDeviceManager.shared.playerStates

        let watchPlayers = players.map { player -> WatchPlayerInfo in
            // Get state from MultiDeviceManager if available
            let state = playerStates[player.playerId]

            // Determine if this player is a group member (synced to another player)
            let isGroupMember = player.syncedTo != nil

            // Convert playback state
            let playbackState: String
            if let stateEnum = state?.playbackState {
                switch stateEnum {
                case .playing: playbackState = "playing"
                case .paused: playbackState = "paused"
                case .stopped: playbackState = "idle"
                case .loading: playbackState = "idle"
                case .error: playbackState = "idle"
                }
            } else if let playerState = player.state {
                playbackState = playerState.rawValue
            } else {
                playbackState = "idle"
            }

            // Get current track (prefer MultiDeviceManager state)
            let currentTrack: WatchTrackInfo?
            if let track = state?.currentTrack {
                currentTrack = track.toWatchTrackInfo()
            } else {
                currentTrack = nil
            }

            return WatchPlayerInfo(
                playerId: player.playerId,
                name: player.name,
                provider: player.provider,
                available: player.available,
                playbackState: playbackState,
                volume: state?.volume ?? player.volume ?? 50,
                currentTrack: currentTrack,
                currentTime: state?.currentTime ?? 0,
                duration: state?.duration ?? 0,
                isSelected: player.playerId == currentPlayerId,
                groupChildIds: player.groupChilds ?? [],
                isGroupMember: isGroupMember
            )
        }

        return WatchPlayersSnapshot(
            players: watchPlayers,
            activePlayerId: currentPlayerId,
            timestamp: Date()
        )
    }

    private func buildNowPlayingState() -> WatchNowPlayingState {
        let isConnected = XonoraClient.shared.connectionState == .connected
        let playbackState: String

        switch PlayerManager.shared.playbackState {
        case .playing: playbackState = "playing"
        case .paused: playbackState = "paused"
        case .stopped: playbackState = "idle"
        case .loading: playbackState = "idle"
        case .error: playbackState = "idle"
        }

        let repeatMode: String
        switch PlayerManager.shared.repeatMode {
        case .off: repeatMode = "off"
        case .all: repeatMode = "all"
        case .one: repeatMode = "one"
        }

        let track = PlayerManager.shared.currentTrack?.toWatchTrackInfo()

        // Only log when called from command handler (not periodic updates)
        // Removed to reduce log spam - track changes logged in sendUpdate()

        return WatchNowPlayingState(
            track: track,
            playbackState: playbackState,
            currentTime: PlayerManager.shared.currentTime,
            duration: PlayerManager.shared.duration,
            shuffleEnabled: PlayerManager.shared.shuffleEnabled,
            repeatMode: repeatMode,
            volume: Float(XonoraClient.shared.currentPlayer?.volume ?? 100) / 100.0,
            isConnected: isConnected,
            activePlayerId: XonoraClient.shared.currentPlayer?.playerId,
            activePlayerName: XonoraClient.shared.currentPlayer?.name
        )
    }

    private func buildLibrarySnapshot() -> WatchLibrarySnapshot {
        let allAlbums = LibraryViewModel.shared.albums
        let allPlaylists = LibraryViewModel.shared.playlists
        let allArtists = LibraryViewModel.shared.artists

        // Truncate if library is too large (> 500 items total)
        let totalItems = allAlbums.count + allPlaylists.count + allArtists.count
        let shouldTruncate = totalItems > 500

        let albums: [WatchAlbumInfo]
        let playlists: [WatchPlaylistInfo]
        let artists: [WatchArtistInfo]

        if shouldTruncate {
            // Prioritize favorites, then recent items
            let favoriteAlbums = allAlbums.filter { $0.favorite == true }
            let recentAlbums = allAlbums.prefix(100)
            let combinedAlbums = Array(Set(favoriteAlbums + recentAlbums)).prefix(100)
            albums = combinedAlbums.map { $0.toWatchAlbumInfo() }

            let favoritePlaylists = allPlaylists.filter { $0.favorite == true }
            let recentPlaylists = allPlaylists.prefix(50)
            let combinedPlaylists = Array(Set(favoritePlaylists + recentPlaylists)).prefix(50)
            playlists = combinedPlaylists.map { $0.toWatchPlaylistInfo() }

            let favoriteArtists = allArtists.filter { $0.favorite == true }
            let recentArtists = allArtists.prefix(50)
            let combinedArtists = Array(Set(favoriteArtists + recentArtists)).prefix(50)
            artists = combinedArtists.map { $0.toWatchArtistInfo() }
        } else {
            albums = allAlbums.map { $0.toWatchAlbumInfo() }
            playlists = allPlaylists.map { $0.toWatchPlaylistInfo() }
            artists = allArtists.map { $0.toWatchArtistInfo() }
        }

        return WatchLibrarySnapshot(
            albums: albums,
            playlists: playlists,
            artists: artists,
            timestamp: Date()
        )
    }

    // MARK: - Send Update

    private func sendUpdate() async {
        guard let session = session, session.isPaired, session.isWatchAppInstalled else {
            return
        }

        var hasChanges = false
        var context: [String: Data] = [:]

        // Only rebuild snapshots whose source data actually changed
        if playersNeedsRebuild {
            playersNeedsRebuild = false
            let playersSnapshot = buildPlayersSnapshot()

            let playersChanged: Bool
            if let last = lastPlayersSnapshot {
                playersChanged = playersSnapshot.players != last.players ||
                    playersSnapshot.activePlayerId != last.activePlayerId
            } else {
                playersChanged = true
            }

            if playersChanged {
                if let data = try? JSONEncoder().encode(playersSnapshot) {
                    context["players"] = data
                    
                    let previousCount = lastPlayersSnapshot?.players.count
                    lastPlayersSnapshot = playersSnapshot
                    hasChanges = true
                    
                    if previousCount != playersSnapshot.players.count {
                        print("[WatchSessionManager] Players updated: \(playersSnapshot.players.count) players")
                    }
                }
            }
        }

        if nowPlayingNeedsRebuild {
            nowPlayingNeedsRebuild = false
            let nowPlayingState = buildNowPlayingState()

            let nowPlayingChanged: Bool
            if let last = lastNowPlayingState {
                let trackChanged = nowPlayingState.track?.uri != last.track?.uri
                let playbackStateChanged = nowPlayingState.playbackState != last.playbackState
                let timeDiff = nowPlayingState.currentTime - last.currentTime
                let timeChanged = timeDiff > 0.9 || timeDiff < -0.9
                let shuffleChanged = nowPlayingState.shuffleEnabled != last.shuffleEnabled
                let repeatChanged = nowPlayingState.repeatMode != last.repeatMode
                let volumeChanged = nowPlayingState.volume != last.volume
                let activePlayerChanged = nowPlayingState.activePlayerId != last.activePlayerId
                
                nowPlayingChanged = trackChanged || playbackStateChanged || timeChanged || 
                                    shuffleChanged || repeatChanged || volumeChanged || 
                                    activePlayerChanged
            } else {
                nowPlayingChanged = true
            }

            if nowPlayingChanged {
                if let data = try? JSONEncoder().encode(nowPlayingState) {
                    context["nowPlaying"] = data
                    lastNowPlayingState = nowPlayingState
                    hasChanges = true
                }
            }
        }

        if libraryNeedsRebuild {
            libraryNeedsRebuild = false
            let librarySnapshot = buildLibrarySnapshot()

            let libraryChanged: Bool
            if let last = lastLibrarySnapshot {
                libraryChanged = librarySnapshot.albums.count != last.albums.count ||
                    librarySnapshot.playlists.count != last.playlists.count ||
                    librarySnapshot.artists.count != last.artists.count
            } else {
                libraryChanged = true
            }

            if libraryChanged {
                if let data = try? JSONEncoder().encode(librarySnapshot) {
                    context["library"] = data
                    lastLibrarySnapshot = librarySnapshot
                    hasChanges = true
                    print("[WatchSessionManager] Library: \(librarySnapshot.albums.count) albums, \(librarySnapshot.playlists.count) playlists, \(librarySnapshot.artists.count) artists")
                }
            }
        }

        // Only send if there are changes
        guard hasChanges else { return }

        do {
            // Merge with existing context to preserve other keys
            var updatedContext = session.applicationContext
            for (key, value) in context {
                updatedContext[key] = value
            }

            try session.updateApplicationContext(updatedContext)
        } catch {
            print("[WatchSessionManager] Failed to update context: \(error.localizedDescription)")
        }
    }

    // MARK: - Handle Commands

    private func handleCommand(_ message: WatchCommandMessage) async -> WatchNowPlayingState {
        do {
            switch message.command {
            case .playPause:
                if let playerId = message.payload?["playerId"] {
                    try await XonoraClient.shared.playPause(playerId: playerId)
                } else {
                    try await PlayerManager.shared.togglePlayPause()
                }

            case .next:
                if let playerId = message.payload?["playerId"] {
                    try await XonoraClient.shared.next(playerId: playerId)
                } else {
                    try await XonoraClient.shared.next()
                }
                // Wait for state to propagate from server
                try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms

            case .previous:
                if let playerId = message.payload?["playerId"] {
                    try await XonoraClient.shared.previous(playerId: playerId)
                } else {
                    try await XonoraClient.shared.previous()
                }
                // Wait for state to propagate from server
                try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms

            case .seek:
                if let timeStr = message.payload?["time"], let time = TimeInterval(timeStr) {
                    PlayerManager.shared.seek(to: time)
                }

            case .setVolume:
                if let volumeStr = message.payload?["volume"], let volume = Int(volumeStr) {
                    if let playerId = message.payload?["playerId"] {
                        // Per-player volume control
                        try await XonoraClient.shared.setVolume(volume, playerId: playerId)
                    } else {
                        try await XonoraClient.shared.setVolume(volume)
                    }
                }

            case .toggleShuffle:
                let newState = !PlayerManager.shared.shuffleEnabled
                try await XonoraClient.shared.setShuffle(enabled: newState)

            case .cycleRepeat:
                let currentMode = PlayerManager.shared.repeatMode
                let newMode: RepeatMode
                switch currentMode {
                case .off: newMode = .all
                case .all: newMode = .one
                case .one: newMode = .off
                }

                let modeString: String
                switch newMode {
                case .off: modeString = "off"
                case .all: modeString = "all"
                case .one: modeString = "one"
                }

                try await XonoraClient.shared.setRepeat(mode: modeString)

            case .playMedia:
                if let uri = message.payload?["uri"] {
                    try await XonoraClient.shared.playMedia(uris: [uri])
                    // Wait for state to propagate from server
                    try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms
                }

            case .toggleFavorite:
                if let uri = message.payload?["uri"], let favoriteStr = message.payload?["favorite"] {
                    let favorite = favoriteStr == "true"
                    try await XonoraClient.shared.toggleItemFavorite(uri: uri, favorite: favorite)
                }

            case .switchPlayer:
                if let playerId = message.payload?["playerId"] {
                    if let player = XonoraClient.shared.players.first(where: { $0.playerId == playerId }) {
                        XonoraClient.shared.setPreferredPlayer(player)
                    }
                }
            }
        } catch {
            print("[WatchSessionManager] Command failed: \(error.localizedDescription)")
        }

        // Return updated state for instant feedback
        return buildNowPlayingState()
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("[WatchSessionManager] Activation failed: \(error.localizedDescription)")
        } else {
            print("[WatchSessionManager] Activation completed with state: \(activationState.rawValue)")
        }

        // Send initial update
        Task { @MainActor in
            await self.sendUpdate()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        print("[WatchSessionManager] Session became inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        print("[WatchSessionManager] Session deactivated")
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        Task { @MainActor in
            // Decode command
            guard let data = try? JSONSerialization.data(withJSONObject: message),
                  let commandMessage = try? JSONDecoder().decode(WatchCommandMessage.self, from: data) else {
                replyHandler(["error": "Invalid command"])
                return
            }

            // Handle command
            let updatedState = await self.handleCommand(commandMessage)

            // Reply with updated state
            if let stateData = try? JSONEncoder().encode(updatedState),
               let stateDict = try? JSONSerialization.jsonObject(with: stateData) as? [String: Any] {
                replyHandler(stateDict)
            } else {
                replyHandler(["error": "Failed to encode state"])
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // Handle messages without reply handler (for fetch requests)
        Task { @MainActor in
            print("[WatchSessionManager] Received message: \(message.keys.joined(separator: ", "))")

            // Check if this is an album tracks request
            if let albumId = message["fetchAlbumTracks"] as? String {
                await self.fetchAndSendAlbumTracks(albumId: albumId)
            } else {
                print("[WatchSessionManager] Unknown message type")
            }
        }
    }

    // MARK: - Album Tracks Fetching

    private func fetchAndSendAlbumTracks(albumId: String) async {
        print("[WatchSessionManager] Received track request for album: \(albumId)")

        // Find album info from library first (need provider)
        let albums = LibraryViewModel.shared.albums
        guard let album = albums.first(where: { $0.itemId == albumId }) else {
            print("[WatchSessionManager] ERROR: Album not found in library: \(albumId)")
            return
        }

        print("[WatchSessionManager] Fetching tracks for: \(album.name) (provider: \(album.provider))")

        do {
            let tracks = try await XonoraClient.shared.fetchAlbumTracks(albumId: albumId, provider: album.provider)
            print("[WatchSessionManager] Fetched \(tracks.count) tracks")

            // Build response
            let watchTracks = tracks.map { $0.toWatchTrackInfo() }
            print("[WatchSessionManager] Built \(watchTracks.count) watch tracks from \(tracks.count) original tracks")

            let response = WatchAlbumTracksResponse(
                albumId: albumId,
                albumName: album.name,
                artistNames: album.artistNames,
                tracks: watchTracks
            )

            print("[WatchSessionManager] Response object has \(response.tracks.count) tracks")

            // Send via message
            guard let session = session else {
                print("[WatchSessionManager] ERROR: No session")
                return
            }

            print("[WatchSessionManager] Session state - paired: \(session.isPaired), watchAppInstalled: \(session.isWatchAppInstalled), reachable: \(session.isReachable)")

            guard session.isReachable else {
                print("[WatchSessionManager] ERROR: Watch not reachable")
                return
            }

            if let data = try? JSONEncoder().encode(response) {
                print("[WatchSessionManager] Encoded response to \(data.count) bytes")

                if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("[WatchSessionManager] Converted to dict with keys: \(dict.keys.joined(separator: ", "))")

                    if let tracksArray = dict["tracks"] as? [[String: Any]] {
                        print("[WatchSessionManager] Dict has \(tracksArray.count) tracks in array")
                    }

                    var message: [String: Any] = ["albumTracks": dict]
                    print("[WatchSessionManager] Sending \(response.tracks.count) tracks to Watch")
                    session.sendMessage(message, replyHandler: nil, errorHandler: { error in
                        print("[WatchSessionManager] ERROR: Failed to send album tracks: \(error.localizedDescription)")
                    })
                    print("[WatchSessionManager] sendMessage call completed")
                } else {
                    print("[WatchSessionManager] ERROR: Failed to convert data to dict")
                }
            } else {
                print("[WatchSessionManager] ERROR: Failed to encode tracks response")
            }
        } catch {
            print("[WatchSessionManager] ERROR: Failed to fetch album tracks: \(error.localizedDescription)")
        }
    }
}

// MARK: - Model Extensions (DTO Mapping)

@MainActor
extension Track {
    func toWatchTrackInfo() -> WatchTrackInfo {
        // Pre-resolve image URL via XonoraClient
        let imageURLString = XonoraClient.shared.getImageURL(for: self.imageUrl, size: .small)?.absoluteString

        return WatchTrackInfo(
            name: self.name,
            artistNames: self.artistNames,
            albumName: self.album?.name,
            duration: self.duration,
            imageURLString: imageURLString,
            favorite: self.favorite ?? false,
            uri: self.uri
        )
    }
}

@MainActor
extension Album {
    func toWatchAlbumInfo() -> WatchAlbumInfo {
        let imageURLString = XonoraClient.shared.getImageURL(for: self.imageUrl, size: .small)?.absoluteString

        return WatchAlbumInfo(
            itemId: self.itemId,
            provider: self.provider,
            name: self.name,
            artistNames: self.artistNames,
            year: self.year,
            imageURLString: imageURLString,
            uri: self.uri
        )
    }
}

@MainActor
extension Playlist {
    func toWatchPlaylistInfo() -> WatchPlaylistInfo {
        let imageURLString = XonoraClient.shared.getImageURL(for: self.imageUrl, size: .small)?.absoluteString

        return WatchPlaylistInfo(
            itemId: self.itemId,
            name: self.name,
            imageURLString: imageURLString,
            uri: self.uri
        )
    }
}

@MainActor
extension Artist {
    func toWatchArtistInfo() -> WatchArtistInfo {
        let imageURLString = XonoraClient.shared.getImageURL(for: self.imageUrl, size: .small)?.absoluteString

        return WatchArtistInfo(
            itemId: self.itemId,
            name: self.name,
            imageURLString: imageURLString
        )
    }
}
