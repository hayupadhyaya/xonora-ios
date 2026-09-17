//
//  WatchModels.swift
//  Xonora
//
//  Shared models for WatchConnectivity communication between iPhone and Apple Watch.
//  These DTOs are lightweight and Codable for efficient serialization.
//

import Foundation

// MARK: - Track Info

/// Track representation for Watch (simplified from Track model)
struct WatchTrackInfo: Codable, Equatable, Hashable {
    let name: String
    let artistNames: String          // Pre-joined from artists array
    let albumName: String?
    let duration: TimeInterval?
    let imageURLString: String?      // Pre-resolved via XonoraClient.getImageURL
    let favorite: Bool
    let uri: String

    var formattedDuration: String {
        guard let duration = duration else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Player Info

/// Player with per-player state (merged from MAPlayer + MultiDeviceManager.PlayerState)
struct WatchPlayerInfo: Codable, Equatable, Identifiable, Hashable {
    let playerId: String
    let name: String
    let provider: String
    let available: Bool
    let playbackState: String        // "playing", "paused", "idle", "off"
    let volume: Int
    let currentTrack: WatchTrackInfo?
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isSelected: Bool             // Is this the active player?
    let groupChildIds: [String]
    let isGroupMember: Bool

    var id: String { playerId }

    var isPlaying: Bool {
        playbackState == "playing"
    }

    var isGroupLeader: Bool {
        !groupChildIds.isEmpty
    }
}

// MARK: - Players Snapshot

/// Complete snapshot of all players in the system
struct WatchPlayersSnapshot: Codable, Equatable, Hashable {
    let players: [WatchPlayerInfo]
    let activePlayerId: String?
    let timestamp: Date

    static var empty: WatchPlayersSnapshot {
        WatchPlayersSnapshot(players: [], activePlayerId: nil, timestamp: Date())
    }
}

// MARK: - Now Playing State

/// Now playing state for the active player
struct WatchNowPlayingState: Codable, Equatable, Hashable {
    let track: WatchTrackInfo?
    let playbackState: String        // "playing", "paused", "idle", "off"
    let currentTime: TimeInterval
    let duration: TimeInterval
    let shuffleEnabled: Bool
    let repeatMode: String           // "off", "all", "one"
    let volume: Float
    let isConnected: Bool
    let activePlayerId: String?
    let activePlayerName: String?

    static var empty: WatchNowPlayingState {
        WatchNowPlayingState(
            track: nil,
            playbackState: "idle",
            currentTime: 0,
            duration: 0,
            shuffleEnabled: false,
            repeatMode: "off",
            volume: 0.5,
            isConnected: false,
            activePlayerId: nil,
            activePlayerName: nil
        )
    }

    var isPlaying: Bool {
        playbackState == "playing"
    }
}

// MARK: - Library Items

struct WatchAlbumInfo: Codable, Equatable, Identifiable, Hashable {
    let itemId: String
    let provider: String
    let name: String
    let artistNames: String
    let year: Int?
    let imageURLString: String?
    let uri: String

    var id: String { itemId }

    var displayYear: String {
        if let year = year {
            return String(year)
        }
        return ""
    }
}

struct WatchPlaylistInfo: Codable, Equatable, Identifiable, Hashable {
    let itemId: String
    let name: String
    let imageURLString: String?
    let uri: String

    var id: String { itemId }
}

struct WatchArtistInfo: Codable, Equatable, Identifiable, Hashable {
    let itemId: String
    let name: String
    let imageURLString: String?

    var id: String { itemId }
}

// MARK: - Library Snapshot

/// Library snapshot (truncated for large libraries)
struct WatchLibrarySnapshot: Codable, Equatable, Hashable {
    let albums: [WatchAlbumInfo]
    let playlists: [WatchPlaylistInfo]
    let artists: [WatchArtistInfo]
    let timestamp: Date

    static var empty: WatchLibrarySnapshot {
        WatchLibrarySnapshot(albums: [], playlists: [], artists: [], timestamp: Date())
    }
}

// MARK: - Commands

/// Commands from Watch to iPhone
enum WatchCommand: String, Codable {
    case playPause
    case next
    case previous
    case seek
    case setVolume
    case toggleShuffle
    case cycleRepeat
    case playMedia
    case toggleFavorite
    case switchPlayer
}

/// Command message with optional payload
struct WatchCommandMessage: Codable {
    let command: WatchCommand
    let payload: [String: String]?   // Optional parameters (e.g., playerId, volume, uri)
}

// MARK: - Album Tracks Response

/// Response containing tracks for a specific album
struct WatchAlbumTracksResponse: Codable {
    let albumId: String
    let albumName: String
    let artistNames: String
    let tracks: [WatchTrackInfo]
}
