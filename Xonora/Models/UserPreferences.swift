import Foundation
import SwiftUI
import Combine

/// Centralized user preferences using @AppStorage for persistence
@MainActor
class UserPreferences: ObservableObject {
    static let shared = UserPreferences()
    
    // MARK: - Home Tab Customization
    
    /// Order of sections in Home tab (by identifier)
    @AppStorage("homeTabSectionOrder") private var homeTabSectionOrderData: Data = Data()
    
    /// Which sections are enabled in Home tab
    @AppStorage("homeTabSectionsEnabled") private var homeTabSectionsEnabledData: Data = Data()
    
    // MARK: - Library Tab Customization
    
    /// Order of sections in Library tab (by identifier)
    @AppStorage("libraryTabSectionOrder") private var libraryTabSectionOrderData: Data = Data()
    
    /// Which sections are enabled in Library tab
    @AppStorage("libraryTabSectionsEnabled") private var libraryTabSectionsEnabledData: Data = Data()
    
    // MARK: - Tab Bar Customization
    
    /// Order of tabs (by tag index)
    @AppStorage("tabBarOrder") private var tabBarOrderData: Data = Data()
    
    /// Which tabs are enabled
    @AppStorage("tabsEnabled") private var tabsEnabledData: Data = Data()
    
    /// Tabs the user wants shown even when no content is available
    @AppStorage("tabForceEnabled") private var tabForceEnabledData: Data = Data()

    // MARK: - Appearance

    @AppStorage("colorScheme") var colorSchemePreference: String = "auto" // "auto", "light", "dark"
    @AppStorage("accentColorHex") var accentColorHex: String = ""
    @AppStorage("appLanguage") var appLanguage: String = "system"
    
    // MARK: - Playback

    @AppStorage("defaultPlaybackSpeed") var defaultPlaybackSpeed: Double = 1.0
    @AppStorage("crossfadeEnabled") var crossfadeEnabled: Bool = false
    @AppStorage("crossfadeDuration") var crossfadeDuration: Double = 5.0

    // MARK: - Lyrics

    /// User-adjustable lyrics timing offset in seconds (-2.0 to +2.0)
    /// Positive values delay lyrics (if lyrics appear too early)
    /// Negative values advance lyrics (if lyrics appear too late)
    @AppStorage("lyricsOffset") var lyricsOffset: Double = 0.0

    // MARK: - Multi-Device

    @AppStorage("maxTrackedPlayers") var maxTrackedPlayers: Int = 5
    @AppStorage("playerSortOrder") var playerSortOrder: String = "name_asc"

    // MARK: - Library Sort

    @AppStorage("sort_albums") var sortAlbums: String = SortOption.nameAsc.rawValue
    @AppStorage("sort_playlists") var sortPlaylists: String = SortOption.nameAsc.rawValue
    @AppStorage("sort_tracks") var sortTracks: String = SortOption.nameAsc.rawValue
    @AppStorage("sort_artists") var sortArtists: String = SortOption.nameAsc.rawValue
    @AppStorage("sort_audiobooks") var sortAudiobooks: String = SortOption.nameAsc.rawValue
    @AppStorage("sort_podcasts") var sortPodcasts: String = SortOption.nameAsc.rawValue
    @AppStorage("sort_radios") var sortRadios: String = SortOption.nameAsc.rawValue

    // MARK: - Library View Mode

    @AppStorage("viewMode_albums") var viewModeAlbums: String = ViewMode.grid.rawValue
    @AppStorage("viewMode_playlists") var viewModePlaylists: String = ViewMode.grid.rawValue
    @AppStorage("viewMode_audiobooks") var viewModeAudiobooks: String = ViewMode.grid.rawValue
    @AppStorage("viewMode_podcasts") var viewModePodcasts: String = ViewMode.grid.rawValue
    @AppStorage("viewMode_radios") var viewModeRadios: String = ViewMode.grid.rawValue

    // MARK: - Grid Column Count (0 = device default), portrait and landscape stored separately

    @AppStorage("gridColumns_albums_p") var gridColumnsAlbumsPortrait: Int = 0
    @AppStorage("gridColumns_albums_l") var gridColumnsAlbumsLandscape: Int = 0
    @AppStorage("gridColumns_playlists_p") var gridColumnsPlaylistsPortrait: Int = 0
    @AppStorage("gridColumns_playlists_l") var gridColumnsPlaylistsLandscape: Int = 0
    @AppStorage("gridColumns_audiobooks_p") var gridColumnsAudiobooksPortrait: Int = 0
    @AppStorage("gridColumns_audiobooks_l") var gridColumnsAudiobooksLandscape: Int = 0
    @AppStorage("gridColumns_podcasts_p") var gridColumnsPodcastsPortrait: Int = 0
    @AppStorage("gridColumns_podcasts_l") var gridColumnsPodcastsLandscape: Int = 0
    @AppStorage("gridColumns_radios_p") var gridColumnsRadiosPortrait: Int = 0
    @AppStorage("gridColumns_radios_l") var gridColumnsRadiosLandscape: Int = 0

    // MARK: - Grid Column Helpers

    func gridColumnCount(for category: String, landscape: Bool) -> Int {
        if landscape {
            switch category {
            case "albums": return gridColumnsAlbumsLandscape
            case "playlists": return gridColumnsPlaylistsLandscape
            case "audiobooks": return gridColumnsAudiobooksLandscape
            case "podcasts": return gridColumnsPodcastsLandscape
            case "radios": return gridColumnsRadiosLandscape
            default: return 0
            }
        } else {
            switch category {
            case "albums": return gridColumnsAlbumsPortrait
            case "playlists": return gridColumnsPlaylistsPortrait
            case "audiobooks": return gridColumnsAudiobooksPortrait
            case "podcasts": return gridColumnsPodcastsPortrait
            case "radios": return gridColumnsRadiosPortrait
            default: return 0
            }
        }
    }

    func setGridColumnCount(_ count: Int, for category: String, landscape: Bool) {
        objectWillChange.send()
        if landscape {
            switch category {
            case "albums": gridColumnsAlbumsLandscape = count
            case "playlists": gridColumnsPlaylistsLandscape = count
            case "audiobooks": gridColumnsAudiobooksLandscape = count
            case "podcasts": gridColumnsPodcastsLandscape = count
            case "radios": gridColumnsRadiosLandscape = count
            default: break
            }
        } else {
            switch category {
            case "albums": gridColumnsAlbumsPortrait = count
            case "playlists": gridColumnsPlaylistsPortrait = count
            case "audiobooks": gridColumnsAudiobooksPortrait = count
            case "podcasts": gridColumnsPodcastsPortrait = count
            case "radios": gridColumnsRadiosPortrait = count
            default: break
            }
        }
    }
    
    // MARK: - Computed Properties
    
    /// Available Home sections with their identifiers (Static only)
    static let allHomeSections: [HomeSection] = [
        HomeSection(id: "recentlyPlayed", name: "Recently Played", icon: "clock.fill", isRequired: false),
        HomeSection(id: "favorites", name: "Favorites", icon: "heart.fill", isRequired: false),
        HomeSection(id: "continueListening", name: "Continue Listening", icon: "book.fill", isRequired: false)
    ]
    
    /// Available Library sections with their identifiers (Static only)
    static let allLibrarySections: [LibrarySection] = [
        LibrarySection(id: "Tracks", name: "Tracks", icon: "music.note", isRequired: false),
        LibrarySection(id: "Albums", name: "Albums", icon: "rectangle.stack.fill", isRequired: false),
        LibrarySection(id: "Artists", name: "Artists", icon: "person.2.fill", isRequired: false),
        LibrarySection(id: "Audiobooks", name: "Audiobooks", icon: "book.fill", isRequired: false),
        LibrarySection(id: "Podcasts", name: "Podcasts", icon: "mic.fill", isRequired: false),
        LibrarySection(id: "Radio", name: "Radio", icon: "antenna.radiowaves.left.and.right", isRequired: false)
    ]
    
    /// Available tabs with their identifiers
    static let allTabs: [TabItem] = [
        TabItem(tag: 0, name: "Music", icon: "music.note"),
        TabItem(tag: 1, name: "Podcasts", icon: "mic.fill"),
        TabItem(tag: 2, name: "Home", icon: "house.fill", isRequired: true),
        TabItem(tag: 3, name: "Audiobooks", icon: "book.fill"),
        TabItem(tag: 4, name: "Radio", icon: "antenna.radiowaves.left.and.right")
    ]
    
    // MARK: - Home Sections
    
    var homeSectionOrder: [String] {
        get {
            guard let decoded = try? JSONDecoder().decode([String].self, from: homeTabSectionOrderData),
                  !decoded.isEmpty else {
                return Self.allHomeSections.map { $0.id }
            }
            return decoded
        }
        set {
            // Deduplicate while preserving order
            var seen = Set<String>()
            let uniqueOrder = newValue.filter { seen.insert($0).inserted }
            
            if let encoded = try? JSONEncoder().encode(uniqueOrder) {
                homeTabSectionOrderData = encoded
                objectWillChange.send()
            }
        }
    }
    
    var homeSectionsEnabled: [String: Bool] {
        get {
            guard let decoded = try? JSONDecoder().decode([String: Bool].self, from: homeTabSectionsEnabledData),
                  !decoded.isEmpty else {
                // Default: all enabled
                var defaults: [String: Bool] = [:]
                for section in Self.allHomeSections {
                    defaults[section.id] = true
                }
                return defaults
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                homeTabSectionsEnabledData = encoded
                objectWillChange.send()
            }
        }
    }
    
    func isSectionEnabled(_ id: String) -> Bool {
        return homeSectionsEnabled[id] ?? true
    }
    
    func setSectionEnabled(_ id: String, enabled: Bool) {
        var current = homeSectionsEnabled
        current[id] = enabled
        homeSectionsEnabled = current
    }
    
    // MARK: - Library Sections
    
    var librarySectionOrder: [String] {
        get {
            guard let decoded = try? JSONDecoder().decode([String].self, from: libraryTabSectionOrderData),
                  !decoded.isEmpty else {
                return Self.allLibrarySections.map { $0.id }
            }
            return decoded
        }
        set {
            // Deduplicate while preserving order
            var seen = Set<String>()
            let uniqueOrder = newValue.filter { seen.insert($0).inserted }
            
            if let encoded = try? JSONEncoder().encode(uniqueOrder) {
                libraryTabSectionOrderData = encoded
                objectWillChange.send()
            }
        }
    }
    
    var librarySectionsEnabled: [String: Bool] {
        get {
            guard let decoded = try? JSONDecoder().decode([String: Bool].self, from: libraryTabSectionsEnabledData),
                  !decoded.isEmpty else {
                // Default: all enabled
                var defaults: [String: Bool] = [:]
                for section in Self.allLibrarySections {
                    defaults[section.id] = true
                }
                return defaults
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                libraryTabSectionsEnabledData = encoded
                objectWillChange.send()
            }
        }
    }
    
    func isLibrarySectionEnabled(_ id: String) -> Bool {
        return librarySectionsEnabled[id] ?? true
    }
    
    func setLibrarySectionEnabled(_ id: String, enabled: Bool) {
        var current = librarySectionsEnabled
        current[id] = enabled
        librarySectionsEnabled = current
    }
    
    // MARK: - Tab Bar
    
    var tabBarOrder: [Int] {
        get {
            guard let decoded = try? JSONDecoder().decode([Int].self, from: tabBarOrderData),
                  !decoded.isEmpty else {
                return Self.allTabs.map { $0.tag }
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                tabBarOrderData = encoded
                objectWillChange.send()
            }
        }
    }
    
    var tabsEnabled: [Int: Bool] {
        get {
            guard let decoded = try? JSONDecoder().decode([Int: Bool].self, from: tabsEnabledData),
                  !decoded.isEmpty else {
                // Default: all enabled
                var defaults: [Int: Bool] = [:]
                for tab in Self.allTabs {
                    defaults[tab.tag] = true
                }
                return defaults
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                tabsEnabledData = encoded
                objectWillChange.send()
            }
        }
    }
    
    func isTabEnabled(_ tag: Int) -> Bool {
        return tabsEnabled[tag] ?? true
    }
    
    func setTabEnabled(_ tag: Int, enabled: Bool) {
        // Ensure at least 2 tabs remain enabled
        let currentlyEnabled = tabsEnabled.filter { $0.value }.count
        if !enabled && currentlyEnabled <= 2 {
            return // Don't allow disabling if only 2 tabs left
        }
        
        // Home tab (tag 2) is always required
        if tag == 2 && !enabled {
            return
        }
        
        var current = tabsEnabled
        current[tag] = enabled
        tabsEnabled = current
    }
    
    // MARK: - Tab Force Enable (show even when empty)

    var tabForceEnabled: [Int: Bool] {
        get {
            guard let decoded = try? JSONDecoder().decode([Int: Bool].self, from: tabForceEnabledData),
                  !decoded.isEmpty else {
                return [:]
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                tabForceEnabledData = encoded
                objectWillChange.send()
            }
        }
    }

    func isTabForceEnabled(_ tag: Int) -> Bool {
        return tabForceEnabled[tag] ?? false
    }

    func setTabForceEnabled(_ tag: Int, enabled: Bool) {
        var current = tabForceEnabled
        current[tag] = enabled
        tabForceEnabled = current
    }

    // MARK: - Appearance Helpers
    
    var preferredColorScheme: ColorScheme? {
        switch colorSchemePreference {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
    
    var accentColor: Color? {
        guard !accentColorHex.isEmpty else { return nil }
        return Color(hex: accentColorHex)
    }
    
    // MARK: - Reset
    
    func resetToDefaults() {
        homeTabSectionOrderData = Data()
        homeTabSectionsEnabledData = Data()
        libraryTabSectionOrderData = Data()
        libraryTabSectionsEnabledData = Data()
        tabBarOrderData = Data()
        tabsEnabledData = Data()
        tabForceEnabledData = Data()
        colorSchemePreference = "auto"
        accentColorHex = ""
        appLanguage = "system"
        defaultPlaybackSpeed = 1.0
        crossfadeEnabled = false
        crossfadeDuration = 5.0
        lyricsOffset = 0.0
        maxTrackedPlayers = 5
        playerSortOrder = "activefirst"
        sortAlbums = SortOption.nameAsc.rawValue
        sortPlaylists = SortOption.nameAsc.rawValue
        sortTracks = SortOption.nameAsc.rawValue
        sortArtists = SortOption.nameAsc.rawValue
        sortAudiobooks = SortOption.nameAsc.rawValue
        sortPodcasts = SortOption.nameAsc.rawValue
        sortRadios = SortOption.nameAsc.rawValue
        viewModeAlbums = ViewMode.grid.rawValue
        viewModePlaylists = ViewMode.grid.rawValue
        viewModeAudiobooks = ViewMode.grid.rawValue
        viewModePodcasts = ViewMode.grid.rawValue
        viewModeRadios = ViewMode.grid.rawValue
        gridColumnsAlbumsPortrait = 0; gridColumnsAlbumsLandscape = 0
        gridColumnsPlaylistsPortrait = 0; gridColumnsPlaylistsLandscape = 0
        gridColumnsAudiobooksPortrait = 0; gridColumnsAudiobooksLandscape = 0
        gridColumnsPodcastsPortrait = 0; gridColumnsPodcastsLandscape = 0
        gridColumnsRadiosPortrait = 0; gridColumnsRadiosLandscape = 0
        objectWillChange.send()
    }
}

// MARK: - Sort & View Mode Enums

enum PlayerSortOrder: String, CaseIterable {
    case nameAsc = "name_asc"
    case nameDesc = "name_desc"

    var label: String {
        switch self {
        case .nameAsc: return "Name (A-Z)"
        case .nameDesc: return "Name (Z-A)"
        }
    }

    var icon: String {
        switch self {
        case .nameAsc: return "arrow.down.circle"
        case .nameDesc: return "arrow.up.circle"
        }
    }
}

enum SortOption: String, CaseIterable {
    case nameAsc = "name_asc"
    case nameDesc = "name_desc"
    case dateAddedNewest = "date_added_desc"
    case dateAddedOldest = "date_added_asc"

    var label: String {
        switch self {
        case .nameAsc: return "Name (A-Z)"
        case .nameDesc: return "Name (Z-A)"
        case .dateAddedNewest: return "Date Added (Newest)"
        case .dateAddedOldest: return "Date Added (Oldest)"
        }
    }
}

enum ViewMode: String {
    case grid = "grid"
    case list = "list"
}

// MARK: - Supporting Types

struct HomeSection: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let isRequired: Bool
}

struct LibrarySection: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let isRequired: Bool
}

struct TabItem: Identifiable, Equatable {
    var id: Int { tag }
    let tag: Int
    let name: String
    let icon: String
    var isRequired: Bool = false
}

// MARK: - Color Extension for Hex

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
    
    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return nil
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
