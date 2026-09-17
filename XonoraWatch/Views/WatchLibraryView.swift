//
//  WatchLibraryView.swift
//  XonoraWatch
//
//  Library navigation view.
//

import SwiftUI

struct WatchLibraryView: View {
    @EnvironmentObject var dataProvider: WatchConnectivityProvider

    var body: some View {
        NavigationStack {
            List {
                NavigationLink(destination: WatchAlbumsListView()) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Albums")
                                .font(.headline)
                            Text("\(dataProvider.librarySnapshot.albums.count) albums")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "square.stack")
                            .foregroundColor(.accentColor)
                    }
                }

                NavigationLink(destination: WatchPlaylistsListView()) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Playlists")
                                .font(.headline)
                            Text("\(dataProvider.librarySnapshot.playlists.count) playlists")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "music.note.list")
                            .foregroundColor(.accentColor)
                    }
                }

                NavigationLink(destination: WatchArtistsListView()) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Artists")
                                .font(.headline)
                            Text("\(dataProvider.librarySnapshot.artists.count) artists")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "music.mic")
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .navigationTitle("Library")
        }
    }
}

#if DEBUG
#Preview {
    WatchLibraryView()
        .environmentObject(WatchConnectivityProvider.previewPlaying)
}
#endif
