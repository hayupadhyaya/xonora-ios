import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @ObservedObject private var prefs = UserPreferences.shared
    @Environment(\.miniPlayerBottomPadding) private var miniPlayerPadding
    @Environment(BarVisibilityManager.self) private var barManager

    @State private var selectedCategory: LibraryCategory = .albums
    @State private var isInitialLoad = true

    enum LibraryCategory: String, CaseIterable {
        case albums = "Albums"
        case songs = "Songs"
        case playlists = "Playlists"
        case artists = "Artists"

        var localizedName: LocalizedStringKey {
            LocalizedStringKey(rawValue)
        }

        var icon: String {
            switch self {
            case .albums: return "square.stack.fill"
            case .songs: return "music.note"
            case .playlists: return "music.note.list"
            case .artists: return "person.2.fill"
            }
        }
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // MARK: - Computed Sort Options

    private var albumSortOption: SortOption {
        SortOption(rawValue: prefs.sortAlbums) ?? .nameAsc
    }
    private var playlistSortOption: SortOption {
        SortOption(rawValue: prefs.sortPlaylists) ?? .nameAsc
    }
    private var trackSortOption: SortOption {
        SortOption(rawValue: prefs.sortTracks) ?? .nameAsc
    }
    private var artistSortOption: SortOption {
        SortOption(rawValue: prefs.sortArtists) ?? .nameAsc
    }

    private var albumViewMode: ViewMode {
        ViewMode(rawValue: prefs.viewModeAlbums) ?? .grid
    }
    private var playlistViewMode: ViewMode {
        ViewMode(rawValue: prefs.viewModePlaylists) ?? .grid
    }

    // MARK: - Grid Columns

    private var albumColumns: [GridItem] {
        gridColumns(for: "albums", horizontalSizeClass: horizontalSizeClass, verticalSizeClass: verticalSizeClass)
    }
    private var playlistColumns: [GridItem] {
        gridColumns(for: "playlists", horizontalSizeClass: horizontalSizeClass, verticalSizeClass: verticalSizeClass)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if (libraryViewModel.isLoading || isInitialLoad) && libraryViewModel.albums.isEmpty {
                    VStack {
                        Spacer()
                        ProgressView("Loading Library...")
                            .controlSize(.large)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if let error = libraryViewModel.errorMessage, libraryViewModel.albums.isEmpty {
                    ContentUnavailableView {
                        Label("Unable to Load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") {
                            Task {
                                await libraryViewModel.loadLibrary(forceRefresh: true)
                            }
                        }
                    }
                } else {
                    categoryView(for: selectedCategory)
                        .id(selectedCategory)
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                }
            }
            .navigationTitle(selectedCategory.localizedName)
            .background(Color(UIColor.systemBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    let isPortraitPhone = horizontalSizeClass == .compact && verticalSizeClass != .compact
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(LibraryCategory.allCases, id: \.self) { category in
                            if isPortraitPhone {
                                Image(systemName: category.icon).tag(category)
                            } else {
                                Text(category.localizedName).tag(category)
                            }
                        }
                    }
                    .pickerStyle(.segmented)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 4) {
                        // View mode toggle (Albums, Playlists only)
                        if selectedCategory == .albums {
                            viewModeButton(mode: albumViewMode) {
                                prefs.viewModeAlbums = (albumViewMode == .grid ? ViewMode.list : .grid).rawValue
                            }
                        } else if selectedCategory == .playlists {
                            viewModeButton(mode: playlistViewMode) {
                                prefs.viewModePlaylists = (playlistViewMode == .grid ? ViewMode.list : .grid).rawValue
                            }
                        }
                        // Sort menu
                        sortMenu
                    }
                }
            }
            .globalToolbar(searchFilter: .songs)
            .refreshable {
                await libraryViewModel.loadLibrary(forceRefresh: true)
            }
            .task {
                if isInitialLoad {
                    await libraryViewModel.loadLibrary()
                    isInitialLoad = false
                }
            }
            .onChange(of: playerViewModel.isConnected) { _, connected in
                if connected {
                    Task {
                        await libraryViewModel.loadLibrary()
                    }
                }
            }
        }
    }

    // MARK: - Toolbar Helpers

    @ViewBuilder
    private func viewModeButton(mode: ViewMode, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: mode == .grid ? "square.grid.2x2" : "list.bullet")
        }
    }

    private var sortMenu: some View {
        Menu {
            sortMenuItems
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    private var currentSort: String {
        switch selectedCategory {
        case .albums: return prefs.sortAlbums
        case .playlists: return prefs.sortPlaylists
        case .songs: return prefs.sortTracks
        case .artists: return prefs.sortArtists
        }
    }

    @ViewBuilder
    private var sortMenuItems: some View {

        ForEach(SortOption.allCases, id: \.self) { option in
            Button {
                switch selectedCategory {
                case .albums: prefs.sortAlbums = option.rawValue
                case .playlists: prefs.sortPlaylists = option.rawValue
                case .songs: prefs.sortTracks = option.rawValue
                case .artists: prefs.sortArtists = option.rawValue
                }
            } label: {
                Label {
                    Text(option.label)
                } icon: {
                    if currentSort == option.rawValue {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }

    // MARK: - Category Views

    @ViewBuilder
    private func categoryView(for category: LibraryCategory) -> some View {
        switch category {
        case .albums:
            albumsView
        case .songs:
            songsList
        case .playlists:
            playlistsView
        case .artists:
            artistsList
        }
    }

    // MARK: - Albums

    private var albumsView: some View {
        let sorted = libraryViewModel.sortedAlbums(option: albumSortOption)
        return Group {
            if albumViewMode == .grid {
                albumsGrid(items: sorted)
            } else {
                albumsListView(items: sorted)
            }
        }
    }

    private func albumsGrid(items: [Album]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Albums",
                        systemImage: "square.stack",
                        description: Text("Your library is empty. Add some music to get started.")
                    )
                    .padding(.top, 100)
                } else {
                    LazyVGrid(columns: albumColumns, spacing: 20) {
                        ForEach(items) { album in
                            NavigationLink(destination: AlbumDetailView(album: album)) {
                                MediaGridItem(
                                    name: album.name,
                                    subtitle: album.artistNames,
                                    imageURL: XonoraClient.shared.getImageURL(for: album.imageUrl, size: .small),
                                    placeholderIcon: "music.note",
                                    providerIcon: album.sourceProvider
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, miniPlayerPadding)
                }
            }
        }
        .trackScrollForBars(barManager)
        .background(Color(UIColor.systemBackground))
    }

    private func albumsListView(items: [Album]) -> some View {
        ScrollView {
            if items.isEmpty {
                ContentUnavailableView(
                    "No Albums",
                    systemImage: "square.stack",
                    description: Text("Your library is empty.")
                )
                .padding(.top, 100)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { album in
                        NavigationLink(destination: AlbumDetailView(album: album)) {
                            MediaListRow(
                                title: album.name,
                                subtitle: album.artistNames,
                                imageUrl: album.imageUrl,
                                imageShape: .rounded
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, miniPlayerPadding)
            }
        }
        .trackScrollForBars(barManager)
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Playlists

    private var playlistsView: some View {
        let sorted = libraryViewModel.sortedPlaylists(option: playlistSortOption)
        return Group {
            if playlistViewMode == .grid {
                playlistsGrid(items: sorted)
            } else {
                playlistsListView(items: sorted)
            }
        }
    }

    private func playlistsGrid(items: [Playlist]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Playlists",
                        systemImage: "music.note.list",
                        description: Text("Your library has no playlists.")
                    )
                    .padding(.top, 100)
                } else {
                    LazyVGrid(columns: playlistColumns, spacing: 20) {
                        ForEach(items) { playlist in
                            NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                                MediaGridItem(
                                    name: playlist.name,
                                    subtitle: "Playlist",
                                    imageURL: XonoraClient.shared.getImageURL(for: playlist.imageUrl, size: .small),
                                    placeholderIcon: "music.note.list",
                                    providerIcon: playlist.sourceProvider
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, miniPlayerPadding)
                }
            }
        }
        .trackScrollForBars(barManager)
        .background(Color(UIColor.systemBackground))
    }

    private func playlistsListView(items: [Playlist]) -> some View {
        ScrollView {
            if items.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "music.note.list",
                    description: Text("Your library has no playlists.")
                )
                .padding(.top, 100)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { playlist in
                        NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                            MediaListRow(
                                title: playlist.name,
                                subtitle: nil,
                                imageUrl: playlist.imageUrl,
                                imageShape: .rounded
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, miniPlayerPadding)
            }
        }
        .trackScrollForBars(barManager)
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Songs

    private var songsList: some View {
        let sorted = libraryViewModel.sortedTracks(option: trackSortOption)
        return ScrollView {
            if sorted.isEmpty {
                ContentUnavailableView(
                    "No Songs",
                    systemImage: "music.note",
                    description: Text("Your library has no songs. Add individual tracks to see them here.")
                )
                .padding(.top, 100)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, track in
                        TrackRow(
                            track: track,
                            index: index + 1,
                            showArtwork: true,
                            isPlaying: playerViewModel.currentTrack?.itemId == track.itemId,
                            numberFirst: true
                        ) {
                            playerViewModel.playTrack(track, fromQueue: sorted, sourceName: "Songs")
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, miniPlayerPadding)
            }
        }
        .trackScrollForBars(barManager)
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Artists

    private var artistsList: some View {
        let sorted = libraryViewModel.sortedArtists(option: artistSortOption)
        return ScrollView {
            if sorted.isEmpty {
                ContentUnavailableView(
                    "No Artists",
                    systemImage: "person.2",
                    description: Text("Your library is empty.")
                )
                .padding(.top, 100)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(sorted) { artist in
                        NavigationLink(destination: ArtistDetailView(artist: artist)) {
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
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())

                                Text(artist.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, miniPlayerPadding)
            }
        }
        .trackScrollForBars(barManager)
        .background(Color(UIColor.systemBackground))
    }
}

// MARK: - Smart List Card Component


struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
            .environmentObject(LibraryViewModel())
            .environmentObject(PlayerViewModel())
    }
}
