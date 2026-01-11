import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @ObservedObject private var playerManager = PlayerManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var isPresentedModally: Bool = true

    @State private var dragOffset: CGFloat = 0
    @State private var showQueue = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.top, 16) // Standard padding

            Spacer()

            // Album artwork
            albumArtwork
                .padding(.horizontal, 40)
                .padding(.vertical, 20)

            Spacer()

            // Track info
            trackInfo
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

            // Controls
            PlayerControls(playerManager: playerManager, size: .full)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(
            backgroundView.ignoresSafeArea()
        )
        .gesture(
            isPresentedModally ? 
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 100 {
                        dismiss()
                    }
                    dragOffset = 0
                }
            : nil
        )
        .offset(y: dragOffset)
        .animation(.interactiveSpring(), value: dragOffset)
        .sheet(isPresented: $showQueue) {
            QueueView()
        }
        .preferredColorScheme(.dark)
    }

    private var backgroundView: some View {
        ZStack {
            AsyncImage(url: trackImageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 60)
                        .scaleEffect(1.2)
                case .failure, .empty:
                    Color.xonoraGradient
                @unknown default:
                    Color.xonoraGradient
                }
            }

            Color.black.opacity(0.3)
        }
    }

    private var header: some View {
        HStack {
            if isPresentedModally {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
            } else {
                Spacer().frame(width: 44) // Balance layout
            }

            Spacer()

            VStack(spacing: 2) {
                Text("PLAYING FROM")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.7))

                Text(playerManager.currentTrack?.album?.name ?? "Library")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal)
    }

    private var albumArtwork: some View {
        AsyncImage(url: trackImageURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .failure:
                artworkPlaceholder
            case .empty:
                artworkPlaceholder
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            @unknown default:
                artworkPlaceholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 20)
        .scaleEffect(playerManager.isPlaying ? 1.0 : 0.95)
        .animation(.easeInOut(duration: 0.3), value: playerManager.isPlaying)
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [.gray.opacity(0.4), .gray.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 80))
                    .foregroundColor(.white.opacity(0.5))
            }
    }

    private var trackInfo: some View {
        VStack(spacing: 4) {
            Text(playerManager.currentTrack?.name ?? "Not Playing")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(1)

            Text(playerManager.currentTrack?.artistNames ?? "")
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
        }
    }

    private var trackImageURL: URL? {
        let imageString = playerManager.currentTrack?.imageUrl ?? playerManager.currentTrack?.album?.imageUrl
        return XonoraClient.shared.getImageURL(for: imageString, size: .large)
    }

    private var thumbnailImageURL: URL? {
        let imageString = playerManager.currentTrack?.imageUrl ?? playerManager.currentTrack?.album?.imageUrl
        return XonoraClient.shared.getImageURL(for: imageString, size: .thumbnail)
    }
}

struct QueueView: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if playerManager.queue.isEmpty {
                    emptyQueueView
                } else {
                    queueSection
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if !playerManager.queue.isEmpty {
                        Button("Clear") {
                            playerManager.clearQueue()
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var emptyQueueView: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                "Queue is Empty",
                systemImage: "music.note.list",
                description: Text("Add some songs to your queue")
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)
                Text("Queue is Empty")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Add some songs to your queue")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }
    
    private var queueSection: some View {
        Section {
            ForEach(Array(playerManager.queue.enumerated()), id: \.element.id) { index, track in
                queueRow(for: track, at: index)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playerManager.playTrack(track)
                    }
            }
        } header: {
            Text("Up Next")
        }
    }
    
    @ViewBuilder
    private func queueRow(for track: Track, at index: Int) -> some View {
        HStack(spacing: 12) {
            indexOrPlayingIndicator(for: index)
            
            trackThumbnail(for: track)
            
            trackDetails(for: track, at: index)
            
            Spacer()
            
            Text(track.formattedDuration)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private func indexOrPlayingIndicator(for index: Int) -> some View {
        if index == playerManager.currentIndex {
            if #available(iOS 17.0, *) {
                Image(systemName: "waveform")
                    .foregroundColor(.accentColor)
                    .symbolEffect(.variableColor.iterative)
                    .frame(width: 20)
            } else {
                Image(systemName: "waveform")
                    .foregroundColor(.accentColor)
                    .frame(width: 20)
            }
        } else {
            Text("\(index + 1)")
                .foregroundColor(.secondary)
                .frame(width: 20)
        }
    }
    
    private func trackThumbnail(for track: Track) -> some View {
        let imageURL = XonoraClient.shared.getImageURL(for: track.imageUrl ?? track.album?.imageUrl, size: .thumbnail)

        return CachedAsyncImage(url: imageURL) {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
        }
        .aspectRatio(contentMode: .fill)
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    
    private func trackDetails(for track: Track, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.name)
                .font(.body)
                .foregroundColor(index == playerManager.currentIndex ? .accentColor : .primary)
                .lineLimit(1)
            
            Text(track.artistNames)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

struct NowPlayingView_Previews: PreviewProvider {
    static var previews: some View {
        NowPlayingView()
            .environmentObject(PlayerViewModel())
    }
}
