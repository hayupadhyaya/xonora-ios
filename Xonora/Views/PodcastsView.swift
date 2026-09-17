import SwiftUI

struct PodcastsView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @ObservedObject private var prefs = UserPreferences.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isInitialLoad = true
    @Environment(\.miniPlayerBottomPadding) private var miniPlayerPadding
    @Environment(BarVisibilityManager.self) private var barManager

    private var sortOption: SortOption {
        SortOption(rawValue: prefs.sortPodcasts) ?? .nameAsc
    }
    private var viewMode: ViewMode {
        ViewMode(rawValue: prefs.viewModePodcasts) ?? .grid
    }
    private var columns: [GridItem] {
        gridColumns(for: "podcasts", horizontalSizeClass: horizontalSizeClass, verticalSizeClass: verticalSizeClass)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if (libraryViewModel.isLoading || isInitialLoad) && libraryViewModel.podcasts.isEmpty {
                    VStack {
                        Spacer()
                        ProgressView("Loading Podcasts...")
                            .controlSize(.large)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if let error = libraryViewModel.errorMessage, libraryViewModel.podcasts.isEmpty {
                    ContentUnavailableView {
                        Label("Unable to Load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") {
                            Task {
                                await libraryViewModel.loadLibrary(forceRefresh: true)
                            }
                        }
                    }
                } else {
                    podcastsContent
                }
            }
            .navigationTitle("Podcasts")
            .background(Color(UIColor.systemBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 4) {
                        Button {
                            prefs.viewModePodcasts = (viewMode == .grid ? ViewMode.list : .grid).rawValue
                        } label: {
                            Image(systemName: viewMode == .grid ? "square.grid.2x2" : "list.bullet")
                        }
                        sortMenu
                    }
                }
            }
            .globalToolbar(searchFilter: .podcasts)
            .refreshable {
                await libraryViewModel.refreshLibrary()
            }
            .task {
                if isInitialLoad {
                    await libraryViewModel.loadLibrary()
                    isInitialLoad = false
                }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortOption.allCases, id: \.self) { option in
                Button {
                    prefs.sortPodcasts = option.rawValue
                } label: {
                    HStack {
                        Text(option.label)
                        if prefs.sortPodcasts == option.rawValue {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    @ViewBuilder
    private var podcastsContent: some View {
        if viewMode == .grid {
            podcastsGrid
        } else {
            podcastsListView
        }
    }

    private var podcastsGrid: some View {
        let sorted = libraryViewModel.sortedPodcasts(option: sortOption)
        return ScrollView {
            LazyVStack(spacing: 0) {
                if sorted.isEmpty {
                    ContentUnavailableView(
                        "No Podcasts",
                        systemImage: "mic",
                        description: Text("Your library has no podcasts.")
                    )
                    .padding(.top, 100)
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(sorted) { podcast in
                            NavigationLink(destination: PodcastDetailView(podcast: podcast)) {
                                MediaGridItem(
                                    name: podcast.name,
                                    subtitle: podcast.publisher ?? "Unknown Publisher",
                                    imageURL: XonoraClient.shared.getImageURL(for: podcast.imageUrl, size: .small),
                                    placeholderIcon: "mic.fill"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, miniPlayerPadding)
                }
            }
        }
        .trackScrollForBars(barManager)
        .background(Color(UIColor.systemBackground))
    }

    private var podcastsListView: some View {
        let sorted = libraryViewModel.sortedPodcasts(option: sortOption)
        return ScrollView {
            if sorted.isEmpty {
                ContentUnavailableView(
                    "No Podcasts",
                    systemImage: "mic",
                    description: Text("Your library has no podcasts.")
                )
                .padding(.top, 100)
            } else {
                VStack(spacing: 0) {
                    ForEach(sorted) { podcast in
                        NavigationLink(destination: PodcastDetailView(podcast: podcast)) {
                            MediaListRow(
                                title: podcast.name,
                                subtitle: podcast.publisher,
                                imageUrl: podcast.imageUrl,
                                imageShape: .rounded
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, miniPlayerPadding)
            }
        }
        .trackScrollForBars(barManager)
        .background(Color(UIColor.systemBackground))
    }
}
