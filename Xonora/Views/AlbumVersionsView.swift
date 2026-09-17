import SwiftUI

struct AlbumVersionsView: View {
    let album: Album

    @Environment(\.dismiss) private var dismiss
    @State private var versions: [Album] = []
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
                        Image(systemName: "opticaldisc")
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
                        Image(systemName: "opticaldisc")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text("No Other Versions")
                            .font(.title3.bold())

                        Text("This is the only version of \"\(album.name)\" available")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(versions) { version in
                                NavigationLink(destination: AlbumDetailView(album: version)) {
                                    HStack(spacing: 12) {
                                        // Album artwork
                                        CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: version.imageUrl, size: .thumbnail)) {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.gray.opacity(0.3))
                                                .overlay {
                                                    Image(systemName: "opticaldisc")
                                                        .foregroundColor(.gray)
                                                }
                                        }
                                        .aspectRatio(1, contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(version.name)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                                .lineLimit(2)

                                            if let versionText = version.version {
                                                Text(versionText)
                                                    .font(.caption)
                                                    .foregroundColor(.pink)
                                                    .lineLimit(1)
                                            }

                                            HStack(spacing: 4) {
                                                Text(version.provider.capitalized)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)

                                                if let year = version.year {
                                                    Text("•")
                                                        .foregroundColor(.secondary)
                                                        .font(.caption2)
                                                    Text("\(year)")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Versions of \(album.name)")
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
            versions = try await XonoraClient.shared.fetchAlbumVersions(itemId: album.itemId, provider: album.provider)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
