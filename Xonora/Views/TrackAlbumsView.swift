import SwiftUI

struct TrackAlbumsView: View {
    let track: Track

    @Environment(\.dismiss) private var dismiss
    @State private var albums: [Album] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Finding albums...")
                            .foregroundColor(.secondary)
                    }
                } else if let error = error {
                    VStack(spacing: 16) {
                        Image(systemName: "opticaldisc")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text("No Albums Found")
                            .font(.title3.bold())

                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Retry") {
                            Task { await loadAlbums() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                } else if albums.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "opticaldisc")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text("No Albums Found")
                            .font(.title3.bold())

                        Text("\"\(track.name)\" doesn't appear on any other albums")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                            ForEach(albums) { album in
                                NavigationLink(destination: AlbumDetailView(album: album)) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: album.imageUrl, size: .small)) {
                                            Rectangle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.5)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .overlay {
                                                    Image(systemName: "opticaldisc")
                                                        .font(.largeTitle)
                                                        .foregroundColor(.gray)
                                                }
                                        }
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(album.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.primary)
                                                .lineLimit(2)

                                            Text(album.artistNames)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)

                                            if let year = album.year {
                                                Text("\(year)")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .frame(width: 150)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Albums with \(track.name)")
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
            await loadAlbums()
        }
    }

    private func loadAlbums() async {
        isLoading = true
        error = nil

        do {
            albums = try await XonoraClient.shared.fetchTrackAlbums(itemId: track.itemId, provider: track.provider)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
