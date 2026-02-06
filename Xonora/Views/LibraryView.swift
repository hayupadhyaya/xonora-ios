import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    @State private var isInitialLoad = true

    var body: some View {
        NavigationStack {
            Group {
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
                                await libraryViewModel.loadLibrary()
                            }
                        }
                    }
                } else {
                    libraryContent
                }
            }
            .navigationTitle("Library")
            .background(Color(UIColor.systemGroupedBackground))
            .refreshable {
                await libraryViewModel.loadLibrary(forceRefresh: true)
                await libraryViewModel.loadRecentlyPlayed()
            }
        }
        .task {
            await libraryViewModel.loadLibrary()
            await libraryViewModel.loadRecentlyPlayed()
            isInitialLoad = false
        }
        .onChange(of: playerViewModel.isConnected) { oldValue, connected in
            if connected {
                Task {
                    await libraryViewModel.loadLibrary()
                    await libraryViewModel.loadRecentlyPlayed()
                }
            }
        }
    }

    private var libraryContent: some View {
        List {
            // Recently Played Section
            if !libraryViewModel.recentlyPlayed.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(libraryViewModel.recentlyPlayed) { item in
                                RecentlyPlayedCard(item: item)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                } header: {
                    HStack {
                        Text("Recently Played")
                        Spacer()
                        if libraryViewModel.isLoadingRecent {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
            }

            // Library Categories Section
            Section {
                NavigationLink {
                    PlaylistsListView()
                } label: {
                    LibraryMenuRow(
                        icon: "music.note.list",
                        iconColor: .orange,
                        title: "Playlists",
                        count: libraryViewModel.playlists.count
                    )
                }

                NavigationLink {
                    ArtistsListView()
                } label: {
                    LibraryMenuRow(
                        icon: "person.2.fill",
                        iconColor: .pink,
                        title: "Artists",
                        count: libraryViewModel.artists.count
                    )
                }

                NavigationLink {
                    AlbumsListView()
                } label: {
                    LibraryMenuRow(
                        icon: "square.stack.fill",
                        iconColor: .purple,
                        title: "Albums",
                        count: libraryViewModel.albums.count
                    )
                }

                NavigationLink {
                    SongsListView()
                } label: {
                    LibraryMenuRow(
                        icon: "music.note",
                        iconColor: .red,
                        title: "Songs",
                        count: libraryViewModel.tracks.count
                    )
                }
            }

            // Recently Added Section
            if !libraryViewModel.albums.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(libraryViewModel.albums.prefix(10)) { album in
                                NavigationLink(destination: AlbumDetailView(album: album)) {
                                    RecentAlbumCard(album: album)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                } header: {
                    Text("Recently Added")
                }
            }

            // Quick Access to Artists
            if !libraryViewModel.artists.isEmpty {
                Section {
                    ForEach(libraryViewModel.artists.prefix(5)) { artist in
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

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(artist.name)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    HStack(spacing: 4) {
                                        ProviderIcon(provider: artist.provider, size: 12)
                                        Text("Artist")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Artists")
                        Spacer()
                        NavigationLink("See All") {
                            ArtistsListView()
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            if playerViewModel.hasTrack {
                Color.clear.frame(height: 80)
            }
        }
    }
}

// MARK: - Library Menu Row

struct LibraryMenuRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 28)

            Text(title)
                .font(.body)

            Spacer()

            Text("\(count)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Recent Album Card

struct RecentAlbumCard: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: album.imageUrl, size: .small)) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.title)
                            .foregroundColor(.gray)
                    }
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 140, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                HStack(spacing: 3) {
                    ProviderIcon(provider: album.provider, size: 10)
                    Text(album.artistNames)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 140, alignment: .leading)
        }
    }
}

// MARK: - Albums List View

struct AlbumsListView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            if libraryViewModel.albums.isEmpty {
                ContentUnavailableView(
                    "No Albums",
                    systemImage: "square.stack",
                    description: Text("Your library has no albums.")
                )
                .padding(.top, 100)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(libraryViewModel.albums) { album in
                        NavigationLink(destination: AlbumDetailView(album: album)) {
                            AlbumGridItem(album: album)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, playerViewModel.hasTrack ? 120 : 20)
            }
        }
        .navigationTitle("Albums")
        .navigationBarTitleDisplayMode(.large)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

// MARK: - Songs List View

struct SongsListView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if libraryViewModel.tracks.isEmpty {
                    ContentUnavailableView(
                        "No Songs",
                        systemImage: "music.note",
                        description: Text("Your library has no songs.")
                    )
                    .padding(.top, 100)
                } else {
                    ForEach(Array(libraryViewModel.tracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(
                            track: track,
                            index: index + 1,
                            showArtwork: true,
                            isPlaying: playerViewModel.currentTrack?.itemId == track.itemId,
                            numberFirst: true
                        ) {
                            playerViewModel.playTrack(track, sourceName: "Songs")
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.bottom, playerViewModel.hasTrack ? 120 : 20)
        }
        .navigationTitle("Songs")
        .navigationBarTitleDisplayMode(.large)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

// MARK: - Playlists List View

struct PlaylistsListView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            if libraryViewModel.playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "music.note.list",
                    description: Text("Your library has no playlists.")
                )
                .padding(.top, 100)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(libraryViewModel.playlists) { playlist in
                        NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                            PlaylistGridItem(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, playerViewModel.hasTrack ? 120 : 20)
            }
        }
        .navigationTitle("Playlists")
        .navigationBarTitleDisplayMode(.large)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

// MARK: - Artists List View

struct ArtistsListView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if libraryViewModel.artists.isEmpty {
                    ContentUnavailableView(
                        "No Artists",
                        systemImage: "person.2",
                        description: Text("Your library has no artists.")
                    )
                    .padding(.top, 100)
                } else {
                    ForEach(libraryViewModel.artists) { artist in
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
                                .frame(width: 50, height: 50)
                                .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(artist.name)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    HStack(spacing: 4) {
                                        ProviderIcon(provider: artist.provider, size: 12)
                                        Text("Artist")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if artist.id != libraryViewModel.artists.last?.id {
                            Divider()
                                .padding(.leading, 78)
                        }
                    }
                }
            }
            .padding(.bottom, playerViewModel.hasTrack ? 120 : 20)
        }
        .navigationTitle("Artists")
        .navigationBarTitleDisplayMode(.large)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

// MARK: - Recently Played Card

struct RecentlyPlayedCard: View {
    let item: RecentlyPlayedItem
    @ObservedObject private var playerManager = PlayerManager.shared

    var body: some View {
        Button {
            playItem()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // Artwork
                ZStack(alignment: .bottomTrailing) {
                    CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: item.imageUrl, size: .small)) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .overlay {
                                Image(systemName: iconForMediaType)
                                    .font(.title2)
                                    .foregroundColor(.gray)
                            }
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

                    // Media type badge
                    mediaTypeBadge
                        .padding(6)
                }

                // Title and artist
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundColor(.primary)

                    if let artist = item.artist {
                        Text(artist)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(width: 120, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private var iconForMediaType: String {
        switch item.mediaType {
        case "track": return "music.note"
        case "album": return "square.stack"
        case "playlist": return "music.note.list"
        case "artist": return "person.fill"
        default: return "music.note"
        }
    }

    private var mediaTypeBadge: some View {
        Group {
            switch item.mediaType {
            case "track":
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.red.opacity(0.9))
                    .clipShape(Circle())
            case "album":
                Image(systemName: "square.stack.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.purple.opacity(0.9))
                    .clipShape(Circle())
            case "playlist":
                Image(systemName: "music.note.list")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.orange.opacity(0.9))
                    .clipShape(Circle())
            default:
                EmptyView()
            }
        }
    }

    private func playItem() {
        Task {
            do {
                // Play the item via Music Assistant
                try await XonoraClient.shared.playMedia(uris: [item.uri], queueOption: "play")
                print("[RecentlyPlayedCard] Playing: \(item.name)")
            } catch {
                print("[RecentlyPlayedCard] Failed to play: \(error)")
            }
        }
    }
}

struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
            .environmentObject(LibraryViewModel())
            .environmentObject(PlayerViewModel())
    }
}
