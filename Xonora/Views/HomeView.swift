import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel.shared

    @ObservedObject private var preferences = UserPreferences.shared
    @Environment(\.miniPlayerBottomPadding) private var miniPlayerPadding
    @Environment(BarVisibilityManager.self) private var barManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    ForEach(preferences.homeSectionOrder, id: \.self) { sectionId in
                        if preferences.isSectionEnabled(sectionId) {
                            // 1. Check for Dynamic Sections (Categories & Recommendations)
                            if let dynamicSection = viewModel.allSections.first(where: { $0.id == sectionId }) {
                                if dynamicSection.isCategory {
                                    // CATEGORY SECTION (Music, Podcasts, etc.)
                                    // Extract the category raw value from ID "category_Name"
                                    let categoryName = String(sectionId.dropFirst("category_".count))
                                    if let category = HomeViewModel.CategorySection.Category(rawValue: categoryName),
                                       let sectionData = viewModel.categoryItems.first(where: { $0.category == category }) {
                                        
                                        VStack(alignment: .leading, spacing: 12) {
                                            // Header
                                            HStack {
                                                Image(systemName: sectionData.category.icon)
                                                    .font(.title3)
                                                    .foregroundColor(.pink)

                                                Text(LocalizedStringKey(sectionData.category.rawValue))
                                                    .font(.title2.bold())

                                                Spacer()
                                            }
                                            .padding(.horizontal)

                                            // Cards
                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack(alignment: .top, spacing: 16) {
                                                    ForEach(sectionData.items) { item in
                                                        if item.contentType == .track {
                                                            Button {
                                                                viewModel.playItem(item: item)
                                                            } label: {
                                                                HistoryCardItem(item: item)
                                                            }
                                                            .buttonStyle(.plain)
                                                        } else {
                                                            viewModel.navigationLinkForItem(item)
                                                        }
                                                    }
                                                }
                                                .padding(.horizontal)
                                            }
                                        }
                                    }
                                } else {
                                    // RECOMMENDATION SECTION (Trending, For You, etc.)
                                    // Extract name "rec_Name"
                                    let recName = String(sectionId.dropFirst("rec_".count))
                                    if let sectionData = viewModel.recommendationSections.first(where: { $0.name == recName }) {
                                        
                                        VStack(alignment: .leading, spacing: 12) {
                                            // Header
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack {
                                                    Image(systemName: "sparkles")
                                                        .font(.title3)
                                                        .foregroundColor(.pink)
                                                    
                                                    Text(LocalizedStringKey(sectionData.name))
                                                        .font(.title2.bold())
                                                    
                                                    Spacer()
                                                }
                                                
                                                if let subtitle = sectionData.subtitle {
                                                    Text(subtitle)
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .padding(.horizontal)
                                            
                                            // Cards
                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack(spacing: 16) {
                                                    ForEach(sectionData.items) { item in
                                                        if item.contentType == .track {
                                                            Button {
                                                                viewModel.playItem(item: item)
                                                            } label: {
                                                                HistoryCardItem(item: item)
                                                            }
                                                            .buttonStyle(.plain)
                                                        } else {
                                                            viewModel.navigationLinkForItem(item)
                                                        }
                                                    }
                                                }
                                                .padding(.horizontal)
                                            }
                                        }
                                    }
                                }
                            }
                            // 2. Check for Static Sections
                            else {
                                switch sectionId {
                                case "recentlyPlayed":
                                    if !viewModel.recentlyPlayedItems.isEmpty {
                                        VStack(alignment: .leading, spacing: 12) {
                                            // Header
                                            HStack {
                                                Image(systemName: "clock.fill")
                                                    .font(.title3)
                                                    .foregroundColor(.pink)

                                                Text("Recently Played")
                                                    .font(.title2.bold())

                                                Spacer()
                                            }
                                            .padding(.horizontal)

                                            // Cards
                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack(alignment: .top, spacing: 16) {
                                                    ForEach(viewModel.recentlyPlayedItems) { item in
                                                        if item.contentType == .track {
                                                            Button {
                                                                viewModel.playItem(item: item)
                                                            } label: {
                                                                HistoryCardItem(item: item)
                                                            }
                                                            .buttonStyle(.plain)
                                                        } else {
                                                            viewModel.navigationLinkForItem(item)
                                                        }
                                                    }
                                                }
                                                .padding(.horizontal)
                                            }
                                        }
                                    }

                                case "continueListening":
                                    if !viewModel.continueListeningItems.isEmpty {
                                        VStack(alignment: .leading, spacing: 12) {
                                            // Header
                                            HStack {
                                                Image(systemName: "play.circle.fill")
                                                    .font(.title3)
                                                    .foregroundColor(.pink)

                                                Text("Continue Listening")
                                                    .font(.title2.bold())

                                                Spacer()
                                            }
                                            .padding(.horizontal)

                                            // Progress cards
                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack(alignment: .top, spacing: 16) {
                                                    ForEach(viewModel.continueListeningItems) { item in
                                                        Button {
                                                            viewModel.playItem(item: item)
                                                        } label: {
                                                            HistoryCardItem(item: item)
                                                        }
                                                        .buttonStyle(.plain)
                                                    }
                                                }
                                                .padding(.horizontal)
                                            }
                                        }
                                    }

                                case "favorites":
                                    if !viewModel.favoriteItems.isEmpty {
                                        VStack(alignment: .leading, spacing: 12) {
                                            // Header
                                            HStack {
                                                Image(systemName: "heart.fill")
                                                    .font(.title3)
                                                    .foregroundColor(.pink)

                                                Text("Favorites")
                                                    .font(.title2.bold())

                                                Spacer()
                                            }
                                            .padding(.horizontal)

                                            // Cards
                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack(alignment: .top, spacing: 16) {
                                                    ForEach(viewModel.favoriteItems) { item in
                                                        if item.contentType == .track {
                                                            Button {
                                                                viewModel.playItem(item: item)
                                                            } label: {
                                                                HistoryCardItem(item: item)
                                                            }
                                                            .buttonStyle(.plain)
                                                        } else {
                                                            viewModel.navigationLinkForItem(item)
                                                        }
                                                    }
                                                }
                                                .padding(.horizontal)
                                            }
                                        }
                                    }

                                default:
                                    EmptyView()
                                }
                            }
                        }
                    }

                    // Loading state
                    if viewModel.isLoading && viewModel.categoryItems.isEmpty && viewModel.recommendationSections.isEmpty {
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Loading Home...")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                    }
                    // Empty state
                    else if viewModel.categoryItems.isEmpty && viewModel.recommendationSections.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)

                            Text("No Listening History")
                                .font(.title3.bold())

                            Text("Start playing music, audiobooks, or podcasts to see them here")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                                
                            Button {
                                Task { await viewModel.refresh() }
                            } label: {
                                Text("Refresh")
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.pink)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                    }
                }
                .padding(.vertical)
                .padding(.bottom, miniPlayerPadding)
            }
            .trackScrollForBars(barManager)
            .navigationTitle("Home")
            .refreshable {
                await viewModel.refresh()
            }
            .globalToolbar(includeSettings: true, searchFilter: .all)
        }
        .task {
            // Ensure data is loaded when view appears (safeguard for missed init events)
            if viewModel.allSections.isEmpty && !viewModel.isLoading {
                await viewModel.refresh()
            }
        }
    }
    
    @ViewBuilder
    private func historyCards(for items: [PlaybackHistoryItem]) -> some View {
        ForEach(items) { item in
            if item.contentType == .track {
                Button {
                    viewModel.playItem(item: item)
                } label: {
                    HistoryCardItem(item: item)
                }
                .buttonStyle(.plain)
            } else {
                viewModel.navigationLinkForItem(item)
            }
        }
    }
}

// MARK: - Lazy Detail Views
// These wrapper views handle fetching full content for non-library items (e.g. recommendations)
// before displaying the standard detail view.

struct LazyAlbumDetailView: View {
    let itemId: String
    let provider: String
    let placeholder: PlaybackHistoryItem
    
    @State private var album: Album?
    @State private var isLoading = true
    @State private var error: String?
    
    var body: some View {
        Group {
            if let album = album {
                AlbumDetailView(album: album, fallbackImageString: placeholder.imageUrl)
            } else if isLoading {
                loadingView
            } else if let error = error {
                errorView(message: error) {
                    Task { await loadAlbum() }
                }
            }
        }
        .task {
            if album == nil {
                await loadAlbum()
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: placeholder.imageUrl, size: .large)) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ProgressView()
                            .scaleEffect(1.5)
                    }
            }
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(spacing: 8) {
                Text(placeholder.itemName)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                
                if let artist = placeholder.artistName {
                    Text(artist)
                        .font(.headline)
                        .foregroundColor(.pink)
                }
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
    
    private func loadAlbum() async {
        isLoading = true
        error = nil
        do {
            album = try await XonoraClient.shared.fetchAlbum(itemId: itemId, provider: provider)
        } catch {
            print("[LazyAlbum] Error: \(error)")
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct LazyPlaylistDetailView: View {
    let itemId: String
    let provider: String
    let placeholder: PlaybackHistoryItem
    
    @State private var playlist: Playlist?
    @State private var isLoading = true
    @State private var error: String?
    
    var body: some View {
        Group {
            if let playlist = playlist {
                PlaylistDetailView(playlist: playlist, fallbackImageString: placeholder.imageUrl)
            } else if isLoading {
                loadingView
            } else if let error = error {
                errorView(message: error) {
                    Task { await loadPlaylist() }
                }
            }
        }
        .task {
            if playlist == nil {
                await loadPlaylist()
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: placeholder.imageUrl, size: .large)) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ProgressView()
                            .scaleEffect(1.5)
                    }
            }
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Text(placeholder.itemName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
    
    private func loadPlaylist() async {
        isLoading = true
        error = nil
        do {
            playlist = try await XonoraClient.shared.fetchPlaylist(itemId: itemId, provider: provider)
        } catch {
            print("[LazyPlaylist] Error: \(error)")
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct LazyAudiobookDetailView: View {
    let itemId: String
    let provider: String
    let placeholder: PlaybackHistoryItem
    
    @State private var audiobook: Audiobook?
    @State private var isLoading = true
    @State private var error: String?
    
    var body: some View {
        Group {
            if let audiobook = audiobook {
                AudiobookDetailView(audiobook: audiobook, fallbackImageString: placeholder.imageUrl)
            } else if isLoading {
                loadingView
            } else if let error = error {
                errorView(message: error) {
                    Task { await loadAudiobook() }
                }
            }
        }
        .task {
            if audiobook == nil {
                await loadAudiobook()
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: placeholder.imageUrl, size: .large)) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ProgressView()
                            .scaleEffect(1.5)
                    }
            }
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(spacing: 8) {
                Text(placeholder.itemName)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                
                if let artist = placeholder.artistName {
                    Text(artist)
                        .font(.headline)
                        .foregroundColor(.pink)
                }
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
    
    private func loadAudiobook() async {
        isLoading = true
        error = nil
        do {
            audiobook = try await XonoraClient.shared.fetchAudiobook(itemId: itemId, provider: provider)
        } catch {
            print("[LazyAudiobook] Error: \(error)")
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// Shared Error View Helper
@ViewBuilder
fileprivate func errorView(message: String, retryAction: @escaping () -> Void) -> some View {
    VStack(spacing: 16) {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 50))
            .foregroundColor(.yellow)
        
        Text("Failed to load content")
            .font(.headline)
        
        Text(message)
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        
        Button(action: retryAction) {
            Text("Retry")
                .fontWeight(.semibold)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.pink)
                .foregroundColor(.white)
                .cornerRadius(8)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(UIColor.systemBackground))
}

struct LazyPodcastDetailView: View {
    let itemId: String
    let provider: String
    let placeholder: PlaybackHistoryItem
    
    @State private var podcast: Podcast?
    @State private var isLoading = true
    @State private var error: String?
    
    var body: some View {
        Group {
            if let podcast = podcast {
                PodcastDetailView(podcast: podcast, fallbackImageString: placeholder.imageUrl)
            } else if isLoading {
                loadingView
            } else if let error = error {
                errorView(message: error) {
                    Task { await loadPodcast() }
                }
            }
        }
        .task {
            if podcast == nil {
                await loadPodcast()
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: placeholder.imageUrl, size: .large)) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ProgressView()
                            .scaleEffect(1.5)
                    }
            }
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(spacing: 8) {
                Text(placeholder.itemName)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
    
    private func loadPodcast() async {
        isLoading = true
        error = nil
        do {
            podcast = try await XonoraClient.shared.fetchPodcast(itemId: itemId, provider: provider)
        } catch {
            print("[LazyPodcast] Error: \(error)")
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

