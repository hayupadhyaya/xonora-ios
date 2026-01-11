import Foundation
import Combine

@MainActor
class LibraryViewModel: ObservableObject {
    static let shared = LibraryViewModel()

    @Published var albums: [Album] = []
    @Published var artists: [Artist] = []
    @Published var playlists: [Playlist] = []
    @Published var tracks: [Track] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchQuery = ""
    @Published var searchResults: (albums: [Album], artists: [Artist], tracks: [Track]) = ([], [], [])
    @Published var isSearching = false

    private let client = XonoraClient.shared
    private let cache = MetadataCache.shared
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private let searchQueue = DispatchQueue(label: "com.musicassistant.search", qos: .userInitiated)
    private let loadQueue = DispatchQueue(label: "com.musicassistant.library", qos: .utility)

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
                        self.searchResults = ([], [], [])
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

            if let albums = cachedAlbums, let artists = cachedArtists,
               let playlists = cachedPlaylists, let tracks = cachedTracks {
                self.albums = albums
                self.artists = artists
                self.playlists = playlists
                self.tracks = tracks
                print("[LibraryViewModel] Loaded from cache")
            }
        }

        // 2. Fetch from server
        // Only show fullscreen loader if we have no data
        if albums.isEmpty {
            isLoading = true
        }

        errorMessage = nil

        do {
            async let albumsTask = client.fetchAlbums()
            async let artistsTask = client.fetchArtists()
            async let playlistsTask = client.fetchPlaylists()
            async let tracksTask = client.fetchTracks()

            let (fetchedAlbums, fetchedArtists, fetchedPlaylists, fetchedTracks) = try await (albumsTask, artistsTask, playlistsTask, tracksTask)

            let sortedAlbums = fetchedAlbums.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let sortedArtists = fetchedArtists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let sortedPlaylists = fetchedPlaylists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let sortedTracks = fetchedTracks.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            // Update UI with fresh data
            self.albums = sortedAlbums
            self.artists = sortedArtists
            self.playlists = sortedPlaylists
            self.tracks = sortedTracks
            isLoading = false

            // Update Cache
            await cache.setAlbums(sortedAlbums)
            await cache.setArtists(sortedArtists)
            await cache.setPlaylists(sortedPlaylists)
            await cache.setTracks(sortedTracks)

            print("[LibraryViewModel] Fetched and cached library")
        } catch {
            print("[LibraryViewModel] Network fetch failed: \(error)")
            if albums.isEmpty {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func toggleFavorite<T: Identifiable>(item: T) async {
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
        }
        
        guard !uri.isEmpty else { return }
        let newFavorite = !currentFavorite
        
        // Optimistically update local state
        updateLocalFavorite(uri: uri, favorite: newFavorite)
        
        do {
            try await client.toggleItemFavorite(uri: uri, favorite: newFavorite)
            // Update cache after successful server update
            if let album = item as? Album { await cache.setAlbums(albums) }
            else if let artist = item as? Artist { await cache.setArtists(artists) }
            else if let playlist = item as? Playlist { await cache.setPlaylists(playlists) }
        } catch {
            print("[LibraryViewModel] Failed to toggle favorite: \(error)")
            // Revert on error
            updateLocalFavorite(uri: uri, favorite: currentFavorite)
        }
    }

    private func updateLocalFavorite(uri: String, favorite: Bool) {
        if let index = albums.firstIndex(where: { $0.uri == uri }) {
            albums[index].favorite = favorite
        } else if let index = artists.firstIndex(where: { $0.uri == uri }) {
            artists[index].favorite = favorite
        } else if let index = playlists.firstIndex(where: { $0.uri == uri }) {
            playlists[index].favorite = favorite
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
    }

    func loadAlbumTracks(album: Album) async throws -> [Track] {
        // Try cache first
        if let cached = await cache.getAlbumTracks(albumId: album.itemId) {
            return cached
        }

        let tracks = try await client.fetchAlbumTracks(albumId: album.itemId, provider: album.provider)

        // Cache the tracks
        await cache.setAlbumTracks(tracks, albumId: album.itemId)

        return tracks
    }

    func loadPlaylistTracks(playlist: Playlist) async throws -> [Track] {
        // Try cache first
        if let cached = await cache.getPlaylistTracks(playlistId: playlist.itemId) {
            return cached
        }

        let tracks = try await client.fetchPlaylistTracks(playlistId: playlist.itemId, provider: playlist.provider)

        // Cache the tracks
        await cache.setPlaylistTracks(tracks, playlistId: playlist.itemId)

        return tracks
    }

    private func performSearch(_ query: String) async {
        searchTask?.cancel()

        searchTask = Task {
            isSearching = true

            do {
                let results = try await client.search(query: query)
                if !Task.isCancelled {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                if !Task.isCancelled {
                    print("Search error: \(error)")
                    isSearching = false
                }
            }
        }
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = ([], [], [])
        isSearching = false
    }

    func refreshLibrary() async {
        await cache.invalidateLibrary()
        await loadLibrary(forceRefresh: true)
    }

    func clearCache() async {
        await cache.clearAll()
    }
}
