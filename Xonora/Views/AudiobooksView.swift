import SwiftUI

struct AudiobooksView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @ObservedObject private var prefs = UserPreferences.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isInitialLoad = true
    @Environment(\.miniPlayerBottomPadding) private var miniPlayerPadding
    @Environment(BarVisibilityManager.self) private var barManager
    @State private var selectedCategory: AudiobookCategory = .all

    enum AudiobookCategory: String, CaseIterable {
        case all = "All"
        case authors = "Authors"
    }

    private var sortOption: SortOption {
        SortOption(rawValue: prefs.sortAudiobooks) ?? .nameAsc
    }
    private var viewMode: ViewMode {
        ViewMode(rawValue: prefs.viewModeAudiobooks) ?? .grid
    }
    private var columns: [GridItem] {
        gridColumns(for: "audiobooks", horizontalSizeClass: horizontalSizeClass, verticalSizeClass: verticalSizeClass)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if (libraryViewModel.isLoading || isInitialLoad) && libraryViewModel.audiobooks.isEmpty {
                    VStack {
                        Spacer()
                        ProgressView("Loading Audiobooks...")
                            .controlSize(.large)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if let error = libraryViewModel.errorMessage, libraryViewModel.audiobooks.isEmpty {
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
                    currentCategoryView
                }
            }
            .navigationTitle("Audiobooks")
            .background(Color(UIColor.systemBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(AudiobookCategory.allCases, id: \.self) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 250)
                }
                if selectedCategory == .all {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 4) {
                            Button {
                                prefs.viewModeAudiobooks = (viewMode == .grid ? ViewMode.list : .grid).rawValue
                            } label: {
                                Image(systemName: viewMode == .grid ? "square.grid.2x2" : "list.bullet")
                            }
                            sortMenu
                        }
                    }
                }
            }
            .globalToolbar(searchFilter: .audiobooks)
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
                    prefs.sortAudiobooks = option.rawValue
                } label: {
                    HStack {
                        Text(option.label)
                        if prefs.sortAudiobooks == option.rawValue {
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
    private var currentCategoryView: some View {
        switch selectedCategory {
        case .all:
            if viewMode == .grid {
                audiobooksGrid
            } else {
                audiobooksListView
            }
        case .authors:
            authorsList
        }
    }

    private var audiobooksGrid: some View {
        let sorted = libraryViewModel.sortedAudiobooks(option: sortOption)
        return ScrollView {
            LazyVStack(spacing: 0) {
                if sorted.isEmpty {
                    ContentUnavailableView(
                        "No Audiobooks",
                        systemImage: "book",
                        description: Text("Your library has no audiobooks.")
                    )
                    .padding(.top, 100)
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(sorted) { audiobook in
                            NavigationLink(destination: AudiobookDetailView(audiobook: audiobook)) {
                                MediaGridItem(
                                    name: audiobook.name,
                                    subtitle: audiobook.authorNames,
                                    imageURL: XonoraClient.shared.getImageURL(for: audiobook.imageUrl, size: .small),
                                    placeholderIcon: "book"
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

    private var audiobooksListView: some View {
        let sorted = libraryViewModel.sortedAudiobooks(option: sortOption)
        return ScrollView {
            if sorted.isEmpty {
                ContentUnavailableView(
                    "No Audiobooks",
                    systemImage: "book",
                    description: Text("Your library has no audiobooks.")
                )
                .padding(.top, 100)
            } else {
                VStack(spacing: 0) {
                    ForEach(sorted) { audiobook in
                        NavigationLink(destination: AudiobookDetailView(audiobook: audiobook)) {
                            MediaListRow(
                                title: audiobook.name,
                                subtitle: audiobook.authorNames,
                                imageUrl: audiobook.imageUrl,
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

    private var authorsList: some View {
        let authors = Set(libraryViewModel.audiobooks.flatMap { $0.authors ?? [] }).sorted()

        return ScrollView {
            if authors.isEmpty {
                ContentUnavailableView(
                    "No Authors",
                    systemImage: "person.2",
                    description: Text("No authors found in your audiobooks.")
                )
                .padding(.top, 100)
            } else {
                VStack(spacing: 0) {
                    ForEach(authors, id: \.self) { author in
                        let authorBooks = libraryViewModel.audiobooks.filter { $0.authors?.contains(author) == true }

                        NavigationLink(destination: AuthorAudiobooksView(author: author, audiobooks: authorBooks)) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.gray)
                                    }

                                Text(author)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Spacer()

                                Text("\(authorBooks.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 72)
                    }
                }
                .padding(.bottom, miniPlayerPadding)
            }
        }
        .trackScrollForBars(barManager)
        .background(Color(UIColor.systemBackground))
    }

}

struct AuthorAudiobooksView: View {
    let author: String
    let audiobooks: [Audiobook]
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.miniPlayerBottomPadding) private var miniPlayerPadding

    private var columns: [GridItem] {
        gridColumns(for: "audiobooks", horizontalSizeClass: horizontalSizeClass, verticalSizeClass: verticalSizeClass)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(audiobooks) { audiobook in
                    NavigationLink(destination: AudiobookDetailView(audiobook: audiobook)) {
                        MediaGridItem(
                            name: audiobook.name,
                            subtitle: audiobook.authorNames,
                            imageURL: XonoraClient.shared.getImageURL(for: audiobook.imageUrl, size: .small),
                            placeholderIcon: "book"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .padding(.bottom, miniPlayerPadding)
        }
        .navigationTitle(author)
        .background(Color(UIColor.systemBackground))
    }
}

