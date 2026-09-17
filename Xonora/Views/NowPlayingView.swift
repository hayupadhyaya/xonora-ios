import SwiftUI
import AVKit
import MediaPlayer

// MARK: - Now Playing Scale Environment Key

/// Propagates a proportional scale factor (0.7 … 1.15) through the environment
/// so every child view can adapt its sizing to the available screen height.
private struct NPScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var npScale: CGFloat {
        get { self[NPScaleKey.self] }
        set { self[NPScaleKey.self] = newValue }
    }
}

struct NowPlayingView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @ObservedObject private var playerManager = PlayerManager.shared
    @ObservedObject private var xonoraClient = XonoraClient.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var isPresentedModally: Bool = true
    var namespace: Namespace.ID?
    var onDismiss: (() -> Void)?

    @State private var dragOffset: CGFloat = 0
    @State private var showQueue = false
    @State private var showChapters = false
    @State private var showLyrics = false
    @State private var showAddToPlaylist = false
    @State private var showSimilarTracks = false
    @State private var showGrouping = false

    // MARK: - Computed Properties

    /// Returns true if the current player is part of a group (either as leader or member)
    private var isPlayerGrouped: Bool {
        guard let player = xonoraClient.currentPlayer else { return false }

        // Check if player is a group leader (has members)
        if let groupChilds = player.groupChilds, !groupChilds.isEmpty {
            return true
        }

        // Check if player is a group member (synced to leader)
        if player.syncedTo != nil {
            return true
        }

        return false
    }

    var body: some View {
        mainContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .colorScheme(.dark)
            .background(albumArtView)
            .offset(y: dragOffset)
            .gesture(isPresentedModally ? dismissGesture : nil)
            .sheet(isPresented: $showQueue) {
                QueueView()
            }
            .sheet(isPresented: $showChapters) {
                if let audiobook = playerManager.currentAudiobook {
                    ChapterListView(audiobook: audiobook, playerManager: playerManager)
                }
            }
            .sheet(isPresented: $showAddToPlaylist) {
                if let track = playerManager.currentTrack {
                    AddToPlaylistSheet(track: track, trackUris: nil)
                }
            }
            .sheet(isPresented: $showSimilarTracks) {
                if let track = playerManager.currentTrack {
                    SimilarTracksView(track: track)
                        .environmentObject(playerViewModel)
                }
            }
            .sheet(isPresented: $showGrouping) {
                if let player = xonoraClient.currentPlayer {
                     PlayerGroupingView(leaderPlayer: player)
                        .environmentObject(xonoraClient)
                }
            }
            .onAppear {
                updateFavoriteState()
                prefetchLyrics()
            }
            .onChange(of: playerManager.currentTrack?.uri) {
                updateFavoriteState()
                // Keep showLyrics state - don't reset when track changes
                prefetchLyrics()
            }
    }

    private var mainContent: some View {
        Group {
            if horizontalSizeClass == .regular || verticalSizeClass == .compact {
                landscapeLayout
            } else {
                portraitLayout
            }
        }
    }

    private var dismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation.height > 0 {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height > 150 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        if let onDismiss = onDismiss {
                            onDismiss()
                        } else {
                            dismiss()
                        }
                    }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
            }
    }
    
    // MARK: - Portrait Layout

    /// Reference height based on iPhone 16 Pro usable area (~812pt).
    private static let referenceHeight: CGFloat = 812

    private var portraitLayout: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let scale = min(max(height / Self.referenceHeight, 0.7), 1.15)
            let controlHPadding: CGFloat = 24 * scale
            let artworkMaxH = height * (0.32 + 0.10 * scale) // ~32%…42% of height

            VStack(spacing: 0) {
                // Drag handle
                if isPresentedModally {
                    dragHandle
                        .padding(.top, 8 * scale)
                }

                // Header
                header
                    .padding(.top, (isPresentedModally ? 8 : 16) * scale)

                if showLyrics {
                    lyricsContentView
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                } else {
                    // Normal mode -- artwork fills flexible space, controls pinned at bottom.
                    // ViewThatFits tries the flat layout first; falls back to ScrollView
                    // on very small screens where content would clip.
                    ViewThatFits(in: .vertical) {
                        // Primary: flat VStack -- artwork is flexible, controls anchored at bottom
                        nowPlayingFixedLayout(scale: scale, controlHPadding: controlHPadding, artworkMaxH: artworkMaxH)

                        // Fallback: scrollable for very small screens
                        ScrollView(.vertical, showsIndicators: false) {
                            nowPlayingContentStack(scale: scale, controlHPadding: controlHPadding, artworkMaxH: artworkMaxH)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                }
            }
            .environment(\.npScale, scale)
        }
    }
    
    // MARK: - Portrait Content Helpers

    /// Flat layout: artwork fills flexible space, controls anchored at bottom.
    /// Used when content fits without scrolling (most devices).
    private func nowPlayingFixedLayout(scale: CGFloat, controlHPadding: CGFloat, artworkMaxH: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Artwork -- flexible, fills remaining vertical space
            albumArtwork
                .padding(.horizontal, 40 * scale)
                .frame(maxHeight: artworkMaxH)
                .frame(maxHeight: .infinity)
                .padding(.top, 4 * scale)

            // Controls group -- fixed at bottom, uniform spacing
            VStack(spacing: 8 * scale) {
                trackInfo
                    .padding(.horizontal, controlHPadding)

                extraControlsRow
                    .padding(.horizontal, controlHPadding)

                PlayerControls(playerManager: playerManager, size: .full)
                    .padding(.horizontal, controlHPadding)
            }
            .padding(.bottom, 24 * scale)
        }
    }

    /// Scrollable content stack for small screens where the flat layout would clip.
    private func nowPlayingContentStack(scale: CGFloat, controlHPadding: CGFloat, artworkMaxH: CGFloat) -> some View {
        VStack(spacing: 8 * scale) {
            albumArtwork
                .padding(.horizontal, 40 * scale)
                .frame(maxHeight: artworkMaxH)

            trackInfo
                .padding(.horizontal, controlHPadding)

            extraControlsRow
                .padding(.horizontal, controlHPadding)

            PlayerControls(playerManager: playerManager, size: .full)
                .padding(.horizontal, controlHPadding)
        }
        .padding(.top, 4 * scale)
        .padding(.bottom, 24 * scale)
    }

    // MARK: - Landscape Layout
    
    private var landscapeLayout: some View {
        Group {
            if showLyrics {
                landscapeLyricsLayout
            } else {
                landscapeNormalLayout
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showLyrics)
    }

    private var landscapeNormalLayout: some View {
        HStack(spacing: 0) {
            // LEFT: Artwork panel
            VStack {
                Spacer()
                albumArtwork
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            
            // RIGHT: Info + Controls panel
            VStack(spacing: 0) {
                if isPresentedModally {
                    dragHandle
                        .padding(.top, 8)
                }
                
                // Scrollable content to handle short screens
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        header
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                        
                        trackInfo
                            .padding(.horizontal, 16)
                        
                        extraControlsRow
                            .padding(.horizontal, 16)
                        
                        PlayerControls(playerManager: playerManager, size: .full)
                            .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 12)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var landscapeLyricsLayout: some View {
        HStack(spacing: 0) {
            // LEFT: Compact artwork + controls column
            VStack(spacing: 12) {
                // Drag handle
                if isPresentedModally {
                    dragHandle
                        .padding(.top, 8)
                }

                Spacer()

                // Artwork (shrunk to ~40% of panel width)
                CachedAsyncImage(url: trackImageURL) {
                    artworkPlaceholder
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                .padding(.horizontal, 24)
                .modifier(MatchedGeometryModifier(id: "playerArtwork", namespace: namespace))

                // Track info (compact)
                VStack(spacing: 4) {
                    Text(playerManager.currentTrack?.name ?? "Not Playing")
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(playerManager.currentTrack?.artistNames ?? "")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)

                // Compact player controls (progress + buttons only, no volume/shuffle)
                VStack(spacing: 8) {
                    CompactProgressBar(
                        progress: progress,
                        currentTime: playerManager.displayCurrentTime,
                        duration: playerManager.displayDuration,
                        isLoading: playerManager.isLoading
                    )

                    // Playback buttons row
                    HStack(spacing: 24) {
                        Button { playerManager.previous() } label: {
                            Image(systemName: "backward.fill").font(.title3).foregroundColor(.white)
                        }
                        Button { playerManager.togglePlayPause() } label: {
                            Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        }
                        Button { playerManager.next() } label: {
                            Image(systemName: "forward.fill").font(.title3).foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 16)

                // Extra controls (speed, sleep, lyrics toggle, AirPlay)
                extraControlsRow
                    .padding(.horizontal, 12)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .opacity
            ))

            // Divider removed (Bug 7)

            // RIGHT: Lyrics panel
            VStack(spacing: 0) {
                // Close lyrics button pinned top-right
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showLyrics = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(12)
                    }
                }

                // Full lyrics view
                LyricsView(isEmbedded: true)
            }
            .frame(maxWidth: .infinity)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
    
    // MARK: - Drag Handle
    
    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(0.5))
            .frame(width: 40, height: 5)
            .padding(.vertical, 4)
            .accessibilityLabel("Drag to dismiss")
            .accessibilityHint("Swipe down to close the player")
    }
    
    // MARK: - Background

    private var albumArtView: some View {
        ZStack {
            CachedAsyncImage(url: trackImageURL) {
                Color.xonoraGradient
            }
            .blur(radius: 30)
            .scaleEffect(1.2)

            Color.black.opacity(0.5)
        }
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var header: some View {
        _HeaderView(
            playerManager: playerManager,
            showChapters: $showChapters,
            showQueue: $showQueue
        )
    }
}

/// Extracted so it can read `npScale` from the environment.
private struct _HeaderView: View {
    @ObservedObject var playerManager: PlayerManager
    @Binding var showChapters: Bool
    @Binding var showQueue: Bool
    @Environment(\.npScale) private var scale

    var body: some View {
        let tap: CGFloat = max(36, 44 * scale)

        HStack {
            Spacer().frame(width: tap)
            Spacer()

            VStack(spacing: 2) {
                Text("PLAYING FROM")
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))

                Text(playerManager.currentSource ?? playerManager.currentTrack?.album?.name ?? "Library")
                    .font(.system(size: 12 * scale, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer()

            HStack(spacing: 4) {
                if playerManager.isPlayingAudiobook {
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        showChapters = true
                    } label: {
                        Image(systemName: "text.book.closed")
                            .font(.system(size: 16 * scale))
                            .foregroundColor(.white)
                            .frame(width: tap, height: tap)
                    }
                    .accessibilityLabel("Chapters")
                    .accessibilityHint("Open chapter list")
                }

                if !playerManager.isPlayingAudiobook && !playerManager.isPlayingPodcast && !playerManager.isPlayingRadio {
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        showQueue = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 18 * scale))
                            .foregroundColor(.white)
                            .frame(width: tap, height: tap)
                    }
                    .accessibilityLabel("Queue")
                    .accessibilityHint("Open the playback queue")
                }
            }
        }
        .padding(.horizontal)
    }
}

extension NowPlayingView {

    // MARK: - Album Artwork
    
    private var albumArtwork: some View {
        CachedAsyncImage(url: trackImageURL) {
            artworkPlaceholder
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 20)
        .scaleEffect(playerManager.isPlaying ? 1.0 : 0.95)
        .animation(.easeInOut(duration: 0.3), value: playerManager.isPlaying)
        .accessibilityLabel(playerManager.currentTrack?.name ?? "Album artwork")
        .modifier(MatchedGeometryModifier(id: "playerArtwork", namespace: namespace))
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

    // MARK: - Track Info

    private var trackInfo: some View {
        _TrackInfoView(
            playerManager: playerManager,
            showSimilarTracks: $showSimilarTracks,
            showAddToPlaylist: $showAddToPlaylist
        )
    }

    // MARK: - Extra Controls Row

    private var extraControlsRow: some View {
        _ExtraControlsRow(
            playerManager: playerManager,
            isPlayerGrouped: isPlayerGrouped,
            showLyrics: $showLyrics,
            showGrouping: $showGrouping
        )
    }

    // MARK: - Lyrics Content View

    private var lyricsContentView: some View {
        VStack(spacing: 0) {
            // Mini player header
            miniPlayerHeader
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Lyrics view embedded
            LyricsView(isEmbedded: true)
        }
    }

    private var miniPlayerHeader: some View {
        VStack(spacing: 12) {
            // Artwork and track info row
            HStack(spacing: 12) {
                // Album artwork (small)
                CachedAsyncImage(url: trackImageURL) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Track info
                VStack(alignment: .leading, spacing: 2) {
                    Text(playerManager.currentTrack?.name ?? "Not Playing")
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(playerManager.currentTrack?.artistNames ?? "")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Favorite button
                Button {
                    playerManager.toggleCurrentTrackFavorite()
                } label: {
                    Image(systemName: playerManager.isCurrentTrackFavorited ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundColor(playerManager.isCurrentTrackFavorited ? .pink : .white)
                }

                // Close Lyrics Button
                Button {
                    #if os(iOS)
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    #endif
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showLyrics = false
                    }
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Hide lyrics")
                .accessibilityHint("Return to album artwork view")
            }

            // Playback controls (compact)
            HStack(spacing: 40) {
                // Previous/Skip back button
                Button {
                    if playerManager.isPlayingAudiobook {
                        playerManager.skipBackward(seconds: 15)
                    } else {
                        playerManager.previous()
                    }
                } label: {
                    if playerManager.isPlayingAudiobook {
                        Image(systemName: "gobackward.15")
                            .font(.title3)
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "backward.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                }

                // Play/Pause
                Button {
                    #if os(iOS)
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    #endif
                    playerManager.togglePlayPause()
                } label: {
                    if playerManager.isLoading {
                        ProgressView()
                            .scaleEffect(1.2)
                            .frame(width: 40, height: 40)
                            .tint(.white)
                    } else {
                        Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                    }
                }
                .disabled(playerManager.isLoading)

                // Next/Skip forward button
                Button {
                    if playerManager.isPlayingAudiobook {
                        playerManager.skipForward(seconds: 15)
                    } else {
                        playerManager.next()
                    }
                } label: {
                    if playerManager.isPlayingAudiobook {
                        Image(systemName: "goforward.15")
                            .font(.title3)
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                }
            }

            // Seekable progress bar
            VStack(spacing: 4) {
                if playerManager.isLoading {
                    LoadingProgressSlider()
                } else {
                    ProgressSlider(
                        value: Binding(
                            get: {
                                if let chapter = playerManager.currentChapter {
                                    return chapter.start + playerManager.displayCurrentTime
                                }
                                return playerManager.displayCurrentTime
                            },
                            set: { playerManager.seek(to: $0) }
                        ),
                        range: {
                            if let chapter = playerManager.currentChapter {
                                return chapter.start...chapter.end
                            }
                            return 0...max(playerManager.displayDuration, 1)
                        }()
                    )
                }

                HStack {
                    if playerManager.isLoading {
                        Text("Loading...")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                    } else {
                        Text(formatTime(playerManager.displayCurrentTime))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                    if !playerManager.isLoading {
                        Text("-\(formatTime(playerManager.displayDuration - playerManager.displayCurrentTime))")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
        }
    }

    private var progress: CGFloat {
        guard playerManager.displayDuration > 0 else { return 0 }
        return CGFloat(playerManager.displayCurrentTime / playerManager.displayDuration)
    }

    // MARK: - Helpers

    private var trackImageURL: URL? {
        let imageString = playerManager.currentTrack?.imageUrl ?? playerManager.currentTrack?.album?.imageUrl
        return XonoraClient.shared.getImageURL(for: imageString, size: .large)
    }

    private var thumbnailImageURL: URL? {
        let imageString = playerManager.currentTrack?.imageUrl ?? playerManager.currentTrack?.album?.imageUrl
        return XonoraClient.shared.getImageURL(for: imageString, size: .thumbnail)
    }

    private func updateFavoriteState() {
        // Check if current track is favorited
        if let track = playerManager.currentTrack {
            playerManager.isCurrentTrackFavorited = track.favorite ?? false
        }
    }

    private func prefetchLyrics() {
        guard let track = playerManager.currentTrack else { return }

        // Optimistically trigger a fetch, but don't block UI or toggle buttons
        Task {
            // Just populate the cache
            _ = try? await LyricsManager.shared.getLyrics(for: track)
        }
    }
}

private struct _TrackInfoView: View {
    @ObservedObject var playerManager: PlayerManager
    @Binding var showSimilarTracks: Bool
    @Binding var showAddToPlaylist: Bool
    @Environment(\.npScale) private var scale

    var body: some View {
        let tap: CGFloat = max(36, 44 * scale)
        let titleSize: CGFloat = max(18, 22 * scale)
        let subtitleSize: CGFloat = max(14, 17 * scale)

        VStack(spacing: 6 * scale) {
            HStack(spacing: 10 * scale) {
                VStack(alignment: .leading, spacing: 3 * scale) {
                    if let chapter = playerManager.currentChapter {
                        MarqueeText(chapter.name, font: .system(size: titleSize, weight: .bold), size: titleSize, color: .white)

                        Text(playerManager.currentTrack?.name ?? "")
                            .font(.system(size: subtitleSize))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    } else {
                        MarqueeText(playerManager.currentTrack?.name ?? "Not Playing", font: .system(size: titleSize, weight: .bold), size: titleSize, color: .white)

                        if let _ = playerManager.currentTrack?.artists?.first,
                           let _ = playerManager.currentTrack?.artists?.first?.itemId,
                           let _ = playerManager.currentTrack?.provider {
                            Button { } label: {
                                Text(playerManager.currentTrack?.artistNames ?? "")
                                    .font(.system(size: subtitleSize))
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                            .disabled(true)
                        } else {
                            Text(playerManager.currentTrack?.artistNames ?? "")
                                .font(.system(size: subtitleSize))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Context Menu — isolated to prevent flicker from progress timer updates
                _TrackOptionsMenu(
                    track: playerManager.currentTrack,
                    showSimilarTracks: $showSimilarTracks,
                    showAddToPlaylist: $showAddToPlaylist,
                    scale: scale
                )

                // Favorite button
                Button {
                    playerManager.toggleCurrentTrackFavorite()
                } label: {
                    Image(systemName: playerManager.isCurrentTrackFavorited ? "heart.fill" : "heart")
                        .font(.system(size: 20 * scale))
                        .foregroundColor(playerManager.isCurrentTrackFavorited ? .pink : .white)
                        .frame(width: tap, height: tap)
                }
                .accessibilityLabel(playerManager.isCurrentTrackFavorited ? "Remove from favorites" : "Add to favorites")
                .accessibilityHint("Double tap to toggle favorite status")
            }
        }
    }
}

// MARK: - Isolated Menu Views (prevent flicker from 4Hz progress timer)

/// Extracted so it only re-renders when track identity changes, not on every currentTime tick.
private struct _TrackOptionsMenu: Equatable, View {
    let track: Track?
    @Binding var showSimilarTracks: Bool
    @Binding var showAddToPlaylist: Bool
    let scale: CGFloat

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.track?.itemId == rhs.track?.itemId &&
        lhs.track?.uri == rhs.track?.uri &&
        lhs.scale == rhs.scale
    }

    var body: some View {
        let tap: CGFloat = max(36, 44 * scale)

        Menu {
            Button {
                PlayerManager.shared.next()
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            if let track {
                Button {
                    PlayerManager.shared.addToQueue(track)
                } label: {
                    Label("Add to Queue", systemImage: "text.badge.plus")
                }
            }

            Button {
                showSimilarTracks = true
            } label: {
                Label("More Like This", systemImage: "sparkles")
            }

            Divider()

            Button {
                showAddToPlaylist = true
            } label: {
                Label("Add to Playlist...", systemImage: "text.badge.plus")
            }

            if let track, !track.uri.hasPrefix("library://") {
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
                .font(.system(size: 16 * scale))
                .foregroundColor(.white)
                .frame(width: tap, height: tap)
        }
    }
}

/// Extracted so it only re-renders when sleep timer state changes, not on every currentTime tick.
private struct _SleepTimerMenu: Equatable, View {
    let isActive: Bool
    let remaining: TimeInterval
    let remainingFormatted: String
    let iconSize: CGFloat
    let pillH: CGFloat
    let pillV: CGFloat

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isActive == rhs.isActive &&
        lhs.remainingFormatted == rhs.remainingFormatted &&
        lhs.iconSize == rhs.iconSize
    }

    var body: some View {
        Menu {
            Button("Off") { PlayerManager.shared.cancelSleepTimer() }
            Button("5 minutes") { PlayerManager.shared.setSleepTimer(minutes: 5) }
            Button("15 minutes") { PlayerManager.shared.setSleepTimer(minutes: 15) }
            Button("30 minutes") { PlayerManager.shared.setSleepTimer(minutes: 30) }
            Button("45 minutes") { PlayerManager.shared.setSleepTimer(minutes: 45) }
            Button("1 hour") { PlayerManager.shared.setSleepTimer(minutes: 60) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isActive ? "moon.fill" : "moon")
                    .font(.system(size: iconSize))
                if isActive && remaining > 0 {
                    Text(remainingFormatted)
                        .font(.system(size: iconSize))
                        .monospacedDigit()
                }
            }
            .foregroundColor(isActive ? .orange : .white)
            .padding(.horizontal, pillH)
            .padding(.vertical, pillV)
            .background(isActive ? Color.white.opacity(0.2) : Color.clear)
            .clipShape(Capsule())
        }
        .simultaneousGesture(
            TapGesture().onEnded { _ in
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                if isActive {
                    PlayerManager.shared.cancelSleepTimer()
                } else {
                    PlayerManager.shared.setSleepTimer(minutes: 15)
                }
            }
        )
    }
}

/// Extracted so it only re-renders when playback rate changes, not on every currentTime tick.
private struct _SpeedMenu: Equatable, View {
    let playbackRate: Float
    let iconSize: CGFloat
    let pillH: CGFloat
    let pillV: CGFloat

    var body: some View {
        Menu {
            Picker("Speed", selection: Binding(
                get: { playbackRate },
                set: { PlayerManager.shared.setPlaybackRate($0) }
            )) {
                ForEach(PlayerManager.playbackRates, id: \.self) { rate in
                    Text(String(format: "%.2fx", rate)).tag(rate)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(String(format: "%.2fx", playbackRate))
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, pillH)
                .padding(.vertical, pillV)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())
        }
        .simultaneousGesture(
            TapGesture().onEnded { _ in
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                PlayerManager.shared.cyclePlaybackRate()
            }
        )
    }
}

private struct _ExtraControlsRow: View {
    @ObservedObject var playerManager: PlayerManager
    let isPlayerGrouped: Bool
    @Binding var showLyrics: Bool
    @Binding var showGrouping: Bool
    @Environment(\.npScale) private var scale

    var body: some View {
        let iconSize: CGFloat = max(12, 14 * scale)
        let pillH: CGFloat = max(8, 12 * scale)
        let pillV: CGFloat = max(4, 6 * scale)

        HStack(spacing: 12 * scale) {
            // Playback speed (only for audiobooks/podcasts, not radio)
            if (playerManager.isPlayingAudiobook || playerManager.isPlayingPodcast) && !playerManager.isPlayingRadio {
                _SpeedMenu(
                    playbackRate: playerManager.playbackRate,
                    iconSize: iconSize,
                    pillH: pillH,
                    pillV: pillV
                )
            }

            Spacer()

            // Sleep timer — isolated to prevent flicker from progress timer
            _SleepTimerMenu(
                isActive: playerManager.isSleepTimerActive,
                remaining: playerManager.sleepTimerRemaining,
                remainingFormatted: playerManager.sleepTimerRemainingFormatted,
                iconSize: iconSize,
                pillH: pillH,
                pillV: pillV
            )

            // Lyrics
            if !playerManager.isPlayingAudiobook && !playerManager.isPlayingPodcast && !playerManager.isPlayingRadio {
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showLyrics.toggle()
                    }
                } label: {
                    Image(systemName: showLyrics ? "music.note" : "quote.bubble")
                        .font(.system(size: iconSize))
                        .foregroundColor(.white)
                        .padding(.horizontal, pillH)
                        .padding(.vertical, pillV)
                        .background(showLyrics ? Color.white.opacity(0.2) : Color.clear)
                        .clipShape(Capsule())
                }
                .accessibilityLabel(showLyrics ? "Show artwork" : "Show lyrics")
            }

            // Grouping
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                showGrouping = true
            } label: {
                Image(systemName: "hifispeaker.2.fill")
                    .font(.system(size: iconSize))
                    .foregroundColor(isPlayerGrouped ? .accentColor : .white)
                    .padding(6 * scale)
                    .background(isPlayerGrouped ? Color.white.opacity(0.2) : Color.clear)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Group Players")

            // AirPlay
            AirPlayButton()
                .frame(width: max(36, 44 * scale), height: max(24, 30 * scale))
                .accessibilityLabel("AirPlay")
        }
    }
}

// MARK: - AirPlay Button

struct AirPlayButton: UIViewRepresentable {
    #if os(iOS)
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = .systemOrange
        picker.prioritizesVideoDevices = false
        return picker
    }
    
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
    #else
    func makeUIView(context: Context) -> UIView {
        return UIView()
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    #endif
}

// MARK: - Queue View

struct QueueView: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var serverQueue: [QueueItem] = []
    @State private var playedItems: [QueueItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var currentItemId: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading queue...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    errorView(message: error)
                } else if serverQueue.isEmpty && playedItems.isEmpty {
                    emptyQueueView
                } else {
                    queueList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Queue")
                        .font(.headline)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if !serverQueue.isEmpty {
                        Button("Clear") {
                            Task {
                                do {
                                    try await XonoraClient.shared.clearQueue()
                                } catch {
                                    print("[QueueView] Failed to clear queue: \(error)")
                                }
                            }
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .queueUpdated)) { _ in
                // Auto-reload when queue is updated on the server
                Task {
                    await loadQueue()
                }
            }
        }
        .task {
            await loadQueue()
        }
    }

    private var queueList: some View {
        List {
            // Played Songs Section (scrollable history above current track)
            if !playedItems.isEmpty {
                Section {
                    ForEach(Array(playedItems.enumerated()), id: \.element.id) { index, item in
                        playedItemRow(for: item, at: index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                playPlayedItem(item)
                            }
                            .listRowBackground(Color.clear)
                            .opacity(0.65) // Slightly faded to indicate history
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    Text("Played Songs")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }

            // Current Queue Section
            if !serverQueue.isEmpty {
                Section {
                    ForEach(Array(serverQueue.enumerated()), id: \.element.id) { index, item in
                        swipeableRow(for: item, at: index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                playAtIndex(index)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteItems(at: IndexSet(integer: index))
                                } label: {
                                    Label("Remove from Queue", systemImage: "trash")
                                }
                            }
                            .listRowSeparator(.hidden)
                    }
                    .onMove(perform: moveItems)
                } header: {
                    if !playedItems.isEmpty {
                        Text("Up Next")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
    }
    
    @ViewBuilder
    private var emptyQueueView: some View {
        ContentUnavailableView(
            "Queue is Empty",
            systemImage: "music.note.list",
            description: Text("Play some music to see it here")
        )
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            Text("Failed to load queue")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Retry") {
                Task { await loadQueue() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func swipeableRow(for item: QueueItem, at index: Int) -> some View {
        SwipeToDeleteRow(
            content: {
                upNextRow(for: item, at: index)
            },
            onDelete: {
                deleteItems(at: IndexSet(integer: index))
            }
        )
    }

    @ViewBuilder
    private func upNextRow(for item: QueueItem, at index: Int) -> some View {
        let isCurrent = item.queueItemId == currentItemId

        HStack(spacing: 12) {
            // Show playing indicator for current track
            if isCurrent {
                Image(systemName: "waveform")
                    .foregroundColor(.accentColor)
                    .symbolEffect(.variableColor.iterative, isActive: playerManager.isPlaying)
                    .frame(width: 24)
            } else {
                Text("\(index + 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 24)
            }

            // Thumbnail
            let imageURL = XonoraClient.shared.getImageURL(for: item.imageUrl, size: .thumbnail)
            CachedAsyncImage(url: imageURL) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Track details
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .foregroundColor(isCurrent ? .accentColor : .primary)
                    .lineLimit(1)

                Text(item.artistNames)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Duration
            Text(item.formattedDuration)
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func playedItemRow(for item: QueueItem, at index: Int) -> some View {
        HStack(spacing: 12) {
            // No drag handle or index for played items - just a spacer
            Spacer()
                .frame(width: 24)

            // Thumbnail
            let imageURL = XonoraClient.shared.getImageURL(for: item.imageUrl, size: .thumbnail)
            CachedAsyncImage(url: imageURL) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Track details
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(item.artistNames)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Duration
            Text(item.formattedDuration)
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()

            // No delete button for played items
            Spacer().frame(width: 20)
        }
        .padding(.vertical, 2)
    }

    private func playPlayedItem(_ item: QueueItem) {
        // Play the track from played history
        Task {
            do {
                // If we have a URI, try to play it
                if let uri = item.uri {
                    // Use "play" option to start immediately without clearing queue
                    try await XonoraClient.shared.playMedia(uris: [uri], queueOption: "play")
                }
            } catch {
                print("[QueueView] Failed to play item from history: \(error)")
            }
        }
    }

    // MARK: - Actions

    private func loadQueue() async {
        isLoading = true
        errorMessage = nil

        do {
            // Load upcoming queue
            if let queue = try await XonoraClient.shared.fetchQueue() {
                serverQueue = queue.items

                print("[QueueView] Loaded queue with \(queue.items.count) items, currentIndex: \(queue.currentIndex ?? -1)")

                // Try to find current playing item
                if let currentTrack = playerManager.currentTrack {
                    currentItemId = serverQueue.first(where: { $0.uri == currentTrack.uri })?.queueItemId
                }
            } else {
                serverQueue = []
            }

            // Load played items history
            playedItems = try await XonoraClient.shared.fetchRecentlyPlayedItems(limit: 10)
            print("[QueueView] Loaded \(playedItems.count) played items, \(serverQueue.count) upcoming items")
        } catch {
            print("[QueueView] Error loading queue: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
    
    private func deleteItems(at offsets: IndexSet) {
        // Get items to delete before modifying array
        let itemsToDelete = offsets.map { serverQueue[$0] }
        
        // Optimistically update UI
        serverQueue.remove(atOffsets: offsets)
        
        // Send delete commands to server
        for item in itemsToDelete {
            Task {
                do {
                    try await XonoraClient.shared.deleteQueueItem(itemId: item.queueItemId)
                } catch {
                    print("[QueueView] Failed to delete item: \(error)")
                    // Reload queue on error
                    await loadQueue()
                }
            }
        }
    }
    
    private func moveItems(from source: IndexSet, to destination: Int) {
        // Get the item being moved
        guard let sourceIndex = source.first else { return }
        let item = serverQueue[sourceIndex]

        print("[QueueView] ===== MOVE DEBUG =====")
        print("[QueueView] Moving '\(item.name)' from index \(sourceIndex) to destination \(destination)")
        print("[QueueView] Queue before move:")
        for (idx, queueItem) in serverQueue.enumerated() {
            print("  [\(idx)] \(queueItem.name) (id: \(queueItem.queueItemId))")
        }

        // Send move command to server FIRST
        Task {
            do {
                // Get current queue to determine offset
                guard let queue = try await XonoraClient.shared.fetchQueue(),
                      let currentIdx = queue.currentIndex else {
                    print("[QueueView] Can't determine queue offset, using relative positions")

                    // Fallback to relative positioning if currentIndex not available
                    let newPosition: Int
                    if sourceIndex < destination {
                        newPosition = destination - 1
                    } else {
                        newPosition = destination
                    }

                    try await XonoraClient.shared.moveQueueItem(itemId: item.queueItemId, toPosition: newPosition)
                    await MainActor.run {
                        serverQueue.move(fromOffsets: source, toOffset: destination)
                    }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    await loadQueue()
                    return
                }

                // serverQueue only contains items AFTER currentIndex
                // Add offset to convert to absolute positions
                let offset = currentIdx + 1

                let absoluteSource = sourceIndex + offset
                let absoluteDestination: Int
                if sourceIndex < destination {
                    absoluteDestination = (destination - 1) + offset
                } else {
                    absoluteDestination = destination + offset
                }

                print("[QueueView] Moving from absolute position \(absoluteSource) to \(absoluteDestination) (offset: \(offset))")

                try await XonoraClient.shared.moveQueueItem(itemId: item.queueItemId, toPosition: absoluteDestination)
                print("[QueueView] Move succeeded - server confirmed")

                // Now update UI optimistically
                await MainActor.run {
                    serverQueue.move(fromOffsets: source, toOffset: destination)
                    print("[QueueView] Queue after UI update:")
                    for (idx, queueItem) in serverQueue.enumerated() {
                        print("  [\(idx)] \(queueItem.name)")
                    }
                }

                // Reload queue after a short delay to verify
                try? await Task.sleep(nanoseconds: 300_000_000)
                await loadQueue()
                print("[QueueView] Queue reloaded from server")
            } catch {
                print("[QueueView] Failed to move item: \(error)")
                // Reload queue on error
                await loadQueue()
            }
        }
    }
    
    private func playAtIndex(_ index: Int) {
        Task {
            do {
                try await XonoraClient.shared.playQueueIndex(index)
                // Update current item indicator
                if index < serverQueue.count {
                    currentItemId = serverQueue[index].queueItemId
                }
            } catch {
                print("[QueueView] Failed to play at index: \(error)")
            }
        }
    }
    
}

struct NowPlayingView_Previews: PreviewProvider {
    static var previews: some View {
        NowPlayingView()
            .environmentObject(PlayerViewModel())
            .environmentObject(LibraryViewModel())
    }
}

// MARK: - Matched Geometry Helper

struct MatchedGeometryModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace = namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

// MARK: - Swipe to Delete Row

struct SwipeToDeleteRow<Content: View>: View {
    let content: Content
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isDeleting = false

    init(@ViewBuilder content: () -> Content, onDelete: @escaping () -> Void) {
        self.content = content()
        self.onDelete = onDelete
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Background Delete Action
            if offset < 0 {
                HStack {
                    Spacer()
                    Image(systemName: "trash.fill")
                        .foregroundColor(.white)
                        .padding(.trailing, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.red)
            }

            // Foreground Content
            content
                .background(Color(UIColor.systemBackground))
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            // Only allow swiping left
                            if value.translation.width < 0 {
                                offset = value.translation.width
                            }
                        }
                        .onEnded { value in
                            if value.translation.width < -100 {
                                // Full swipe - delete immediately
                                withAnimation {
                                    offset = -1000
                                    isDeleting = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    onDelete()
                                    offset = 0
                                }
                            } else if value.translation.width < -50 {
                                // Half swipe - show delete button
                                withAnimation {
                                    offset = -80
                                }
                            } else {
                                // Snap back
                                withAnimation {
                                    offset = 0
                                }
                            }
                        }
                )
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Loading Progress Indicator

struct LoadingProgressIndicator: View {
    let color: Color
    @State private var animationOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(0),
                            color.opacity(0.8),
                            color.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: geometry.size.width * 0.3)
                .offset(x: geometry.size.width * animationOffset)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false)) {
                        animationOffset = 0.7 // Changed from 1.0 to 0.7 to keep within bounds
                    }
                }
        }
    }
}
