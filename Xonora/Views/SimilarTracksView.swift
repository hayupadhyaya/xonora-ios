import SwiftUI

struct SimilarTracksView: View {
    let track: Track

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @State private var similarTracks: [Track] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Finding similar tracks...")
                            .foregroundColor(.secondary)
                    }
                } else if let error = error {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text("No Similar Tracks Found")
                            .font(.title3.bold())

                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Retry") {
                            Task { await loadSimilarTracks() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                } else if similarTracks.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text("No Similar Tracks Found")
                            .font(.title3.bold())

                        Text("We couldn't find tracks similar to \"\(track.name)\"")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    VStack(spacing: 0) {
                        // Play All button
                        Button {
                            playerViewModel.playAlbum(similarTracks)
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Play All")
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
                        .padding(.horizontal)
                        .padding(.vertical, 16)

                        // Track list
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(similarTracks.enumerated()), id: \.element.id) { index, similarTrack in
                                    TrackRow(
                                        track: similarTrack,
                                        index: index + 1,
                                        showArtwork: true,
                                        isPlaying: playerViewModel.playerManager.currentTrack?.id == similarTrack.id,
                                        onTap: {
                                            playerViewModel.playAlbum(similarTracks, startingAt: index)
                                        }
                                    )
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Similar to \(track.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadSimilarTracks()
        }
    }

    private func loadSimilarTracks() async {
        isLoading = true
        error = nil

        do {
            similarTracks = try await XonoraClient.shared.fetchSimilarTracks(for: track, limit: 25)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
