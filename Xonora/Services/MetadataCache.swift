import Foundation

/// Local metadata cache to reduce server requests and improve performance
actor MetadataCache {
    static let shared = MetadataCache()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // In-memory cache for fast access
    private var albumsCache: [Album]?
    private var artistsCache: [Artist]?
    private var playlistsCache: [Playlist]?
    private var tracksCache: [Track]?
    private var albumTracksCache: [String: [Track]] = [:] // albumId -> tracks
    private var playlistTracksCache: [String: [Track]] = [:] // playlistId -> tracks

    // Cache timestamps
    private var albumsCacheTime: Date?
    private var artistsCacheTime: Date?
    private var playlistsCacheTime: Date?
    private var tracksCacheTime: Date?

    // Cache expiry (1 hour for library data)
    private let cacheExpiry: TimeInterval = 3600

    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("MetadataCache", isDirectory: true)

        // Create cache directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Load caches from disk on init
        Task {
            await loadCachesFromDisk()
        }
    }

    // MARK: - Albums

    func getAlbums() -> [Album]? {
        guard let cache = albumsCache,
              let cacheTime = albumsCacheTime,
              Date().timeIntervalSince(cacheTime) < cacheExpiry else {
            return nil
        }
        return cache
    }

    func setAlbums(_ albums: [Album]) {
        albumsCache = albums
        albumsCacheTime = Date()
        Task { await saveToDisk(albums, filename: "albums.json") }
    }

    // MARK: - Artists

    func getArtists() -> [Artist]? {
        guard let cache = artistsCache,
              let cacheTime = artistsCacheTime,
              Date().timeIntervalSince(cacheTime) < cacheExpiry else {
            return nil
        }
        return cache
    }

    func setArtists(_ artists: [Artist]) {
        artistsCache = artists
        artistsCacheTime = Date()
        Task { await saveToDisk(artists, filename: "artists.json") }
    }

    // MARK: - Playlists

    func getPlaylists() -> [Playlist]? {
        guard let cache = playlistsCache,
              let cacheTime = playlistsCacheTime,
              Date().timeIntervalSince(cacheTime) < cacheExpiry else {
            return nil
        }
        return cache
    }

    func setPlaylists(_ playlists: [Playlist]) {
        playlistsCache = playlists
        playlistsCacheTime = Date()
        Task { await saveToDisk(playlists, filename: "playlists.json") }
    }

    // MARK: - Tracks

    func getTracks() -> [Track]? {
        guard let cache = tracksCache,
              let cacheTime = tracksCacheTime,
              Date().timeIntervalSince(cacheTime) < cacheExpiry else {
            return nil
        }
        return cache
    }

    func setTracks(_ tracks: [Track]) {
        tracksCache = tracks
        tracksCacheTime = Date()
        Task { await saveToDisk(tracks, filename: "tracks.json") }
    }

    // MARK: - Album Tracks

    func getAlbumTracks(albumId: String) -> [Track]? {
        return albumTracksCache[albumId]
    }

    func setAlbumTracks(_ tracks: [Track], albumId: String) {
        albumTracksCache[albumId] = tracks
        Task { await saveToDisk(tracks, filename: "album_\(albumId).json") }
    }

    // MARK: - Playlist Tracks

    func getPlaylistTracks(playlistId: String) -> [Track]? {
        return playlistTracksCache[playlistId]
    }

    func setPlaylistTracks(_ tracks: [Track], playlistId: String) {
        playlistTracksCache[playlistId] = tracks
        Task { await saveToDisk(tracks, filename: "playlist_\(playlistId).json") }
    }

    // MARK: - Clear Cache

    func clearAll() {
        albumsCache = nil
        artistsCache = nil
        playlistsCache = nil
        tracksCache = nil
        albumTracksCache.removeAll()
        playlistTracksCache.removeAll()
        albumsCacheTime = nil
        artistsCacheTime = nil
        playlistsCacheTime = nil
        tracksCacheTime = nil

        // Clear disk cache
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func invalidateLibrary() {
        // Force refresh on next request
        albumsCacheTime = nil
        artistsCacheTime = nil
        playlistsCacheTime = nil
        tracksCacheTime = nil
    }

    // MARK: - Disk Persistence

    private func saveToDisk<T: Encodable>(_ data: T, filename: String) async {
        let fileURL = cacheDirectory.appendingPathComponent(filename)
        do {
            let encoded = try encoder.encode(data)
            try encoded.write(to: fileURL)
        } catch {
            print("[MetadataCache] Failed to save \(filename): \(error)")
        }
    }

    private func loadFromDisk<T: Decodable>(_ type: T.Type, filename: String) -> T? {
        let fileURL = cacheDirectory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(type, from: data)
        } catch {
            print("[MetadataCache] Failed to load \(filename): \(error)")
            return nil
        }
    }

    private func loadCachesFromDisk() {
        // Load library caches
        if let albums: [Album] = loadFromDisk([Album].self, filename: "albums.json") {
            albumsCache = albums
            albumsCacheTime = Date()
        }

        if let artists: [Artist] = loadFromDisk([Artist].self, filename: "artists.json") {
            artistsCache = artists
            artistsCacheTime = Date()
        }

        if let playlists: [Playlist] = loadFromDisk([Playlist].self, filename: "playlists.json") {
            playlistsCache = playlists
            playlistsCacheTime = Date()
        }

        if let tracks: [Track] = loadFromDisk([Track].self, filename: "tracks.json") {
            tracksCache = tracks
            tracksCacheTime = Date()
        }

        print("[MetadataCache] Loaded caches from disk")
    }
}
