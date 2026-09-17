import SwiftUI
import Combine

enum SearchFilter: String, CaseIterable {
    case all = "All"
    case songs = "Songs"
    case albums = "Albums"
    case artists = "Artists"
    case playlists = "Playlists"
    case audiobooks = "Audiobooks"
    case podcasts = "Podcasts"
    case radio = "Radio"
}

@MainActor
class GlobalNavigationViewModel: ObservableObject {
    @Published var showingSearch = false
    @Published var showingSettings = false
    @Published var initialSearchFilter: SearchFilter = .all

    // Persistent search state - survives sheet dismiss/reopen
    @Published var searchQuery = ""
    @Published var selectedSearchFilter: SearchFilter = .all

    // Selected items for overlay display (outside the search sheet)
    @Published var selectedAlbum: Album?
    @Published var selectedArtist: Artist?
    @Published var selectedPlaylist: Playlist?
    @Published var selectedAudiobook: Audiobook?
    @Published var selectedPodcast: Podcast?

    func openSearch(with filter: SearchFilter = .all) {
        initialSearchFilter = filter
        if searchQuery.isEmpty {
            selectedSearchFilter = filter
        }
        showingSearch = true
    }

    func navigateToAlbum(_ album: Album) {
        selectedAlbum = album
    }

    func navigateToArtist(_ artist: Artist) {
        selectedArtist = artist
    }

    func navigateToPlaylist(_ playlist: Playlist) {
        selectedPlaylist = playlist
    }

    func navigateToAudiobook(_ audiobook: Audiobook) {
        selectedAudiobook = audiobook
    }

    func navigateToPodcast(_ podcast: Podcast) {
        selectedPodcast = podcast
    }

    func closeDetailView() {
        selectedAlbum = nil
        selectedArtist = nil
        selectedPlaylist = nil
        selectedAudiobook = nil
        selectedPodcast = nil
    }
}
