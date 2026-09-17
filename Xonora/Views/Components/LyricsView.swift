import SwiftUI

// MARK: - LyricLine Model
struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let timestamp: TimeInterval
    let text: String
}

struct LyricsView: View {
    var isEmbedded: Bool = false

    @Environment(\.dismiss) var dismiss
    @ObservedObject private var playerManager = PlayerManager.shared
    @ObservedObject private var preferences = UserPreferences.shared

    @State private var lyrics: String?
    @State private var lrcLyrics: String?
    @State private var parsedLines: [LyricLine] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var currentLineIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Only show header if not embedded
            if !isEmbedded {
                // Drag handle
                Capsule()
                    .fill(Color.secondary)
                    .frame(width: 40, height: 4)
                    .padding(.top, 12)

                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playerManager.currentTrack?.name ?? "Unknown Track")
                            .font(.headline)
                            .lineLimit(1)
                        Text(playerManager.currentTrack?.artistNames ?? "Unknown Artist")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider()
            }

            // Content
            Group {
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(message: error)
                } else if !parsedLines.isEmpty {
                    syncedLyricsView
                } else if let displayLyrics = lyrics {
                    plainLyricsView(displayLyrics)
                } else {
                    noLyricsView
                }
            }
        }
        .background(isEmbedded ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Material.regular))
        .task {
            await loadLyrics()
        }
        .onChange(of: playerManager.currentTrack?.uri) { _, _ in
            Task {
                await loadLyrics()
            }
        }
        // Lyrics line tracking is now driven by TimelineView inside syncedLyricsView
        // for 10Hz polling of live engine time, decoupled from the 4Hz progress timer.
    }

    // MARK: - Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading lyrics...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Failed to load lyrics")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry") {
                Task { await loadLyrics() }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
    }
    
    private var noLyricsView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "music.mic")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .padding(.bottom)

            Text("Lyrics Unavailable")
                .font(.title3)
                .bold()
                .foregroundStyle(.secondary)

            Text("No lyrics found for this track.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
    }

    private var syncedLyricsView: some View {
        // TimelineView polls at 10Hz, reading live engine time each tick.
        // This decouples lyrics accuracy from the 4Hz progress timer entirely.
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let liveTime = playerManager.lyricsTime + preferences.lyricsOffset
            let lineIndex = currentLineFor(position: liveTime)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Top padding for centering
                        Spacer()
                            .frame(height: 180)

                        ForEach(Array(parsedLines.enumerated()), id: \.element.id) { index, line in
                            let isActive = index == lineIndex
                            let isPast = index < lineIndex
                            let isNextUp = index == lineIndex + 1

                            Text(line.text)
                                .font(.system(size: isActive ? 32 : 20, weight: isActive ? .bold : .medium))
                                .foregroundStyle(
                                    isActive ? Color.white :
                                    isPast ? Color.white.opacity(0.4) :
                                    isNextUp ? Color.white.opacity(0.6) :
                                    Color.white.opacity(0.35)
                                )
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                                .padding(.horizontal, 32)
                                .padding(.vertical, isActive ? 16 : 10)
                                .frame(maxWidth: .infinity)
                                .id(line.id)
                                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isActive)
                                .animation(.easeInOut(duration: 0.3), value: lineIndex)
                        }

                        // Bottom padding for centering
                        Spacer()
                            .frame(height: 180)
                    }
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: lineIndex) { _, newIndex in
                    if newIndex != currentLineIndex {
                        currentLineIndex = newIndex
                    }
                    if newIndex < parsedLines.count {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                            proxy.scrollTo(parsedLines[newIndex].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    /// Pure function — computes the active line index for a given position without mutating state.
    private func currentLineFor(position: TimeInterval) -> Int {
        guard !parsedLines.isEmpty else { return 0 }
        // Binary-style: find last line whose timestamp <= position
        var result = 0
        for (index, line) in parsedLines.enumerated() {
            if position >= line.timestamp {
                result = index
            } else {
                break
            }
        }
        return result
    }

    private func plainLyricsView(_ text: String) -> some View {
        ScrollView(showsIndicators: false) {
            Text(text)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineSpacing(8)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.vertical, 60)
                .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Helpers

    private func loadLyrics() async {
        guard let track = playerManager.currentTrack else {
            lyrics = nil
            lrcLyrics = nil
            parsedLines = []
            currentLineIndex = 0
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        currentLineIndex = 0  // Reset line index when loading new lyrics

        // First check if lyrics are already in track metadata
        if let metadata = track.metadata {
            if metadata.lyrics != nil || metadata.lrcLyrics != nil {
                lyrics = metadata.lyrics
                lrcLyrics = metadata.lrcLyrics

                // Parse LRC lyrics if available
                if let lrcText = metadata.lrcLyrics {
                    parsedLines = parseLRCLyrics(lrcText)
                }

                isLoading = false
                return
            }
        }

        do {
            let result = try await LyricsManager.shared.getLyrics(for: track)
            lyrics = result.lyrics
            lrcLyrics = result.lrcLyrics

                // Parse LRC lyrics if available
                if let lrcText = result.lrcLyrics {
                    parsedLines = parseLRCLyrics(lrcText)
                }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Parse LRC format lyrics into timestamped lines
    /// LRC format: [mm:ss.xx]Lyric text
    private func parseLRCLyrics(_ text: String) -> [LyricLine] {
        let lines = text.components(separatedBy: .newlines)
        var lyricLines: [LyricLine] = []

        for line in lines {
            // Match timestamp pattern [mm:ss.xx] or [mm:ss.xxx]
            let pattern = #"\[(\d{1,2}):(\d{2})\.(\d{2,3})\](.*)$"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
                continue
            }

            // Extract timestamp components
            guard let minutesRange = Range(match.range(at: 1), in: line),
                  let secondsRange = Range(match.range(at: 2), in: line),
                  let centisecondsRange = Range(match.range(at: 3), in: line),
                  let textRange = Range(match.range(at: 4), in: line) else {
                continue
            }

            let minutes = Int(line[minutesRange]) ?? 0
            let seconds = Int(line[secondsRange]) ?? 0
            let centiseconds = Int(line[centisecondsRange]) ?? 0

            // Convert to total seconds
            let timestamp = TimeInterval(minutes * 60 + seconds) + TimeInterval(centiseconds) / 100.0

            let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if !text.isEmpty {
                lyricLines.append(LyricLine(timestamp: timestamp, text: text))
            }
        }

        return lyricLines.sorted { $0.timestamp < $1.timestamp }
    }

}

#Preview {
    LyricsView()
}
