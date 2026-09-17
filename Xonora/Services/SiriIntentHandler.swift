import Foundation
import Intents

class SiriIntentHandler: NSObject, INPlayMediaIntentHandling {

    // MARK: - Resolve

    func resolveMediaItems(for intent: INPlayMediaIntent, with completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void) {
        guard let mediaSearch = intent.mediaSearch,
              let searchTerm = mediaSearch.mediaName, !searchTerm.isEmpty else {
            completion([.unsupported()])
            return
        }

        let mediaType = mediaSearch.mediaType
        let artistFilter = mediaSearch.artistName?.lowercased()

        Task { @MainActor in
            guard XonoraClient.shared.connectionState == .connected else {
                print("[SiriIntentHandler] Server not connected, cannot resolve media")
                completion([.unsupported()])
                return
            }

            do {
                let results = try await XonoraClient.shared.search(query: searchTerm)
                var resolved: [INMediaItem] = []

                switch mediaType {
                case .song:
                    let filtered = filterByArtist(tracks: Array(results.tracks.prefix(10)), artistName: artistFilter)
                    resolved = filtered.prefix(5).map { track in
                        INMediaItem(
                            identifier: track.uri,
                            title: track.name,
                            type: .song,
                            artwork: nil,
                            artist: track.artistNames
                        )
                    }
                case .album:
                    let filtered = filterByArtist(albums: Array(results.albums.prefix(10)), artistName: artistFilter)
                    resolved = filtered.prefix(5).map { album in
                        INMediaItem(
                            identifier: album.uri,
                            title: album.name,
                            type: .album,
                            artwork: nil,
                            artist: album.artistNames
                        )
                    }
                case .artist:
                    resolved = results.artists.prefix(5).map { artist in
                        INMediaItem(
                            identifier: artist.uri,
                            title: artist.name,
                            type: .artist,
                            artwork: nil
                        )
                    }
                case .playlist:
                    resolved = results.playlists.prefix(5).map { playlist in
                        INMediaItem(
                            identifier: playlist.uri,
                            title: playlist.name,
                            type: .playlist,
                            artwork: nil
                        )
                    }
                default:
                    resolved = bestMatches(searchTerm: searchTerm, artistFilter: artistFilter, results: results)
                }

                if resolved.isEmpty {
                    resolved = bestMatches(searchTerm: searchTerm, artistFilter: artistFilter, results: results)
                }

                if let first = resolved.first {
                    if resolved.count > 1 {
                        completion(INPlayMediaMediaItemResolutionResult.successes(with: resolved))
                    } else {
                        completion([.success(with: first)])
                    }
                } else {
                    print("[SiriIntentHandler] No results for '\(searchTerm)'")
                    completion([.unsupported()])
                }
            } catch {
                print("[SiriIntentHandler] Search failed: \(error)")
                completion([.unsupported()])
            }
        }
    }

    // MARK: - Normalization

    private func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
         .components(separatedBy: .punctuationCharacters).joined(separator: " ")
         .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Strip leading articles so "The Beatles" ↔ "Beatles", "A Tribe Called Quest" ↔ "Tribe Called Quest"
    private func stripArticles(_ s: String) -> String {
        for prefix in ["the ", "a ", "an "] {
            if s.hasPrefix(prefix) { return String(s.dropFirst(prefix.count)) }
        }
        return s
    }

    /// Fraction of query words found verbatim in target (0.0–1.0). Single-word queries treated as binary.
    private func wordOverlap(_ query: String, _ target: String) -> Double {
        let qWords = query.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !qWords.isEmpty else { return 0 }
        let tWords = Set(target.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
        return Double(qWords.filter { tWords.contains($0) }.count) / Double(qWords.count)
    }

    // MARK: - Scoring

    /// Unified name-vs-query scorer used by every local match and resolve path.
    ///
    /// Score tiers:
    ///  100 — exact (with/without leading articles)
    ///   80 — target starts with query
    ///   60 — target contains query (substring)
    ///   55 — query contains target (name is a prefix of a longer spoken phrase)
    ///   45 — ≥75% of query words appear in target (partial word match)
    ///   30 — ≥50% of query words appear in target
    ///    0 — no useful match
    private func matchScore(name: String, query: String) -> Int {
        let normName  = normalize(name)
        let normQuery = normalize(query)
        let sName  = stripArticles(normName)
        let sQuery = stripArticles(normQuery)

        if normName == normQuery || sName == sQuery { return 100 }
        if normName.hasPrefix(normQuery) || sName.hasPrefix(sQuery) { return 80 }
        if normName.contains(normQuery) || sName.contains(sQuery) { return 60 }
        if normQuery.contains(normName) { return 55 }   // e.g. "Love Story" inside "Love Story Taylors Version"
        let overlap = max(wordOverlap(normQuery, normName), wordOverlap(sQuery, sName))
        if overlap >= 0.75 { return 45 }
        if overlap >= 0.50 { return 30 }
        return 0
    }

    /// Generic scored lookup — returns the best-scoring item above zero, nil if nothing qualifies.
    private func bestMatch<T>(_ query: String, in items: [T], name keyPath: KeyPath<T, String>) -> T? {
        items
            .compactMap { item -> (T, Int)? in
                let s = matchScore(name: item[keyPath: keyPath], query: query)
                return s > 0 ? (item, s) : nil
            }
            .max(by: { $0.1 < $1.1 })?
            .0
    }

    // MARK: - Artist Filtering

    private func filterByArtist(tracks: [Track], artistName: String?) -> [Track] {
        guard let artist = artistName, !artist.isEmpty else { return tracks }
        let norm = normalize(artist)
        let stripped = stripArticles(norm)
        let filtered = tracks.filter {
            let n = normalize($0.artistNames)
            return n.contains(norm) || n.contains(stripped)
        }
        return filtered.isEmpty ? tracks : filtered
    }

    private func filterByArtist(albums: [Album], artistName: String?) -> [Album] {
        guard let artist = artistName, !artist.isEmpty else { return albums }
        let norm = normalize(artist)
        let stripped = stripArticles(norm)
        let filtered = albums.filter {
            let n = normalize($0.artistNames)
            return n.contains(norm) || n.contains(stripped)
        }
        return filtered.isEmpty ? albums : filtered
    }

    // MARK: - Resolve Scoring

    private func bestMatches(
        searchTerm: String,
        artistFilter: String?,
        results: (albums: [Album], artists: [Artist], tracks: [Track], playlists: [Playlist], audiobooks: [Audiobook], podcasts: [Podcast], radios: [Radio])
    ) -> [INMediaItem] {
        var items: [(item: INMediaItem, score: Int)] = []

        let filteredTracks = filterByArtist(tracks: Array(results.tracks.prefix(5)), artistName: artistFilter)
        for track in filteredTracks.prefix(3) {
            let item = INMediaItem(identifier: track.uri, title: track.name, type: .song, artwork: nil, artist: track.artistNames)
            items.append((item, matchScore(name: track.name, query: searchTerm)))
        }
        let filteredAlbums = filterByArtist(albums: Array(results.albums.prefix(5)), artistName: artistFilter)
        for album in filteredAlbums.prefix(3) {
            let item = INMediaItem(identifier: album.uri, title: album.name, type: .album, artwork: nil, artist: album.artistNames)
            items.append((item, matchScore(name: album.name, query: searchTerm)))
        }
        for artist in results.artists.prefix(3) {
            let item = INMediaItem(identifier: artist.uri, title: artist.name, type: .artist, artwork: nil)
            items.append((item, matchScore(name: artist.name, query: searchTerm)))
        }
        for playlist in results.playlists.prefix(3) {
            let item = INMediaItem(identifier: playlist.uri, title: playlist.name, type: .playlist, artwork: nil)
            items.append((item, matchScore(name: playlist.name, query: searchTerm)))
        }

        return items.sorted { $0.score > $1.score }.prefix(5).map(\.item)
    }

    // MARK: - Handle

    func handle(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        let searchQuery: String
        let mediaType: INMediaItemType
        let artistFilter: String?

        if let mediaSearch = intent.mediaSearch, let name = mediaSearch.mediaName, !name.isEmpty {
            searchQuery = name
            artistFilter = mediaSearch.artistName
            switch mediaSearch.mediaType {
            case .song: mediaType = .song
            case .album: mediaType = .album
            case .artist: mediaType = .artist
            case .playlist: mediaType = .playlist
            default: mediaType = intent.mediaItems?.first?.type ?? .unknown
            }
        } else if let firstItem = intent.mediaItems?.first, let identifier = firstItem.identifier {
            searchQuery = firstItem.title ?? identifier
            mediaType = firstItem.type
            artistFilter = nil
        } else {
            completion(INPlayMediaIntentResponse(code: .failure, userActivity: nil))
            return
        }

        let wantsShuffle = intent.playShuffled ?? false
        let repeatMode = intent.playbackRepeatMode

        Task { @MainActor in
            // Wait up to 5s for connection (Siri can cold-launch the app)
            let client = XonoraClient.shared
            if client.connectionState != .connected {
                for _ in 0..<10 {
                    try? await Task.sleep(for: .milliseconds(500))
                    if client.connectionState == .connected { break }
                }
                guard client.connectionState == .connected else {
                    print("[SiriIntentHandler] Server not connected after wait, cannot play")
                    completion(INPlayMediaIntentResponse(code: .failureRequiringAppLaunch, userActivity: nil))
                    return
                }
            }

            do {
                // Try local library first (fast path, no network)
                let didPlayLocal = try await playFromLibrary(query: searchQuery, mediaType: mediaType, artistFilter: artistFilter)

                if didPlayLocal {
                    print("[SiriIntentHandler] Played '\(searchQuery)' from local library")
                    applySiriPlaybackOptions(shuffle: wantsShuffle, repeatMode: repeatMode)
                    completion(INPlayMediaIntentResponse(code: .success, userActivity: nil))
                    return
                }

                // Fall back to server search with targeted media types
                print("[SiriIntentHandler] Local miss for '\(searchQuery)', searching server...")
                let results: (albums: [Album], artists: [Artist], tracks: [Track], playlists: [Playlist], audiobooks: [Audiobook], podcasts: [Podcast], radios: [Radio])
                switch mediaType {
                case .song:
                    let res = try await client.search(query: searchQuery, mediaTypes: ["track"], limit: 5)
                    results = res
                case .artist:
                    let res = try await client.search(query: searchQuery, mediaTypes: ["artist", "track"], limit: 10)
                    results = res
                case .album:
                    let res = try await client.search(query: searchQuery, mediaTypes: ["album"], limit: 5)
                    results = res
                default:
                    let res = try await client.search(query: searchQuery, mediaTypes: ["track", "album", "artist"], limit: 10)
                    results = res
                }
                let didPlay = try await playFromSearchResults(results, mediaType: mediaType, artistFilter: artistFilter)

                if didPlay {
                    applySiriPlaybackOptions(shuffle: wantsShuffle, repeatMode: repeatMode)
                    completion(INPlayMediaIntentResponse(code: .success, userActivity: nil))
                } else {
                    print("[SiriIntentHandler] No playable results for '\(searchQuery)' (artists: \(results.artists.count), albums: \(results.albums.count), tracks: \(results.tracks.count), playlists: \(results.playlists.count))")
                    completion(INPlayMediaIntentResponse(code: .failure, userActivity: nil))
                }
            } catch {
                print("[SiriIntentHandler] Error handling intent: \(error)")
                completion(INPlayMediaIntentResponse(code: .failure, userActivity: nil))
            }
        }
    }

    // MARK: - Local Library Playback

    @MainActor
    private func playFromLibrary(query: String, mediaType: INMediaItemType, artistFilter: String?) async throws -> Bool {
        let lib = LibraryViewModel.shared

        // Try the requested type first, then fall through to others
        switch mediaType {
        case .artist:
            if let artist = bestMatch(query, in: lib.artists, name: \.name) {
                return try await playArtist(artist)
            }
        case .album:
            if let album = matchAlbum(query, artistFilter: artistFilter, albums: lib.albums) {
                let tracks = try await lib.loadAlbumTracks(album: album)
                PlayerManager.shared.playAlbum(tracks, startingAt: 0)
                return true
            }
        case .playlist:
            if let playlist = bestMatch(query, in: lib.playlists, name: \.name) {
                let tracks = try await lib.loadPlaylistTracks(playlist: playlist)
                PlayerManager.shared.playPlaylist(playlist, tracks: tracks, startingAt: 0)
                return true
            }
        case .song:
            if let track = matchTrack(query, artistFilter: artistFilter, tracks: lib.tracks) {
                PlayerManager.shared.playTrack(track, fromQueue: [track])
                return true
            }
        default:
            break
        }

        // Fall through: try artist -> album -> track -> playlist regardless of requested type
        if mediaType != .artist {
            if let artist = bestMatch(query, in: lib.artists, name: \.name) {
                return try await playArtist(artist)
            }
        }
        if mediaType != .album {
            if let album = matchAlbum(query, artistFilter: artistFilter, albums: lib.albums) {
                let tracks = try await lib.loadAlbumTracks(album: album)
                PlayerManager.shared.playAlbum(tracks, startingAt: 0)
                return true
            }
        }
        if mediaType != .song {
            if let track = matchTrack(query, artistFilter: artistFilter, tracks: lib.tracks) {
                PlayerManager.shared.playTrack(track, fromQueue: [track])
                return true
            }
        }
        if mediaType != .playlist {
            if let playlist = bestMatch(query, in: lib.playlists, name: \.name) {
                let tracks = try await lib.loadPlaylistTracks(playlist: playlist)
                PlayerManager.shared.playPlaylist(playlist, tracks: tracks, startingAt: 0)
                return true
            }
        }

        return false
    }

    private func matchTrack(_ query: String, artistFilter: String?, tracks: [Track]) -> Track? {
        // Rank all tracks by match quality, then apply optional artist filter
        let ranked = tracks
            .compactMap { t -> (Track, Int)? in
                let s = matchScore(name: t.name, query: query)
                return s > 0 ? (t, s) : nil
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        guard !ranked.isEmpty else { return nil }
        if let artist = artistFilter, !artist.isEmpty {
            let norm = normalize(artist)
            let stripped = stripArticles(norm)
            let filtered = ranked.filter {
                let n = normalize($0.artistNames)
                return n.contains(norm) || n.contains(stripped)
            }
            if !filtered.isEmpty { return filtered.first }
        }
        return ranked.first
    }

    private func matchAlbum(_ query: String, artistFilter: String?, albums: [Album]) -> Album? {
        let ranked = albums
            .compactMap { a -> (Album, Int)? in
                let s = matchScore(name: a.name, query: query)
                return s > 0 ? (a, s) : nil
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        guard !ranked.isEmpty else { return nil }
        if let artist = artistFilter, !artist.isEmpty {
            let norm = normalize(artist)
            let stripped = stripArticles(norm)
            let filtered = ranked.filter {
                let n = normalize($0.artistNames)
                return n.contains(norm) || n.contains(stripped)
            }
            if !filtered.isEmpty { return filtered.first }
        }
        return ranked.first
    }

    @MainActor
    private func playArtist(_ artist: Artist) async throws -> Bool {
        // Try direct track search first (1 call vs 2)
        let results = try await XonoraClient.shared.search(
            query: artist.name, mediaTypes: ["track"], limit: 20)
        let tracks = filterByArtist(tracks: results.tracks, artistName: artist.name)
        if !tracks.isEmpty {
            PlayerManager.shared.playTrack(tracks[0], fromQueue: tracks)
            return true
        }
        // Fallback: load artist discography
        let (albums, _) = try await LibraryViewModel.shared.loadArtistDetails(artist: artist)
        if let firstAlbum = albums.first {
            let albumTracks = try await LibraryViewModel.shared.loadAlbumTracks(album: firstAlbum)
            PlayerManager.shared.playAlbum(albumTracks, startingAt: 0)
            return true
        }
        return false
    }

    // MARK: - Server Search Playback

    @MainActor
    private func playFromSearchResults(
        _ results: (albums: [Album], artists: [Artist], tracks: [Track], playlists: [Playlist], audiobooks: [Audiobook], podcasts: [Podcast], radios: [Radio]),
        mediaType: INMediaItemType,
        artistFilter: String?
    ) async throws -> Bool {
        // Try requested type first
        switch mediaType {
        case .artist:
            if let artist = results.artists.first {
                if try await playArtist(artist) { return true }
            }
        case .album:
            let filtered = filterByArtist(albums: Array(results.albums.prefix(5)), artistName: artistFilter?.lowercased())
            if let album = filtered.first {
                let tracks = try await LibraryViewModel.shared.loadAlbumTracks(album: album)
                PlayerManager.shared.playAlbum(tracks, startingAt: 0)
                return true
            }
        case .playlist:
            if let playlist = results.playlists.first {
                let tracks = try await LibraryViewModel.shared.loadPlaylistTracks(playlist: playlist)
                PlayerManager.shared.playPlaylist(playlist, tracks: tracks, startingAt: 0)
                return true
            }
        case .song:
            let filtered = filterByArtist(tracks: Array(results.tracks.prefix(5)), artistName: artistFilter?.lowercased())
            if let track = filtered.first {
                PlayerManager.shared.playTrack(track, fromQueue: [track])
                return true
            }
        default:
            break
        }

        // Fall through to any category with results — prefer tracks over artists
        let filteredTracks = filterByArtist(tracks: Array(results.tracks.prefix(5)), artistName: artistFilter?.lowercased())
        if let track = filteredTracks.first {
            PlayerManager.shared.playTrack(track, fromQueue: [track])
            return true
        }
        if let album = results.albums.first {
            let tracks = try await LibraryViewModel.shared.loadAlbumTracks(album: album)
            PlayerManager.shared.playAlbum(tracks, startingAt: 0)
            return true
        }
        if let artist = results.artists.first {
            if try await playArtist(artist) { return true }
        }
        if let playlist = results.playlists.first {
            let tracks = try await LibraryViewModel.shared.loadPlaylistTracks(playlist: playlist)
            PlayerManager.shared.playPlaylist(playlist, tracks: tracks, startingAt: 0)
            return true
        }

        return false
    }

    // MARK: - Playback Options

    @MainActor
    private func applySiriPlaybackOptions(shuffle: Bool, repeatMode: INPlaybackRepeatMode) {
        let player = PlayerManager.shared

        // Apply shuffle if Siri requested it and current state differs
        if shuffle && !player.shuffleEnabled {
            player.toggleShuffle()
        } else if !shuffle && player.shuffleEnabled {
            player.toggleShuffle()
        }

        // Apply repeat mode
        switch repeatMode {
        case .one:
            while player.repeatMode != .one { player.cycleRepeatMode() }
        case .all:
            while player.repeatMode != .all { player.cycleRepeatMode() }
        case .none:
            while player.repeatMode != .off { player.cycleRepeatMode() }
        default:
            break // .unknown -- don't change
        }
    }

    // MARK: - Vocabulary

    static func updateSiriVocabulary(playlists: [Playlist], artists: [Artist], albums: [Album] = [], podcasts: [Podcast] = []) {
        let vocabulary = INVocabulary.shared()

        // Artists and playlists have dedicated speech recognition vocabulary types —
        // these teach Siri to recognise exact library names in speech.
        let playlistNames = NSOrderedSet(array: playlists.prefix(500).map { $0.name as NSString })
        vocabulary.setVocabularyStrings(playlistNames, of: .mediaPlaylistTitle)

        let artistNames = NSOrderedSet(array: artists.prefix(500).map { $0.name as NSString })
        vocabulary.setVocabularyStrings(artistNames, of: .mediaMusicArtistName)

        // Albums and podcasts also have dedicated vocabulary types — register them so Siri
        // can recognise uncommon album/show titles in speech without a language model miss.
        if !albums.isEmpty {
            let albumNames = NSOrderedSet(array: albums.prefix(500).map { $0.name as NSString })
            vocabulary.setVocabularyStrings(albumNames, of: .mediaAudiobookTitle)
        }
        if !podcasts.isEmpty {
            let podcastTitles = NSOrderedSet(array: podcasts.prefix(500).map { $0.name as NSString })
            vocabulary.setVocabularyStrings(podcastTitles, of: .mediaShowTitle)
        }

        print("[SiriIntentHandler] Updated Siri vocabulary: \(playlistNames.count) playlists, \(artistNames.count) artists, \(albums.prefix(500).count) albums, \(podcasts.prefix(500).count) podcasts")
    }
}
