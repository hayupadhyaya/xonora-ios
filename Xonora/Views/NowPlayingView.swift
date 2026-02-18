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
        .colorScheme(.dark)
        .background(
            albumArtView.ignoresSafeArea()
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
    }
    
    private var albumArtView: some View {
        ZStack {
            AsyncImage(url: trackImageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 30) // Reduced from 60 to improve rendering performance
                        .scaleEffect(1.1)
                case .failure, .empty:
                    Color.xonoraGradient
                @unknown default:
                    Color.xonoraGradient
                }
            }

            Color.black.opacity(0.5)
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

                Text(playerManager.currentSource ?? playerManager.currentTrack?.album?.name ?? "Library")
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

// MARK: - Player Card

struct PlayerCard: View {
    let player: MAPlayer
    let isSelected: Bool
    let onTap: () -> Void

    /// Determine if this player is currently playing (from player's own state)
    private var isPlaying: Bool {
        player.state == .playing
    }

    /// Get the current media from the player itself
    private var currentMedia: CurrentMedia? {
        player.currentMedia
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Player icon and status
                HStack(spacing: 8) {
                    // Player icon
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                            .frame(width: 32, height: 32)

                        Image(systemName: player.provider == "sendspin" ? "iphone" : "hifispeaker.fill")
                            .font(.system(size: 14))
                            .foregroundColor(isSelected ? .accentColor : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.name)
                            .font(.caption)
                            .fontWeight(isSelected ? .semibold : .medium)
                            .foregroundColor(isSelected ? .primary : .secondary)
                            .lineLimit(1)

                        if isPlaying {
                            HStack(spacing: 4) {
                                if #available(iOS 17.0, *) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 8))
                                        .foregroundColor(.accentColor)
                                        .symbolEffect(.variableColor.iterative)
                                } else {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 8))
                                        .foregroundColor(.accentColor)
                                }
                                Text("Playing")
                                    .font(.system(size: 9))
                                    .foregroundColor(.accentColor)
                            }
                        } else if player.state == .paused {
                            Text("Paused")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                        } else if !player.available {
                            Text("Unavailable")
                                .font(.system(size: 9))
                                .foregroundColor(.red.opacity(0.7))
                        } else if isSelected {
                            Text("Selected")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                    }
                }

                // Track info from player's currentMedia (shows what's playing on THIS player)
                if let media = currentMedia, media.title != nil {
                    HStack(spacing: 8) {
                        // Track artwork
                        let imageURL = XonoraClient.shared.getImageURL(for: media.imageUrlResolved, size: .thumbnail)
                        CachedAsyncImage(url: imageURL) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.3))
                                .overlay {
                                    Image(systemName: "music.note")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(media.title ?? "Unknown")
                                .font(.system(size: 11))
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Text(media.artist ?? "Unknown Artist")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                } else {
                    // Empty state - no media playing on this player
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 36, height: 36)
                            .overlay {
                                Image(systemName: "music.note")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray.opacity(0.5))
                            }

                        Text("Nothing playing")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .frame(width: 160)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Queue Tab View (for bottom tab bar)

struct QueueTabView: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    @ObservedObject private var xonoraClient = XonoraClient.shared
    @State private var showSleepTimerSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Horizontal Player Cards
                playerCardsSection
                    .padding(.top, 8)

                // Sleep Timer Banner (if active)
                if playerManager.isSleepTimerActive {
                    sleepTimerBanner
                }

                // Queue List
                List {
                    // Now Playing Section
                    if let currentTrack = playerManager.currentTrack {
                        nowPlayingSection(track: currentTrack)
                    }

                    // Queue Section
                    if playerManager.queue.isEmpty {
                        emptyQueueView
                    } else {
                        queueSection
                    }
                }
                .listStyle(.insetGrouped)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Queue")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSleepTimerSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: playerManager.isSleepTimerActive ? "moon.fill" : "moon.zzz")
                            if playerManager.isSleepTimerActive {
                                Text(playerManager.sleepTimerRemainingFormatted)
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                        }
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
            .sheet(isPresented: $showSleepTimerSheet) {
                SleepTimerSheet()
            }
        }
    }

    // MARK: - Sleep Timer Banner

    private var sleepTimerBanner: some View {
        HStack {
            Image(systemName: "moon.fill")
                .foregroundColor(.indigo)
            Text("Sleep timer: \(playerManager.sleepTimerRemainingFormatted)")
                .font(.subheadline)
                .monospacedDigit()
            Spacer()
            Button("Cancel") {
                playerManager.cancelSleepTimer()
            }
            .font(.subheadline)
            .foregroundColor(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.indigo.opacity(0.1))
    }

    // MARK: - Player Cards Section

    private var playerCardsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PLAYERS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Show all players, available ones first
                    ForEach(xonoraClient.players.sorted { $0.available && !$1.available }) { player in
                        PlayerCard(
                            player: player,
                            isSelected: player.playerId == xonoraClient.currentPlayer?.playerId
                        ) {
                            guard player.available else { return }

                            if player.playerId != xonoraClient.currentPlayer?.playerId {
                                // Switch to this player
                                playerManager.transferPlayback(to: player, resumePlayback: true)
                            } else {
                                // Already selected - refresh the queue from server
                                Task {
                                    await playerManager.fetchQueueFromServer(for: player)
                                }
                            }
                        }
                        .opacity(player.available ? 1.0 : 0.5)
                        .allowsHitTesting(player.available)
                    }

                    // Empty state if no players at all
                    if xonoraClient.players.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "speaker.slash")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("No players")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 140, height: 100)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Now Playing Section

    private func nowPlayingSection(track: Track) -> some View {
        Section {
            HStack(spacing: 12) {
                // Artwork
                let imageURL = XonoraClient.shared.getImageURL(for: track.imageUrl ?? track.album?.imageUrl, size: .thumbnail)
                CachedAsyncImage(url: imageURL) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            Image(systemName: "music.note")
                                .foregroundColor(.gray)
                        }
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(.headline)
                        .foregroundColor(.accentColor)
                        .lineLimit(1)

                    Text(track.artistNames)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    // Progress indicator
                    if playerManager.duration > 0 {
                        ProgressView(value: playerManager.currentTime, total: playerManager.duration)
                            .tint(.accentColor)
                    }
                }

                Spacer()

                // Play/Pause button
                Button {
                    playerManager.togglePlayPause()
                } label: {
                    Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Now Playing")
        }
    }

    // MARK: - Queue Section

    @ViewBuilder
    private var emptyQueueView: some View {
        Section {
            if #available(iOS 17.0, *) {
                ContentUnavailableView(
                    "Queue is Empty",
                    systemImage: "music.note.list",
                    description: Text("Play some music or add songs to your queue")
                )
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("Queue is Empty")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Play some music or add songs to your queue")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        } header: {
            Text("Up Next")
        }
    }

    private var queueSection: some View {
        Section {
            ForEach(Array(playerManager.queue.enumerated()), id: \.element.id) { index, track in
                queueRow(for: track, at: index)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playerManager.currentIndex = index
                        playerManager.playTrack(track, fromQueue: playerManager.queue, sourceName: playerManager.currentSource)
                    }
            }
        } header: {
            HStack {
                Text("Up Next")
                Spacer()
                Text("\(playerManager.queue.count) tracks")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func queueRow(for track: Track, at index: Int) -> some View {
        HStack(spacing: 12) {
            // Index or playing indicator
            if index == playerManager.currentIndex {
                if #available(iOS 17.0, *) {
                    Image(systemName: "waveform")
                        .foregroundColor(.accentColor)
                        .symbolEffect(.variableColor.iterative)
                        .frame(width: 24)
                } else {
                    Image(systemName: "waveform")
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                }
            } else {
                Text("\(index + 1)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(width: 24)
            }

            // Thumbnail
            let imageURL = XonoraClient.shared.getImageURL(for: track.imageUrl ?? track.album?.imageUrl, size: .thumbnail)
            CachedAsyncImage(url: imageURL) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Track info
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

            Spacer()

            // Duration
            Text(track.formattedDuration)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Player Selection Section

    private var playerSelectionSection: some View {
        Section {
            if xonoraClient.players.filter({ $0.available }).isEmpty {
                HStack {
                    Image(systemName: "speaker.slash")
                        .foregroundColor(.secondary)
                    Text("No players available")
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(xonoraClient.players.filter { $0.available }) { player in
                    Button {
                        print("[QueueTabView] User selected player: \(player.name)")
                        playerManager.transferPlayback(to: player, resumePlayback: true)
                    } label: {
                        HStack {
                            Image(systemName: player.provider == "sendspin" ? "iphone" : "speaker.wave.2")
                                .foregroundColor(player.playerId == xonoraClient.currentPlayer?.playerId ? .accentColor : .primary)
                                .frame(width: 28)

                            Text(player.name)
                                .foregroundColor(player.playerId == xonoraClient.currentPlayer?.playerId ? .accentColor : .primary)

                            Spacer()

                            if player.playerId == xonoraClient.currentPlayer?.playerId {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Playing On")
        } footer: {
            if let player = xonoraClient.currentPlayer {
                Text("Music will play on \(player.name)")
            }
        }
    }
}

// MARK: - Player Picker Sheet

struct PlayerPickerSheet: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    @ObservedObject private var xonoraClient = XonoraClient.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if xonoraClient.players.filter({ $0.available }).isEmpty {
                    ContentUnavailableView(
                        "No Players Available",
                        systemImage: "speaker.slash",
                        description: Text("Connect to Music Assistant to see available players")
                    )
                } else {
                    ForEach(xonoraClient.players.filter { $0.available }) { player in
                        Button {
                            if player.playerId != xonoraClient.currentPlayer?.playerId {
                                playerManager.transferPlayback(to: player, resumePlayback: true)
                            }
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                // Player icon
                                ZStack {
                                    Circle()
                                        .fill(player.playerId == xonoraClient.currentPlayer?.playerId ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.1))
                                        .frame(width: 44, height: 44)

                                    Image(systemName: player.provider == "sendspin" ? "iphone" : "hifispeaker.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(player.playerId == xonoraClient.currentPlayer?.playerId ? .accentColor : .primary)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(player.name)
                                        .font(.body)
                                        .fontWeight(player.playerId == xonoraClient.currentPlayer?.playerId ? .semibold : .regular)
                                        .foregroundColor(.primary)

                                    Text(player.provider == "sendspin" ? "This device" : "External speaker")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if player.playerId == xonoraClient.currentPlayer?.playerId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                        .font(.title3)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Select Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Sleep Timer Sheet

struct SleepTimerSheet: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showCustomPicker = false
    @State private var customHours = 0
    @State private var customMinutes = 30

    private let presetOptions: [(label: String, minutes: Int)] = [
        ("15 minutes", 15),
        ("30 minutes", 30),
        ("45 minutes", 45),
        ("1 hour", 60),
        ("1.5 hours", 90),
        ("2 hours", 120),
        ("3 hours", 180)
    ]

    var body: some View {
        NavigationStack {
            List {
                // Current timer status
                if playerManager.isSleepTimerActive {
                    Section {
                        HStack {
                            Image(systemName: "moon.fill")
                                .foregroundColor(.indigo)
                                .font(.title2)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Timer Active")
                                    .font(.headline)
                                Text("Stops in \(playerManager.sleepTimerRemainingFormatted)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }

                            Spacer()

                            Button("Cancel") {
                                playerManager.cancelSleepTimer()
                            }
                            .foregroundColor(.red)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Preset options
                Section {
                    ForEach(presetOptions, id: \.minutes) { option in
                        Button {
                            playerManager.setSleepTimer(minutes: option.minutes)
                            dismiss()
                        } label: {
                            HStack {
                                Text(option.label)
                                    .foregroundColor(.primary)
                                Spacer()
                                if isTimerSetTo(minutes: option.minutes) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Stop music after")
                }

                // Custom time option
                Section {
                    Button {
                        showCustomPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "clock")
                            Text("Custom time...")
                                .foregroundColor(.primary)
                            Spacer()
                            if showCustomPicker {
                                Image(systemName: "chevron.up")
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "chevron.down")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if showCustomPicker {
                        VStack(spacing: 16) {
                            HStack {
                                // Hours picker
                                VStack {
                                    Text("Hours")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Picker("Hours", selection: $customHours) {
                                        ForEach(0..<13) { hour in
                                            Text("\(hour)").tag(hour)
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    .frame(width: 80, height: 120)
                                    .clipped()
                                }

                                // Minutes picker
                                VStack {
                                    Text("Minutes")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Picker("Minutes", selection: $customMinutes) {
                                        ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { minute in
                                            Text("\(minute)").tag(minute)
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    .frame(width: 80, height: 120)
                                    .clipped()
                                }
                            }

                            Button {
                                let totalSeconds = (customHours * 3600) + (customMinutes * 60)
                                if totalSeconds > 0 {
                                    playerManager.setSleepTimer(seconds: TimeInterval(totalSeconds))
                                    dismiss()
                                }
                            } label: {
                                Text("Set Timer")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.accentColor)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .disabled(customHours == 0 && customMinutes == 0)
                        }
                        .padding(.vertical, 8)
                    }
                } header: {
                    Text("Custom")
                }

                // End of track option
                Section {
                    Button {
                        // Set timer for remaining duration of current track
                        if playerManager.duration > 0 {
                            let remaining = playerManager.duration - playerManager.currentTime
                            playerManager.setSleepTimer(seconds: max(60, remaining))
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "music.note")
                            Text("End of current track")
                                .foregroundColor(.primary)
                        }
                    }
                    .disabled(playerManager.currentTrack == nil || playerManager.duration == 0)
                } header: {
                    Text("Other options")
                }

                // Turn off timer
                if playerManager.isSleepTimerActive {
                    Section {
                        Button(role: .destructive) {
                            playerManager.cancelSleepTimer()
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "xmark.circle")
                                Text("Turn Off Timer")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func isTimerSetTo(minutes: Int) -> Bool {
        guard playerManager.isSleepTimerActive else { return false }
        let currentMinutes = Int(playerManager.sleepTimerRemaining / 60)
        // Allow some tolerance (within 1 minute)
        return abs(currentMinutes - minutes) <= 1
    }
}

struct NowPlayingView_Previews: PreviewProvider {
    static var previews: some View {
        NowPlayingView()
            .environmentObject(PlayerViewModel())
    }
}
