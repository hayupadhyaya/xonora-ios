import SwiftUI

struct AudiobookDetailView: View {
    let audiobook: Audiobook
    var fallbackImageString: String? = nil

    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @Environment(\.miniPlayerBottomPadding) private var miniPlayerPadding
    @Environment(BarVisibilityManager.self) private var barManager
    @ObservedObject private var playerManager = PlayerManager.shared
    
    @State private var savedProgress: TimeInterval = 0
    @State private var savedDuration: TimeInterval = 0
    @State private var hasLoadedProgress = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Audiobook header
                audiobookHeader
                    .padding(.bottom, 24)

                // Play controls
                HStack(spacing: 16) {
                    Button {
                        // Play the audiobook
                        PlayerManager.shared.playAudiobook(audiobook)
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Play")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [.pink, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)

                // Chapter list
                if audiobook.hasChapters {
                    chapterList
                }
            }
            .padding(.bottom, miniPlayerPadding)
        }
        .trackScrollForBars(barManager)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await libraryViewModel.toggleFavorite(item: audiobook)
                    }
                } label: {
                    Image(systemName: (libraryViewModel.audiobooks.first(where: { $0.id == audiobook.id })?.favorite ?? audiobook.favorite ?? false) ? "heart.fill" : "heart")
                        .foregroundColor((libraryViewModel.audiobooks.first(where: { $0.id == audiobook.id })?.favorite ?? audiobook.favorite ?? false) ? .pink : .primary)
                }
            }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
    }

    private var audiobookHeader: some View {
        VStack(spacing: 16) {
            // Audiobook artwork
            CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: audiobook.imageUrl ?? fallbackImageString, size: .large)) {
                audiobookArtPlaceholder
            }
            .aspectRatio(1, contentMode: .fill)
            .frame(width: 240, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)

            // Audiobook info
            VStack(spacing: 4) {
                Text(audiobook.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(audiobook.authorNames)
                    .font(.headline)
                    .foregroundColor(.pink)

                if let narrator = audiobook.narratorNames {
                    Text("Narrated by \(narrator)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    if !audiobook.displayYear.isEmpty {
                        Text(audiobook.displayYear)
                    }

                    if audiobook.hasChapters {
                        if !audiobook.displayYear.isEmpty {
                            Text("•")
                        }
                        Text("\(audiobook.chapters.count) chapters")
                    }

                    if let duration = audiobook.formattedDuration {
                        Text("•")
                        Text(duration)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.horizontal)
            
            // Overall Progress Bar (Bug 10 Fix)
            if effectiveProgress > 0 && effectiveDuration > 0 {
                VStack(spacing: 4) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.3))
                                .frame(height: 6)
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor)
                                .frame(width: geometry.size.width * CGFloat(min(effectiveProgress / effectiveDuration, 1.0)), height: 6)
                        }
                    }
                    .frame(height: 6)
                    
                    HStack {
                        Text("\(Int(effectiveProgress / effectiveDuration * 100))% completed")
                        Spacer()
                        if effectiveDuration - effectiveProgress > 0 {
                            Text(formatDuration(effectiveDuration - effectiveProgress) + " remaining")
                        } else {
                            Text("Completed")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
        }
        .padding(.top)
        .task {
            barManager.resetBars()
            await loadProgress()
        }
    }

    private var audiobookArtPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "book")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
            }
    }

    private var chapterList: some View {
        LazyVStack(spacing: 0) {
            ForEach(audiobook.chapters) { chapter in
                Button {
                    // Seek to chapter start time
                    PlayerManager.shared.seekToChapter(audiobook: audiobook, chapter: chapter)
                } label: {
                    HStack(spacing: 12) {
                        // Chapter number
                        Text("\(chapter.position)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 24)

                        // Chapter info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chapter.name)
                                .font(.body)
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Text(formatTime(chapter.start))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                        
                        // Chapter Status (Bug 10 Fix)
                        chapterStatusView(for: chapter)

                        // Duration
                        Text(chapter.formattedDuration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    // Helpers for Progress Logic
    
    private var isCurrentlyPlayingThisAudiobook: Bool {
        playerManager.isPlayingAudiobook && playerManager.currentAudiobook?.id == audiobook.id
    }
    
    private var effectiveProgress: TimeInterval {
        if isCurrentlyPlayingThisAudiobook {
            return playerManager.currentTime
        }
        return savedProgress
    }
    
    private var effectiveDuration: TimeInterval {
        if let d = audiobook.duration, d > 0 { return d }
        return savedDuration > 0 ? savedDuration : 0
    }
    
    private func chapterStatusView(for chapter: Chapter) -> some View {
        let currentPos = effectiveProgress
        let chapterEnd = chapter.start + (chapter.duration)
        let isCompleted = currentPos >= chapterEnd - 5 // Tolerance
        let isPlaying = isCurrentlyPlayingThisAudiobook && playerManager.isPlaying && currentPos >= chapter.start && currentPos < chapterEnd
        let isCurrentChapter = currentPos >= chapter.start && currentPos < chapterEnd
        
        return Group {
            if isPlaying {
                Image(systemName: "waveform")
                    .foregroundColor(.accentColor)
                    .symbolEffect(.variableColor.iterative)
            } else if isCompleted {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            } else if isCurrentChapter {
                // Partial progress bar for current chapter
                let chapterProgress = currentPos - chapter.start
                let chapterTotal = max(chapter.duration, 1)
                let fraction = max(0, min(1, chapterProgress / chapterTotal))
                
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 30, height: 4)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 30 * fraction, height: 4)
                }
            } else {
                EmptyView()
            }
        }
    }
    
    private func loadProgress() async {
        let history = await PlaybackHistoryManager.shared.getRecentlyPlayed(limit: 200)
        if let item = history.first(where: { $0.itemId == audiobook.id }) {
            savedProgress = item.progress ?? 0
            savedDuration = item.duration ?? 0
        }
        hasLoadedProgress = true
    }
}
