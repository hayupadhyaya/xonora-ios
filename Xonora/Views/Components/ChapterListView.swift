import SwiftUI

/// Modal sheet for audiobook chapter navigation
struct ChapterListView: View {
    let audiobook: Audiobook
    @ObservedObject var playerManager: PlayerManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(audiobook.chapters.sorted(by: { $0.position < $1.position })) { chapter in
                    chapterRow(chapter)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            playerManager.seekToChapter(audiobook: audiobook, chapter: chapter)
                            dismiss()
                        }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func chapterRow(_ chapter: Chapter) -> some View {
        let isCurrent = playerManager.currentChapter?.position == chapter.position
        let progress = chapterProgress(for: chapter)
        
        HStack(spacing: 12) {
            // Chapter number or now playing indicator
            if isCurrent {
                Image(systemName: "waveform")
                    .foregroundColor(.accentColor)
                    .symbolEffect(.variableColor.iterative, isActive: playerManager.isPlaying)
                    .frame(width: 28)
            } else {
                Text("\(chapter.position + 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 28)
            }
            
            // Chapter info
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.name)
                    .font(.body)
                    .foregroundColor(isCurrent ? .accentColor : .primary)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Text(formatDuration(chapter.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Progress indicator for partially played chapters
                    if progress > 0 && progress < 1 {
                        ProgressView(value: progress)
                            .frame(width: 60)
                            .tint(.accentColor)
                    } else if progress >= 1 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            
            Spacer()
            
            // Chevron for tap affordance
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityLabel("Chapter \(chapter.position + 1): \(chapter.name)")
        .accessibilityHint(isCurrent ? "Currently playing" : "Double tap to play this chapter")
    }
    
    private func chapterProgress(for chapter: Chapter) -> Double {
        guard chapter.duration > 0 else { return 0 }
        
        let currentTime = playerManager.currentTime
        
        if currentTime < chapter.start {
            return 0
        } else if currentTime >= chapter.end {
            return 1
        } else {
            return (currentTime - chapter.start) / chapter.duration
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
