import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist

    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Playlist header
                playlistHeader
                    .padding(.bottom, 24)

                // Play controls
                HStack(spacing: 16) {
                    Button {
                        if !tracks.isEmpty {
                            playerViewModel.playAlbum(tracks)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Play")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [.pink, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Button {
                        if !tracks.isEmpty {
                            let shuffledTracks = tracks.shuffled()
                            playerViewModel.playerManager.shuffleEnabled = true
                            playerViewModel.playAlbum(shuffledTracks)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "shuffle")
                            Text("Shuffle")
                        }
                        .font(.headline)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)

                // Track list
                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if let error = error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(error)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task {
                                await loadTracks()
                            }
                        }
                    }
                    .padding(.top, 40)
                } else {
                    trackList
                }
            }
            .padding(.bottom, playerViewModel.hasTrack ? 100 : 20)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await libraryViewModel.toggleFavorite(item: playlist)
                    }
                } label: {
                    Image(systemName: (libraryViewModel.playlists.first(where: { $0.id == playlist.id })?.favorite ?? playlist.favorite ?? false) ? "heart.fill" : "heart")
                        .foregroundColor((libraryViewModel.playlists.first(where: { $0.id == playlist.id })?.favorite ?? playlist.favorite ?? false) ? .pink : .primary)
                }
            }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .task {
            await loadTracks()
        }
    }

    private var playlistHeader: some View {
        VStack(spacing: 16) {
            // Playlist artwork
            CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: playlist.imageUrl, size: .medium)) {
                playlistArtPlaceholder
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 240, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)

            // Playlist info
            VStack(spacing: 4) {
                Text(playlist.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    if !tracks.isEmpty {
                        Text("\(tracks.count) songs")
                    }

                    if let totalDuration = totalDuration {
                        Text("•")
                        Text(totalDuration)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)
        }
        .padding(.top)
    }

    private var playlistArtPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "music.note.list")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
            }
    }

    private var trackList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(
                    track: track,
                    index: index + 1,
                    isPlaying: playerViewModel.playerManager.currentTrack?.id == track.id,
                    onTap: {
                        playerViewModel.playAlbum(tracks, startingAt: index)
                    }
                )
                .padding(.horizontal)

                if index < tracks.count - 1 {
                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
    }

    private var totalDuration: String? {
        let total = tracks.compactMap { $0.duration }.reduce(0, +)
        guard total > 0 else { return nil }

        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60

        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        } else {
            return "\(minutes) min"
        }
    }

    private func loadTracks() async {
        isLoading = true
        error = nil

        do {
            tracks = try await libraryViewModel.loadPlaylistTracks(playlist: playlist)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
