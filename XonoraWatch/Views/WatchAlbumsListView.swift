//
//  WatchAlbumsListView.swift
//  XonoraWatch
//
//  Albums list view.
//

import SwiftUI

struct WatchAlbumsListView: View {
    @EnvironmentObject var dataProvider: WatchConnectivityProvider

    var body: some View {
        List {
            if dataProvider.librarySnapshot.albums.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)

                    Text("No Albums")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
            } else {
                ForEach(dataProvider.librarySnapshot.albums) { album in
                    NavigationLink(destination: WatchAlbumDetailView(album: album)) {
                        HStack(spacing: 10) {
                            // Album artwork thumbnail
                            if let imageURLString = album.imageURLString,
                               let imageURL = URL(string: imageURLString) {
                                AsyncImage(url: imageURL) { phase in
                                    switch phase {
                                    case .empty:
                                        ProgressView()
                                            .frame(width: 50, height: 50)
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 50, height: 50)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    case .failure:
                                        Image(systemName: "music.note")
                                            .foregroundColor(.secondary)
                                            .frame(width: 50, height: 50)
                                            .background(Color.gray.opacity(0.2))
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            } else {
                                Image(systemName: "music.note")
                                    .foregroundColor(.secondary)
                                    .frame(width: 50, height: 50)
                                    .background(Color.gray.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }

                            // Album info
                            VStack(alignment: .leading, spacing: 3) {
                                Text(album.name)
                                    .font(.headline)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(spacing: 4) {
                                    Text(album.artistNames)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)

                                    if let year = album.year {
                                        Text("·")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(String(format: "%d", year))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle("Albums")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        WatchAlbumsListView()
    }
    .environmentObject(WatchConnectivityProvider.previewPlaying)
}
#endif
