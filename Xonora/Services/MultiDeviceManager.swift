import Foundation
import Combine

/// Tracks playback state for ALL players in the system, not just the currently selected one.
/// This enables viewing what's playing on multiple devices simultaneously.
@MainActor
class MultiDeviceManager: ObservableObject {
    /// Dictionary of player states, keyed by player ID
    @Published var playerStates: [String: PlayerState] = [:]

    /// Represents the current state of a single player
    struct PlayerState: Equatable {
        var currentTrack: Track?
        var playbackState: PlaybackState
        var currentTime: TimeInterval
        var duration: TimeInterval
        var volume: Int
        var queueId: String
        var lastUpdated: Date

        init(
            currentTrack: Track? = nil,
            playbackState: PlaybackState = .stopped,
            currentTime: TimeInterval = 0,
            duration: TimeInterval = 0,
            volume: Int = 50,
            queueId: String,
            lastUpdated: Date = Date()
        ) {
            self.currentTrack = currentTrack
            self.playbackState = playbackState
            self.currentTime = currentTime
            self.duration = duration
            self.volume = volume
            self.queueId = queueId
            self.lastUpdated = lastUpdated
        }
    }

    private var cancellables = Set<AnyCancellable>()

    static let shared = MultiDeviceManager()

    private init() {
        setupQueueSubscription()
        startStaleStateCleanup()
        startProgressTimer()
        print("[MultiDeviceManager] Initialized and ready to track all players")
    }

    // MARK: - Queue Event Subscription

    /// Subscribe to ALL queue_updated events from the server (unfiltered by current player)
    private func setupQueueSubscription() {
        NotificationCenter.default.publisher(for: .allQueuesUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self,
                      let userInfo = notification.userInfo as? [String: Any],
                      let queueId = userInfo["queue_id"] as? String else { return }

                self.updatePlayerState(queueId: queueId, from: userInfo)
            }
            .store(in: &cancellables)

        print("[MultiDeviceManager] Subscribed to all queue_updated events")
    }
    
    // MARK: - Local Progress Timer
    
    private func startProgressTimer() {
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateProgress()
            }
            .store(in: &cancellables)
    }
    
    private func updateProgress() {
        for (id, var state) in playerStates where state.playbackState == .playing {
            // Increment by 1 second
            state.currentTime += 1.0
            
            // Clamp to duration if known
            if state.duration > 0 {
                state.currentTime = min(state.currentTime, state.duration)
            }
            
            // Update state to trigger UI refresh
            playerStates[id] = state
        }
    }

    // MARK: - State Updates

    /// Update stored state for a specific player directly
    func updateState(for playerId: String, state: PlayerState) {
        playerStates[playerId] = state
    }

    /// Update stored state for a specific player based on queue event data
    func updatePlayerState(queueId: String, from data: [String: Any]) {
        // Get existing state or create new one
        var state = playerStates[queueId] ?? PlayerState(queueId: queueId)

        // Update elapsed time
        if let elapsed = data["elapsed_time"] as? Double {
            state.currentTime = elapsed
        }

        // Update playback state
        if let stateStr = data["state"] as? String {
            switch stateStr {
            case "playing":
                state.playbackState = .playing
            case "paused":
                state.playbackState = .paused
            case "idle":
                state.playbackState = .stopped
            default:
                state.playbackState = .stopped
            }
        }

        // Update current track and duration
        if let currentItem = data["current_item"] as? [String: Any] {
            // Update duration
            if let duration = currentItem["duration"] as? Int {
                state.duration = TimeInterval(duration)
            } else if let duration = currentItem["duration"] as? Double {
                state.duration = duration
            }

            // Update current track
            if let mediaItemDict = currentItem["media_item"] as? [String: Any] {
                do {
                    let data = try JSONSerialization.data(withJSONObject: mediaItemDict)
                    let track = try JSONDecoder().decode(Track.self, from: data)
                    state.currentTrack = track
                } catch {
                    print("[MultiDeviceManager] Failed to decode track for \(queueId): \(error)")
                }
            }
        }

        // Update timestamp
        state.lastUpdated = Date()

        // Store updated state
        playerStates[queueId] = state

        // Enforce max player count
        enforceMaxPlayerCount(excluding: queueId)
    }

    // MARK: - Player Count Management

    /// Enforce max player count by removing oldest entries
    private func enforceMaxPlayerCount(excluding currentQueueId: String) {
        let maxPlayers = UserPreferences.shared.maxTrackedPlayers

        // If we're at or below the limit, no action needed
        if playerStates.count <= maxPlayers {
            return
        }

        // Sort by lastUpdated (oldest first) and remove excess
        let sortedPlayers = playerStates.sorted { $0.value.lastUpdated < $1.value.lastUpdated }

        var toRemove: [String] = []
        for (queueId, _) in sortedPlayers {
            // Skip the current player being updated
            if queueId == currentQueueId {
                continue
            }

            toRemove.append(queueId)

            // Stop once we're back under the limit
            if playerStates.count - toRemove.count <= maxPlayers {
                break
            }
        }

        for queueId in toRemove {
            playerStates.removeValue(forKey: queueId)
        }

        if !toRemove.isEmpty {
            print("[MultiDeviceManager] Evicted \(toRemove.count) oldest player(s) to maintain max count of \(maxPlayers)")
        }
    }

    // MARK: - Stale State Cleanup

    /// Start periodic cleanup of old player states
    private func startStaleStateCleanup() {
        // Run cleanup every 60 seconds
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.cleanupStaleStates()
            }
            .store(in: &cancellables)
    }

    /// Remove player states that haven't been updated in 5 minutes
    private func cleanupStaleStates() {
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        let beforeCount = playerStates.count

        playerStates = playerStates.filter { _, state in
            state.lastUpdated > fiveMinutesAgo
        }

        let removedCount = beforeCount - playerStates.count
        if removedCount > 0 {
            print("[MultiDeviceManager] Cleaned up \(removedCount) stale player states")
        }
    }

    // MARK: - Public Helper Methods

    /// Get the current state for a specific player
    func state(for playerId: String) -> PlayerState? {
        return playerStates[playerId]
    }

    /// Get all players that are currently playing
    func activePlayers() -> [String: PlayerState] {
        return playerStates.filter { _, state in
            state.playbackState == .playing
        }
    }

    /// Check if a player has a recent state update (within last 5 minutes)
    func hasRecentState(for playerId: String) -> Bool {
        guard let state = playerStates[playerId] else { return false }
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        return state.lastUpdated > fiveMinutesAgo
    }

    /// Clear all stored player states (useful for testing/debugging)
    func clearAllStates() {
        playerStates.removeAll()
        print("[MultiDeviceManager] Cleared all player states")
    }
}
