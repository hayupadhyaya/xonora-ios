//
//  WatchConnectivityProvider.swift
//  XonoraWatch
//
//  Watch-side WCSessionDelegate that receives state and sends commands.
//  Implements WatchDataProvider protocol for use by Watch views.
//

import Foundation
import Combine
import WatchConnectivity

@MainActor
class WatchConnectivityProvider: NSObject, WatchDataProvider, ObservableObject {
    @Published var nowPlayingState: WatchNowPlayingState = .empty
    @Published var playersSnapshot: WatchPlayersSnapshot = .empty
    @Published var librarySnapshot: WatchLibrarySnapshot = .empty
    @Published var isConnected: Bool = false

    private var session: WCSession?
    private var lastLogTime: Date = .distantPast
    private var lastLibraryCount: (albums: Int, playlists: Int, artists: Int) = (0, 0, 0)

    override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        guard WCSession.isSupported() else {
            print("[WatchConnectivityProvider] WatchConnectivity not supported")
            return
        }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
        print("[WatchConnectivityProvider] Activated")
    }

    // MARK: - WatchDataProvider Implementation

    func sendCommand(_ command: WatchCommand, payload: [String: String]?) async {
        guard let session = session, session.isReachable else {
            print("[WatchConnectivityProvider] iPhone not reachable")
            return
        }

        let commandMessage = WatchCommandMessage(command: command, payload: payload)

        do {
            let data = try JSONEncoder().encode(commandMessage)
            guard let messageDict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            session.sendMessage(messageDict, replyHandler: { [weak self] reply in
                Task { @MainActor in
                    // Update state from reply
                    if let data = try? JSONSerialization.data(withJSONObject: reply),
                       let updatedState = try? JSONDecoder().decode(WatchNowPlayingState.self, from: data) {
                        self?.nowPlayingState = updatedState
                    }
                }
            }, errorHandler: { error in
                print("[WatchConnectivityProvider] Command failed: \(error.localizedDescription)")
            })
        } catch {
            print("[WatchConnectivityProvider] Failed to encode command: \(error.localizedDescription)")
        }
    }

    func playMedia(uri: String) async {
        await sendCommand(.playMedia, payload: ["uri": uri])
    }

    func switchPlayer(playerId: String) async {
        await sendCommand(.switchPlayer, payload: ["playerId": playerId])
    }

    func fetchAlbumTracks(albumId: String) async -> WatchAlbumTracksResponse? {
        guard let session = session, session.isReachable else {
            print("[WatchConnectivityProvider] ERROR: iPhone not reachable for track fetch")
            return nil
        }

        print("[WatchConnectivityProvider] Requesting tracks for album: \(albumId)")

        return await withCheckedContinuation { continuation in
            let message: [String: Any] = ["fetchAlbumTracks": albumId]

            // Thread-safe resume guard (all closures dispatch to main)
            let resumed = ResumeGuard()

            // Set up one-time listener that matches this specific albumId
            var observer: NSObjectProtocol?
            observer = NotificationCenter.default.addObserver(
                forName: .albumTracksReceived,
                object: nil,
                queue: .main
            ) { notification in
                guard let response = notification.object as? WatchAlbumTracksResponse else {
                    return
                }

                // Only accept responses for OUR albumId (fixes race with concurrent fetches)
                guard response.albumId == albumId else { return }
                guard resumed.tryResume() else { return }

                if let obs = observer {
                    NotificationCenter.default.removeObserver(obs)
                }

                print("[WatchConnectivityProvider] Received \(response.tracks.count) tracks for album: \(response.albumName)")
                continuation.resume(returning: response)
            }

            session.sendMessage(message, replyHandler: nil, errorHandler: { error in
                // Dispatch to main to avoid data races with the observer/timeout
                DispatchQueue.main.async {
                    guard resumed.tryResume() else { return }

                    print("[WatchConnectivityProvider] ERROR: Failed to request album tracks: \(error.localizedDescription)")
                    if let obs = observer {
                        NotificationCenter.default.removeObserver(obs)
                    }
                    continuation.resume(returning: nil)
                }
            })

            // Timeout after 30 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                guard resumed.tryResume() else { return }

                print("[WatchConnectivityProvider] TIMEOUT: Track fetch for album: \(albumId)")
                if let obs = observer {
                    NotificationCenter.default.removeObserver(obs)
                }
                continuation.resume(returning: nil)
            }
        }
    }
}

// MARK: - Resume Guard (thread-safe single-resume)

/// Ensures a continuation is resumed exactly once, even if multiple
/// closures (observer, error handler, timeout) race to complete.
private final class ResumeGuard: @unchecked Sendable {
    private var _hasResumed = false
    private let lock = NSLock()

    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !_hasResumed else { return false }
        _hasResumed = true
        return true
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let albumTracksReceived = Notification.Name("albumTracksReceived")
}

// MARK: - WCSessionDelegate

extension WatchConnectivityProvider: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("[WatchConnectivityProvider] Activation failed: \(error.localizedDescription)")
        } else {
            print("[WatchConnectivityProvider] Activation completed with state: \(activationState.rawValue)")
        }

        Task { @MainActor in
            self.isConnected = session.isReachable
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            let wasConnected = self.isConnected
            self.isConnected = session.isReachable

            // Only log when state actually changes
            if wasConnected != session.isReachable {
                print("[WatchConnectivityProvider] Reachability changed: \(session.isReachable)")
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        Task { @MainActor in
            // Only log every 10 seconds to reduce spam
            let shouldLog = Date().timeIntervalSince(self.lastLogTime) > 10

            // Decode now playing state
            if let data = applicationContext["nowPlaying"] as? Data {
                if let state = try? JSONDecoder().decode(WatchNowPlayingState.self, from: data) {
                    self.nowPlayingState = state
                }
            }

            // Decode players snapshot
            if let data = applicationContext["players"] as? Data {
                if let snapshot = try? JSONDecoder().decode(WatchPlayersSnapshot.self, from: data) {
                    self.playersSnapshot = snapshot
                }
            }

            // Decode library snapshot
            if let data = applicationContext["library"] as? Data {
                if let snapshot = try? JSONDecoder().decode(WatchLibrarySnapshot.self, from: data) {
                    let counts = (snapshot.albums.count, snapshot.playlists.count, snapshot.artists.count)

                    // Only log when counts actually change
                    if counts != self.lastLibraryCount {
                        print("[WatchConnectivityProvider] Library: \(snapshot.albums.count) albums, \(snapshot.playlists.count) playlists, \(snapshot.artists.count) artists")
                        self.lastLibraryCount = counts
                        self.lastLogTime = Date()
                    }

                    self.librarySnapshot = snapshot
                }
            }
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        Task { @MainActor in
            print("[WatchConnectivityProvider] Received message with keys: \(message.keys.joined(separator: ", "))")

            // Handle album tracks response
            if let albumTracksDict = message["albumTracks"] as? [String: Any] {
                print("[WatchConnectivityProvider] Found albumTracks dict with keys: \(albumTracksDict.keys.joined(separator: ", "))")

                if let tracksArray = albumTracksDict["tracks"] as? [[String: Any]] {
                    print("[WatchConnectivityProvider] Dict has \(tracksArray.count) tracks before decoding")
                } else {
                    print("[WatchConnectivityProvider] WARNING: No tracks array in dict or wrong type")
                }

                if let data = try? JSONSerialization.data(withJSONObject: albumTracksDict) {
                    print("[WatchConnectivityProvider] Serialized data: \(data.count) bytes")

                    if let response = try? JSONDecoder().decode(WatchAlbumTracksResponse.self, from: data) {
                        print("[WatchConnectivityProvider] Successfully decoded response with \(response.tracks.count) tracks")
                        // Post notification for awaiting fetch
                        NotificationCenter.default.post(name: .albumTracksReceived, object: response)
                    } else {
                        print("[WatchConnectivityProvider] ERROR: Failed to decode WatchAlbumTracksResponse")

                        // Try to see what went wrong
                        let decoder = JSONDecoder()
                        do {
                            _ = try decoder.decode(WatchAlbumTracksResponse.self, from: data)
                        } catch {
                            print("[WatchConnectivityProvider] Decode error: \(error)")
                        }
                    }
                } else {
                    print("[WatchConnectivityProvider] ERROR: Failed to serialize dict to data")
                }
            } else {
                print("[WatchConnectivityProvider] ERROR: No albumTracks in message")
            }
        }
    }
}
