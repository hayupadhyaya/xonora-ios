//
//  WatchArtistsListView.swift
//  XonoraWatch
//
//  Artists list view.
//

import SwiftUI

struct WatchArtistsListView: View {
    @EnvironmentObject var dataProvider: WatchConnectivityProvider

    var body: some View {
        List {
            if dataProvider.librarySnapshot.artists.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.mic")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)

                    Text("No Artists")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
            } else {
                ForEach(dataProvider.librarySnapshot.artists) { artist in
                    Button {
                        Task {
                            // Play artist (shuffle play all artist tracks)
                            await dataProvider.playMedia(uri: artist.id)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            // Artist image thumbnail
                            if let imageURLString = artist.imageURLString,
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
                                            .clipShape(Circle())
                                    case .failure:
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.secondary)
                                            .frame(width: 50, height: 50)
                                            .background(Color.gray.opacity(0.2))
                                            .clipShape(Circle())
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            } else {
                                Image(systemName: "person.fill")
                                    .foregroundColor(.secondary)
                                    .frame(width: 50, height: 50)
                                    .background(Color.gray.opacity(0.2))
                                    .clipShape(Circle())
                            }

                            // Artist name
                            VStack(alignment: .leading, spacing: 3) {
                                Text(artist.name)
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
        .navigationTitle("Artists")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        WatchArtistsListView()
    }
    .environmentObject(WatchConnectivityProvider.previewPlaying)
}
#endif

