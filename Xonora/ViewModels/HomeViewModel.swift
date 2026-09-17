import Foundation
import SwiftUI
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    static let shared = HomeViewModel()

    @Published var categoryItems: [CategorySection] = []
    @Published var recommendationSections: [RecommendationSection] = []
    @Published var recentlyPlayedItems: [PlaybackHistoryItem] = []
    @Published var continueListeningItems: [PlaybackHistoryItem] = []
    @Published var favoriteItems: [PlaybackHistoryItem] = []
    @Published var isLoading = false

    /// All available sections for use in CustomizeHomeView (combines categories + recommendations)
    @Published var allSections: [DynamicHomeSection] = []
    
    struct DynamicHomeSection: Identifiable, Equatable {
        let id: String
        let name: String
        let icon: String
        let isCategory: Bool // True for category sections, false for recommendation sections
    }

    struct CategorySection: Identifiable {
        let id = UUID()
        let category: Category
        let items: [PlaybackHistoryItem]
        let mostRecentTimestamp: Date

        enum Category: String {
            case music = "Music"
            case audiobooks = "Audiobooks"
            case podcasts = "Podcasts"
            case radio = "Radio"

            var icon: String {
                switch self {
                case .music: return "music.note"
                case .audiobooks: return "book.fill"
                case .podcasts: return "mic.fill"
                case .radio: return "antenna.radiowaves.left.and.right"
                }
            }
        }
    }
    
    struct RecommendationSection: Identifiable {
        let id = UUID()
        let name: String
        let subtitle: String?
        let items: [PlaybackHistoryItem]
    }

    private var connectionTask: Task<Void, Never>?

    private init() {
        // Observe connection state to load data when connected
        connectionTask = Task { [weak self] in
            // Initial load
            if case .connected = XonoraClient.shared.connectionState {
                await self?.loadData()
            }

            for await state in await XonoraClient.shared.$connectionState.values {
                guard !Task.isCancelled else { break }
                if case .connected = state {
                    // Slight delay to ensure connection is fully established
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await self?.loadData()
                }
            }
        }
    }

    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        // Fetch recently played from server
        let allHistory: [PlaybackHistoryItem]
        do {
            allHistory = try await XonoraClient.shared.fetchRecentlyPlayed(limit: 100)
        } catch {
            print("[HomeViewModel] Error fetching recently played: \(error)")
            allHistory = []
        }
        
        // Ensure library is loaded in LibraryViewModel (shared data)
        if LibraryViewModel.shared.albums.isEmpty {
            await LibraryViewModel.shared.loadLibrary()
        }

        // Create lightweight image-URL-only dictionaries off the main thread
        let albums = LibraryViewModel.shared.albums
        let tracks = LibraryViewModel.shared.tracks
        let audiobooks = LibraryViewModel.shared.audiobooks
        let playlists = LibraryViewModel.shared.playlists
        let podcasts = LibraryViewModel.shared.podcasts

        let (albumsDict, tracksDict, audiobooksDict, playlistsDict, podcastsDict) = await Task.detached(priority: .userInitiated) {
            let a = Dictionary(uniqueKeysWithValues: albums.map { ($0.itemId, $0.imageUrl) })
            let t = Dictionary(uniqueKeysWithValues: tracks.map { ($0.itemId, $0.imageUrl) })
            let ab = Dictionary(uniqueKeysWithValues: audiobooks.map { ($0.itemId, $0.imageUrl) })
            let p = Dictionary(uniqueKeysWithValues: playlists.map { ($0.itemId, $0.imageUrl) })
            let pd = Dictionary(uniqueKeysWithValues: podcasts.map { ($0.itemId, $0.imageUrl) })
            return (a, t, ab, p, pd)
        }.value
        
        // Populate artwork URLs using lightweight string lookups
        let historyWithArtwork = allHistory.map { item -> PlaybackHistoryItem in
            var imageUrl = item.imageUrl

            switch item.contentType {
            case .album:
                imageUrl = albumsDict[item.itemId] ?? imageUrl
            case .track:
                imageUrl = tracksDict[item.itemId] ?? imageUrl
            case .audiobook:
                imageUrl = audiobooksDict[item.itemId] ?? imageUrl
            case .playlist:
                imageUrl = playlistsDict[item.itemId] ?? imageUrl
            case .podcast:
                imageUrl = podcastsDict[item.itemId] ?? imageUrl
            default:
                break
            }
            
            return PlaybackHistoryItem(
                id: item.id,
                timestamp: item.timestamp,
                contentType: item.contentType,
                itemId: item.itemId,
                itemName: item.itemName,
                itemUri: item.itemUri,
                artistName: item.artistName,
                imageUrl: imageUrl,
                progress: item.progress,
                duration: item.duration
            )
        }
        
        // Store the recently played items for explicit use in Home/CarPlay
        recentlyPlayedItems = Array(historyWithArtwork.prefix(20))

        // Collect favorite items from all library sources
        var favorites: [PlaybackHistoryItem] = []

        // Favorites from tracks
        for track in LibraryViewModel.shared.tracks where track.favorite == true {
            favorites.append(PlaybackHistoryItem(
                timestamp: Date(),
                contentType: .track,
                itemId: track.itemId,
                itemName: track.name,
                itemUri: track.uri,
                artistName: track.artistNames,
                imageUrl: track.imageUrl,
                duration: track.duration
            ))
        }

        // Favorites from albums
        for album in LibraryViewModel.shared.albums where album.favorite == true {
            favorites.append(PlaybackHistoryItem(
                timestamp: Date(),
                contentType: .album,
                itemId: album.itemId,
                itemName: album.name,
                itemUri: album.uri,
                artistName: album.artistNames,
                imageUrl: album.imageUrl,
                duration: nil
            ))
        }

        // Favorites from playlists
        for playlist in LibraryViewModel.shared.playlists where playlist.favorite == true {
            favorites.append(PlaybackHistoryItem(
                timestamp: Date(),
                contentType: .playlist,
                itemId: playlist.itemId,
                itemName: playlist.name,
                itemUri: playlist.uri,
                artistName: "",
                imageUrl: playlist.imageUrl,
                duration: nil
            ))
        }

        // Favorites from audiobooks
        for audiobook in LibraryViewModel.shared.audiobooks where audiobook.favorite == true {
            favorites.append(PlaybackHistoryItem(
                timestamp: Date(),
                contentType: .audiobook,
                itemId: audiobook.itemId,
                itemName: audiobook.name,
                itemUri: audiobook.uri,
                artistName: audiobook.authorNames,
                imageUrl: audiobook.imageUrl,
                duration: audiobook.duration
            ))
        }

        // Sort by name and store
        favoriteItems = favorites.sorted { ($0.itemName).localizedCaseInsensitiveCompare($1.itemName) == .orderedAscending }

        // Group items by category
        var musicItems: [PlaybackHistoryItem] = []
        var audiobookItems: [PlaybackHistoryItem] = []
        var podcastItems: [PlaybackHistoryItem] = []
        var radioItems: [PlaybackHistoryItem] = []

        for item in historyWithArtwork {
            switch item.contentType {
            case .album, .track, .playlist:
                musicItems.append(item)
            case .audiobook:
                audiobookItems.append(item)
            case .podcast:
                podcastItems.append(item)
            case .radio:
                radioItems.append(item)
            }
        }
        
        // Helper to convert library items to history format
        func backfillItems<T: Identifiable>(currentItems: [PlaybackHistoryItem], libraryItems: [T], limit: Int = 10, mapper: (T) -> PlaybackHistoryItem) -> [PlaybackHistoryItem] {
            if currentItems.count >= limit {
                return currentItems
            }
            
            var items = currentItems
            let existingIds = Set(items.map { $0.itemId })
            let needed = limit - items.count
            
            // Randomly sample items to keep it dynamic, or just take mostly recent additions if array is sorted
            // Since we don't know sort order of libraryItems here (usually alphabetical), shuffling is good for "discovery"
            // But for "Recently Added" feel, we might want to assume they came in some order. 
            // Let's just shuffle a subset to avoid sorting huge lists
            let candidates = libraryItems.prefix(100).shuffled()
            
            for item in candidates {
                let historyItem = mapper(item)
                if !existingIds.contains(historyItem.itemId) {
                    items.append(historyItem)
                    if items.count >= limit { break }
                }
            }
            
            return items
        }
        
        // Backfill Music (Albums) from LibraryViewModel cache
        if musicItems.count < 10 {
            musicItems = backfillItems(currentItems: musicItems, libraryItems: LibraryViewModel.shared.albums) { album in
                PlaybackHistoryItem(
                    timestamp: Date.distantPast,
                    contentType: .album,
                    itemId: album.itemId,
                    itemName: album.name,
                    itemUri: album.uri,
                    artistName: album.artistNames,
                    imageUrl: album.imageUrl,
                    duration: nil
                )
            }
        }
        
        // Backfill Audiobooks
        if audiobookItems.count < 10 {
            audiobookItems = backfillItems(currentItems: audiobookItems, libraryItems: LibraryViewModel.shared.audiobooks) { book in
                PlaybackHistoryItem(
                    timestamp: Date.distantPast,
                    contentType: .audiobook,
                    itemId: book.itemId,
                    itemName: book.name,
                    itemUri: book.uri,
                    artistName: book.authorNames,
                    imageUrl: book.imageUrl,
                    duration: book.duration
                )
            }
        }
        
        // Backfill Podcasts
        if podcastItems.count < 10 {
            podcastItems = backfillItems(currentItems: podcastItems, libraryItems: LibraryViewModel.shared.podcasts) { podcast in
                PlaybackHistoryItem(
                    timestamp: Date.distantPast,
                    contentType: .podcast,
                    itemId: podcast.itemId,
                    itemName: podcast.name,
                    itemUri: podcast.uri,
                    artistName: podcast.publisher ?? "",
                    imageUrl: podcast.imageUrl,
                    duration: nil
                )
            }
        }

        // Create category sections with most recent timestamp
        var sections: [CategorySection] = []

        if !musicItems.isEmpty {
            sections.append(CategorySection(
                category: .music,
                items: musicItems,
                mostRecentTimestamp: musicItems.first?.timestamp ?? Date.distantPast
            ))
        }

        if !audiobookItems.isEmpty {
            sections.append(CategorySection(
                category: .audiobooks,
                items: audiobookItems,
                mostRecentTimestamp: audiobookItems.first?.timestamp ?? Date.distantPast
            ))
        }

        if !podcastItems.isEmpty {
            sections.append(CategorySection(
                category: .podcasts,
                items: podcastItems,
                mostRecentTimestamp: podcastItems.first?.timestamp ?? Date.distantPast
            ))
        }

        if !radioItems.isEmpty {
            sections.append(CategorySection(
                category: .radio,
                items: radioItems,
                mostRecentTimestamp: radioItems.first?.timestamp ?? Date.distantPast
            ))
        }

        // Sort sections by most recent timestamp (most recent first)
        categoryItems = sections.sorted { $0.mostRecentTimestamp > $1.mostRecentTimestamp }
        
        // Load recommendations
        do {
            let recommendationFolders = try await XonoraClient.shared.fetchRecommendations()
            var recSections: [RecommendationSection] = []
            
            for folder in recommendationFolders {
                // Filter out redundant "In Progress" section (usually duplicates "Continue Listening")
                guard let name = folder["name"] as? String,
                      name != "In Progress",
                      let items = folder["items"] as? [[String: Any]] else {
                    continue
                }
                
                let subtitle = folder["subtitle"] as? String
                
                // Convert items to PlaybackHistoryItem format
                var historyItems: [PlaybackHistoryItem] = []
                for item in items.prefix(20) { // Limit to 20 items per section
                    guard let itemId = item["item_id"] as? String,
                          let itemName = item["name"] as? String,
                          let uri = item["uri"] as? String,
                          let mediaTypeStr = item["media_type"] as? String else {
                        continue
                    }
                    
                    // Determine content type
                    let contentType: PlaybackHistoryItem.ContentType
                    switch mediaTypeStr {
                    case "album": contentType = .album
                    case "track": contentType = .track
                    case "playlist": contentType = .playlist
                    case "audiobook": contentType = .audiobook
                    case "podcast": contentType = .podcast
                    case "radio": contentType = .radio
                    default: continue
                    }
                    
                    let artistName = (item["artists"] as? [[String: Any]])?.first?["name"] as? String
                    
                    // Get image URL - handle metadata structure properly
                    var imageUrl: String?
                    if let image = item["image"] as? [String: Any] {
                        // Image can have path and provider
                        let path = image["path"] as? String ?? ""
                        let provider = image["provider"] as? String ?? ""
                        
                        if path.hasPrefix("http://") || path.hasPrefix("https://") {
                            imageUrl = path
                        } else if !provider.isEmpty && !path.isEmpty {
                            imageUrl = "\(provider)://\(path)"
                        } else if !path.isEmpty {
                            imageUrl = path
                        }
                    }
                    
                    // Fallback: try metadata.images like other library items
                    if imageUrl == nil, let metadata = item["metadata"] as? [String: Any],
                       let images = metadata["images"] as? [[String: Any]],
                       let firstImage = images.first {
                        let path = firstImage["path"] as? String ?? ""
                        let provider = firstImage["provider"] as? String ?? ""
                        
                        if path.hasPrefix("http://") || path.hasPrefix("https://") {
                            imageUrl = path
                        } else if !provider.isEmpty && !path.isEmpty {
                            imageUrl = "\(provider)://\(path)"
                        } else if !path.isEmpty {
                            imageUrl = path
                        }
                    }
                    
                    // Special handling for Radio/Podcast if still missing
                    if imageUrl == nil {
                         if contentType == .podcast || contentType == .radio {
                            // Try to construct URL from item_id/provider if available
                            if let provider = item["provider"] as? String {
                                // This is a best-effort guess, often the provider+id is enough for the image proxy
                                // but we ideally want the real image path.
                                // If the item has no image in history, the client might try to fetch details later.
                            }
                         }
                    }
                    
                    // Parse progress (duration and resume position)
                    var duration: TimeInterval?
                    if let dur = item["duration"] as? Int, dur > 0 {
                        duration = TimeInterval(dur)
                    }
                    
                    var progress: TimeInterval?
                    if let resumePos = item["resume_position_ms"] as? Int {
                        // resume_position_ms is in milliseconds
                        progress = TimeInterval(resumePos) / 1000.0
                    } else if let fullyPlayed = item["fully_played"] as? Bool, fullyPlayed {
                        progress = duration // Mark as complete
                    }
                    
                    let historyItem = PlaybackHistoryItem(
                        timestamp: Date(),
                        contentType: contentType,
                        itemId: itemId,
                        itemName: itemName,
                        itemUri: uri,
                        artistName: artistName,
                        imageUrl: imageUrl,
                        progress: progress,
                        duration: duration
                    )
                    historyItems.append(historyItem)
                }
                
                if !historyItems.isEmpty {
                    recSections.append(RecommendationSection(
                        name: name,
                        subtitle: subtitle,
                        items: historyItems
                    ))
                }
            }
            
            recommendationSections = recSections
        } catch {
            print("[HomeViewModel] Error loading recommendations: \(error)")
            recommendationSections = []
        }
        // Removed Recently Added tracks fetch logic per user request

        // Load Continue Listening (in-progress audiobooks/podcasts)
        do {
            continueListeningItems = try await XonoraClient.shared.fetchInProgressItems(limit: 20)
        } catch {
            print("[HomeViewModel] Error loading in-progress items: \(error)")
            continueListeningItems = []
        }

        // Update allSections for customization
        var dynamicSectionsList: [DynamicHomeSection] = []

        // Add static sections first (if they have content)
        if !recentlyPlayedItems.isEmpty {
            dynamicSectionsList.append(DynamicHomeSection(
                id: "recentlyPlayed",
                name: "Recently Played",
                icon: "clock.fill",
                isCategory: false
            ))
        }

        if !continueListeningItems.isEmpty {
            dynamicSectionsList.append(DynamicHomeSection(
                id: "continueListening",
                name: "Continue Listening",
                icon: "play.circle.fill",
                isCategory: false
            ))
        }

        // Add dynamic categories
        for category in categoryItems {
            dynamicSectionsList.append(DynamicHomeSection(
                id: "category_\(category.category.rawValue)",
                name: category.category.rawValue,
                icon: category.category.icon,
                isCategory: true
            ))
        }

        // Add recommendation sections
        for rec in recommendationSections {
            dynamicSectionsList.append(DynamicHomeSection(
                id: "rec_\(rec.name)",
                name: rec.name,
                icon: "sparkles",
                isCategory: false
            ))
        }

        self.allSections = dynamicSectionsList
        
        // Ensure new sections are added to user preferences order automatically
        // This fixes the issue where new installs show an empty home screen because dynamic sections weren't in the saved order
        Task { @MainActor in
            var currentOrder = UserPreferences.shared.homeSectionOrder
            var hasChanges = false
            
            for section in dynamicSectionsList {
                if !currentOrder.contains(section.id) {
                    currentOrder.append(section.id)
                    hasChanges = true
                }
            }
            
            if hasChanges {
                UserPreferences.shared.homeSectionOrder = currentOrder
            }
        }
    }

    func refresh() async {
        await loadData()
    }

    func playItem(item: PlaybackHistoryItem) {
        Task {
            do {
                switch item.contentType {
                case .album:
                    // Fetch album tracks
                    guard let album = try await fetchAlbum(for: item) else { return }
                    let tracks = try await XonoraClient.shared.fetchAlbumTracks(
                        albumId: album.itemId,
                        provider: album.provider
                    )
                    PlayerManager.shared.playAlbum(tracks, startingAt: 0)
                    
                case .audiobook:
                    // Fetch audiobook and resume at progress
                    guard let audiobook = try await fetchAudiobook(for: item) else { return }
                    PlayerManager.shared.playAudiobook(audiobook, startingProgress: item.progress)
                    
                case .podcast:
                    // Create a temporary track from the history item to play it
                    // This works for episodes that appear in history
                    let track = Track(
                        itemId: item.itemId,
                        provider: item.itemUri.components(separatedBy: "://").first ?? "unknown",
                        name: item.itemName,
                        version: nil,
                        duration: item.duration ?? 0,
                        trackNumber: nil,
                        discNumber: nil,
                        uri: item.itemUri,
                        artists: item.artistName.map { [ArtistReference(itemId: nil, provider: nil, name: $0)] } ?? [],
                        album: nil,
                        metadata: item.imageUrl.map { MediaItemMetadata(images: [MediaItemImage(type: "thumb", path: $0, provider: "")]) },
                        providerMappings: nil,
                        image: nil
                    )
                    PlayerManager.shared.playTrack(track, fromQueue: [track], sourceName: "Podcasts")
                    
                    if let progress = item.progress {
                        PlayerManager.shared.seek(to: progress)
                    }
                    
                case .playlist:
                    // Fetch playlist tracks
                    guard let playlist = try await fetchPlaylist(for: item) else { return }
                    let tracks = try await XonoraClient.shared.fetchPlaylistTracks(
                        playlistId: playlist.itemId,
                        provider: playlist.provider
                    )
                    PlayerManager.shared.playPlaylist(playlist, tracks: tracks, startingAt: 0)
                    
                case .track:
                    // Try to find track in library first
                    if let track = try await fetchTrack(for: item) {
                        PlayerManager.shared.playTrack(track, fromQueue: [track], sourceName: "Recent")
                    } else {
                        // Track not in library (e.g., from YouTube Music history)
                        // Create a track from the history item
                        let track = Track(
                            itemId: item.itemId,
                            provider: item.itemUri.components(separatedBy: "://").first ?? "unknown",
                            name: item.itemName,
                            version: nil,
                            duration: item.duration ?? 0,
                            trackNumber: nil,
                            discNumber: nil,
                            uri: item.itemUri,
                            artists: item.artistName.map { [ArtistReference(itemId: nil, provider: nil, name: $0)] } ?? [],
                            album: nil,
                            metadata: item.imageUrl.map { MediaItemMetadata(images: [MediaItemImage(type: "thumb", path: $0, provider: "")]) },
                            providerMappings: nil,
                            image: nil
                        )
                        PlayerManager.shared.playTrack(track, fromQueue: [track], sourceName: "Recent")
                    }
                    
                case .radio:
                    // Radio playback - just play the station
                    if let radio = try await fetchRadio(for: item) {
                        // Map Radio to Track for playback
                        let track = Track(
                            itemId: radio.itemId,
                            provider: radio.provider,
                            name: radio.name,
                            version: nil,
                            duration: 0,
                            trackNumber: nil,
                            discNumber: nil,
                            uri: radio.uri,
                            artists: nil,
                            album: nil,
                            metadata: radio.metadata,
                            providerMappings: nil,
                            image: radio.image
                        )
                        PlayerManager.shared.playTrack(track, fromQueue: [track], sourceName: "Radio")
                    }
                }
            } catch {
                print("[HomeViewModel] Error playing item: \(error)")
            }
        }
    }
    
    // MARK: - Helper methods to fetch items
    
    private func fetchAlbum(for item: PlaybackHistoryItem) async throws -> Album? {
        // Try library cache first
        if let album = LibraryViewModel.shared.albums.first(where: { $0.itemId == item.itemId || $0.uri == item.itemUri }) {
            return album
        }
        
        // Parse provider from URI if possible (format: provider://item_id)
        let parts = item.itemUri.components(separatedBy: "://")
        if parts.count >= 2 {
            let provider = parts[0]
            // Try explicit fetch
            do {
                return try await XonoraClient.shared.fetchAlbum(itemId: item.itemId, provider: provider)
            } catch {
                print("[HomeViewModel] Failed to fetch album: \(error)")
            }
        }
        return nil
    }
    
    private func fetchAudiobook(for item: PlaybackHistoryItem) async throws -> Audiobook? {
        // Try library cache first
        if let audiobook = LibraryViewModel.shared.audiobooks.first(where: { $0.itemId == item.itemId || $0.uri == item.itemUri }) {
            return audiobook
        }
        
        let parts = item.itemUri.components(separatedBy: "://")
        if parts.count >= 2 {
            let provider = parts[0]
            do {
                return try await XonoraClient.shared.fetchAudiobook(itemId: item.itemId, provider: provider)
            } catch {
                print("[HomeViewModel] Failed to fetch audiobook: \(error)")
            }
        }
        return nil
    }
    
    private func fetchPlaylist(for item: PlaybackHistoryItem) async throws -> Playlist? {
        // Try library cache first
        if let playlist = LibraryViewModel.shared.playlists.first(where: { $0.itemId == item.itemId || $0.uri == item.itemUri }) {
            return playlist
        }
        
        let parts = item.itemUri.components(separatedBy: "://")
        if parts.count >= 2 {
            let provider = parts[0]
            do {
                return try await XonoraClient.shared.fetchPlaylist(itemId: item.itemId, provider: provider)
            } catch {
                print("[HomeViewModel] Failed to fetch playlist: \(error)")
            }
        }
        return nil
    }
    
    private func fetchTrack(for item: PlaybackHistoryItem) async throws -> Track? {
        // Search LibraryViewModel.shared.tracks instead of fetching from server
        return LibraryViewModel.shared.tracks.first { $0.itemId == item.itemId || $0.uri == item.itemUri }
    }
    
    private func fetchPodcast(for item: PlaybackHistoryItem) async throws -> Podcast? {
        // Try library cache logic if needed, or straight to server
        // (LibraryViewModel doesn't currently expose full podcasts list easily? It has 'podcasts')
        if let podcast = LibraryViewModel.shared.podcasts.first(where: { $0.itemId == item.itemId || $0.uri == item.itemUri }) {
            return podcast
        }
        
        let parts = item.itemUri.components(separatedBy: "://")
        if parts.count >= 2 {
            let provider = parts[0]
            do {
                return try await XonoraClient.shared.fetchPodcast(itemId: item.itemId, provider: provider)
            } catch {
                print("[HomeViewModel] Failed to fetch podcast: \(error)")
            }
        }
        return nil
    }
    
    private func fetchRadio(for item: PlaybackHistoryItem) async throws -> Radio? {
        // Try library cache
        if let radio = LibraryViewModel.shared.radios.first(where: { $0.itemId == item.itemId || $0.uri == item.itemUri }) {
            return radio
        }
        
        let parts = item.itemUri.components(separatedBy: "://")
        if parts.count >= 2 {
            let provider = parts[0]
            do {
                return try await XonoraClient.shared.fetchRadio(itemId: item.itemId, provider: provider)
            } catch {
                print("[HomeViewModel] Failed to fetch radio: \(error)")
            }
        }
        return nil
    }
    
    // MARK: - Navigation Links

    #if os(iOS)
    @ViewBuilder
    func navigationLinkForItem(_ item: PlaybackHistoryItem) -> some View {
        switch item.contentType {
        case .album:
            // Find album in library and navigate to detail view
            if let album = LibraryViewModel.shared.albums.first(where: { $0.itemId == item.itemId }) {
                NavigationLink(destination: AlbumDetailView(album: album)) {
                    HistoryCardItem(item: item)
                }
                .buttonStyle(.plain)
            } else {
                // Fallback: fetch and navigate
                if let provider = item.itemUri.components(separatedBy: "://").first {
                    NavigationLink(destination: LazyAlbumDetailView(itemId: item.itemId, provider: provider, placeholder: item)) {
                        HistoryCardItem(item: item)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Safety fallback if provider parsing fails
                    Button {
                        self.playItem(item: item)
                    } label: {
                        HistoryCardItem(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            
        case .playlist:
            // Find playlist in library and navigate to detail view
            if let playlist = LibraryViewModel.shared.playlists.first(where: { $0.itemId == item.itemId }) {
                NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                    HistoryCardItem(item: item)
                }
                .buttonStyle(.plain)
            } else {
                // Fallback: fetch and navigate
                if let provider = item.itemUri.components(separatedBy: "://").first {
                    NavigationLink(destination: LazyPlaylistDetailView(itemId: item.itemId, provider: provider, placeholder: item)) {
                        HistoryCardItem(item: item)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        self.playItem(item: item)
                    } label: {
                        HistoryCardItem(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            
        case .audiobook:
            // Find audiobook in library and navigate to detail view
            if let audiobook = LibraryViewModel.shared.audiobooks.first(where: { $0.itemId == item.itemId }) {
                NavigationLink(destination: AudiobookDetailView(audiobook: audiobook)) {
                    HistoryCardItem(item: item)
                }
                .buttonStyle(.plain)
            } else {
                // Fallback: fetch and navigate
                if let provider = item.itemUri.components(separatedBy: "://").first {
                    NavigationLink(destination: LazyAudiobookDetailView(itemId: item.itemId, provider: provider, placeholder: item)) {
                        HistoryCardItem(item: item)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        self.playItem(item: item)
                    } label: {
                        HistoryCardItem(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            
        case .podcast:
             // Find podcast in library and navigate to detail view
             if let podcast = LibraryViewModel.shared.podcasts.first(where: { $0.itemId == item.itemId }) {
                 NavigationLink(destination: PodcastDetailView(podcast: podcast)) {
                     HistoryCardItem(item: item)
                 }
                 .buttonStyle(.plain)
             } else {
                 // Fallback: fetch and navigate
                 if let provider = item.itemUri.components(separatedBy: "://").first {
                     NavigationLink(destination: LazyPodcastDetailView(itemId: item.itemId, provider: provider, placeholder: item)) {
                         HistoryCardItem(item: item)
                     }
                     .buttonStyle(.plain)
                 } else {
                     Button {
                         self.playItem(item: item)
                     } label: {
                         HistoryCardItem(item: item)
                     }
                     .buttonStyle(.plain)
                 }
             }
            
        default:
            // For tracks, radio - use playItem
            Button {
                self.playItem(item: item)
            } label: {
                HistoryCardItem(item: item)
            }
            .buttonStyle(.plain)
        }
    }
    #else
    @ViewBuilder
    func navigationLinkForItem(_ item: PlaybackHistoryItem) -> some View {
        Button {
            self.playItem(item: item)
        } label: {
            Text(item.itemName)
        }
        .buttonStyle(.plain)
    }
    #endif
}
