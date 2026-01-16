import SwiftUI

struct ArtistDetailView: View {
    let artist: Artist
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @State private var albums: [Album] = []
    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerView

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                } else {
                    // Top Tracks
                    if !tracks.isEmpty {
                        tracksSection
                    }

                    // Albums
                    if !albums.isEmpty {
                        albumsSection
                    }
                }
            }
            .padding(.bottom, 100)
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await libraryViewModel.toggleFavorite(item: artist)
                    }
                } label: {
                    Image(systemName: artist.favorite ?? false ? "heart.fill" : "heart")
                        .foregroundColor(artist.favorite ?? false ? .red : .primary)
                }
            }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .task {
            await loadData()
        }
    }

    private var headerView: some View {
        HStack(spacing: 20) {
            CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: artist.imageUrl, size: .medium)) {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                    }
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            .shadow(radius: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.title)
                    .fontWeight(.bold)
                    .lineLimit(2)
                
                Text("Artist")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
    }

    private var tracksSection: some View {
        VStack(alignment: .leading) {
            Text("Top Songs")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)

            ForEach(Array(tracks.prefix(5).enumerated()), id: \.element.id) { index, track in
                TrackRow(
                    track: track,
                    index: index + 1,
                    showArtwork: true,
                    isPlaying: playerViewModel.currentTrack?.id == track.id,
                    numberFirst: true
                ) {
                    Task {
                        // Play artist tracks starting from this one
                        playerViewModel.playTrack(track, fromQueue: tracks, sourceName: artist.name)
                    }
                }
                .padding(.horizontal)
            }
            
            if tracks.count > 5 {
                NavigationLink("See all songs") {
                    List {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(
                                track: track,
                                index: index + 1,
                                showArtwork: true,
                                isPlaying: playerViewModel.currentTrack?.id == track.id,
                                numberFirst: true
                            ) {
                                Task {
                                    playerViewModel.playTrack(track, fromQueue: tracks, sourceName: artist.name)
                                }
                            }
                        }
                    }
                    .navigationTitle("Songs")
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
    }

    private var albumsSection: some View {
        VStack(alignment: .leading) {
            Text("Albums")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(albums) { album in
                        NavigationLink(destination: AlbumDetailView(album: album)) {
                            VStack(alignment: .leading) {
                                CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: album.imageUrl)) {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                }
                                .aspectRatio(1, contentMode: .fill)
                                .frame(width: 140, height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                Text(album.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                    .foregroundColor(.primary)
                                
                                Text(String(album.year ?? 0))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 140)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func loadData() async {
        do {
            let (fetchedAlbums, fetchedTracks) = try await libraryViewModel.loadArtistDetails(artist: artist)
            // Sort albums by year descending
            self.albums = fetchedAlbums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
            self.tracks = fetchedTracks
            isLoading = false
        } catch {
            errorMessage = "Failed to load artist details"
            isLoading = false
        }
    }
}
