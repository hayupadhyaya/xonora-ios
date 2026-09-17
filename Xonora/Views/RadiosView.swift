import SwiftUI

struct RadiosView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @ObservedObject private var prefs = UserPreferences.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isInitialLoad = true
    @Environment(\.miniPlayerBottomPadding) private var miniPlayerPadding
    @Environment(BarVisibilityManager.self) private var barManager

    private var sortOption: SortOption {
        SortOption(rawValue: prefs.sortRadios) ?? .nameAsc
    }
    private var viewMode: ViewMode {
        ViewMode(rawValue: prefs.viewModeRadios) ?? .grid
    }
    private var columns: [GridItem] {
        gridColumns(for: "radios", horizontalSizeClass: horizontalSizeClass, verticalSizeClass: verticalSizeClass)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if (libraryViewModel.isLoading || isInitialLoad) && libraryViewModel.radios.isEmpty {
                    VStack {
                        Spacer()
                        ProgressView("Loading Radio Stations...")
                            .controlSize(.large)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if let error = libraryViewModel.errorMessage, libraryViewModel.radios.isEmpty {
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
                    radiosContent
                }
            }
            .navigationTitle("Radio")
            .background(Color(UIColor.systemBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 4) {
                        Button {
                            prefs.viewModeRadios = (viewMode == .grid ? ViewMode.list : .grid).rawValue
                        } label: {
                            Image(systemName: viewMode == .grid ? "square.grid.2x2" : "list.bullet")
                        }
                        sortMenu
                    }
                }
            }
            .globalToolbar(searchFilter: .radio)
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
                    prefs.sortRadios = option.rawValue
                } label: {
                    HStack {
                        Text(option.label)
                        if prefs.sortRadios == option.rawValue {
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
    private var radiosContent: some View {
        if viewMode == .grid {
            radiosGrid
        } else {
            radiosListView
        }
    }

    private var radiosGrid: some View {
        let sorted = libraryViewModel.sortedRadios(option: sortOption)
        return ScrollView {
            LazyVStack(spacing: 0) {
                if sorted.isEmpty {
                    ContentUnavailableView(
                        "No Radio Stations",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Your library has no radio stations.")
                    )
                    .padding(.top, 100)
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(sorted) { radio in
                            Button {
                                playerViewModel.playRadio(radio)
                            } label: {
                                MediaGridItem(
                                    name: radio.name,
                                    subtitle: nil,
                                    imageURL: XonoraClient.shared.getImageURL(for: radio.imageUrl, size: .small),
                                    placeholderIcon: "antenna.radiowaves.left.and.right"
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

    private var radiosListView: some View {
        let sorted = libraryViewModel.sortedRadios(option: sortOption)
        return ScrollView {
            if sorted.isEmpty {
                ContentUnavailableView(
                    "No Radio Stations",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Your library has no radio stations.")
                )
                .padding(.top, 100)
            } else {
                VStack(spacing: 0) {
                    ForEach(sorted) { radio in
                        Button {
                            playerViewModel.playRadio(radio)
                        } label: {
                            RadioListRow(title: radio.name, imageUrl: radio.imageUrl)
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
