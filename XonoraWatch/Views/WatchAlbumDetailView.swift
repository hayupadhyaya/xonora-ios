//
//  WatchAlbumDetailView.swift
//  XonoraWatch
//
//  Album detail view showing track list with Play All and Shuffle options.
//

import SwiftUI

struct WatchAlbumDetailView: View {
    @EnvironmentObject var dataProvider: WatchConnectivityProvider
    let album: WatchAlbumInfo

    @State private var tracks: [WatchTrackInfo] = []
    @State private var isLoading = true
    @State private var albumName: String = ""
    @State private var artistNames: String = ""
    @State private var currentImage: UIImage? = nil
    @State private var previousImage: UIImage? = nil
    @State private var previousOpacity: Double = 0.0

    var body: some View {
        ZStack {
            // Background artwork fills entire screen
            backgroundArtwork
                .ignoresSafeArea(.all)

            // Dark gradient for text readability
            LinearGradient(
                colors: [
                    Color.black.opacity(0.3),
                    Color.black.opacity(0.05),
                    Color.black.opacity(0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(.all)

            ScrollView {
                VStack(spacing: 12) {

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
                                    await dataProvider.playMedia(uri: album.uri)
                                }
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                Task {
                                    // Play with shuffle (send special command or just enable shuffle then play)
                                    await dataProvider.sendCommand(.toggleShuffle, payload: nil)
                                    await dataProvider.playMedia(uri: album.uri)
                                }
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, minHeight: 36)
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

                                        if !track.artistNames.isEmpty && track.artistNames != artistNames {
                                            Text(track.artistNames)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    // Duration
                                    if let duration = track.duration {
                                        Text(formatDuration(duration))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadTracks()
            if let urlString = album.imageURLString, let url = URL(string: urlString) {
                currentImage = await fetchImage(from: url)
            }
        }
    }

    // MARK: - Background artwork

    @ViewBuilder
    private var backgroundArtwork: some View {
        ZStack {
            Color.black

            // Layer 1 (bottom): incoming / current artwork
            if let img = currentImage {
                artworkLayer(image: img)
            }

            // Layer 2 (top): outgoing artwork, fades out to reveal layer below
            if let img = previousImage {
                artworkLayer(image: img)
                    .opacity(previousOpacity)
            }
        }
    }

    @ViewBuilder
    private func artworkLayer(image: UIImage) -> some View {
        GeometryReader { geometry in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .blur(radius: 2)
                .opacity(0.5)
        }
    }

    private func fetchImage(from url: URL) async -> UIImage? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return UIImage(data: data)
    }

    private func loadTracks() async {
        isLoading = true

        if let response = await dataProvider.fetchAlbumTracks(albumId: album.itemId) {
            await MainActor.run {
                self.tracks = response.tracks
                self.albumName = response.albumName
                self.artistNames = response.artistNames
                self.isLoading = false
            }
        } else {
            await MainActor.run {
                self.isLoading = false
            }
        }
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
        WatchAlbumDetailView(album: WatchAlbumInfo(
            itemId: "a1",
            provider: "spotify",
            name: "After Hours",
            artistNames: "The Weeknd",
            year: 2020,
            imageURLString: nil,
            uri: "library://album/1"
        ))
    }
    .environmentObject(WatchConnectivityProvider.previewPlaying)
}
#endif
