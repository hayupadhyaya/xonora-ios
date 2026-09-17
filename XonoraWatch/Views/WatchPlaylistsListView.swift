//
//  WatchPlaylistsListView.swift
//  XonoraWatch
//
//  Playlists list view.
//

import SwiftUI

struct WatchPlaylistsListView: View {
    @EnvironmentObject var dataProvider: WatchConnectivityProvider

    var body: some View {
        List {
            if dataProvider.librarySnapshot.playlists.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)

                    Text("No Playlists")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
            } else {
                ForEach(dataProvider.librarySnapshot.playlists) { playlist in
                    Button {
                        Task {
                            await dataProvider.playMedia(uri: playlist.uri)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            // Playlist artwork thumbnail
                            if let imageURLString = playlist.imageURLString,
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
                                        Image(systemName: "music.note.list")
                                            .foregroundColor(.secondary)
                                            .frame(width: 50, height: 50)
                                            .background(Color.gray.opacity(0.2))
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            } else {
                                Image(systemName: "music.note.list")
                                    .foregroundColor(.secondary)
                                    .frame(width: 50, height: 50)
                                    .background(Color.gray.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }

                            // Playlist info
                            VStack(alignment: .leading, spacing: 3) {
                                Text(playlist.name)
                                    .font(.headline)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Playlists")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        WatchPlaylistsListView()
    }
    .environmentObject(WatchConnectivityProvider.previewPlaying)
}
#endif
