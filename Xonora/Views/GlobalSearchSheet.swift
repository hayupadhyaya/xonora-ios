import SwiftUI

struct GlobalSearchSheet: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @EnvironmentObject var globalNav: GlobalNavigationViewModel
    @Environment(BarVisibilityManager.self) private var barManager

    @State private var recentSearches: [String] = []

    var body: some View {
        ZStack {
            NavigationStack {
                Group {
                    if globalNav.searchQuery.isEmpty {
                        recentSearchesView
                    } else if libraryViewModel.isSearching {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        searchResultsView
                    }
                }
                .safeAreaInset(edge: .top) {
                    // Filter chips - Pinned to top
                    VStack(spacing: 0) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(SearchFilter.allCases, id: \.self) { filter in
                                    FilterChip(
                                        label: filter.rawValue,
                                        isSelected: globalNav.selectedSearchFilter == filter
                                    ) {
                                        globalNav.selectedSearchFilter = filter
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.vertical, 12)
                        .background(Material.bar)

                        Divider()
                    }
                }
                .navigationTitle("Search")
                .navigationBarTitleDisplayMode(.large)
                .searchable(text: $globalNav.searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search music, audiobooks, podcasts...")
                .onSubmit(of: .search) {
                    saveRecentSearch(globalNav.searchQuery)
                }
                .onAppear {
                    loadRecentSearches()
                    if globalNav.searchQuery.isEmpty {
                        globalNav.selectedSearchFilter = globalNav.initialSearchFilter
                    }
                    // Restore previous search results if query exists
                    if !globalNav.searchQuery.isEmpty {
                        libraryViewModel.searchQuery = globalNav.searchQuery
                    }
                }
                .onChange(of: globalNav.searchQuery) { _, newValue in
                    if !newValue.isEmpty {
                        libraryViewModel.searchQuery = newValue
                    } else {
                        libraryViewModel.searchQuery = ""
                    }
                }
                .scrollDismissesKeyboard(.immediately)
            }

            // Album detail overlay
            if let album = globalNav.selectedAlbum {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture {
                            globalNav.closeDetailView()
                        }

                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Button {
                                globalNav.closeDetailView()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }

                        NavigationStack {
                            AlbumDetailView(album: album)
                                .environmentObject(playerViewModel)
                                .environmentObject(libraryViewModel)
                                .environment(barManager)
                        }
                    }
                    .background(Color(UIColor.systemBackground))
                }
                .transition(.move(edge: .trailing))
                .zIndex(3)
            }

            // Playlist detail overlay
            if let playlist = globalNav.selectedPlaylist {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture {
                            globalNav.closeDetailView()
                        }

                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Button {
                                globalNav.closeDetailView()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }

                        NavigationStack {
                            PlaylistDetailView(playlist: playlist)
                                .environmentObject(playerViewModel)
                                .environmentObject(libraryViewModel)
                                .environment(barManager)
                        }
                    }
                    .background(Color(UIColor.systemBackground))
                }
                .transition(.move(edge: .trailing))
                .zIndex(3)
            }

            // Artist detail overlay
            if let artist = globalNav.selectedArtist {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture {
                            globalNav.closeDetailView()
                        }

                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Button {
                                globalNav.closeDetailView()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }

                        NavigationStack {
                            ArtistDetailView(artist: artist)
                                .environmentObject(playerViewModel)
                                .environmentObject(libraryViewModel)
                                .environment(barManager)
                        }
                    }
                    .background(Color(UIColor.systemBackground))
                }
                .transition(.move(edge: .trailing))
                .zIndex(3)
            }

            // Audiobook detail overlay
            if let audiobook = globalNav.selectedAudiobook {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture {
                            globalNav.closeDetailView()
                        }

                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Button {
                                globalNav.closeDetailView()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }

                        NavigationStack {
                            AudiobookDetailView(audiobook: audiobook)
                                .environmentObject(playerViewModel)
                                .environmentObject(libraryViewModel)
                                .environment(barManager)
                        }
                    }
                    .background(Color(UIColor.systemBackground))
                }
                .transition(.move(edge: .trailing))
                .zIndex(3)
            }

            // Podcast detail overlay
            if let podcast = globalNav.selectedPodcast {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture {
                            globalNav.closeDetailView()
                        }

                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Button {
                                globalNav.closeDetailView()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }

                        NavigationStack {
                            PodcastDetailView(podcast: podcast)
                                .environmentObject(playerViewModel)
                                .environmentObject(libraryViewModel)
                                .environment(barManager)
                        }
                    }
                    .background(Color(UIColor.systemBackground))
                }
                .transition(.move(edge: .trailing))
                .zIndex(3)
            }
        }
    }

    private var recentSearchesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !recentSearches.isEmpty {
                Text("Recent Searches")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top)

                ForEach(recentSearches, id: \.self) { search in
                    Button {
                        globalNav.searchQuery = search
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.secondary)

                            Text(search)
                                .foregroundColor(.primary)

                            Spacer()

                            Button {
                                removeRecentSearch(search)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ContentUnavailableView(
                    "Search Music",
                    systemImage: "magnifyingglass",
                    description: Text("Search for albums, artists, tracks, audiobooks, podcasts, and more")
                )
            }

            Spacer()
        }
    }

    private var searchResultsView: some View {
        List {
            // Filter results based on selected filter
            if (globalNav.selectedSearchFilter == .all || globalNav.selectedSearchFilter == .songs) && !libraryViewModel.searchResults.tracks.isEmpty {
                Section {
                    let tracks = globalNav.selectedSearchFilter == .all ? Array(libraryViewModel.searchResults.tracks.prefix(5)) : libraryViewModel.searchResults.tracks
                    ForEach(tracks) { track in
                        TrackRow(
                            track: track,
                            showArtwork: true,
                            isPlaying: playerViewModel.playerManager.currentTrack?.id == track.id,
                            onTap: {
                                playerViewModel.playTrack(track, fromQueue: libraryViewModel.searchResults.tracks, sourceName: "Search")
                            }
                        )
                    }
                } header: {
                    HStack {
                        Text("Songs")
                        Spacer()
                        if globalNav.selectedSearchFilter == .all && libraryViewModel.searchResults.tracks.count > 5 {
                            Button {
                                globalNav.selectedSearchFilter = .songs
                            } label: {
                                Text("See all (\(libraryViewModel.searchResults.tracks.count))")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }

            if (globalNav.selectedSearchFilter == .all || globalNav.selectedSearchFilter == .albums) && !libraryViewModel.searchResults.albums.isEmpty {
                Section {
                    let albums = globalNav.selectedSearchFilter == .all ? Array(libraryViewModel.searchResults.albums.prefix(5)) : libraryViewModel.searchResults.albums
                    ForEach(albums) { album in
                        Button {
                            globalNav.navigateToAlbum(album)
                        } label: {
                            HStack(spacing: 12) {
                                CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: album.imageUrl, size: .thumbnail)) {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay {
                                            Image(systemName: "music.note")
                                                .foregroundColor(.gray)
                                        }
                                }
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                                VStack(alignment: .leading) {
                                    Text(album.name)
                                        .lineLimit(1)
                                    Text(album.artistNames)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Menu {
                                    Button {
                                        Task {
                                            if let tracks = try? await XonoraClient.shared.fetchAlbumTracks(albumId: album.itemId, provider: album.provider) {
                                                await MainActor.run {
                                                    PlayerManager.shared.playAlbum(tracks)
                                                }
                                            }
                                        }
                                    } label: { Label("Play", systemImage: "play") }

                                    if album.provider != "library" {
                                        Button {
                                            Task { try? await XonoraClient.shared.addToLibrary(uri: album.uri) }
                                        } label: { Label("Add to Library", systemImage: "plus.circle") }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .foregroundColor(.secondary)
                                        .frame(width: 24, height: 24)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Albums")
                        Spacer()
                        if globalNav.selectedSearchFilter == .all && libraryViewModel.searchResults.albums.count > 5 {
                            Button {
                                globalNav.selectedSearchFilter = .albums
                            } label: {
                                Text("See all (\(libraryViewModel.searchResults.albums.count))")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }

            if (globalNav.selectedSearchFilter == .all || globalNav.selectedSearchFilter == .artists) && !libraryViewModel.searchResults.artists.isEmpty {
                Section {
                    let artists = globalNav.selectedSearchFilter == .all ? Array(libraryViewModel.searchResults.artists.prefix(5)) : libraryViewModel.searchResults.artists
                    ForEach(artists) { artist in
                        Button {
                            globalNav.navigateToArtist(artist)
                        } label: {
                            HStack(spacing: 12) {
                                CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: artist.imageUrl, size: .thumbnail)) {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay {
                                            Image(systemName: "person.fill")
                                                .foregroundColor(.gray)
                                        }
                                }
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 50, height: 50)
                                .clipShape(Circle())

                                Text(artist.name)

                                Spacer()

                                if artist.provider != "library" {
                                    Menu {
                                        Button {
                                            Task { try? await XonoraClient.shared.addToLibrary(uri: artist.uri) }
                                        } label: { Label("Add to Library", systemImage: "plus.circle") }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .foregroundColor(.secondary)
                                            .frame(width: 24, height: 24)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Artists")
                        Spacer()
                        if globalNav.selectedSearchFilter == .all && libraryViewModel.searchResults.artists.count > 5 {
                            Button {
                                globalNav.selectedSearchFilter = .artists
                            } label: {
                                Text("See all (\(libraryViewModel.searchResults.artists.count))")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }

            if (globalNav.selectedSearchFilter == .all || globalNav.selectedSearchFilter == .playlists) && !libraryViewModel.searchResults.playlists.isEmpty {
                Section {
                    let playlists = globalNav.selectedSearchFilter == .all ? Array(libraryViewModel.searchResults.playlists.prefix(5)) : libraryViewModel.searchResults.playlists
                    ForEach(playlists) { playlist in
                        Button {
                            globalNav.navigateToPlaylist(playlist)
                        } label: {
                            HStack(spacing: 12) {
                                CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: playlist.imageUrl, size: .thumbnail)) {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay {
                                            Image(systemName: "music.note.list")
                                                .foregroundColor(.gray)
                                        }
                                }
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                                Text(playlist.name)
                                    .lineLimit(1)

                                Spacer()

                                Menu {
                                    Button {
                                        Task {
                                            if let tracks = try? await XonoraClient.shared.fetchPlaylistTracks(playlistId: playlist.itemId, provider: playlist.provider) {
                                                await MainActor.run {
                                                    PlayerManager.shared.playPlaylist(playlist, tracks: tracks)
                                                }
                                            }
                                        }
                                    } label: { Label("Play", systemImage: "play") }

                                    if playlist.provider != "library" {
                                        Button {
                                            Task { try? await XonoraClient.shared.addToLibrary(uri: playlist.uri) }
                                        } label: { Label("Add to Library", systemImage: "plus.circle") }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .foregroundColor(.secondary)
                                        .frame(width: 24, height: 24)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Playlists")
                        Spacer()
                        if globalNav.selectedSearchFilter == .all && libraryViewModel.searchResults.playlists.count > 5 {
                            Button {
                                globalNav.selectedSearchFilter = .playlists
                            } label: {
                                Text("See all (\(libraryViewModel.searchResults.playlists.count))")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }

            if (globalNav.selectedSearchFilter == .all || globalNav.selectedSearchFilter == .audiobooks) && !libraryViewModel.searchResults.audiobooks.isEmpty {
                Section {
                    let audiobooks = globalNav.selectedSearchFilter == .all ? Array(libraryViewModel.searchResults.audiobooks.prefix(5)) : libraryViewModel.searchResults.audiobooks
                    ForEach(audiobooks) { audiobook in
                        Button {
                            globalNav.navigateToAudiobook(audiobook)
                        } label: {
                            HStack(spacing: 12) {
                                CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: audiobook.imageUrl, size: .thumbnail)) {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay {
                                            Image(systemName: "book")
                                                .foregroundColor(.gray)
                                        }
                                }
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                                VStack(alignment: .leading) {
                                    Text(audiobook.name)
                                        .lineLimit(1)
                                    if let authors = audiobook.authors?.joined(separator: ", ") {
                                        Text(authors)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Menu {
                                    Button {
                                        Task {
                                            // Audiobooks play differently, usually need to fetch chapters or just play
                                            // Assuming playAudiobook logic exists or falling back to simple play
                                            // For now, no direct play button in menu without knowing logic
                                        }
                                    } label: { Label("Play", systemImage: "play") }
                                    .disabled(true) // Placeholder

                                    if audiobook.provider != "library" {
                                        Button {
                                            Task { try? await XonoraClient.shared.addToLibrary(uri: audiobook.uri) }
                                        } label: { Label("Add to Library", systemImage: "plus.circle") }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .foregroundColor(.secondary)
                                        .frame(width: 24, height: 24)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Audiobooks")
                        Spacer()
                        if globalNav.selectedSearchFilter == .all && libraryViewModel.searchResults.audiobooks.count > 5 {
                            Button {
                                globalNav.selectedSearchFilter = .audiobooks
                            } label: {
                                Text("See all (\(libraryViewModel.searchResults.audiobooks.count))")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }

            if (globalNav.selectedSearchFilter == .all || globalNav.selectedSearchFilter == .podcasts) && !libraryViewModel.searchResults.podcasts.isEmpty {
                Section {
                    let podcasts = globalNav.selectedSearchFilter == .all ? Array(libraryViewModel.searchResults.podcasts.prefix(5)) : libraryViewModel.searchResults.podcasts
                    ForEach(podcasts) { podcast in
                        Button {
                            globalNav.navigateToPodcast(podcast)
                        } label: {
                            HStack(spacing: 12) {
                                CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: podcast.imageUrl, size: .thumbnail)) {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay {
                                            Image(systemName: "mic")
                                                .foregroundColor(.gray)
                                        }
                                }
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                                VStack(alignment: .leading) {
                                    Text(podcast.name)
                                        .lineLimit(1)
                                    if let publisher = podcast.publisher {
                                        Text(publisher)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                if podcast.provider != "library" {
                                    Menu {
                                        Button {
                                            Task { try? await XonoraClient.shared.addToLibrary(uri: podcast.uri) }
                                        } label: { Label("Add to Library", systemImage: "plus.circle") }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .foregroundColor(.secondary)
                                            .frame(width: 24, height: 24)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Podcasts")
                        Spacer()
                        if globalNav.selectedSearchFilter == .all && libraryViewModel.searchResults.podcasts.count > 5 {
                            Button {
                                globalNav.selectedSearchFilter = .podcasts
                            } label: {
                                Text("See all (\(libraryViewModel.searchResults.podcasts.count))")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }

            if (globalNav.selectedSearchFilter == .all || globalNav.selectedSearchFilter == .radio) && !libraryViewModel.searchResults.radios.isEmpty {
                Section {
                    let radios = globalNav.selectedSearchFilter == .all ? Array(libraryViewModel.searchResults.radios.prefix(5)) : libraryViewModel.searchResults.radios
                    ForEach(radios) { radio in
                        Button {
                            playerViewModel.playRadio(radio)
                        } label: {
                            HStack(spacing: 12) {
                                CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: radio.imageUrl, size: .thumbnail)) {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay {
                                            Image(systemName: "antenna.radiowaves.left.and.right")
                                                .foregroundColor(.gray)
                                        }
                                }
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                                Text(radio.name)
                                    .lineLimit(1)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Menu {
                                    Button {
                                        playerViewModel.playRadio(radio)
                                    } label: { Label("Play", systemImage: "play") }
                                    
                                    if radio.provider != "library" {
                                        Button {
                                            Task { try? await XonoraClient.shared.addToLibrary(uri: radio.uri) }
                                        } label: { Label("Add to Library", systemImage: "plus.circle") }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .foregroundColor(.secondary)
                                        .frame(width: 24, height: 24)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Radio")
                        Spacer()
                        if globalNav.selectedSearchFilter == .all && libraryViewModel.searchResults.radios.count > 5 {
                            Button {
                                globalNav.selectedSearchFilter = .radio
                            } label: {
                                Text("See all (\(libraryViewModel.searchResults.radios.count))")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }

            // Empty state if no results
            if libraryViewModel.searchResults.albums.isEmpty &&
               libraryViewModel.searchResults.artists.isEmpty &&
               libraryViewModel.searchResults.tracks.isEmpty &&
               libraryViewModel.searchResults.playlists.isEmpty &&
               libraryViewModel.searchResults.audiobooks.isEmpty &&
               libraryViewModel.searchResults.podcasts.isEmpty &&
               libraryViewModel.searchResults.radios.isEmpty {
                ContentUnavailableView.search(text: globalNav.searchQuery)
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: - Recent Searches Management

    private func loadRecentSearches() {
        if let saved = UserDefaults.standard.stringArray(forKey: "recentSearches") {
            recentSearches = Array(saved.prefix(10)) // Limit to 10
        }
    }

    private func saveRecentSearch(_ search: String) {
        guard !search.isEmpty else { return }

        var searches = recentSearches
        searches.removeAll { $0 == search }
        searches.insert(search, at: 0)
        searches = Array(searches.prefix(10))

        recentSearches = searches
        UserDefaults.standard.set(searches, forKey: "recentSearches")
    }

    private func removeRecentSearch(_ search: String) {
        recentSearches.removeAll { $0 == search }
        UserDefaults.standard.set(recentSearches, forKey: "recentSearches")
    }
}

