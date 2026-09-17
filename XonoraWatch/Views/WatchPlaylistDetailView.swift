//
//  WatchPlaylistDetailView.swift
//  XonoraWatch
//
//  Playlist detail view showing track list.
//

import SwiftUI

struct WatchPlaylistDetailView: View {
    @EnvironmentObject var dataProvider: WatchConnectivityProvider
    let playlist: WatchPlaylistInfo

    @State private var tracks: [WatchTrackInfo] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Playlist name at top
                Text(playlist.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
                    .padding(.top, 8)

                if isLoading {
                    ProgressView()
                        .padding()
                } else if tracks.isEmpty {
                    Text("No tracks available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    // Play All and Shuffle buttons
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await dataProvider.playMedia(uri: playlist.uri)
                            }
                        } label: {
                            Label("Play All", systemImage: "play.fill")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            Task {
                                await dataProvider.sendCommand(.toggleShuffle, payload: nil)
                                await dataProvider.playMedia(uri: playlist.uri)
                            }
                        } label: {
                            Label("Shuffle", systemImage: "shuffle")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)

                    // Track list
                    ForEach(Array(tracks.enumerated()), id: \.element.uri) { index, track in
                        Button {
                            Task {
                                await dataProvider.playMedia(uri: track.uri)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                // Track number
                                Text("\(index + 1)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 20, alignment: .trailing)

                                // Track name
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.name)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text(track.artistNames)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                // Duration
                                if let duration = track.duration {
                                    Text(formatDuration(duration))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom)
        }
        .navigationTitle("Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadTracks()
        }
    }

    private func loadTracks() async {
        // For now, just play - in future, implement playlist track fetching
        // This would require adding a fetchPlaylistTracks method similar to fetchAlbumTracks
        isLoading = false
        // TODO: Implement playlist track fetching
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        WatchPlaylistDetailView(playlist: WatchPlaylistInfo(
            itemId: "p1",
            name: "Chill Vibes",
            imageURLString: nil,
            uri: "library://playlist/1"
        ))
    }
    .environmentObject(WatchConnectivityProvider.previewPlaying)
}
#endif
