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
    private var audiobooksCache: [Audiobook]?
    private var podcastsCache: [Podcast]?
    private var radiosCache: [Radio]?
    private var albumTracksCache: [String: [Track]] = [:] // albumId -> tracks
    private var playlistTracksCache: [String: [Track]] = [:] // playlistId -> tracks
    private var podcastEpisodesCache: [String: [PodcastEpisode]] = [:] // podcastId -> episodes
    private var artistAlbumsCache: [String: [Album]] = [:] // artistId -> albums
    private var artistTracksCache: [String: [Track]] = [:] // artistId -> tracks
    private var audiobookChaptersCache: [String: [Track]] = [:] // audiobookId -> chapters

    // LRU tracking for secondary caches
    private var albumTracksAccessOrder: [String] = []
    private var playlistTracksAccessOrder: [String] = []
    private var podcastEpisodesAccessOrder: [String] = []
    private var artistAlbumsAccessOrder: [String] = []
    private var artistTracksAccessOrder: [String] = []
    private var audiobookChaptersAccessOrder: [String] = []
    private let maxSecondaryEntries = 20

    // Cache timestamps
    private var albumsCacheTime: Date?
    private var artistsCacheTime: Date?
    private var playlistsCacheTime: Date?
    private var tracksCacheTime: Date?
    private var audiobooksCacheTime: Date?
    private var podcastsCacheTime: Date?
    private var radiosCacheTime: Date?

    // Cache expiry (1 hour for library data)
    private let cacheExpiry: TimeInterval = 3600

    private init() {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        cacheDirectory = caches.appendingPathComponent("MetadataCache", isDirectory: true)

        // Create cache directory if needed
        try? fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Albums

    func getAlbums() async -> [Album]? {
        if albumsCache == nil {
            if let albums: [Album] = await loadFromDiskAsync([Album].self, filename: "albums.json") {
                albumsCache = albums
                albumsCacheTime = diskFileDate(filename: "albums.json") ?? Date()
            }
        }

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
    
    // MARK: - Podcasts

    func getPodcasts() async -> [Podcast]? {
        if podcastsCache == nil {
            if let podcasts: [Podcast] = await loadFromDiskAsync([Podcast].self, filename: "podcasts.json") {
                podcastsCache = podcasts
                podcastsCacheTime = diskFileDate(filename: "podcasts.json") ?? Date()
            }
        }

        guard let cache = podcastsCache,
              let cacheTime = podcastsCacheTime,
              Date().timeIntervalSince(cacheTime) < cacheExpiry else {
            return nil
        }
        return cache
    }

    func setPodcasts(_ podcasts: [Podcast]) {
        podcastsCache = podcasts
        podcastsCacheTime = Date()
        Task { await saveToDisk(podcasts, filename: "podcasts.json") }
    }
    
    // MARK: - Podcast Episodes

    func getPodcastEpisodes(podcastId: String) -> [PodcastEpisode]? {
        if let episodes = podcastEpisodesCache[podcastId] {
            touchAccessOrder(&podcastEpisodesAccessOrder, key: podcastId)
            return episodes
        }
        return nil
    }

    func setPodcastEpisodes(_ episodes: [PodcastEpisode], podcastId: String) {
        podcastEpisodesCache[podcastId] = episodes
        evictIfNeeded(cache: &podcastEpisodesCache, accessOrder: &podcastEpisodesAccessOrder, key: podcastId)
        // Usually don't persist episodes list to disk to save space/complexity, or could do:
        // Task { await saveToDisk(episodes, filename: "podcast_\(podcastId).json") }
    }

    // MARK: - Radios

    func getRadios() async -> [Radio]? {
        if radiosCache == nil {
            if let radios: [Radio] = await loadFromDiskAsync([Radio].self, filename: "radios.json") {
                radiosCache = radios
                radiosCacheTime = diskFileDate(filename: "radios.json") ?? Date()
            }
        }

        guard let cache = radiosCache,
              let cacheTime = radiosCacheTime,
              Date().timeIntervalSince(cacheTime) < cacheExpiry else {
            return nil
        }
        return cache
    }

    func setRadios(_ radios: [Radio]) {
        radiosCache = radios
        radiosCacheTime = Date()
        Task { await saveToDisk(radios, filename: "radios.json") }
    }

    // MARK: - Artists

    // MARK: - Artists

    func getArtists() async -> [Artist]? {
        if artistsCache == nil {
            if let artists: [Artist] = await loadFromDiskAsync([Artist].self, filename: "artists.json") {
                artistsCache = artists
                artistsCacheTime = diskFileDate(filename: "artists.json") ?? Date()
            }
        }

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

    func getPlaylists() async -> [Playlist]? {
        if playlistsCache == nil {
            if let playlists: [Playlist] = await loadFromDiskAsync([Playlist].self, filename: "playlists.json") {
                playlistsCache = playlists
                playlistsCacheTime = diskFileDate(filename: "playlists.json") ?? Date()
            }
        }

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

    func getTracks() async -> [Track]? {
        if tracksCache == nil {
            if let tracks: [Track] = await loadFromDiskAsync([Track].self, filename: "tracks.json") {
                tracksCache = tracks
                tracksCacheTime = diskFileDate(filename: "tracks.json") ?? Date()
            }
        }

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

    // MARK: - Audiobooks

    func getAudiobooks() async -> [Audiobook]? {
        if audiobooksCache == nil {
            if let audiobooks: [Audiobook] = await loadFromDiskAsync([Audiobook].self, filename: "audiobooks.json") {
                audiobooksCache = audiobooks
                audiobooksCacheTime = diskFileDate(filename: "audiobooks.json") ?? Date()
            }
        }

        guard let cache = audiobooksCache,
              let cacheTime = audiobooksCacheTime,
              Date().timeIntervalSince(cacheTime) < cacheExpiry else {
            return nil
        }
        return cache
    }

    func setAudiobooks(_ audiobooks: [Audiobook]) {
        audiobooksCache = audiobooks
        audiobooksCacheTime = Date()
        Task { await saveToDisk(audiobooks, filename: "audiobooks.json") }
    }

    // MARK: - Album Tracks

    func getAlbumTracks(albumId: String) -> [Track]? {
        if let tracks = albumTracksCache[albumId] {
            touchAccessOrder(&albumTracksAccessOrder, key: albumId)
            return tracks
        }
        return nil
    }

    func setAlbumTracks(_ tracks: [Track], albumId: String) {
        albumTracksCache[albumId] = tracks
        evictIfNeeded(cache: &albumTracksCache, accessOrder: &albumTracksAccessOrder, key: albumId)
        Task { await saveToDisk(tracks, filename: "album_\(albumId).json") }
    }

    // MARK: - Playlist Tracks

    func getPlaylistTracks(playlistId: String) -> [Track]? {
        if let tracks = playlistTracksCache[playlistId] {
            touchAccessOrder(&playlistTracksAccessOrder, key: playlistId)
            return tracks
        }
        return nil
    }

    func setPlaylistTracks(_ tracks: [Track], playlistId: String) {
        playlistTracksCache[playlistId] = tracks
        evictIfNeeded(cache: &playlistTracksCache, accessOrder: &playlistTracksAccessOrder, key: playlistId)
        Task { await saveToDisk(tracks, filename: "playlist_\(playlistId).json") }
    }

    func invalidatePlaylistTracks(playlistId: String) {
        playlistTracksCache.removeValue(forKey: playlistId)
        playlistTracksAccessOrder.removeAll { $0 == playlistId }
        let filename = "playlist_\(playlistId).json"
        let fileURL = cacheDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: fileURL)
    }

    // MARK: - Audiobook Chapters

    func getAudiobookChapters(audiobookId: String) -> [Track]? {
        if let chapters = audiobookChaptersCache[audiobookId] {
            touchAccessOrder(&audiobookChaptersAccessOrder, key: audiobookId)
            return chapters
        }
        return nil
    }

    func setAudiobookChapters(_ chapters: [Track], audiobookId: String) {
        audiobookChaptersCache[audiobookId] = chapters
        evictIfNeeded(cache: &audiobookChaptersCache, accessOrder: &audiobookChaptersAccessOrder, key: audiobookId)
        Task { await saveToDisk(chapters, filename: "audiobook_\(audiobookId).json") }
    }

    // MARK: - Artist Details

    func getArtistAlbums(artistId: String) -> [Album]? {
        if let albums = artistAlbumsCache[artistId] {
            touchAccessOrder(&artistAlbumsAccessOrder, key: artistId)
            return albums
        }
        return nil
    }

    func setArtistAlbums(_ albums: [Album], artistId: String) {
        artistAlbumsCache[artistId] = albums
        evictIfNeeded(cache: &artistAlbumsCache, accessOrder: &artistAlbumsAccessOrder, key: artistId)
        Task { await saveToDisk(albums, filename: "artist_albums_\(artistId).json") }
    }

    func getArtistTracks(artistId: String) -> [Track]? {
        if let tracks = artistTracksCache[artistId] {
            touchAccessOrder(&artistTracksAccessOrder, key: artistId)
            return tracks
        }
        return nil
    }

    func setArtistTracks(_ tracks: [Track], artistId: String) {
        artistTracksCache[artistId] = tracks
        evictIfNeeded(cache: &artistTracksCache, accessOrder: &artistTracksAccessOrder, key: artistId)
        Task { await saveToDisk(tracks, filename: "artist_tracks_\(artistId).json") }
    }

    // MARK: - Memory Management

    /// Release in-memory library data while preserving timestamps and disk cache
    /// This eliminates duplicate storage when LibraryViewModel has the same data loaded
    func releaseInMemoryLibraryData() {
        albumsCache = nil
        artistsCache = nil
        playlistsCache = nil
        tracksCache = nil
        audiobooksCache = nil
        podcastsCache = nil
        radiosCache = nil
        // Keep timestamps intact so expiry checking still works
        // Keep secondary caches (album tracks, playlist tracks, etc.) as they aren't duplicated
    }

    // MARK: - LRU Helpers

    /// Update access order for LRU tracking
    private func touchAccessOrder(_ accessOrder: inout [String], key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    /// Evict oldest entries if cache exceeds max size
    private func evictIfNeeded<T>(cache: inout [String: T], accessOrder: inout [String], key: String) {
        touchAccessOrder(&accessOrder, key: key)

        while accessOrder.count > maxSecondaryEntries {
            let oldestKey = accessOrder.removeFirst()
            cache.removeValue(forKey: oldestKey)
        }
    }

    // MARK: - Favorites Update

    func updateTrackFavorite(uri: String, favorite: Bool) {
        // Disk-first approach: load from disk if not in memory, mutate, save to disk, don't retain

        // Update global tracks cache
        var tracks = tracksCache ?? loadFromDisk([Track].self, filename: "tracks.json")
        if var unwrappedTracks = tracks, let index = unwrappedTracks.firstIndex(where: { $0.uri == uri }) {
            unwrappedTracks[index].favorite = favorite
            tracksCache = nil // Don't retain in memory
            tracksCacheTime = Date() // Update timestamp for expiry
            Task { await saveToDisk(unwrappedTracks, filename: "tracks.json") }
        }

        // Update album tracks cache
        for (albumId, var tracks) in albumTracksCache {
            if let index = tracks.firstIndex(where: { $0.uri == uri }) {
                tracks[index].favorite = favorite
                albumTracksCache[albumId] = tracks
                Task { await saveToDisk(tracks, filename: "album_\(albumId).json") }
            }
        }

        // Update playlist tracks cache
        for (playlistId, var tracks) in playlistTracksCache {
            if let index = tracks.firstIndex(where: { $0.uri == uri }) {
                tracks[index].favorite = favorite
                playlistTracksCache[playlistId] = tracks
                Task { await saveToDisk(tracks, filename: "playlist_\(playlistId).json") }
            }
        }

        // Update artist tracks cache
        for (artistId, var tracks) in artistTracksCache {
            if let index = tracks.firstIndex(where: { $0.uri == uri }) {
                tracks[index].favorite = favorite
                artistTracksCache[artistId] = tracks
                Task { await saveToDisk(tracks, filename: "artist_tracks_\(artistId).json") }
            }
        }
    }
    
    func updateItemFavorite<T: Identifiable>(item: T, favorite: Bool, uri: String) where T: Codable {
        // Disk-first approach: load from disk if not in memory, mutate, save to disk, don't retain

        if item is Album {
            var albums = albumsCache ?? loadFromDisk([Album].self, filename: "albums.json")
            if var unwrappedAlbums = albums, let index = unwrappedAlbums.firstIndex(where: { $0.uri == uri }) {
                unwrappedAlbums[index].favorite = favorite
                albumsCache = nil // Don't retain in memory
                albumsCacheTime = Date() // Update timestamp for expiry
                Task { await saveToDisk(unwrappedAlbums, filename: "albums.json") }
            }
        } else if item is Artist {
            var artists = artistsCache ?? loadFromDisk([Artist].self, filename: "artists.json")
            if var unwrappedArtists = artists, let index = unwrappedArtists.firstIndex(where: { $0.uri == uri }) {
                unwrappedArtists[index].favorite = favorite
                artistsCache = nil // Don't retain in memory
                artistsCacheTime = Date() // Update timestamp for expiry
                Task { await saveToDisk(unwrappedArtists, filename: "artists.json") }
            }
        } else if item is Playlist {
            var playlists = playlistsCache ?? loadFromDisk([Playlist].self, filename: "playlists.json")
            if var unwrappedPlaylists = playlists, let index = unwrappedPlaylists.firstIndex(where: { $0.uri == uri }) {
                unwrappedPlaylists[index].favorite = favorite
                playlistsCache = nil // Don't retain in memory
                playlistsCacheTime = Date() // Update timestamp for expiry
                Task { await saveToDisk(unwrappedPlaylists, filename: "playlists.json") }
            }
        } else if item is Audiobook {
            var audiobooks = audiobooksCache ?? loadFromDisk([Audiobook].self, filename: "audiobooks.json")
            if var unwrappedAudiobooks = audiobooks, let index = unwrappedAudiobooks.firstIndex(where: { $0.uri == uri }) {
                unwrappedAudiobooks[index].favorite = favorite
                audiobooksCache = nil // Don't retain in memory
                audiobooksCacheTime = Date() // Update timestamp for expiry
                Task { await saveToDisk(unwrappedAudiobooks, filename: "audiobooks.json") }
            }
        }
    }

    func clearCache() {
        albumsCache = nil
        artistsCache = nil
        playlistsCache = nil
        tracksCache = nil
        audiobooksCache = nil
        podcastsCache = nil
        radiosCache = nil
        albumTracksCache.removeAll()
        playlistTracksCache.removeAll()
        podcastEpisodesCache.removeAll()
        artistAlbumsCache.removeAll()
        artistTracksCache.removeAll()
        audiobookChaptersCache.removeAll()

        // Clear LRU access order arrays
        albumTracksAccessOrder.removeAll()
        playlistTracksAccessOrder.removeAll()
        podcastEpisodesAccessOrder.removeAll()
        artistAlbumsAccessOrder.removeAll()
        artistTracksAccessOrder.removeAll()
        audiobookChaptersAccessOrder.removeAll()

        albumsCacheTime = nil
        artistsCacheTime = nil
        playlistsCacheTime = nil
        tracksCacheTime = nil
        audiobooksCacheTime = nil
        podcastsCacheTime = nil
        radiosCacheTime = nil

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
        audiobooksCacheTime = nil
        podcastsCacheTime = nil
        radiosCacheTime = nil
    }

    // MARK: - Disk Persistence

    func getDiskUsage() -> Int {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        return files.reduce(0) { total, url in
            let resources = try? url.resourceValues(forKeys: [.fileSizeKey])
            return total + (resources?.fileSize ?? 0)
        }
    }

    private func saveToDisk<T: Encodable>(_ data: T, filename: String) async {
        let fileURL = cacheDirectory.appendingPathComponent(filename)
        do {
            let encoded = try encoder.encode(data)
            try encoded.write(to: fileURL)
        } catch {
            print("[MetadataCache] Failed to save \(filename): \(error)")
        }
    }

    /// Returns the modification date of a cached file, or nil if it doesn't exist.
    private func diskFileDate(filename: String) -> Date? {
        let fileURL = cacheDirectory.appendingPathComponent(filename)
        let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path)
        return attrs?[.modificationDate] as? Date
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

    // Async version that performs disk I/O on background thread to avoid blocking actor
    nonisolated private func loadFromDiskAsync<T: Decodable>(_ type: T.Type, filename: String) async -> T? {
        return await Task.detached(priority: .userInitiated) { [weak self] () -> T? in
            guard let self = self else { return nil }
            let fileURL = self.cacheDirectory.appendingPathComponent(filename)
            guard self.fileManager.fileExists(atPath: fileURL.path) else { return nil }

            do {
                let data = try Data(contentsOf: fileURL)
                return try self.decoder.decode(type, from: data)
            } catch {
                print("[MetadataCache] Failed to load \(filename): \(error)")
                return nil
            }
        }.value
    }
}
