//
//  WatchDataProvider.swift
//  XonoraWatch
//
//  Protocol abstraction for Watch data access.
//  Enables future hybrid mode (direct WiFi WebSocket) without changing Watch UI code.
//

import Foundation

/// Protocol that all Watch views depend on for data and commands
protocol WatchDataProvider: ObservableObject {
    /// Current now playing state for the active player
    var nowPlayingState: WatchNowPlayingState { get }

    /// Complete snapshot of all players in the system
    var playersSnapshot: WatchPlayersSnapshot { get }

    /// Library snapshot (albums, playlists, artists)
    var librarySnapshot: WatchLibrarySnapshot { get }

    /// Connection status
    var isConnected: Bool { get }

    /// Send a command to the server
    func sendCommand(_ command: WatchCommand, payload: [String: String]?) async

    /// Play media by URI
    func playMedia(uri: String) async

    /// Switch active player
    func switchPlayer(playerId: String) async

    /// Fetch tracks for an album
    func fetchAlbumTracks(albumId: String) async -> WatchAlbumTracksResponse?
}
