import SwiftUI

struct PodcastDetailView: View {
    let podcast: Podcast
    var fallbackImageString: String? = nil
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.miniPlayerBottomPadding) private var miniPlayerPadding
    @Environment(BarVisibilityManager.self) private var barManager
    @State private var episodes: [PodcastEpisode] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                landscapeLayout
            } else {
                portraitLayout
            }
        }
        .background(Color(UIColor.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            barManager.resetBars()
            await loadEpisodes()
        }
    }
    
    // MARK: - Portrait Layout
    
    private var portraitLayout: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: podcast.imageUrl ?? fallbackImageString, size: .large)) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray)
                            }
                    }
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 10)

                    VStack(spacing: 8) {
                        Text(podcast.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text(podcast.publisher ?? "Unknown Publisher")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.top, 20)

                episodesContent
            }
            .padding(.bottom, miniPlayerPadding)
        }
        .trackScrollForBars(barManager)
    }

    // MARK: - Landscape Layout
    
    private var landscapeLayout: some View {
        HStack(alignment: .top, spacing: 24) {
            // Left side - Artwork and info
            VStack(spacing: 16) {
                CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: podcast.imageUrl ?? fallbackImageString, size: .large)) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                        }
                }
                .aspectRatio(1, contentMode: .fill)
                .frame(width: 250, height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 10)

                VStack(spacing: 8) {
                    Text(podcast.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text(podcast.publisher ?? "Unknown Publisher")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                
                Spacer()
            }
            .frame(width: 280)
            .padding(.top, 20)
            .padding(.leading, 20)
            
            // Right side - Episodes list
            ScrollView {
                VStack(spacing: 0) {
                    episodesContent
                }
                .padding(.bottom, miniPlayerPadding)
            }
        }
    }
    
    // MARK: - Episodes Content
    
    @ViewBuilder
    private var episodesContent: some View {
        if isLoading {
            ProgressView()
                .padding(.top, 40)
        } else if episodes.isEmpty {
            ContentUnavailableView(
                "No Episodes",
                systemImage: "mic.slash",
                description: Text("This podcast has no available episodes.")
            )
            .padding(.top, 40)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(episodes) { episode in
                    Button {
                        playerViewModel.playPodcast(podcast, episode: episode)
                    } label: {
                        HStack(spacing: 16) {
                            Text(episode.formattedDuration)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .trailing)
                                .monospacedDigit()

                            VStack(alignment: .leading, spacing: 4) {
                                Text(episode.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            Image(systemName: "play.circle")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loadEpisodes() async {
        do {
            episodes = try await libraryViewModel.loadPodcastEpisodes(podcast: podcast)
            isLoading = false
        } catch {
            print("Failed to load episodes: \(error)")
            isLoading = false
        }
    }
}
