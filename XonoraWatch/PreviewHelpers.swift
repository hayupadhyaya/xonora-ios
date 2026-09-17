//
//  PreviewHelpers.swift
//  XonoraWatch
//
//  Preview mock data for Xcode canvas previews.
//

#if DEBUG
import Foundation

@MainActor
extension WatchConnectivityProvider {

    // MARK: - Now Playing Previews

    static var previewPlaying: WatchConnectivityProvider {
        let p = WatchConnectivityProvider()
        p.isConnected = true
        p.nowPlayingState = WatchNowPlayingState(
            track: WatchTrackInfo(
                name: "What It Sounds Like",
                artistNames: "HUNTR/X, EJAE, AUDREY NUNA",
                albumName: "What It Sounds Like - Single",
                duration: 217,
                imageURLString: nil,
                favorite: false,
                uri: "library://track/1"
            ),
            playbackState: "playing",
            currentTime: 45,
            duration: 217,
            shuffleEnabled: false,
            repeatMode: "off",
            volume: 0.5,
            isConnected: true,
            activePlayerId: "player1",
            activePlayerName: "iPhone"
        )
        p.playersSnapshot = WatchPlayersSnapshot(
            players: [previewPlayer1, previewPlayer2],
            activePlayerId: "player1",
            timestamp: Date()
        )
        p.librarySnapshot = previewLibrary
        return p
    }

    static var previewPaused: WatchConnectivityProvider {
        let p = WatchConnectivityProvider()
        p.isConnected = true
        p.nowPlayingState = WatchNowPlayingState(
            track: WatchTrackInfo(
                name: "Blinding Lights",
                artistNames: "The Weeknd",
                albumName: "After Hours",
                duration: 200,
                imageURLString: nil,
                favorite: true,
                uri: "library://track/2"
            ),
            playbackState: "paused",
            currentTime: 120,
            duration: 200,
            shuffleEnabled: true,
            repeatMode: "all",
            volume: 0.7,
            isConnected: true,
            activePlayerId: "player1",
            activePlayerName: "Living Room"
        )
        p.playersSnapshot = WatchPlayersSnapshot(
            players: [previewPlayer1, previewPlayer2],
            activePlayerId: "player1",
            timestamp: Date()
        )
        p.librarySnapshot = previewLibrary
        return p
    }

    static var previewEmpty: WatchConnectivityProvider {
        WatchConnectivityProvider()
    }

    // MARK: - Sample Data

    private static var previewPlayer1: WatchPlayerInfo {
        WatchPlayerInfo(
            playerId: "player1",
            name: "iPhone",
            provider: "sendspin",
            available: true,
            playbackState: "playing",
            volume: 50,
            currentTrack: WatchTrackInfo(
                name: "What It Sounds Like",
                artistNames: "HUNTR/X",
                albumName: nil,
                duration: 217,
                imageURLString: nil,
                favorite: false,
                uri: "library://track/1"
            ),
            currentTime: 45,
            duration: 217,
            isSelected: true,
            groupChildIds: [],
            isGroupMember: false
        )
    }

    private static var previewPlayer2: WatchPlayerInfo {
        WatchPlayerInfo(
            playerId: "player2",
            name: "Living Room",
            provider: "sonos",
            available: true,
            playbackState: "idle",
            volume: 30,
            currentTrack: nil,
            currentTime: 0,
            duration: 0,
            isSelected: false,
            groupChildIds: [],
            isGroupMember: false
        )
    }

    private static var previewLibrary: WatchLibrarySnapshot {
        WatchLibrarySnapshot(
            albums: [
                WatchAlbumInfo(itemId: "a1", provider: "spotify", name: "After Hours", artistNames: "The Weeknd", year: 2020, imageURLString: nil, uri: "library://album/1"),
                WatchAlbumInfo(itemId: "a2", provider: "spotify", name: "DAMN.", artistNames: "Kendrick Lamar", year: 2017, imageURLString: nil, uri: "library://album/2"),
                WatchAlbumInfo(itemId: "a3", provider: "spotify", name: "Future Nostalgia", artistNames: "Dua Lipa", year: 2020, imageURLString: nil, uri: "library://album/3"),
            ],
            playlists: [
                WatchPlaylistInfo(itemId: "p1", name: "Chill Vibes", imageURLString: nil, uri: "library://playlist/1"),
                WatchPlaylistInfo(itemId: "p2", name: "Workout Mix", imageURLString: nil, uri: "library://playlist/2"),
            ],
            artists: [
                WatchArtistInfo(itemId: "ar1", name: "The Weeknd", imageURLString: nil),
                WatchArtistInfo(itemId: "ar2", name: "Kendrick Lamar", imageURLString: nil),
                WatchArtistInfo(itemId: "ar3", name: "Dua Lipa", imageURLString: nil),
            ],
            timestamp: Date()
        )
    }
}
#endif
