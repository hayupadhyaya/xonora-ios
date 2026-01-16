import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    @State private var selectedCategory: LibraryCategory = .albums
    @State private var isInitialLoad = true

    enum LibraryCategory: String, CaseIterable, Identifiable {
        case albums = "Albums"
        case songs = "Songs"
        case playlists = "Playlists"
        case artists = "Artists"

        var id: String { self.rawValue }

        var icon: String {
            switch self {
            case .albums: return "square.stack.fill"
            case .songs: return "music.note"
            case .playlists: return "music.note.list"
            case .artists: return "person.2.fill"
            }
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

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
                                await libraryViewModel.loadLibrary()
                            }
                        }
                    }
                } else {
                    TabView(selection: $selectedCategory) {
                        categoryScrollView { albumsGrid }.tag(LibraryCategory.albums)
                        categoryScrollView { songsList }.tag(LibraryCategory.songs)
                        categoryScrollView { playlistsGrid }.tag(LibraryCategory.playlists)
                        categoryScrollView { artistsList }.tag(LibraryCategory.artists)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .safeAreaInset(edge: .top, spacing: 0) {
                        categoryTabBar
                    }
                }
            }
            .navigationBarHidden(true)
            .background(Color(UIColor.systemGroupedBackground))
        }
        .task {
            // Initial load attempt (loads from cache even if disconnected)
            await libraryViewModel.loadLibrary()
            isInitialLoad = false
        }
        .onChange(of: playerViewModel.isConnected) { oldValue, connected in
            if connected {
                Task {
                    await libraryViewModel.loadLibrary()
                }
            }
        }
    }

    private var categoryTabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(LibraryCategory.allCases) { category in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            selectedCategory = category
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: category.icon)
                                .font(.system(size: 20))
                                .symbolVariant(selectedCategory == category ? .fill : .none)
                            
                            Text(category.rawValue)
                                .font(.system(size: 10))
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .foregroundColor(selectedCategory == category ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            
            Divider().background(Color.primary.opacity(0.1))
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func categoryScrollView<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.top, 16)
        }
        .refreshable {
            await libraryViewModel.loadLibrary(forceRefresh: true)
        }
    }

    private var playlistsGrid: some View {
        LazyVStack(spacing: 0) {
            if libraryViewModel.playlists.isEmpty && !libraryViewModel.isLoading {
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
    }

    private var albumsGrid: some View {
        LazyVStack(spacing: 0) {
            if libraryViewModel.albums.isEmpty && !libraryViewModel.isLoading {
                ContentUnavailableView(
                    "No Albums",
                    systemImage: "square.stack",
                    description: Text("Your library is empty. Add some music to get started.")
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
    }

    private var songsList: some View {
        LazyVStack(spacing: 0) {
            if libraryViewModel.tracks.isEmpty && !libraryViewModel.isLoading {
                ContentUnavailableView(
                    "No Songs",
                    systemImage: "music.note",
                    description: Text("Your library has no songs. Add individual tracks to see them here.")
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

    private var artistsList: some View {
        LazyVStack(spacing: 0) {
            if libraryViewModel.artists.isEmpty && !libraryViewModel.isLoading {
                ContentUnavailableView(
                    "No Artists",
                    systemImage: "person.2",
                    description: Text("Your library is empty.")
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
                            .frame(width: 44, height: 44) // Match TrackRow artwork size
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(artist.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }

                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .padding(.vertical, 8) // Match TrackRow vertical padding
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, playerViewModel.hasTrack ? 120 : 20)
    }
}

struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
            .environmentObject(LibraryViewModel())
            .environmentObject(PlayerViewModel())
    }
}
