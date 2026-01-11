import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    @State private var selectedCategory: LibraryCategory = .albums

    enum LibraryCategory: String, CaseIterable {
        case albums = "Albums"
        case songs = "Songs"
        case playlists = "Playlists"
        case artists = "Artists"
    }

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category picker
                Picker("Category", selection: $selectedCategory) {
                    ForEach(LibraryCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // Content
                if libraryViewModel.isLoading {
                    Spacer()
                    ProgressView("Loading Library...")
                    Spacer()
                } else if let error = libraryViewModel.errorMessage {
                    Spacer()
                    if #available(iOS 17.0, *) {
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
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("Unable to Load")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Try Again") {
                                Task {
                                    await libraryViewModel.loadLibrary()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    }
                    Spacer()
                } else {
                    switch selectedCategory {
                    case .albums:
                        albumsGrid
                    case .songs:
                        songsList
                    case .playlists:
                        playlistsGrid
                    case .artists:
                        artistsList
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await libraryViewModel.loadLibrary()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            if libraryViewModel.albums.isEmpty && playerViewModel.isConnected {
                await libraryViewModel.loadLibrary()
            }
        }
        .onChange(of: playerViewModel.isConnected) { connected in
            if connected && libraryViewModel.albums.isEmpty {
                Task {
                    await libraryViewModel.loadLibrary()
                }
            }
        }
    }

    private var playlistsGrid: some View {
        ScrollView {
            if libraryViewModel.playlists.isEmpty {
                if #available(iOS 17.0, *) {
                    ContentUnavailableView(
                        "No Playlists",
                        systemImage: "music.note.list",
                        description: Text("Your library has no playlists.")
                    )
                    .padding(.top, 100)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No Playlists")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Your library has no playlists.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .padding(.top, 100)
                }
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(libraryViewModel.playlists) { playlist in
                        NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                            PlaylistGridItem(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .padding(.bottom, playerViewModel.hasTrack ? 80 : 0)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var albumsGrid: some View {
        ScrollView {
            if libraryViewModel.albums.isEmpty {
                if #available(iOS 17.0, *) {
                    ContentUnavailableView(
                        "No Albums",
                        systemImage: "square.stack",
                        description: Text("Your library is empty. Add some music to get started.")
                    )
                    .padding(.top, 100)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "square.stack")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No Albums")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Your library is empty. Add some music to get started.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .padding(.top, 100)
                }
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(libraryViewModel.albums) { album in
                        NavigationLink(destination: AlbumDetailView(album: album)) {
                            AlbumGridItem(album: album)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .padding(.bottom, playerViewModel.hasTrack ? 80 : 0)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var songsList: some View {
        List {
            if libraryViewModel.tracks.isEmpty {
                if #available(iOS 17.0, *) {
                    ContentUnavailableView(
                        "No Songs",
                        systemImage: "music.note",
                        description: Text("Your library has no songs. Add individual tracks to see them here.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No Songs")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Your library has no songs. Add individual tracks to see them here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                ForEach(Array(libraryViewModel.tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(
                        track: track,
                        index: index + 1,
                        showArtwork: true,
                        isPlaying: playerViewModel.currentTrack?.itemId == track.itemId,
                        numberFirst: true
                    ) {
                        Task {
                            await playerViewModel.playTrack(track)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.bottom, playerViewModel.hasTrack ? 80 : 0)
    }

    private var artistsList: some View {
        List {
            if libraryViewModel.artists.isEmpty {
                if #available(iOS 17.0, *) {
                    ContentUnavailableView(
                        "No Artists",
                        systemImage: "person.2",
                        description: Text("Your library is empty.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No Artists")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Your library is empty.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                ForEach(libraryViewModel.artists) { artist in
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
                            .font(.body)

                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.bottom, playerViewModel.hasTrack ? 80 : 0)
    }
}

struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
            .environmentObject(LibraryViewModel())
            .environmentObject(PlayerViewModel())
    }
}
