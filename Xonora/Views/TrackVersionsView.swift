import SwiftUI

struct TrackVersionsView: View {
    let track: Track

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @State private var versions: [Track] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Finding versions...")
                            .foregroundColor(.secondary)
                    }
                } else if let error = error {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text("No Versions Found")
                            .font(.title3.bold())

                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Retry") {
                            Task { await loadVersions() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                } else if versions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text("No Other Versions")
                            .font(.title3.bold())

                        Text("This is the only version of \"\(track.name)\" available")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                                TrackRow(
                                    track: version,
                                    showArtwork: true,
                                    isPlaying: playerViewModel.playerManager.currentTrack?.id == version.id,
                                    onTap: {
                                        playerViewModel.playerManager.playTrack(version, fromQueue: [version])
                                    }
                                )
                                .padding(.horizontal)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Versions of \(track.name)")
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
            await loadVersions()
        }
    }

    private func loadVersions() async {
        isLoading = true
        error = nil

        do {
            versions = try await XonoraClient.shared.fetchTrackVersions(itemId: track.itemId, provider: track.provider)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
