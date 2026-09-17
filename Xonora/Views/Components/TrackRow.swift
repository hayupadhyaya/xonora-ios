import SwiftUI

struct TrackRow: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    let track: Track
    let index: Int?
    let showArtwork: Bool
    let isPlaying: Bool
    let numberFirst: Bool
    let onTap: () -> Void

    @State private var isFavorite: Bool
    @State private var showAddToPlaylist = false
    @State private var showSimilarTracks = false
    @State private var showVersions = false
    @State private var showAlbums = false
    @State private var showDeleteConfirmation = false

    init(track: Track, index: Int? = nil, showArtwork: Bool = false, isPlaying: Bool = false, numberFirst: Bool = false, onTap: @escaping () -> Void) {
        self.track = track
        self.index = index
        self.showArtwork = showArtwork
        self.isPlaying = isPlaying
        self.numberFirst = numberFirst
        self.onTap = onTap
        _isFavorite = State(initialValue: track.favorite ?? false)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Track number or playing indicator (before artwork if numberFirst is true)
                if numberFirst, let index = index {
                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .frame(width: 32)
                            .symbolEffect(.variableColor.iterative)
                    } else {
                        Text("\(index)")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(width: 32)
                    }
                }

                // Artwork
                if showArtwork {
                    CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: track.imageUrl ?? track.album?.imageUrl, size: .thumbnail)) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.3))
                            .overlay {
                                Image(systemName: "music.note")
                                    .foregroundColor(.gray)
                            }
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // Track number or playing indicator (after artwork if numberFirst is false)
                if !numberFirst, let index = index {
                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .frame(width: 32)
                            .symbolEffect(.variableColor.iterative)
                    } else {
                        Text("\(index)")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(width: 32)
                    }
                }

                // Track info
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(.body)
                        .foregroundColor(isPlaying ? .accentColor : .primary)
                        .lineLimit(1)

                    Text(track.artistNames)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Duration
                Text(track.formattedDuration)
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Favorite toggle
                Button {
                    isFavorite.toggle()
                    Task {
                        await libraryViewModel.toggleFavorite(item: track)
                    }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(isFavorite ? .pink : .secondary)
                        .font(.body)
                        .frame(width: 32, height: 32)
                }

                // More options menu
                Menu {
                    Button {
                        PlayerManager.shared.playTrack(track, fromQueue: [track])
                    } label: {
                        Label("Play", systemImage: "play")
                    }
                    
                    if let album = track.album {
                        Button {
                            Task {
                                if let tracks = try? await XonoraClient.shared.fetchAlbumTracks(albumId: album.itemId, provider: album.provider) {
                                    await MainActor.run {
                                        PlayerManager.shared.playAlbum(tracks)
                                    }
                                }
                            }
                        } label: {
                            Label("Play Album", systemImage: "opticaldisc")
                        }
                    }

                    Button {
                        showSimilarTracks = true
                    } label: {
                        Label("More Like This", systemImage: "sparkles")
                    }

                    Button {
                        showVersions = true
                    } label: {
                        Label("Other Versions", systemImage: "music.note.list")
                    }

                    Button {
                        showAlbums = true
                    } label: {
                        Label("Show Albums", systemImage: "opticaldisc")
                    }

                    Divider()

                    // Play on... submenu
                    Menu {
                        ForEach(XonoraClient.shared.players.filter { $0.available }) { player in
                            Button {
                                Task {
                                    // Play on selected player
                                    PlayerManager.shared.transferPlayback(to: player, resumePlayback: false)
                                    PlayerManager.shared.playTrack(track, fromQueue: [track])
                                }
                            } label: {
                                HStack {
                                    Text(player.name)
                                    if player.playerId == XonoraClient.shared.currentPlayer?.playerId {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }

                        if XonoraClient.shared.players.filter({ $0.available }).isEmpty {
                            Text("No players available")
                        }
                    } label: {
                        Label("Play on...", systemImage: "airplayaudio")
                    }

                    Divider()

                    Button {
                        PlayerManager.shared.playNext(track)
                    } label: {
                        Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }

                    Button {
                        PlayerManager.shared.addToQueue(track)
                    } label: {
                        Label("Add to Queue", systemImage: "text.badge.plus")
                    }

                    Divider()

                    Button {
                        Task {
                            do {
                                try await XonoraClient.shared.markAsPlayed(track: track)
                                ToastManager.shared.show("Marked \"\(track.name)\" as played", type: .success)
                            } catch {
                                ToastManager.shared.show("Failed to mark as played: \(error.localizedDescription)", type: .error)
                            }
                        }
                    } label: {
                        Label("Mark as Played", systemImage: "checkmark.circle")
                    }

                    Button {
                        Task {
                            do {
                                try await XonoraClient.shared.markAsUnplayed(track: track)
                                ToastManager.shared.show("Marked \"\(track.name)\" as unplayed", type: .success)
                            } catch {
                                ToastManager.shared.show("Failed to mark as unplayed: \(error.localizedDescription)", type: .error)
                            }
                        }
                    } label: {
                        Label("Mark as Unplayed", systemImage: "circle")
                    }

                    Divider()

                    Button {
                        showAddToPlaylist = true
                    } label: {
                        Label("Add to Playlist...", systemImage: "text.badge.plus")
                    }

                    if track.uri.hasPrefix("library://") {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Remove from Library", systemImage: "minus.circle")
                        }
                    } else {
                        Button {
                            Task {
                                do {
                                    try await XonoraClient.shared.addToLibrary(uri: track.uri)
                                    ToastManager.shared.show("Added \"\(track.name)\" to library", type: .success)
                                } catch {
                                    ToastManager.shared.show("Failed to add to library: \(error.localizedDescription)", type: .error)
                                }
                            }
                        } label: {
                            Label("Add to Library", systemImage: "plus.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                .sheet(isPresented: $showAddToPlaylist) {
                    AddToPlaylistSheet(track: track, trackUris: nil)
                }
                .sheet(isPresented: $showSimilarTracks) {
                    SimilarTracksView(track: track)
                        .environmentObject(libraryViewModel)
                }
                .sheet(isPresented: $showVersions) {
                    TrackVersionsView(track: track)
                        .environmentObject(libraryViewModel)
                }
                .sheet(isPresented: $showAlbums) {
                    TrackAlbumsView(track: track)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onChange(of: track.favorite) { _, newValue in
            if let newValue = newValue {
                isFavorite = newValue
            }
        }
        .alert("Delete Track?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await XonoraClient.shared.removeFromLibrary(itemId: track.itemId, mediaType: "track")
                        ToastManager.shared.show("Removed \"\(track.name)\" from library", type: .success)
                    } catch {
                        ToastManager.shared.show("Failed to remove from library: \(error.localizedDescription)", type: .error)
                    }
                }
            }
        } message: {
            Text("This track will be permanently removed from your library and cannot be recovered.")
        }
    }
}

struct TrackRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            TrackRow(
                track: Track(
                    itemId: "1",
                    provider: "apple_music",
                    name: "Sample Track",
                    version: nil,
                    duration: 210,
                    trackNumber: 1,
                    discNumber: 1,
                    uri: "apple_music://track/1",
                    artists: [ArtistReference(itemId: "1", provider: "apple_music", name: "Sample Artist")],
                    album: nil,
                    metadata: nil,
                    providerMappings: nil,
                    image: nil
                ),
                index: 1,
                isPlaying: false,
                onTap: {}
            )

            TrackRow(
                track: Track(
                    itemId: "2",
                    provider: "apple_music",
                    name: "Currently Playing Track",
                    version: nil,
                    duration: 185,
                    trackNumber: 2,
                    discNumber: 1,
                    uri: "apple_music://track/2",
                    artists: [ArtistReference(itemId: "1", provider: "apple_music", name: "Sample Artist")],
                    album: nil,
                    metadata: nil,
                    providerMappings: nil,
                    image: nil
                ),
                index: 2,
                isPlaying: true,
                onTap: {}
            )
        }
        .padding()
    }
}
struct AddToPlaylistSheet: View {
    let track: Track?
    let trackUris: [String]?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @State private var newPlaylistName = ""
    @State private var isCreating = false
    
    // Support adding a single track or multiple URIs
    private var targetUris: [String] {
        if let uris = trackUris { return uris }
        if let track = track { return [track.uri] }
        return []
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New Playlist Name", text: $newPlaylistName)
                            .submitLabel(.done)
                            .onSubmit {
                                if !newPlaylistName.isEmpty {
                                    createAndAdd()
                                }
                            }
                        
                        if isCreating {
                            ProgressView()
                        } else {
                            Button("Create") { createAndAdd() }
                                .disabled(newPlaylistName.isEmpty)
                        }
                    }
                } header: {
                    Text("Create New Playlist")
                }

                Section("Your Playlists") {
                    ForEach(libraryViewModel.playlists) { playlist in
                        if playlist.isEditable != false {
                            Button {
                                addToPlaylist(playlist)
                            } label: {
                                HStack(spacing: 12) {
                                    // Artwork
                                    let imageURL = XonoraClient.shared.getImageURL(for: playlist.imageUrl, size: .thumbnail)
                                    CachedAsyncImage(url: imageURL) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.gray.opacity(0.3))
                                            .overlay {
                                                Image(systemName: "music.note.list")
                                                    .foregroundColor(.gray)
                                            }
                                    }
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    
                                    Text(playlist.name)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    if playlist.provider == "library" {
                                        Image(systemName: "server.rack")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func createAndAdd() {
        guard !newPlaylistName.isEmpty else { return }
        isCreating = true
        
        Task {
            if let playlist = await libraryViewModel.createPlaylist(name: newPlaylistName) {
                addToPlaylist(playlist)
            }
            isCreating = false
        }
    }
    
    private func addToPlaylist(_ playlist: Playlist) {
        Task {
            do {
                try await XonoraClient.shared.addToPlaylist(
                    playlistId: playlist.itemId,
                    provider: playlist.provider,
                    trackUris: targetUris
                )
                // Invalidate cache for this playlist
                await MetadataCache.shared.invalidatePlaylistTracks(playlistId: playlist.itemId)
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                print("Failed to add to playlist: \(error)")
            }
        }
    }
}
