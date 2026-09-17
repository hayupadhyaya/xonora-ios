import CarPlay
import UIKit
import Combine
import Intents

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    var currentAudiobook: Audiobook?
    var currentPodcast: Podcast?
    /// Cleared on disconnect — used for NowPlaying/session-scoped subscriptions.
    var cancellables = Set<AnyCancellable>()
    /// Never cleared — home/library/playlist subscriptions subscribe only once.
    private var persistentCancellables = Set<AnyCancellable>()
    private var homeImageTask: Task<Void, Never>?

    // Tab templates
    var homeTemplate: CPListTemplate?
    var libraryTemplate: CPGridTemplate?
    var playlistsTemplate: CPListTemplate?

    // Cached drill-down templates (rebuilt only when data changes)
    private var cachedAlbumsTemplate: CPListTemplate?
    private var cachedArtistsTemplate: CPListTemplate?
    private var cachedTracksTemplate: CPListTemplate?
    private var cachedAudiobooksTemplate: CPListTemplate?
    private var cachedPodcastsTemplate: CPListTemplate?
    private var cachedRadioTemplate: CPListTemplate?
    private var cachedLibraryPlaylistsTemplate: CPListTemplate?
    // Per-item detail templates keyed by itemId
    private var cachedAlbumTrackTemplates: [String: CPListTemplate] = [:]
    private var cachedPlaylistTrackTemplates: [String: CPListTemplate] = [:]

    // Pagination for large lists
    private static let carPlayPageSize = 200
    private var tracksPageCount = 1
    private var albumsPageCount = 1
    private var artistsPageCount = 1
    private var audiobooksPageCount = 1
    private var podcastsPageCount = 1
    private var radioPageCount = 1
    private var libraryPlaylistsPageCount = 1

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        // Only build templates once — reuse on reconnect to avoid blanking content
        if homeTemplate == nil { setupHomeTemplate() }
        if libraryTemplate == nil { setupLibraryTemplate() }
        if playlistsTemplate == nil { setupPlaylistsTemplate() }
        setupNowPlayingTemplate()

        let tabBar = CPTabBarTemplate(templates: makeTabs())
        interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)

        // Only subscribe once — persistent subscriptions survive disconnect
        if persistentCancellables.isEmpty {
            subscribeToHomeUpdates()
            subscribeToLibraryUpdates()
        }
        subscribeToNowPlayingUpdates()

        let client = XonoraClient.shared
        switch client.connectionState {
        case .disconnected, .error:
            // CarPlay launched before phone UI — trigger reconnection
            NotificationCenter.default.post(name: .reconnectRequired, object: nil)
            // Show any cached data while reconnecting
            if !HomeViewModel.shared.categoryItems.isEmpty {
                rebuildHomeList()
            }
            // Reload fresh data once connection is restored
            client.$connectionState
                .filter { $0 == .connected }
                .first()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor in await HomeViewModel.shared.loadData() }
                }
                .store(in: &cancellables)
        default:
            // Already connected or connecting
            if HomeViewModel.shared.categoryItems.isEmpty {
                Task { @MainActor in await HomeViewModel.shared.loadData() }
            } else {
                rebuildHomeList()
            }
        }

        // Auto-switch to local player when CarPlay connects.
        // CarPlay audio should always route to the phone/car, not a remote speaker.
        Task { await XonoraClient.shared.switchToLocalPlayer() }

        // If the local player hasn't registered yet, wait for it via a one-shot subscriber.
        XonoraClient.shared.$players
            .dropFirst()
            .first(where: { players in
                guard let localId = SendspinClient.shared.clientId else { return false }
                return players.contains(where: { $0.playerId == localId && $0.available })
            })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard self != nil else { return }
                Task { await XonoraClient.shared.switchToLocalPlayer() }
            }
            .store(in: &cancellables)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        CPNowPlayingTemplate.shared.remove(self)
        homeImageTask?.cancel()
        homeImageTask = nil
        cancellables.removeAll()
        // Do NOT clear cached templates — they stay in memory so reconnecting CarPlay
        // reuses already-built templates with images already set.
        self.interfaceController = nil
    }

    private func makeTabs() -> [CPTemplate] {
        homeTemplate?.tabImage = UIImage(systemName: "house.fill")
        libraryTemplate?.tabImage = UIImage(systemName: "music.note.house.fill")
        playlistsTemplate?.tabImage = UIImage(systemName: "music.note.list")
        return [homeTemplate, libraryTemplate, playlistsTemplate].compactMap { $0 }
    }

    // MARK: - Library Tab

    private func setupLibraryTemplate() {
        libraryTemplate = CPGridTemplate(title: "Library", gridButtons: buildLibraryGridButtons())
    }
    
    private func subscribeToLibraryUpdates() {
        // Observe UserDefaults for changes to the library settings
        UserPreferences.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.rebuildLibraryGrid()
                }
            }
            .store(in: &persistentCancellables)

        // Observe LibraryViewModel updates to populate tracks, podcasts, etc.
        LibraryViewModel.shared.$albums
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildLibraryGrid()
                self?.cachedAlbumsTemplate = nil
                self?.cachedAlbumTrackTemplates.removeAll()
            }
            .store(in: &persistentCancellables)

        LibraryViewModel.shared.$artists
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.cachedArtistsTemplate = nil }
            .store(in: &persistentCancellables)

        LibraryViewModel.shared.$tracks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.cachedTracksTemplate = nil }
            .store(in: &persistentCancellables)

        LibraryViewModel.shared.$audiobooks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.cachedAudiobooksTemplate = nil }
            .store(in: &persistentCancellables)

        LibraryViewModel.shared.$podcasts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.cachedPodcastsTemplate = nil }
            .store(in: &persistentCancellables)

        LibraryViewModel.shared.$radios
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.cachedRadioTemplate = nil }
            .store(in: &persistentCancellables)

        LibraryViewModel.shared.$playlists
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.cachedLibraryPlaylistsTemplate = nil
                self?.cachedPlaylistTrackTemplates.removeAll()
                self?.rebuildPlaylistsList()
            }
            .store(in: &persistentCancellables)
    }
    
    private func buildLibraryGridButtons() -> [CPGridButton] {
        let preferences = UserPreferences.shared
        
        var gridButtons: [CPGridButton] = []
        
        for sectionId in preferences.librarySectionOrder {
            guard preferences.isLibrarySectionEnabled(sectionId) else { continue }
            if let section = UserPreferences.allLibrarySections.first(where: { $0.id == sectionId }) {
                // Grid buttons do not natively display 2 distinct labels, so just pass the primary name
                let titleVariants = [section.name]
                
                let icon = createLibraryGridIcon(systemName: section.icon)
                
                let button = CPGridButton(titleVariants: titleVariants, image: icon) { [weak self] _ in
                    self?.handleLibrarySelection(identifier: section.id, completion: {})
                }
                
                gridButtons.append(button)
            }
        }
        
        return gridButtons
    }

    private func rebuildLibraryGrid() {
        libraryTemplate?.updateGridButtons(buildLibraryGridButtons())
    }

    private func createLibraryGridIcon(systemName: String, label: String? = nil) -> UIImage {
        // We use a transparent 240x240 image structure.
        let size = CGSize(width: 240, height: 240)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let iconPointSize: CGFloat = label == nil ? 110 : 80
            if let icon = UIImage(systemName: systemName, withConfiguration: UIImage.SymbolConfiguration(pointSize: iconPointSize, weight: .regular))?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                
                let yOffset: CGFloat = label == nil ? 0 : -20
                let iconRect = CGRect(
                    x: (size.width - icon.size.width) / 2,
                    y: ((size.height - icon.size.height) / 2) + yOffset,
                    width: icon.size.width,
                    height: icon.size.height
                )
                
                icon.draw(in: iconRect)
                
                if let label = label {
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 32, weight: .bold),
                        .foregroundColor: UIColor.white
                    ]
                    let string = NSAttributedString(string: label, attributes: attributes)
                    let stringSize = string.size()
                    let stringRect = CGRect(
                        x: (size.width - stringSize.width) / 2,
                        y: iconRect.maxY + 10,
                        width: stringSize.width,
                        height: stringSize.height
                    )
                    string.draw(in: stringRect)
                }
            }
        }
    }

    private func createTransparentSpacer() -> UIImage {
        let size = CGSize(width: 240, height: 240)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in }
    }

    // MARK: - Pagination Helper

    /// Build a paginated section with optional "Load More" item
    /// - Parameters:
    ///   - items: Full array of items to paginate
    ///   - pageCount: Current page number (1-indexed)
    ///   - title: Title for the section (optional)
    ///   - itemBuilder: Closure to convert item to CPListItem
    ///   - onLoadMore: Callback when user taps "Load More"
    /// - Returns: CPListSection with up to pageSize*pageCount items, plus "Load More" if more exist
    private func pagedSection<T>(
        _ items: [T],
        pageCount: Int,
        title: String? = nil,
        itemBuilder: (T) -> CPListItem,
        onLoadMore: @escaping () -> Void
    ) -> CPListSection {
        let itemsPerPage = Self.carPlayPageSize
        let maxItems = itemsPerPage * pageCount
        let displayItems = Array(items.prefix(maxItems))

        var listItems = displayItems.map(itemBuilder)

        // Add "Load More" if there are remaining items
        if items.count > maxItems {
            let remaining = items.count - maxItems
            let loadMoreItem = CPListItem(
                text: "Load More",
                detailText: "(\(remaining) more \(remaining == 1 ? "item" : "items"))",
                image: createListActionIcon(systemName: "ellipsis")
            )
            loadMoreItem.handler = { _, completion in
                onLoadMore()
                completion()
            }
            listItems.append(loadMoreItem)
        }

        return CPListSection(items: listItems, header: title, sectionIndexTitle: title)
    }

    private func handleLibrarySelection(identifier: String, completion: @escaping () -> Void) {
        guard let interfaceController = interfaceController else {
            completion()
            return
        }
        
        switch identifier {
        case "Albums":
            showAlbums(interfaceController: interfaceController, completionHandler: completion)
        case "Playlists":
            showPlaylists(interfaceController: interfaceController, completionHandler: completion)
        case "Artists":
            showArtists(interfaceController: interfaceController, completionHandler: completion)
        case "Audiobooks":
            showAudiobooks(interfaceController: interfaceController, completionHandler: completion)
        case "Tracks":
            showTracksList(interfaceController: interfaceController, completionHandler: completion)
        case "Podcasts":
            showPodcasts(interfaceController: interfaceController, completionHandler: completion)
        case "Radio":
            showRadio(interfaceController: interfaceController, completionHandler: completion)
        default:
            completion()
        }
    }

    // MARK: - Home Tab

    private func setupHomeTemplate() {
        homeTemplate = CPListTemplate(title: "Home", sections: [])
    }

    private func subscribeToHomeUpdates() {
        // Apply dropFirst per-publisher so @Published's current-value-on-subscribe is dropped
        // but real data changes (second+ emits) still trigger rebuilds.
        // UserPreferences.objectWillChange doesn't emit on subscribe so no dropFirst needed.
        Publishers.MergeMany(
            HomeViewModel.shared.$continueListeningItems.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            HomeViewModel.shared.$categoryItems.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            HomeViewModel.shared.$recommendationSections.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            HomeViewModel.shared.$recentlyPlayedItems.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            UserPreferences.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in self?.rebuildHomeList() }
        .store(in: &persistentCancellables)
    }
    
    // Store items mapped by their unique ID to avoid losing track of them during async image loads
    private var homeRowItems: [UUID: CPListImageRowItem] = [:]
    private var homeItemMap: [UUID: [PlaybackHistoryItem]] = [:]

    private func rebuildHomeList() {
        homeImageTask?.cancel()
        homeRowItems.removeAll()
        homeItemMap.removeAll()

        var sections: [CPListSection] = []
        var itemsToLoadImages: [PlaybackHistoryItem] = []
        let placeholder = createPlaceholderImage()

        let preferences = UserPreferences.shared

        for sectionId in preferences.homeSectionOrder {
            guard preferences.isSectionEnabled(sectionId) else { continue }
            
            // 1. Check for Categories
            if sectionId.hasPrefix("category_") {
                let categoryName = String(sectionId.dropFirst("category_".count))
                if let category = HomeViewModel.CategorySection.Category(rawValue: categoryName),
                   let sectionData = HomeViewModel.shared.categoryItems.first(where: { $0.category == category }) {
                    let section = createHorizontalSection(title: category.rawValue, items: sectionData.items, placeholder: placeholder, itemsToLoadImages: &itemsToLoadImages)
                    sections.append(section)
                }
            } 
            // 2. Check for Recommendations
            else if sectionId.hasPrefix("rec_") {
                let recName = String(sectionId.dropFirst("rec_".count))
                if let sectionData = HomeViewModel.shared.recommendationSections.first(where: { $0.name == recName }) {
                    let section = createHorizontalSection(title: sectionData.name, items: sectionData.items, placeholder: placeholder, itemsToLoadImages: &itemsToLoadImages)
                    sections.append(section)
                }
            } 
            // 3. Check for Static Sections
            else {
                switch sectionId {
                case "recentlyPlayed":
                    let recentItems = HomeViewModel.shared.recentlyPlayedItems
                    if !recentItems.isEmpty {
                         let section = createHorizontalSection(title: "Recently Played", items: recentItems, placeholder: placeholder, itemsToLoadImages: &itemsToLoadImages)
                         sections.append(section)
                    }
                    
                case "continueListening":
                    let continueItems = HomeViewModel.shared.continueListeningItems.filter { item in
                        guard let progress = item.progress, let duration = item.duration, duration > 0 else { return false }
                        return progress > 0 && progress < duration
                    }
                    
                    if !continueItems.isEmpty {
                        let section = createHorizontalSection(title: "Continue Listening", items: continueItems, placeholder: placeholder, itemsToLoadImages: &itemsToLoadImages)
                        sections.append(section)
                    }
                    
                default:
                    break
                }
            }
        }

        print("[CarPlay Home] Rebuilding list with \(sections.count) sections")

        // Show placeholders immediately
        homeTemplate?.updateSections(sections)
        
        guard !itemsToLoadImages.isEmpty else { return }

        // Load images asynchronously
        homeImageTask = Task { [weak self] in
            let session = await ImageCache.shared.session

            await withTaskGroup(of: (String, UIImage?).self) { group in
                // Only load unique URLs to save bandwidth
                let uniqueItems = Dictionary(grouping: itemsToLoadImages, by: { $0.itemId }).compactMap { $0.value.first }
                
                for item in uniqueItems {
                    guard let url = XonoraClient.shared.getImageURL(for: item.imageUrl, size: .thumbnail) else { continue }
                    group.addTask {
                        if Task.isCancelled { return (item.itemId, nil) }

                        // Check memory/disk cache first
                        if let cached = await ImageCache.shared.image(for: url) {
                            return (item.itemId, cached)
                        }

                        // Download and cache - server provides 150px which is ideal for CarPlay
                        guard let (data, _) = try? await session.data(from: url),
                              let img = UIImage(data: data) else { return (item.itemId, nil) }
                        await ImageCache.shared.setImage(img, for: url)
                        return (item.itemId, img)
                    }
                }
                
                // Track our current state of images so we can update rows efficiently
                var currentImagesMap: [String: UIImage] = [:]
                
                for await (id, img) in group {
                    guard !Task.isCancelled, let img = img else { continue }
                    currentImagesMap[id] = img
                    
                    // Incrementally route the new image to the UI immediately
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        
                        // Check if this image belongs to any horizontal row items
                        for (rowId, rowItem) in self.homeRowItems {
                            guard let matchedItems = self.homeItemMap[rowId] else { continue }
                            
                            // If this row contains the item we just downloaded, update the whole row
                            if matchedItems.contains(where: { $0.itemId == id }) {
                                let newImages = matchedItems.map { item -> UIImage in
                                    return currentImagesMap[item.itemId] ?? placeholder
                                }
                                rowItem.update(newImages)
                            }
                        }
                        
                        // Check if this image belongs to any vertical list items
                        for (listId, listItem) in self.homeListItems {
                            guard let matchedItems = self.homeItemMap[listId], let item = matchedItems.first else { continue }
                            if item.itemId == id {
                                listItem.setImage(img)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func createHorizontalSection(title: String, items: [PlaybackHistoryItem], placeholder: UIImage, itemsToLoadImages: inout [PlaybackHistoryItem]) -> CPListSection {
        var rowItems: [CPListImageRowItem] = []
        
        // CarPlay automatically truncates horizontal rows based on screen size (e.g. 4 on small screens, up to 10 on ultrawide).
        // By supplying 12 items to a single row, CarPlay natively displays as many as it can fit. 
        // We use a single row so that we do not generate multiple rows for the same section name.
        let displayItems = Array(items.prefix(12))
        itemsToLoadImages.append(contentsOf: displayItems)
        
        let placeholderImages = Array(repeating: placeholder, count: displayItems.count)
        
        let rowId = UUID()
        let rowItem = CPListImageRowItem(text: title, images: placeholderImages)
        
        rowItem.listImageRowHandler = { [weak self] item, index, completion in
            guard let self = self,
                  let matchedItems = self.homeItemMap[rowId],
                  index < matchedItems.count else {
                completion()
                return
            }
            
            let tappedItem = matchedItems[index]
            print("[CarPlay Home] Tapped row item: \(tappedItem.itemName) (\(tappedItem.contentType))")
            
            // For driver safety, clicking any item on the Home tab (including albums/audiobooks)
            // will immediately start playing its contents instead of drilling down into navigation.
            HomeViewModel.shared.playItem(item: tappedItem)
            completion()
        }
        
        self.homeRowItems[rowId] = rowItem
        self.homeItemMap[rowId] = displayItems
        
        rowItems.append(rowItem)
        
        return CPListSection(items: rowItems, header: nil, sectionIndexTitle: nil)
    }
    
    // Fallback dictionary for vertical items so we can update images late
    private var homeListItems: [UUID: CPListItem] = [:]

    private func createVerticalSection(title: String, items: [PlaybackHistoryItem], placeholder: UIImage, itemsToLoadImages: inout [PlaybackHistoryItem]) -> CPListSection {
        var listItems: [CPListItem] = []
        
        // Vertical sections can be slightly longer since they scroll normally
        let displayItems = Array(items.prefix(15))
        itemsToLoadImages.append(contentsOf: displayItems)
        
        for item in displayItems {
            let itemId = UUID()
            let listItem = CPListItem(text: item.itemName, detailText: item.artistName, image: placeholder)
            
            listItem.handler = { _, completion in
                print("[CarPlay Home] Tapped list item: \(item.itemName)")
                HomeViewModel.shared.playItem(item: item)
                completion()
            }
            
            self.homeListItems[itemId] = listItem
            // Overload the homeItemMap so our async loader updates the image when done
            self.homeItemMap[itemId] = [item]
            
            listItems.append(listItem)
        }
        
        return CPListSection(items: listItems, header: title, sectionIndexTitle: title)
    }
    


    private func createPlaceholderImage() -> UIImage {
        let size = CGSize(width: 240, height: 240)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            // Background
            UIColor.systemGray5.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // Music note icon
            let iconSize: CGFloat = 100
            let iconRect = CGRect(
                x: (size.width - iconSize) / 2,
                y: (size.height - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )
            
            if let musicIcon = UIImage(systemName: "music.note", withConfiguration: UIImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)) {
                UIColor.systemGray3.setFill()
                musicIcon.withTintColor(.systemGray3, renderingMode: .alwaysOriginal).draw(in: iconRect)
            }
        }
    }

    private func createListActionIcon(systemName: String) -> UIImage {
        let size = CGSize(width: 240, height: 240)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let config = UIImage.SymbolConfiguration(pointSize: 100, weight: .semibold)
            if let icon = UIImage(systemName: systemName, withConfiguration: config)?
                .withTintColor(.systemBlue, renderingMode: .alwaysOriginal) {
                
                let iconRect = CGRect(
                    x: (size.width - icon.size.width) / 2,
                    y: (size.height - icon.size.height) / 2,
                    width: icon.size.width,
                    height: icon.size.height
                )
                icon.draw(in: iconRect)
            }
        }
    }


    // MARK: - Playlists Tab

    private func setupPlaylistsTemplate() {
        playlistsTemplate = CPListTemplate(title: "Playlists", sections: [])
    }

    private func rebuildPlaylistsList() {
        let playlists = LibraryViewModel.shared.playlists

        guard !playlists.isEmpty else {
            let placeholder = CPListItem(text: "No playlists", detailText: nil)
            playlistsTemplate?.updateSections([CPListSection(items: [placeholder])])
            return
        }

        let listItems = playlists.map { playlist -> CPListItem in
            return createListItem(text: playlist.name, detailText: "Playlist", image: nil, imageUrl: playlist.imageUrl, userInfo: playlist)
        }

        playlistsTemplate?.updateSections([CPListSection(items: listItems)])
    }

    // MARK: - Now Playing Tab

    private func setupNowPlayingTemplate() {
        CPNowPlayingTemplate.shared.isAlbumArtistButtonEnabled = false
        CPNowPlayingTemplate.shared.isUpNextButtonEnabled = true
        CPNowPlayingTemplate.shared.add(self)
        updateNowPlayingButtons(isFavorited: PlayerManager.shared.isCurrentTrackFavorited)
    }

    private func subscribeToNowPlayingUpdates() {
        PlayerManager.shared.$isCurrentTrackFavorited
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isFavorited in self?.updateNowPlayingButtons(isFavorited: isFavorited) }
            .store(in: &cancellables)

        PlayerManager.shared.$queue
            .receive(on: DispatchQueue.main)
            .sink { queue in
                CPNowPlayingTemplate.shared.upNextTitle = queue.isEmpty ? "" : "\(queue.count) tracks"
            }
            .store(in: &cancellables)
    }

    private func updateNowPlayingButtons(isFavorited: Bool) {
        guard let heartImage = UIImage(systemName: isFavorited ? "heart.fill" : "heart") else { return }
        let favoriteButton = CPNowPlayingImageButton(image: heartImage) { _ in
            PlayerManager.shared.toggleCurrentTrackFavorite()
        }
        CPNowPlayingTemplate.shared.updateNowPlayingButtons([favoriteButton])
    }

    // MARK: - List Item Helper

    private func createListItem(text: String, detailText: String?, image: UIImage?, imageUrl: String? = nil, userInfo: Any? = nil) -> CPListItem {
        let placeholder = image ?? createPlaceholderImage()
        let item = CPListItem(text: text, detailText: detailText, image: placeholder)
        item.userInfo = userInfo
        item.handler = { [weak self] item, completion in
            self?.handleSelection(item: item, completionHandler: completion)
        }
        
        if let imageUrl = imageUrl, let url = XonoraClient.shared.getImageURL(for: imageUrl, size: .thumbnail) {
            Task { [weak item] in
                // Check memory/disk cache first
                if let cached = await ImageCache.shared.image(for: url) {
                    await MainActor.run { item?.setImage(cached) }
                    return
                }

                // Download and cache - server provides 150px which is ideal for CarPlay
                let session = await ImageCache.shared.session
                guard let (data, _) = try? await session.data(from: url),
                      let img = UIImage(data: data) else { return }
                await ImageCache.shared.setImage(img, for: url)
                await MainActor.run { item?.setImage(img) }
            }
        }
        
        return item
    }

    private func handleSelection(item: any CPSelectableListItem, completionHandler: @escaping () -> Void) {
        guard let interfaceController = interfaceController else {
            completionHandler()
            return
        }
        guard let listItem = item as? CPListItem else {
            completionHandler()
            return
        }

        if let album = listItem.userInfo as? Album {
            showTracks(for: album, interfaceController: interfaceController, completionHandler: completionHandler)
        } else if let playlist = listItem.userInfo as? Playlist {
            showTracks(for: playlist, interfaceController: interfaceController, completionHandler: completionHandler)
        } else if let audiobook = listItem.userInfo as? Audiobook {
            showChapters(for: audiobook, interfaceController: interfaceController, completionHandler: completionHandler)
        } else if let chapter = listItem.userInfo as? Chapter {
            playChapter(chapter, completionHandler: completionHandler)
        } else if let podcast = listItem.userInfo as? Podcast {
            showEpisodes(for: podcast, interfaceController: interfaceController, completionHandler: completionHandler)
        } else if let episode = listItem.userInfo as? PodcastEpisode {
            playEpisode(episode, for: currentPodcast, completionHandler: completionHandler)
        } else if let radio = listItem.userInfo as? Radio {
            playRadio(radio, completionHandler: completionHandler)
        } else if let track = listItem.userInfo as? Track {
            playTrack(track, completionHandler: completionHandler)
        } else if let artist = listItem.userInfo as? Artist {
            showAlbums(for: artist, interfaceController: interfaceController, completionHandler: completionHandler)
        } else if listItem.text == "Albums" {
            showAlbums(interfaceController: interfaceController, completionHandler: completionHandler)
        } else if listItem.text == "Playlists" {
            showPlaylists(interfaceController: interfaceController, completionHandler: completionHandler)
        } else if listItem.text == "Artists" {
            showArtists(interfaceController: interfaceController, completionHandler: completionHandler)
        } else if listItem.text == "Audiobooks" {
            showAudiobooks(interfaceController: interfaceController, completionHandler: completionHandler)
        } else if listItem.text == "Tracks" {
            showTracksList(interfaceController: interfaceController, completionHandler: completionHandler)
        } else if listItem.text == "Podcasts" {
            showPodcasts(interfaceController: interfaceController, completionHandler: completionHandler)
        } else if listItem.text == "Radio" {
            showRadio(interfaceController: interfaceController, completionHandler: completionHandler)
        } else {
            completionHandler()
        }
    }

    // MARK: - Library Drill-Down

    private func showAlbums(interfaceController: CPInterfaceController, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if cachedAlbumsTemplate == nil {
                let albums = LibraryViewModel.shared.albums

                let albumsSection = pagedSection(
                    albums,
                    pageCount: albumsPageCount,
                    itemBuilder: { album in
                        self.createListItem(text: album.name, detailText: album.artistNames, image: nil, imageUrl: album.imageUrl, userInfo: album)
                    },
                    onLoadMore: { [weak self] in
                        guard let self else { return }
                        self.albumsPageCount += 1
                        self.cachedAlbumsTemplate = nil
                        self.interfaceController.flatMap { self.showAlbums(interfaceController: $0, completionHandler: {}) }
                    }
                )

                cachedAlbumsTemplate = CPListTemplate(title: "Albums", sections: [albumsSection])
            }
            guard let template = cachedAlbumsTemplate else { completionHandler(); return }
            interfaceController.pushTemplate(template, animated: true, completion: nil)
            completionHandler()
        }
    }

    private func showAlbums(for artist: Artist, interfaceController: CPInterfaceController, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            do {
                let (albums, _) = try await LibraryViewModel.shared.loadArtistDetails(artist: artist)
                let listItems = albums.map {
                    createListItem(text: $0.name, detailText: $0.artistNames, image: nil, imageUrl: $0.imageUrl, userInfo: $0)
                }
                let template = CPListTemplate(title: artist.name, sections: [CPListSection(items: listItems)])
                interfaceController.pushTemplate(template, animated: true, completion: nil)
            } catch {
                print("[CarPlay] Failed to load artist albums: \(error)")
            }
            completionHandler()
        }
    }

    private func showPlaylists(interfaceController: CPInterfaceController, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if cachedLibraryPlaylistsTemplate == nil {
                let playlists = LibraryViewModel.shared.playlists

                let playlistsSection = pagedSection(
                    playlists,
                    pageCount: libraryPlaylistsPageCount,
                    itemBuilder: { playlist in
                        self.createListItem(text: playlist.name, detailText: "Playlist", image: nil, imageUrl: playlist.imageUrl, userInfo: playlist)
                    },
                    onLoadMore: { [weak self] in
                        guard let self else { return }
                        self.libraryPlaylistsPageCount += 1
                        self.cachedLibraryPlaylistsTemplate = nil
                        self.interfaceController.flatMap { self.showPlaylists(interfaceController: $0, completionHandler: {}) }
                    }
                )

                cachedLibraryPlaylistsTemplate = CPListTemplate(title: "Playlists", sections: [playlistsSection])
            }
            guard let template = cachedLibraryPlaylistsTemplate else { completionHandler(); return }
            interfaceController.pushTemplate(template, animated: true, completion: nil)
            completionHandler()
        }
    }

    private func showArtists(interfaceController: CPInterfaceController, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if cachedArtistsTemplate == nil {
                let artists = LibraryViewModel.shared.artists

                let artistsSection = pagedSection(
                    artists,
                    pageCount: artistsPageCount,
                    itemBuilder: { artist in
                        self.createListItem(text: artist.name, detailText: nil, image: nil, imageUrl: artist.imageUrl, userInfo: artist)
                    },
                    onLoadMore: { [weak self] in
                        guard let self else { return }
                        self.artistsPageCount += 1
                        self.cachedArtistsTemplate = nil
                        self.interfaceController.flatMap { self.showArtists(interfaceController: $0, completionHandler: {}) }
                    }
                )

                cachedArtistsTemplate = CPListTemplate(title: "Artists", sections: [artistsSection])
            }
            guard let template = cachedArtistsTemplate else { completionHandler(); return }
            interfaceController.pushTemplate(template, animated: true, completion: nil)
            completionHandler()
        }
    }

    private func showAudiobooks(interfaceController: CPInterfaceController, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if cachedAudiobooksTemplate == nil {
                let audiobooks = LibraryViewModel.shared.audiobooks

                let audiobooksSection = pagedSection(
                    audiobooks,
                    pageCount: audiobooksPageCount,
                    itemBuilder: { audiobook in
                        self.createListItem(text: audiobook.name, detailText: audiobook.authorNames, image: nil, imageUrl: audiobook.imageUrl, userInfo: audiobook)
                    },
                    onLoadMore: { [weak self] in
                        guard let self else { return }
                        self.audiobooksPageCount += 1
                        self.cachedAudiobooksTemplate = nil
                        self.interfaceController.flatMap { self.showAudiobooks(interfaceController: $0, completionHandler: {}) }
                    }
                )

                cachedAudiobooksTemplate = CPListTemplate(title: "Audiobooks", sections: [audiobooksSection])
            }
            guard let template = cachedAudiobooksTemplate else { completionHandler(); return }
            interfaceController.pushTemplate(template, animated: true, completion: nil)
            completionHandler()
        }
    }

    private func showChapters(for audiobook: Audiobook, interfaceController: CPInterfaceController, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            currentAudiobook = audiobook
            let chapters = audiobook.chapters

            if chapters.isEmpty || chapters.count == 1 {
                PlayerManager.shared.playAudiobook(audiobook)
                completionHandler()
                return
            }

            let listItems = chapters.map {
                createListItem(text: $0.name, detailText: $0.formattedDuration, image: nil, imageUrl: currentAudiobook?.imageUrl, userInfo: $0)
            }
            let template = CPListTemplate(title: audiobook.name, sections: [CPListSection(items: listItems)])
            interfaceController.pushTemplate(template, animated: true, completion: nil)
            completionHandler()
        }
    }

    private func playChapter(_ chapter: Chapter, completionHandler: @escaping () -> Void) {
        guard let audiobook = currentAudiobook else {
            completionHandler()
            return
        }
        PlayerManager.shared.playAudiobook(audiobook, startingAtChapter: chapter.position)
        completionHandler()
    }

    private func showTracks(for album: Album, interfaceController: CPInterfaceController, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if let cached = cachedAlbumTrackTemplates[album.itemId] {
                interfaceController.pushTemplate(cached, animated: true, completion: nil)
                completionHandler()
                return
            }
            do {
                let tracks = try await LibraryViewModel.shared.loadAlbumTracks(album: album)

                let playAllItem = CPListItem(text: "Play All", detailText: "Start playback from the first track", image: createListActionIcon(systemName: "play.fill"))
                playAllItem.handler = { _, completion in
                    if let first = tracks.first {
                        PlayerManager.shared.playTrack(first, fromQueue: tracks, sourceName: album.name)
                    }
                    completion()
                }

                let shuffleAllItem = CPListItem(text: "Shuffle", detailText: "Play tracks in random order", image: createListActionIcon(systemName: "shuffle"))
                shuffleAllItem.handler = { _, completion in
                    if !tracks.isEmpty {
                        let shuffled = tracks.shuffled()
                        PlayerManager.shared.playTrack(shuffled[0], fromQueue: shuffled, sourceName: album.name)
                    }
                    completion()
                }

                let listItems = tracks.map {
                    createListItem(text: $0.name, detailText: $0.artistNames, image: nil, imageUrl: $0.imageUrl, userInfo: $0)
                }

                let template = CPListTemplate(title: album.name, sections: [
                    CPListSection(items: [playAllItem, shuffleAllItem]),
                    CPListSection(items: listItems)
                ])
                cachedAlbumTrackTemplates[album.itemId] = template
                interfaceController.pushTemplate(template, animated: true, completion: nil)
            } catch {
                print("[CarPlay] Failed to load album tracks: \(error)")
            }
            completionHandler()
        }
    }

    private func showTracks(for playlist: Playlist, interfaceController: CPInterfaceController, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if let cached = cachedPlaylistTrackTemplates[playlist.itemId] {
                interfaceController.pushTemplate(cached, animated: true, completion: nil)
                completionHandler()
                return
            }
            do {
                let tracks = try await LibraryViewModel.shared.loadPlaylistTracks(playlist: playlist)

                let playAllItem = CPListItem(text: "Play All", detailText: "Start playback from the first track", image: createListActionIcon(systemName: "play.fill"))
                playAllItem.handler = { _, completion in
                    if let first = tracks.first {
                        PlayerManager.shared.playTrack(first, fromQueue: tracks, sourceName: playlist.name)
                    }
                    completion()
                }

                let shuffleAllItem = CPListItem(text: "Shuffle", detailText: "Play tracks in random order", image: createListActionIcon(systemName: "shuffle"))
                shuffleAllItem.handler = { _, completion in
                    if !tracks.isEmpty {
                        let shuffled = tracks.shuffled()
                        PlayerManager.shared.playTrack(shuffled[0], fromQueue: shuffled, sourceName: playlist.name)
                    }
                    completion()
                }

                let listItems = tracks.map {
                    createListItem(text: $0.name, detailText: $0.artistNames, image: nil, imageUrl: $0.imageUrl, userInfo: $0)
                }

                let template = CPListTemplate(title: playlist.name, sections: [
                    CPListSection(items: [playAllItem, shuffleAllItem]),
                    CPListSection(items: listItems)
                ])
                cachedPlaylistTrackTemplates[playlist.itemId] = template
                interfaceController.pushTemplate(template, animated: true, completion: nil)
            } catch {
                print("[CarPlay] Failed to load playlist tracks: \(error)")
            }
            completionHandler()
        }
    }

    private func showTracksList(interfaceController: CPInterfaceController, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if cachedTracksTemplate == nil {
                let tracks = LibraryViewModel.shared.tracks

                let playAllItem = CPListItem(text: "Play All", detailText: "Start playback from the first track", image: createListActionIcon(systemName: "play.fill"))
                playAllItem.handler = { _, completion in
                    if let first = tracks.first {
                        PlayerManager.shared.playTrack(first, fromQueue: tracks, sourceName: "Tracks")
                    }
                    completion()
                }

                let shuffleAllItem = CPListItem(text: "Shuffle", detailText: "Play tracks in random order", image: createListActionIcon(systemName: "shuffle"))
                shuffleAllItem.handler = { _, completion in
                    if !tracks.isEmpty {
                        let shuffled = tracks.shuffled()
                        PlayerManager.shared.playTrack(shuffled[0], fromQueue: shuffled, sourceName: "Tracks")
                    }
                    completion()
                }

                // Use pagination for tracks
                let tracksSection = pagedSection(
                    tracks,
                    pageCount: tracksPageCount,
                    itemBuilder: { track in
                        self.createListItem(text: track.name, detailText: track.artistNames, image: nil, imageUrl: track.imageUrl, userInfo: track)
                    },
                    onLoadMore: { [weak self] in
                        guard let self else { return }
                        self.tracksPageCount += 1
                        self.cachedTracksTemplate = nil
                        self.interfaceController.flatMap { self.showTracksList(interfaceController: $0, completionHandler: {}) }
                    }
                )

                cachedTracksTemplate = CPListTemplate(title: "Tracks", sections: [
                    CPListSection(items: [playAllItem, shuffleAllItem]),
                    tracksSection
                ])
            }
            guard let template = cachedTracksTemplate else { completionHandler(); return }
            interfaceController.pushTemplate(template, animated: true, completion: nil)
            completionHandler()
        }
    }

    private func showPodcasts(interfaceController: CPInterfaceController, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if cachedPodcastsTemplate == nil {
                let podcasts = LibraryViewModel.shared.podcasts

                let podcastsSection = pagedSection(
                    podcasts,
                    pageCount: podcastsPageCount,
                    itemBuilder: { podcast in
                        self.createListItem(text: podcast.name, detailText: podcast.publisher, image: nil, imageUrl: podcast.imageUrl, userInfo: podcast)
                    },
                    onLoadMore: { [weak self] in
                        guard let self else { return }
                        self.podcastsPageCount += 1
                        self.cachedPodcastsTemplate = nil
                        self.interfaceController.flatMap { self.showPodcasts(interfaceController: $0, completionHandler: {}) }
                    }
                )

                cachedPodcastsTemplate = CPListTemplate(title: "Podcasts", sections: [podcastsSection])
            }
            guard let template = cachedPodcastsTemplate else { completionHandler(); return }
            interfaceController.pushTemplate(template, animated: true, completion: nil)
            completionHandler()
        }
    }

    private func showRadio(interfaceController: CPInterfaceController, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if cachedRadioTemplate == nil {
                let radios = LibraryViewModel.shared.radios

                let radioSection = pagedSection(
                    radios,
                    pageCount: radioPageCount,
                    itemBuilder: { radio in
                        self.createListItem(text: radio.name, detailText: nil, image: nil, imageUrl: radio.imageUrl, userInfo: radio)
                    },
                    onLoadMore: { [weak self] in
                        guard let self else { return }
                        self.radioPageCount += 1
                        self.cachedRadioTemplate = nil
                        self.interfaceController.flatMap { self.showRadio(interfaceController: $0, completionHandler: {}) }
                    }
                )

                cachedRadioTemplate = CPListTemplate(title: "Radio", sections: [radioSection])
            }
            guard let template = cachedRadioTemplate else { completionHandler(); return }
            interfaceController.pushTemplate(template, animated: true, completion: nil)
            completionHandler()
        }
    }

    private func showEpisodes(for podcast: Podcast, interfaceController: CPInterfaceController, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            currentPodcast = podcast
            do {
                let episodes = try await LibraryViewModel.shared.loadPodcastEpisodes(podcast: podcast)
                if episodes.isEmpty {
                    PlayerManager.shared.playbackState = .error("No episodes available for this podcast.")
                    completionHandler()
                    return
                }
                if episodes.count == 1 {
                    PlayerManager.shared.playPodcast(podcast, episode: episodes[0])
                    completionHandler()
                    return
                }
                let listItems = episodes.map {
                    createListItem(text: $0.name, detailText: $0.formattedDuration, image: nil, imageUrl: $0.imageUrl, userInfo: $0)
                }
                let template = CPListTemplate(title: podcast.name, sections: [CPListSection(items: listItems)])
                interfaceController.pushTemplate(template, animated: true, completion: nil)
            } catch {
                print("[CarPlay] Failed to load podcast episodes: \(error)")
            }
            completionHandler()
        }
    }

    private func playEpisode(_ episode: PodcastEpisode, for podcast: Podcast?, completionHandler: @escaping () -> Void) {
        guard let podcast = podcast else {
            completionHandler()
            return
        }
        Task { @MainActor in
            PlayerManager.shared.playPodcast(podcast, episode: episode)
            completionHandler()
        }
    }

    private func playRadio(_ radio: Radio, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            PlayerManager.shared.playRadio(radio)
            completionHandler()
        }
    }

    private func playTrack(_ track: Track, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            PlayerManager.shared.playTrack(track, fromQueue: [track])
            completionHandler()
        }
    }
}

// MARK: - CPNowPlayingTemplateObserver

extension CarPlaySceneDelegate: CPNowPlayingTemplateObserver {
    func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        guard let interfaceController = interfaceController else { return }

        let queue = PlayerManager.shared.queue
        let currentIndex = PlayerManager.shared.currentIndex

        let listItems: [CPListItem]
        if queue.isEmpty {
            listItems = [CPListItem(text: "Nothing in queue", detailText: nil)]
        } else {
            listItems = queue.enumerated().map { (index, track) -> CPListItem in
                let prefix = index == currentIndex ? "▶ " : ""
                let item = CPListItem(text: "\(prefix)\(track.name)", detailText: track.artistNames)
                let capturedIndex = index
                item.handler = { _, completion in
                    Task { try? await XonoraClient.shared.playQueueIndex(capturedIndex) }
                    completion()
                }
                return item
            }
        }

        let template = CPListTemplate(title: "Up Next", sections: [CPListSection(items: listItems)])
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }
}
