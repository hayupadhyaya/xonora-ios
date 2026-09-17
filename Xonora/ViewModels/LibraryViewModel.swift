import Foundation
import Combine

@MainActor
class LibraryViewModel: ObservableObject {
    static let shared = LibraryViewModel()

    @Published var albums: [Album] = []
    @Published var artists: [Artist] = []
    @Published var playlists: [Playlist] = []
    @Published var tracks: [Track] = []
    @Published var audiobooks: [Audiobook] = []
    @Published var podcasts: [Podcast] = []
    @Published var radios: [Radio] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchQuery = ""
    @Published var searchResults: (albums: [Album], artists: [Artist], tracks: [Track], playlists: [Playlist], audiobooks: [Audiobook], podcasts: [Podcast], radios: [Radio]) = ([], [], [], [], [], [], [])
    @Published var isSearching = false
    @Published var recentlyPlayed: [PlaybackHistoryItem] = []
    @Published var isLoadingRecent = false
    private var isNetworkFetching = false

    private let client = XonoraClient.shared
    private let cache = MetadataCache.shared
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?

    init() {
        setupSearchDebounce()
    }

    private func setupSearchDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self = self else { return }
                if query.isEmpty {
                    Task {
                        self.searchResults = ([], [], [], [], [], [], [])
                        self.isSearching = false
                    }
                } else {
                    Task {
                        await self.performSearch(query)
                    }
                }
            }
            .store(in: &cancellables)
    }

    func loadLibrary(forceRefresh: Bool = false) async {
        // 1. Load from cache first (Stale-while-revalidate)
        if !forceRefresh {
            let cachedAlbums = await cache.getAlbums()
            let cachedArtists = await cache.getArtists()
            let cachedPlaylists = await cache.getPlaylists()
            let cachedTracks = await cache.getTracks()
            let cachedAudiobooks = await cache.getAudiobooks()
            let cachedPodcasts = await cache.getPodcasts()
            let cachedRadios = await cache.getRadios()

            if let albums = cachedAlbums, let artists = cachedArtists,
               let playlists = cachedPlaylists, let tracks = cachedTracks,
               let audiobooks = cachedAudiobooks {
                self.albums = albums
                self.artists = artists
                self.playlists = playlists
                self.tracks = tracks
                self.audiobooks = audiobooks
                if let podcasts = cachedPodcasts { self.podcasts = podcasts }
                if let radios = cachedRadios { self.radios = radios }
                print("[LibraryViewModel] Loaded from cache")

                await cache.releaseInMemoryLibraryData()
            }
        }

        // 2. Fetch from server
        guard !isNetworkFetching else { return }
        isNetworkFetching = true

        if albums.isEmpty {
            isLoading = true
        }

        errorMessage = nil

        // Server returns items pre-sorted by sort_name - no client-side sorting needed
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                guard let fetched = try? await self.client.fetchAlbums() else { return }
                if self.hasDataChanged(current: self.albums, new: fetched) {
                    self.albums = fetched
                    let cache = self.cache
                    Task.detached(priority: .utility) { await cache.setAlbums(fetched) }
                }
                self.isLoading = false
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                guard let fetched = try? await self.client.fetchArtists() else { return }
                if self.hasDataChanged(current: self.artists, new: fetched) {
                    self.artists = fetched
                    let cache = self.cache
                    Task.detached(priority: .utility) { await cache.setArtists(fetched) }
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                guard let fetched = try? await self.client.fetchPlaylists() else { return }
                if self.hasDataChanged(current: self.playlists, new: fetched) {
                    self.playlists = fetched
                    let cache = self.cache
                    Task.detached(priority: .utility) { await cache.setPlaylists(fetched) }
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                guard let fetched = try? await self.client.fetchTracks() else { return }
                if self.hasDataChanged(current: self.tracks, new: fetched) {
                    self.tracks = fetched
                    let cache = self.cache
                    Task.detached(priority: .utility) { await cache.setTracks(fetched) }
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                guard let fetched = try? await self.client.fetchAudiobooks() else { return }
                if self.hasDataChanged(current: self.audiobooks, new: fetched) {
                    self.audiobooks = fetched
                    let cache = self.cache
                    Task.detached(priority: .utility) { await cache.setAudiobooks(fetched) }
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                guard let fetched = try? await self.client.fetchPodcasts() else { return }
                if self.hasDataChanged(current: self.podcasts, new: fetched) {
                    self.podcasts = fetched
                    let cache = self.cache
                    Task.detached(priority: .utility) { await cache.setPodcasts(fetched) }
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                guard let fetched = try? await self.client.fetchRadios() else { return }
                if self.hasDataChanged(current: self.radios, new: fetched) {
                    self.radios = fetched
                    let cache = self.cache
                    Task.detached(priority: .utility) { await cache.setRadios(fetched) }
                }
            }
        }

        if albums.isEmpty {
            errorMessage = "Failed to load library."
        }
        isLoading = false
        isNetworkFetching = false

        // Update Siri vocabulary with current library names
        let currentPlaylists = playlists
        let currentArtists = artists
        let currentAlbums = albums
        let currentPodcasts = podcasts
        Task.detached(priority: .utility) {
            SiriIntentHandler.updateSiriVocabulary(
                playlists: currentPlaylists,
                artists: currentArtists,
                albums: currentAlbums,
                podcasts: currentPodcasts
            )
        }
    }
    
    func loadPodcastEpisodes(podcast: Podcast) async throws -> [PodcastEpisode] {
        if let cached = await cache.getPodcastEpisodes(podcastId: podcast.itemId) {
            return cached
        }
        
        let episodes = try await client.fetchPodcastEpisodes(podcastId: podcast.itemId, provider: podcast.provider)
        await cache.setPodcastEpisodes(episodes, podcastId: podcast.itemId)
        return episodes
    }

    func toggleFavorite<T: Identifiable & Codable>(item: T) async {
        var uri: String = ""
        var currentFavorite: Bool = false

        if let album = item as? Album {
            uri = album.uri
            currentFavorite = album.favorite ?? false
        } else if let artist = item as? Artist {
            uri = artist.uri
            currentFavorite = artist.favorite ?? false
        } else if let track = item as? Track {
            uri = track.uri
            currentFavorite = track.favorite ?? false
        } else if let playlist = item as? Playlist {
            uri = playlist.uri
            currentFavorite = playlist.favorite ?? false
        } else if let audiobook = item as? Audiobook {
            uri = audiobook.uri
            currentFavorite = audiobook.favorite ?? false
        }

        guard !uri.isEmpty else { return }
        let newFavorite = !currentFavorite

        // Optimistically update local state
        updateLocalFavorite(uri: uri, favorite: newFavorite)

        do {
            try await client.toggleItemFavorite(uri: uri, favorite: newFavorite)
            // Update cache after successful server update
            if item is Track {
                await cache.updateTrackFavorite(uri: uri, favorite: newFavorite)
            } else {
                await cache.updateItemFavorite(item: item, favorite: newFavorite, uri: uri)
            }
        } catch {
            print("[LibraryViewModel] Failed to toggle favorite: \(error)")
            // Revert on error
            updateLocalFavorite(uri: uri, favorite: currentFavorite)
            if item is Track {
                await cache.updateTrackFavorite(uri: uri, favorite: currentFavorite)
            } else {
                await cache.updateItemFavorite(item: item, favorite: currentFavorite, uri: uri)
            }
        }
    }

    private func updateLocalFavorite(uri: String, favorite: Bool) {
        if let index = albums.firstIndex(where: { $0.uri == uri }) {
            albums[index].favorite = favorite
        } else if let index = artists.firstIndex(where: { $0.uri == uri }) {
            artists[index].favorite = favorite
        } else if let index = playlists.firstIndex(where: { $0.uri == uri }) {
            playlists[index].favorite = favorite
        } else if let index = audiobooks.firstIndex(where: { $0.uri == uri }) {
            audiobooks[index].favorite = favorite
        }
        
        // Update global tracks list
        if let index = tracks.firstIndex(where: { $0.uri == uri }) {
            tracks[index].favorite = favorite
        }

        // Also update search results if applicable
        if let index = searchResults.albums.firstIndex(where: { $0.uri == uri }) {
            searchResults.albums[index].favorite = favorite
        }
        if let index = searchResults.artists.firstIndex(where: { $0.uri == uri }) {
            searchResults.artists[index].favorite = favorite
        }
        if let index = searchResults.tracks.firstIndex(where: { $0.uri == uri }) {
            searchResults.tracks[index].favorite = favorite
        }
        if let index = searchResults.playlists.firstIndex(where: { $0.uri == uri }) {
            searchResults.playlists[index].favorite = favorite
        }
    }

    func loadAlbumTracks(album: Album) async throws -> [Track] {
        // Try cache first
        if let cached = await cache.getAlbumTracks(albumId: album.itemId) {
            // Prefetch lyrics in background for cached tracks
            prefetchLyricsForTracks(cached)
            return cached
        }

        let tracks = try await client.fetchAlbumTracks(albumId: album.itemId, provider: album.provider)

        // Cache the tracks
        await cache.setAlbumTracks(tracks, albumId: album.itemId)

        // Prefetch lyrics in background
        prefetchLyricsForTracks(tracks)

        return tracks
    }

    func loadPlaylistTracks(playlist: Playlist) async throws -> [Track] {
        // Try cache first
        if let cached = await cache.getPlaylistTracks(playlistId: playlist.itemId) {
            // Prefetch lyrics in background for cached tracks
            prefetchLyricsForTracks(cached)
            return cached
        }

        let tracks = try await client.fetchPlaylistTracks(playlistId: playlist.itemId, provider: playlist.provider)

        // Cache the tracks
        await cache.setPlaylistTracks(tracks, playlistId: playlist.itemId)

        // Prefetch lyrics in background
        prefetchLyricsForTracks(tracks)

        return tracks
    }

    // MARK: - Lyrics Prefetching

    /// Prefetch lyrics for tracks when user opens album/playlist detail view
    /// This ensures lyrics are ready before playback starts
    func prefetchLyricsForTracks(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }

        // Prefetch first 10 tracks (covers most albums)
        let tracksToPrefetch = Array(tracks.prefix(10))

        print("[LibraryViewModel] Prefetching lyrics for \(tracksToPrefetch.count) tracks")

        Task(priority: .background) {
            for track in tracksToPrefetch {
                try? await LyricsManager.shared.getLyrics(for: track)
            }
        }
    }

    func loadArtistDetails(artist: Artist) async throws -> (albums: [Album], tracks: [Track]) {
        // Try cache first
        let cachedAlbums = await cache.getArtistAlbums(artistId: artist.itemId)
        let cachedTracks = await cache.getArtistTracks(artistId: artist.itemId)

        if let albums = cachedAlbums, let tracks = cachedTracks {
            return (albums, tracks)
        }

        async let albumsTask = client.fetchArtistAlbums(artistId: artist.itemId, provider: artist.provider)
        async let tracksTask = client.fetchArtistTracks(artistId: artist.itemId, provider: artist.provider)

        let (fetchedAlbums, fetchedTracks) = try await (albumsTask, tracksTask)

        // Cache the results
        await cache.setArtistAlbums(fetchedAlbums, artistId: artist.itemId)
        await cache.setArtistTracks(fetchedTracks, artistId: artist.itemId)

        return (fetchedAlbums, fetchedTracks)
    }

    private func performSearch(_ query: String) async {
        searchTask?.cancel()

        searchTask = Task { @MainActor in
            isSearching = true

            // First, perform instant client-side filtering on already-loaded library data
            // This gives immediate feedback to the user
            let localResults = filterLocalLibrary(query: query)

            if !Task.isCancelled {
                searchResults = localResults
                // Keep isSearching = true to show we're still fetching more results
            }

            // Then search the server for comprehensive results (including non-library items)
            do {
                let serverResults = try await client.search(query: query)
                if !Task.isCancelled {
                    // Merge local and server results, removing duplicates
                    searchResults = mergeSearchResults(local: localResults, server: serverResults)
                    isSearching = false
                }
            } catch {
                if !Task.isCancelled {
                    print("Server search error: \(error)")
                    // Keep local results even if server search fails
                    isSearching = false
                }
            }
        }
    }

    /// Merges local and server search results, removing duplicates (server results take precedence)
    private func mergeSearchResults(
        local: (albums: [Album], artists: [Artist], tracks: [Track], playlists: [Playlist], audiobooks: [Audiobook], podcasts: [Podcast], radios: [Radio]),
        server: (albums: [Album], artists: [Artist], tracks: [Track], playlists: [Playlist], audiobooks: [Audiobook], podcasts: [Podcast], radios: [Radio])
    ) -> (albums: [Album], artists: [Artist], tracks: [Track], playlists: [Playlist], audiobooks: [Audiobook], podcasts: [Podcast], radios: [Radio]) {

        // For each category, use server results and add local results that aren't in server results
        let mergedAlbums = mergeArray(server: server.albums, local: local.albums)
        let mergedArtists = mergeArray(server: server.artists, local: local.artists)
        let mergedTracks = mergeArray(server: server.tracks, local: local.tracks)
        let mergedPlaylists = mergeArray(server: server.playlists, local: local.playlists)
        let mergedAudiobooks = mergeArray(server: server.audiobooks, local: local.audiobooks)
        let mergedPodcasts = mergeArray(server: server.podcasts, local: local.podcasts)
        let mergedRadios = mergeArray(server: server.radios, local: local.radios)

        return (mergedAlbums, mergedArtists, mergedTracks, mergedPlaylists, mergedAudiobooks, mergedPodcasts, mergedRadios)
    }

    /// Helper to merge arrays, server results first, then local results not in server
    private func mergeArray<T: Identifiable>(server: [T], local: [T]) -> [T] {
        let serverIds = Set(server.map { $0.id })
        let uniqueLocal = local.filter { !serverIds.contains($0.id) }
        return server + uniqueLocal
    }

    /// Fast client-side filtering of already-loaded library data
    private func filterLocalLibrary(query: String) -> (albums: [Album], artists: [Artist], tracks: [Track], playlists: [Playlist], audiobooks: [Audiobook], podcasts: [Podcast], radios: [Radio]) {
        let lowercaseQuery = query.lowercased()

        let filteredAlbums = albums.filter { album in
            album.name.lowercased().contains(lowercaseQuery) ||
            album.artistNames.lowercased().contains(lowercaseQuery)
        }

        let filteredArtists = artists.filter { artist in
            artist.name.lowercased().contains(lowercaseQuery)
        }

        let filteredTracks = tracks.filter { track in
            track.name.lowercased().contains(lowercaseQuery) ||
            track.artistNames.lowercased().contains(lowercaseQuery) ||
            (track.album?.name.lowercased().contains(lowercaseQuery) ?? false)
        }

        let filteredPlaylists = playlists.filter { playlist in
            playlist.name.lowercased().contains(lowercaseQuery)
        }

        let filteredAudiobooks = audiobooks.filter { audiobook in
            let authorNames = audiobook.authorNames ?? ""
            let narratorNames = audiobook.narratorNames ?? ""
            return audiobook.name.lowercased().contains(lowercaseQuery) ||
                authorNames.lowercased().contains(lowercaseQuery) ||
                narratorNames.lowercased().contains(lowercaseQuery)
        }

        let filteredPodcasts = podcasts.filter { podcast in
            let publisher = podcast.publisher ?? ""
            return podcast.name.lowercased().contains(lowercaseQuery) ||
                publisher.lowercased().contains(lowercaseQuery)
        }

        let filteredRadios = radios.filter { radio in
            radio.name.lowercased().contains(lowercaseQuery)
        }

        return (filteredAlbums, filteredArtists, filteredTracks, filteredPlaylists, filteredAudiobooks, filteredPodcasts, filteredRadios)
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = ([], [], [], [], [], [], [])
        isSearching = false
    }

    func refreshLibrary() async {
        await cache.invalidateLibrary()
        await loadLibrary(forceRefresh: true)
    }

    func clearCache() async {
        await cache.clearCache()
    }

    // MARK: - Recently Played

    func loadRecentlyPlayed() async {
        guard !isLoadingRecent else { return }
        isLoadingRecent = true

        // Use existing PlaybackHistoryManager which tracks client-side recently played
        self.recentlyPlayed = await PlaybackHistoryManager.shared.getRecentlyPlayed()
        isLoadingRecent = false
    }

    func refreshRecentlyPlayed() async {
        await loadRecentlyPlayed()
    }

    // MARK: - Playlist Management

    func createPlaylist(name: String) async -> Playlist? {
        do {
            let playlist = try await client.createPlaylist(name: name)
            // Refresh playlists list
            self.playlists.append(playlist)
            self.playlists.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            await cache.setPlaylists(self.playlists)
            
            return playlist
        } catch {
            print("[LibraryViewModel] Failed to create playlist: \(error)")
            return nil
        }
    }

    func addTrackToPlaylist(_ track: Track, playlist: Playlist) async {
        do {
            try await client.addToPlaylist(
                playlistId: playlist.itemId,
                provider: playlist.provider,
                trackUris: [track.uri]
            )
            // Invalidate playlist tracks cache
            await cache.invalidatePlaylistTracks(playlistId: playlist.itemId)
        } catch {
            print("[LibraryViewModel] Failed to add to playlist: \(error)")
        }
    }

    // MARK: - Sorted Accessors

    func sorted<T>(items: [T], by option: SortOption, name: (T) -> String, itemId: (T) -> String) -> [T] {
        switch option {
        case .nameAsc:
            return items.sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
        case .nameDesc:
            return items.sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedDescending }
        case .dateAddedNewest:
            return items.sorted { idCompare(itemId($0), itemId($1)) == .orderedDescending }
        case .dateAddedOldest:
            return items.sorted { idCompare(itemId($0), itemId($1)) == .orderedAscending }
        }
    }

    private func idCompare(_ a: String, _ b: String) -> ComparisonResult {
        if let ia = Int(a), let ib = Int(b) {
            return ia < ib ? .orderedAscending : (ia > ib ? .orderedDescending : .orderedSame)
        }
        return a.compare(b)
    }

    func sortedAlbums(option: SortOption) -> [Album] {
        sorted(items: albums, by: option, name: { $0.name }, itemId: { $0.itemId })
    }

    func sortedPlaylists(option: SortOption) -> [Playlist] {
        sorted(items: playlists, by: option, name: { $0.name }, itemId: { $0.itemId })
    }

    func sortedTracks(option: SortOption) -> [Track] {
        sorted(items: tracks, by: option, name: { $0.name }, itemId: { $0.itemId })
    }

    func sortedArtists(option: SortOption) -> [Artist] {
        sorted(items: artists, by: option, name: { $0.name }, itemId: { $0.itemId })
    }

    func sortedAudiobooks(option: SortOption) -> [Audiobook] {
        sorted(items: audiobooks, by: option, name: { $0.name }, itemId: { $0.itemId })
    }

    func sortedPodcasts(option: SortOption) -> [Podcast] {
        sorted(items: podcasts, by: option, name: { $0.name }, itemId: { $0.itemId })
    }

    func sortedRadios(option: SortOption) -> [Radio] {
        sorted(items: radios, by: option, name: { $0.name }, itemId: { $0.itemId })
    }

    // MARK: - Data Comparison

    /// Compares current data with new data to detect changes
    /// Returns true if data has changed (items added, removed, or modified)
    private func hasDataChanged<T: Identifiable & Hashable>(current: [T], new: [T]) -> Bool {
        // Quick check: different count means definitely changed
        guard current.count == new.count else { return true }

        // If both empty, no change
        guard !current.isEmpty else { return false }

        // Quick spot check: compare first and last items by ID
        // This catches most changes without expensive Set creation
        if current.first?.id != new.first?.id || current.last?.id != new.last?.id {
            return true
        }

        // For same count and same first/last, assume no meaningful change
        // (avoid expensive Set creation and hashing)
        return false
    }
}
