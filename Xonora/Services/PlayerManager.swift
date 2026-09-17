import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UserNotifications
import UIKit
import CallKit

// Notification names for PlayerManager events
extension Notification.Name {
    static let reconnectRequired = Notification.Name("reconnectRequired")
}

enum PlaybackState: Equatable {
    case stopped
    case playing
    case paused
    case loading
    case error(String)
}

enum RepeatMode: Int {
    case off = 0
    case all = 1
    case one = 2
}

@MainActor
class PlayerManager: NSObject, ObservableObject {
    @Published var playbackState: PlaybackState = .stopped
    @Published var currentTrack: Track?
    @Published var currentTime: TimeInterval = 0 {
        didSet {
            lastUpdateTime = Date()
        }
    }
    @Published var duration: TimeInterval = 0
    @Published var lastUpdateTime: Date = Date()
    @Published var queue: [Track] = []
    @Published var currentIndex: Int = 0
    @Published var shuffleEnabled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Float = 1.0
    @Published var playbackRate: Float = 1.0
    @Published var isCurrentTrackFavorited: Bool = false
    @Published var currentSource: String?
    @Published var isTransferringPlayback: Bool = false

    /// Whether the currently selected player is the local Sendspin audio engine
    var isCurrentPlayerLocal: Bool {
        guard let currentId = XonoraClient.shared.currentPlayer?.playerId,
              let localId = SendspinClient.shared.clientId else { return false }
        return currentId == localId
    }
    @Published var audioSyncedTime: TimeInterval = 0
    private var streamStartServerElapsed: TimeInterval = 0

    // Monotonic wall-clock reference for fallback interpolation (when engine time unavailable)
    private var fallbackWallClockRef: TimeInterval = 0
    private var fallbackTimeRef: TimeInterval = 0

    // Song position when loading began -- used for correct calibration after buffering.
    // Server elapsed_time advances during buffering but engine time 0 corresponds
    // to this position, not to the live elapsed value.
    private var loadingStartElapsed: TimeInterval = 0

    // Sleep Timer properties
    @Published var sleepTimerEndTime: Date? {
        didSet {
            if let endTime = sleepTimerEndTime {
                UserDefaults.standard.set(endTime.timeIntervalSince1970, forKey: "sleepTimerEndTime")
            } else {
                UserDefaults.standard.removeObject(forKey: "sleepTimerEndTime")
            }
        }
    }
    @Published var sleepTimerRemaining: TimeInterval = 0
    private var sleepTimerUpdateTimer: Timer?

    // Audiobook-specific properties
    @Published var currentAudiobook: Audiobook?
    @Published var currentChapter: Chapter?
    
    // Podcast-specific properties
    @Published var currentPodcast: Podcast?

    // Computed properties for chapter-aware playback
    var displayDuration: TimeInterval {
        if let chapter = currentChapter {
            return chapter.duration
        }
        return duration
    }

    var displayCurrentTime: TimeInterval {
        if let chapter = currentChapter {
            // Return time relative to chapter start
            return max(0, min(currentTime - chapter.start, chapter.duration))
        }
        return currentTime
    }

    /// Live lyrics time — reads hardware engine time on-demand for sub-frame accuracy.
    /// Use this from TimelineView instead of audioSyncedTime for drift-free lyrics.
    var lyricsTime: TimeInterval {
        guard playbackState == .playing else { return currentTime }
        let engineTime = SendspinClient.shared.getPlaybackTimeSync()
        if engineTime > 0 {
            return streamStartServerElapsed + engineTime
        }
        // Fallback: monotonic wall-clock interpolation
        if fallbackWallClockRef > 0 {
            let wallDelta = (ProcessInfo.processInfo.systemUptime - fallbackWallClockRef) * Double(playbackRate)
            return fallbackTimeRef + wallDelta
        }
        return currentTime
    }

    var isPlayingAudiobook: Bool {
        currentAudiobook != nil
    }
    
    var isPlayingPodcast: Bool {
        currentPodcast != nil
    }

    var isPlayingRadio: Bool {
        // Radio is identified by currentSource being "Radio" or track provider being "radio"
        return currentSource == "Radio" || currentTrack?.provider.lowercased().contains("radio") == true
    }

    var isSleepTimerActive: Bool {
        sleepTimerEndTime != nil
    }

    var sleepTimerRemainingFormatted: String {
        guard sleepTimerRemaining > 0 else { return "" }
        let minutes = Int(sleepTimerRemaining) / 60
        let seconds = Int(sleepTimerRemaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var progressTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastTrackId: String?
    private var cachedArtwork: MPMediaItemArtwork?
    
    // Deduplicate track changes to prevent restart loops
    private var lastProcessedTrackURI: String?

    // Prevent queue advancement race conditions
    private var lastLocalCommandTime: Date?
    private var lastLocalCommand: String?  // "play", "pause", "next", "previous"
    private var userPlayDebounceTask: Task<Void, Never>?

    // Track when loading started
    private var loadingStartTime: Date?

    // Loading timeout management
    private let loadingStateTimeout: TimeInterval = 10.0 // Force transition after 10s
    private var loadingTimeoutTask: Task<Void, Never>?

    // Playback position persistence
    private let savedTrackURIKey = "SavedTrackURI"
    private let savedPositionKey = "SavedPlaybackPosition"
    private let savedQueueKey = "SavedQueue"
    private let savedSourceKey = "SavedSource"

    // NOTE: We NO LONGER use fixed latency compensation
    // Server elapsed_time is used directly for progress bar (shows what's been sent)
    // Users can adjust lyrics timing independently via Settings → Lyrics Offset

    static let shared = PlayerManager()

    override init() {
        super.init()
        // Configure audio session for playback with AirPlay support
        setupAudioSession()

        // Setup remote commands and notifications asynchronously to avoid blocking init
        Task {
            setupRemoteCommandCenter()
            setupNotifications()
        }

        SendspinClient.shared.$isBuffering
            .removeDuplicates()  // Only fire when value actually changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isBuffering in
                guard let self = self else { return }
                // Only transition when isBuffering goes from true -> false
                // This requires streamStarted to set isBuffering=true first
                if !isBuffering && self.playbackState == .loading {
                    self.playbackState = .playing
                    self.startProgressTimer()
                    print("[PlayerManager] Playback started, progress timer enabled")
                }
            }
            .store(in: &cancellables)

        // Sync volume from server when current player data changes
        XonoraClient.shared.$currentPlayer
            .compactMap { $0?.volume }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] serverVolume in
                self?.volume = Float(serverVolume) / 100.0
            }
            .store(in: &cancellables)

        // Restore sleep timer from UserDefaults
        restoreSleepTimer()

        // Add lifecycle observers for sleep timer
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkSleepTimerOnForeground()
                // Catch any server-side queue changes made while app was suspended
                guard let self = self else { return }
                if case .connected = XonoraClient.shared.connectionState,
                   let player = XonoraClient.shared.currentPlayer {
                    await self.fetchQueueFromServer(for: player)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleSleepTimerNotification()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            try audioSession.setCategory(
                .playback,
                mode: .default,
                policy: .longFormAudio,  // Critical for background playback
                options: [.allowAirPlay, .allowBluetooth, .allowBluetoothA2DP]
            )
            
            try audioSession.setActive(true)
            
            print("[PlayerManager] Audio session configured")
        } catch {
            print("[PlayerManager] Failed to setup audio session: \(error)")
        }
    }
    
    private func startLoadingTimeout() {
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(loadingStateTimeout * 1_000_000_000))

                // If still loading after timeout, check if audio is actually playing
                if self.playbackState == .loading {
                    let isBuffering = await SendspinClient.shared.isBuffering

                    if !isBuffering {
                        // Audio likely playing, force transition
                        self.playbackState = .playing
                        self.loadingStartTime = nil
                        self.startProgressTimer()
                        print("[PlayerManager] Loading timeout - forced transition to playing (audio detected)")
                    } else {
                        // Still buffering, likely a real issue
                        print("[PlayerManager] Loading timeout - still buffering, possible stream issue")
                    }
                }
            } catch {
                // Task was cancelled, do nothing
            }
        }
    }

    private func cancelLoadingTimeout() {
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = nil
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()

        // Create timer on main run loop explicitly
        // Using 0.25s interval for smoother updates, though we only emit significant changes
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                // Only tick if audio is actually playing (not buffering)
                if self.playbackState == .playing && !SendspinClient.shared.isBuffering {
                    // Use hardware engine time when available for drift-free tracking
                    let engineTime = SendspinClient.shared.getPlaybackTimeSync()
                    if engineTime > 0 {
                        let hardwareTime = self.streamStartServerElapsed + engineTime
                        if self.duration > 0 {
                            self.currentTime = min(hardwareTime, self.duration)
                        } else {
                            self.currentTime = hardwareTime
                        }
                        self.audioSyncedTime = hardwareTime
                        // Update wall-clock reference for fallback interpolation
                        self.fallbackTimeRef = self.currentTime
                        self.fallbackWallClockRef = ProcessInfo.processInfo.systemUptime
                    } else {
                        // Fallback: wall-clock interpolation.
                        // For local players: freeze if Sendspin is disconnected (network stall).
                        // Resetting fallbackWallClockRef to 0 forces a re-seed on next valid tick,
                        // preventing currentTime from advancing during the disconnected gap.
                        if self.isCurrentPlayerLocal && !SendspinClient.shared.isConnected {
                            self.fallbackWallClockRef = 0
                        } else {
                            let wallNow = ProcessInfo.processInfo.systemUptime
                            if self.fallbackWallClockRef > 0 {
                                let wallDelta = (wallNow - self.fallbackWallClockRef) * Double(self.playbackRate)
                                let interpolated = self.fallbackTimeRef + wallDelta
                                if self.duration > 0 {
                                    self.currentTime = min(interpolated, self.duration)
                                } else {
                                    self.currentTime = interpolated
                                }
                            } else {
                                // No reference yet, seed from current time
                                self.fallbackWallClockRef = wallNow
                                self.fallbackTimeRef = self.currentTime
                            }
                            self.audioSyncedTime = self.currentTime
                        }
                    }

                    // Update current chapter if playing an audiobook
                    if let audiobook = self.currentAudiobook {
                        self.updateCurrentChapter(for: audiobook, at: self.currentTime)
                    }

                    // Stop local progress when track reaches the end
                    // Server will send the actual end-of-track event for queue advancement
                    if self.duration > 0 && self.currentTime >= self.duration {
                        self.stopProgressTimer()
                        return
                    }

                    // Only update now playing info periodically (every 5 seconds)
                    if Int(self.currentTime) % 5 == 0 {
                        self.updateNowPlayingInfo()

                        // Save playback position every 5 seconds
                        self.savePlaybackPosition()

                        // Update progress for audiobooks/podcasts in history every 5 seconds
                        if let audiobook = self.currentAudiobook {
                            Task {
                                await PlaybackHistoryManager.shared.updateProgress(
                                    itemId: audiobook.itemId,
                                    progress: self.currentTime,
                                    duration: self.duration
                                )
                            }
                        }
                    }
                }
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Remote Command Center

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.play()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if let self = self, self.interruptionState != .none && self.interruptionState != .handled {
                    self.interruptionState = .remoteCommandReceived
                }
                self?.pause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if let self = self, self.interruptionState != .none && self.interruptionState != .handled {
                    self.interruptionState = .remoteCommandReceived
                }
                self?.togglePlayPause()
            }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.next()
            }
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.previous()
            }
            return .success
        }
        
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            Task { @MainActor in
                self?.skipForward(seconds: event.interval)
            }
            return .success
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            Task { @MainActor in
                self?.skipBackward(seconds: event.interval)
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                self?.seek(to: positionEvent.positionTime)
            }
            return .success
        }
    }
    
    private func updateRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // For radio streams, disable skip/next/prev since they're live streams
        if isPlayingRadio {
            commandCenter.nextTrackCommand.isEnabled = false
            commandCenter.previousTrackCommand.isEnabled = false
            commandCenter.skipForwardCommand.isEnabled = false
            commandCenter.skipBackwardCommand.isEnabled = false
        }
        // Toggle between Next/Prev Track and Skip Forward/Backward based on content type
        else if isPlayingAudiobook || isPlayingPodcast {
            commandCenter.nextTrackCommand.isEnabled = false
            commandCenter.previousTrackCommand.isEnabled = false
            commandCenter.skipForwardCommand.isEnabled = true
            commandCenter.skipBackwardCommand.isEnabled = true
        } else {
            commandCenter.nextTrackCommand.isEnabled = true
            commandCenter.previousTrackCommand.isEnabled = true
            commandCenter.skipForwardCommand.isEnabled = false
            commandCenter.skipBackwardCommand.isEnabled = false
        }
    }

    // MARK: - Player Selection Management

    /// Called when the user switches to a different player
    /// Clears current playback state to avoid confusion between players
    func handlePlayerChanged(to newPlayer: MAPlayer?, from oldPlayer: MAPlayer?) {
        // If switching between different players, clear the Now Playing state
        guard let newPlayerId = newPlayer?.playerId else {
            // No player selected, clear everything
            clearPlaybackState()
            return
        }

        // CRITICAL: Only handle actual player switches, not data refreshes
        // If the player ID is the same, this is just a data update, NOT a player switch
        // Calling restoreState here was causing loops because it would overwrite active playback
        guard newPlayerId != oldPlayer?.playerId else {
            // Same player, just a data refresh - do not restore state
            return
        }

        print("[PlayerManager] Player switched: \(oldPlayer?.playerId ?? "nil") -> \(newPlayerId)")

        // Always clear first so restoreState guard doesn't preserve old player's track
        clearPlaybackState()
        // Then restore new player's state if available
        if let savedState = MultiDeviceManager.shared.state(for: newPlayerId) {
            restoreState(from: savedState)
        }

        // Sync volume from the new player
        if let vol = newPlayer?.volume {
            self.volume = Float(vol) / 100.0
        }
    }

    private func restoreState(from state: MultiDeviceManager.PlayerState) {
        // CRITICAL: Don't overwrite active playback with stale nil/stopped state
        // This can happen when player data refreshes trigger handlePlayerChanged
        if currentTrack != nil && (playbackState == .playing || playbackState == .loading) {
            if state.currentTrack == nil || state.playbackState == .stopped {
                print("[PlayerManager] Preserving active playback, ignoring stale restore")
                return
            }
        }
        
        print("[PlayerManager] Restoring state: track=\(state.currentTrack?.name ?? "nil"), state=\(state.playbackState), time=\(state.currentTime)")
        currentTrack = state.currentTrack
        isCurrentTrackFavorited = state.currentTrack?.favorite ?? false
        currentTime = state.currentTime
        duration = state.duration
        playbackState = state.playbackState
        
        if state.playbackState == .playing {
            startProgressTimer()
        } else {
            stopProgressTimer()
        }
        
        updateNowPlayingInfo()
    }

    private func clearPlaybackState() {
        currentTrack = nil
        currentTime = 0
        duration = 0
        playbackState = .stopped
        queue = []
        currentIndex = 0
        stopProgressTimer()
        clearNowPlayingInfo()

        // Clear long-form content state
        currentAudiobook = nil
        currentChapter = nil
        currentPodcast = nil
        currentSource = nil
    }

    // MARK: - Notifications

    private func setupNotifications() {
        // Audio Interruption Handling (Phone calls, etc.)
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] notification in
            self?.handleAudioInterruption(notification: notification)
        }

        // Audio Route Change Handling (Headphone disconnect, Bluetooth, etc.)
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] notification in
            self?.handleAudioRouteChange(notification: notification)
        }

        // Media services reset -- rebuild audio session from scratch
        NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleMediaServicesReset()
        }

        // CallKit observer - catches phone calls that interruptionNotification may miss
        callObserver.setDelegate(self, queue: .main)

        NotificationCenter.default.publisher(for: .queueUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                Task {
                    await self.handleQueueUpdate(notification)
                }
            }
            .store(in: &cancellables)

        // Subscribe to XonoraClient connection state to retry pending play commands
        XonoraClient.shared.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self, case .connected = state, self.pendingPlayAfterReconnect else { return }
                self.pendingPlayAfterReconnect = false
                print("[PlayerManager] Connection restored — resuming playback with saved track verification")
                Task { @MainActor in
                    await self.resumeWithSavedTrackVerification()
                }
            }
            .store(in: &cancellables)

        // Detect Sendspin reconnect after a network stall and sync position from server.
        // The server does not send a queue_updated event on reconnect (state didn't change),
        // so we explicitly fetch queue state to recalibrate currentTime and streamStartServerElapsed.
        SendspinClient.shared.$isConnected
            .removeDuplicates()
            .dropFirst() // ignore the initial value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                guard let self = self,
                      isConnected,
                      self.isCurrentPlayerLocal,
                      self.playbackState == .playing,
                      let player = XonoraClient.shared.currentPlayer else { return }
                print("[PlayerManager] Sendspin reconnected — fetching queue state to recalibrate position")
                Task { await self.fetchQueueFromServer(for: player) }
            }
            .store(in: &cancellables)
    }
    
    private func handleQueueUpdate(_ notification: Notification) async {
        guard let userInfo = notification.userInfo else { return }

        // Skip processing during player transfer to avoid state conflicts
        if isTransferringPlayback {
            return
        }

        // CRITICAL: Only process queue events for the currently selected player
        // Each device can have multiple players registered, and we only care about OUR player's queue
        if let queueId = userInfo["queue_id"] as? String {
            let currentPlayerId = XonoraClient.shared.currentPlayer?.playerId
            if queueId != currentPlayerId {
                // This queue event is for a different player, ignore it
                return
            }
        }

        // Get elapsed time from notification
        let elapsed = userInfo["elapsed_time"] as? Double ?? 0
        
        // Get state string early so it's available throughout the function
        let stateStr = userInfo["state"] as? String

        // Smart debounce: ignore echoes of our own commands during debounce window,
        // but process contradictory remote commands (like Phone B pausing Phone A)
        if let lastTime = lastLocalCommandTime,
           let lastCmd = lastLocalCommand,
           Date().timeIntervalSince(lastTime) < 1.5 {

            // Detect contradictory changes (likely remote commands)
            let isContradictory = (
                (lastCmd == "play" && stateStr == "paused") ||
                (lastCmd == "pause" && stateStr == "playing")
            )

            if !isContradictory {
                // Likely echo of our own command - ignore
                if let currentItem = userInfo["current_item"] as? [String: Any],
                   let duration = currentItem["duration"] as? Int {
                    self.duration = TimeInterval(duration)
                }
                return
            }

            // Contradictory change - clear debounce, process event
            print("[PlayerManager] Remote command during debounce: \(stateStr ?? "unknown")")
            lastLocalCommandTime = nil
            lastLocalCommand = nil
            userPlayDebounceTask?.cancel()
        }

        let isLocal = self.isCurrentPlayerLocal

        // Recalibrate server-to-engine offset, but NOT during loading state.
        // During loading, server elapsed_time advances while audio hasn't started --
        // using it for calibration would bake in the buffering delay permanently.
        if self.playbackState != .loading {
            // For remote players, grouped/synced players: use server time directly
            // Only use hardware engine time for local single player
            let isSyncedToOther = XonoraClient.shared.currentPlayer?.syncedTo != nil
            let hasGroupChildren = (XonoraClient.shared.currentPlayer?.groupChilds?.isEmpty ?? true) == false
            let isGrouped = isSyncedToOther || hasGroupChildren
            let useServerTime = !isLocal || isGrouped

            if useServerTime {
                // Remote or grouped player: Trust server time completely
                self.currentTime = elapsed
                self.streamStartServerElapsed = elapsed
                self.audioSyncedTime = elapsed
                self.fallbackTimeRef = elapsed
                self.fallbackWallClockRef = ProcessInfo.processInfo.systemUptime
            } else {
                // Local single player: Use hardware engine time for smooth playback
                let engineTime = SendspinClient.shared.getPlaybackTimeSync()
                if engineTime > 0 {
                    let newOffset = elapsed - engineTime
                    if abs(newOffset - self.streamStartServerElapsed) > 3.0 {
                        // Large jump (seek or track change) -- snap immediately
                        self.streamStartServerElapsed = newOffset
                        self.currentTime = elapsed
                    } else {
                        // Recalibrate offset -- converge quickly (50/50 blend)
                        self.streamStartServerElapsed = self.streamStartServerElapsed * 0.5 + newOffset * 0.5
                        self.currentTime = self.streamStartServerElapsed + engineTime
                    }
                    self.audioSyncedTime = self.currentTime
                    // Update fallback references
                    self.fallbackTimeRef = self.currentTime
                    self.fallbackWallClockRef = ProcessInfo.processInfo.systemUptime
                } else if abs(elapsed - self.currentTime) > 0.5 {
                    // No engine time and significant server correction
                    self.currentTime = elapsed
                    self.streamStartServerElapsed = elapsed
                    self.audioSyncedTime = elapsed
                    self.fallbackTimeRef = elapsed
                    self.fallbackWallClockRef = ProcessInfo.processInfo.systemUptime
                }
            }
        }

        if let stateStr = stateStr {
            // Check if we have a pending track (means this is a transition, not a real stop)
            let hasCurrentItem = userInfo["current_item"] != nil

            if stateStr == "playing" {
                if self.playbackState == .loading {
                    if elapsed > 0.5 {
                        // Audio has actually started on server.
                        if isLocal {
                            let isGrouped = XonoraClient.shared.currentPlayer?.syncedTo != nil ||
                                           !(XonoraClient.shared.currentPlayer?.groupChilds?.isEmpty ?? true)
                            if isGrouped {
                                self.streamStartServerElapsed = elapsed
                                self.currentTime = elapsed
                                self.audioSyncedTime = elapsed
                            } else {
                                let startEngineTime = SendspinClient.shared.getPlaybackTimeSync()
                                self.streamStartServerElapsed = self.loadingStartElapsed
                                let calibratedTime = self.loadingStartElapsed + startEngineTime
                                self.currentTime = calibratedTime
                                self.audioSyncedTime = calibratedTime
                            }
                        } else {
                            // Remote player: use server time directly
                            self.streamStartServerElapsed = elapsed
                            self.currentTime = elapsed
                            self.audioSyncedTime = elapsed
                        }

                        self.fallbackTimeRef = self.currentTime
                        self.fallbackWallClockRef = ProcessInfo.processInfo.systemUptime
                        self.playbackState = .playing
                        self.loadingStartTime = nil
                        self.cancelLoadingTimeout()
                        self.startProgressTimer()
                        if isLocal {
                            SendspinClient.shared.resumePlayback()
                        }
                    }
                    // else: stay in loading state until server confirms progress
                } else if self.playbackState != .playing {
                    // Check if we're starting a new track (auto-advance) vs just resuming current track
                    if elapsed < 0.5 && hasCurrentItem {
                        // New track starting - go to loading state and wait for stream
                        self.playbackState = .loading
                        self.loadingStartElapsed = elapsed
                        self.loadingStartTime = Date()
                        self.startLoadingTimeout()
                    } else {
                        // Resume from paused/stopped state
                        if isLocal {
                            let resumeEngineTime = SendspinClient.shared.getPlaybackTimeSync()
                            self.streamStartServerElapsed = elapsed - resumeEngineTime
                        } else {
                            self.streamStartServerElapsed = elapsed
                        }
                        self.currentTime = elapsed
                        self.fallbackTimeRef = elapsed
                        self.fallbackWallClockRef = ProcessInfo.processInfo.systemUptime
                        self.playbackState = .playing
                        self.startProgressTimer()
                        if isLocal {
                            SendspinClient.shared.resumePlayback()
                        }
                    }
                }
            } else if stateStr == "paused" {
                self.playbackState = .paused
                self.cancelLoadingTimeout()
                self.stopProgressTimer()
                if isLocal {
                    SendspinClient.shared.pausePlayback()
                }
            } else if stateStr == "idle" {
                // Only handle as "track ended" if:
                // 1. We were actually playing
                // 2. There's no current_item (no next track waiting)
                // This prevents stopping during track-to-track transitions
                if self.playbackState == .playing && !hasCurrentItem {
                    self.handleTrackEnded()
                    if isLocal {
                        SendspinClient.shared.stopPlayback()
                    }
                }
            } else {
                self.playbackState = .stopped
                self.cancelLoadingTimeout()
                self.stopProgressTimer()
                self.audioSyncedTime = 0
                self.streamStartServerElapsed = 0
                if isLocal {
                    SendspinClient.shared.stopPlayback()
                }
            }
        }

        // Handle current item updates (auto-advance)
        if let currentItem = userInfo["current_item"] as? [String: Any] {
            // Update duration
            if let duration = currentItem["duration"] as? Int {
                self.duration = TimeInterval(duration)
            } else if let duration = currentItem["duration"] as? Double {
                self.duration = duration
            }

            // Update current track if it changed
            if let mediaItemDict = currentItem["media_item"] as? [String: Any] {
                do {
                    let data = try JSONSerialization.data(withJSONObject: mediaItemDict)
                    var track = try JSONDecoder().decode(Track.self, from: data)

                    // For audiobooks, the server sends narrators/authors instead of artists.
                    // Inject narrator (preferred) or author into the Track's artists field
                    // so mini player, Now Playing, and lock screen show the right name.
                    if track.artists == nil || track.artists?.isEmpty == true,
                       let mediaType = mediaItemDict["media_type"] as? String,
                       mediaType == "audiobook" {
                        let displayNames: [String] = {
                            if let narrators = mediaItemDict["narrators"] as? [String], !narrators.isEmpty {
                                return narrators
                            }
                            if let authors = mediaItemDict["authors"] as? [String], !authors.isEmpty {
                                return authors
                            }
                            // Try album.artist as last resort (some providers put author there)
                            if let albumDict = mediaItemDict["album"] as? [String: Any],
                               let albumArtist = albumDict["name"] as? String, !albumArtist.isEmpty {
                                return [albumArtist]
                            }
                            return []
                        }()
                        if !displayNames.isEmpty {
                            track = Track(
                                itemId: track.itemId, provider: track.provider, name: track.name,
                                version: track.version, duration: track.duration,
                                trackNumber: track.trackNumber, discNumber: track.discNumber,
                                uri: track.uri,
                                artists: displayNames.map { ArtistReference(itemId: nil, provider: nil, name: $0) },
                                album: track.album, metadata: track.metadata,
                                providerMappings: track.providerMappings, image: track.image,
                                favorite: track.favorite
                            )
                        }
                    }

                    // Deduplicate: Skip if we just processed this exact track change
                    if self.lastProcessedTrackURI == track.uri {
                        // Already processed this track, skip to avoid restart loop
                        return
                    }

                    if self.currentTrack?.uri != track.uri {
                        print("[PlayerManager] Server advanced to next track: \(track.name). Old URI: \(self.currentTrack?.uri ?? "nil"), New URI: \(track.uri)")
                        self.lastProcessedTrackURI = track.uri
                        self.currentTrack = track
                        self.isCurrentTrackFavorited = track.favorite ?? false

                        // Sync currentIndex so next/previous work correctly after server auto-advance
                        if let idx = self.queue.firstIndex(where: { $0.uri == track.uri }) {
                            self.currentIndex = idx
                        } else {
                            // Track not in local queue — server advanced beyond cache or queue was modified
                            print("[PlayerManager] Current track not in local queue — scheduling full queue refresh")
                            Task { @MainActor in
                                guard let player = XonoraClient.shared.currentPlayer else { return }
                                await self.fetchQueueFromServer(for: player)
                            }
                        }
                        
                        // CRITICAL FIX: Only reset currentTime if we're actually starting playback
                        // Don't reset if we're in stopped/idle state (track ended but still showing)
                        if stateStr == "playing" || self.playbackState == .loading {
                            self.currentTime = 0
                            self.streamStartServerElapsed = 0
                            self.audioSyncedTime = 0
                        }
                        
                        // Reset lastTrackId to trigger artwork reload
                        self.lastTrackId = nil
                    }
                } catch {
                    print("[PlayerManager] Failed to decode track from server: \(error)")
                }
            }
        }

        self.updateNowPlayingInfo()
    }

    private func handleTrackEnded() {
        // Don't auto-advance - let server handle queue
        // We only update UI state here
        playbackState = .stopped
        stopProgressTimer()

        // Don't reset currentTime here - let it stay at duration
        // This prevents the progress bar from jumping back to 0 visually
        // currentTime will be reset when a new track starts (line 549, 689, etc.)

        audioSyncedTime = 0
        streamStartServerElapsed = 0

        print("[PlayerManager] Track ended - keeping progress at \(currentTime)")
    }

    // Audio interruption state machine - prevents race conditions between
    // AVAudioSession.interruptionNotification and CXCallObserver handlers
    enum InterruptionState: Equatable {
        case none
        case interrupted(wasSuspension: Bool, wasPlaying: Bool)
        case callInterrupted(wasPlaying: Bool)
        case remoteCommandReceived
        case handled
    }

    // Track if we were playing before an audio interruption (for auto-resume)
    private var interruptionState: InterruptionState = .none
    private let callObserver = CXCallObserver()
    private var pendingPlayAfterReconnect = false // Queue play command to retry after reconnection
    private var pausedAt: Date? // Track when playback was paused to detect long pauses

    // DEPRECATED - Use interruptionState instead (kept for backwards compatibility during transition)
    private var wasPlayingBeforeInterruption: Bool {
        get {
            if case .interrupted(_, let wasPlaying) = interruptionState {
                return wasPlaying
            }
            if case .callInterrupted(let wasPlaying) = interruptionState {
                return wasPlaying
            }
            return false
        }
        set {
            // No-op: state machine is canonical source of truth
        }
    }
    private var isCurrentlyInterrupted: Bool {
        get { interruptionState != .none && interruptionState != .handled }
        set {
            // No-op: state machine is canonical source of truth
        }
    }
    private var interruptionWasSuspension: Bool {
        get {
            if case .interrupted(let wasSuspension, _) = interruptionState {
                return wasSuspension
            }
            return false
        }
        set {
            // No-op: state machine is canonical source of truth
        }
    }
    private var remoteCommandReceivedDuringInterruption: Bool {
        get { interruptionState == .remoteCommandReceived }
        set {
            if newValue {
                interruptionState = .remoteCommandReceived
            }
        }
    }

    private func handleAudioRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones/external audio unplugged
            print("[PlayerManager] Audio route changed - device unplugged")
            // iOS will automatically pause, but we should ensure our state is consistent
            if playbackState == .playing {
                wasPlayingBeforeInterruption = true
                playbackState = .paused
                stopProgressTimer()
                SendspinClient.shared.pausePlayback()
                updateNowPlayingInfo()
            }

        case .newDeviceAvailable:
            // New audio device connected (headphones plugged in, Bluetooth connected)
            print("[PlayerManager] Audio route changed - new device available")
            // Ensure audio session is configured correctly for the new route
            setupAudioSession()

        default:
            // Other route changes (e.g., switching between speaker/receiver)
            print("[PlayerManager] Audio route changed - reason: \(reason.rawValue)")
            break
        }
    }

    private func handleAudioInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            // Check interruption reason
            var wasSuspension = false
            if let reasonValue = userInfo[AVAudioSessionInterruptionReasonKey] as? UInt,
               let reason = AVAudioSession.InterruptionReason(rawValue: reasonValue) {
                if reason == .appWasSuspended {
                    wasSuspension = true
                    print("[PlayerManager] Audio interruption began (app was suspended)")
                } else {
                    print("[PlayerManager] Audio interruption began (reason: \(reason.rawValue))")
                }
            } else {
                print("[PlayerManager] Audio interruption began (e.g. phone call)")
            }

            // Preserve wasPlaying=true if already interrupted — avoids duplicate .began overwriting with false
            // This covers both .interrupted and .callInterrupted (CallKit fires before AVAudioSession)
            let wasPlaying: Bool
            switch interruptionState {
            case .interrupted(_, let existing) where existing,
                 .callInterrupted(let existing) where existing:
                wasPlaying = existing
            default:
                wasPlaying = playbackState == .playing
            }
            print("[PlayerManager] Interruption state before: \(self.interruptionState) | wasSuspension: \(wasSuspension) | wasPlaying: \(wasPlaying)")
            interruptionState = .interrupted(wasSuspension: wasSuspension, wasPlaying: wasPlaying)
            print("[PlayerManager] Interruption state after: \(self.interruptionState)")

            if playbackState == .playing {
                playbackState = .paused
                stopProgressTimer()
                SendspinClient.shared.pausePlayback()
                Task {
                    try? await XonoraClient.shared.pause()
                }
                updateNowPlayingInfo()
            }
        case .ended:
            print("[PlayerManager] Audio interruption ended")

            // Skip false positives: if the app was merely suspended (not a real interruption), ignore
            if let wasSuspended = userInfo[AVAudioSessionInterruptionWasSuspendedKey] as? Bool, wasSuspended {
                print("[PlayerManager] Ignoring interruption .ended — AVAudioSessionInterruptionWasSuspendedKey=true")
                return
            }

            // Skip if already handled or not in interrupted state
            guard case .interrupted(let wasSuspension, let wasPlaying) = interruptionState else {
                print("[PlayerManager] Ignoring interruption .ended — current state: \(interruptionState) (cannot extract wasSuspension/wasPlaying)")
                return
            }
            print("[PlayerManager] Interruption .ended state details: wasSuspension=\(wasSuspension), wasPlaying=\(wasPlaying)")

            let options: AVAudioSession.InterruptionOptions
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            } else {
                options = []
            }

            if wasSuspension {
                // App was suspended -- reactivate session but don't auto-resume
                print("[PlayerManager] Interruption was suspension, reactivating session only")
                interruptionState = .handled
                reactivateSessionOnly()
            } else if case .remoteCommandReceived = interruptionState {
                // User issued pause via Siri/remote during interruption -- respect it
                print("[PlayerManager] Remote command received during interruption, not auto-resuming")
                interruptionState = .handled
                reactivateSessionOnly()
            } else if options.contains(.shouldResume) || wasPlaying {
                print("[PlayerManager] Attempting to resume playback after interruption")
                resumeAfterInterruption()
            } else {
                interruptionState = .handled
            }
        @unknown default:
            break
        }
    }

    private func reactivateSessionOnly() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            print("[PlayerManager] Audio session reactivated (no playback resume)")
        } catch {
            print("[PlayerManager] Failed to reactivate audio session: \(error)")
        }
    }

    private func handleMediaServicesReset() {
        print("[PlayerManager] Media services were reset - rebuilding audio session")
        let wasPlaying = playbackState == .playing
        if wasPlaying {
            playbackState = .paused
            stopProgressTimer()
        }
        setupAudioSession()
        setupRemoteCommandCenter()
        if wasPlaying {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                self.playbackState = .playing
                self.startProgressTimer()
                SendspinClient.shared.resumePlayback()
                self.updateNowPlayingInfo()
                try? await XonoraClient.shared.play()
            }
        } else {
            updateNowPlayingInfo()
        }
    }

    func checkForegroundRecovery() {
        guard interruptionState != .none && interruptionState != .handled else {
            print("[PlayerManager] checkForegroundRecovery: skipping (state is already \(interruptionState))")
            return
        }
        print("[PlayerManager] Foreground recovery: .ended was never delivered, found stale state: \(interruptionState). Resetting interruption state and reactivating session")
        interruptionState = .handled
        reactivateSessionOnly()
        if !SendspinClient.shared.isConnected {
            print("[PlayerManager] SendspinClient not connected during foreground recovery, calling reconnectIfNeeded()...")
            SendspinClient.shared.reconnectIfNeeded()
        } else {
            print("[PlayerManager] SendspinClient already connected during foreground recovery")
        }
    }

    @MainActor
    private func resumeAfterInterruption() {
        // Don't proceed if not in a state that should resume
        let wasPlaying: Bool
        switch interruptionState {
        case .interrupted(_, let wp), .callInterrupted(let wp):
            wasPlaying = wp
        default:
            print("[PlayerManager] resumeAfterInterruption called in invalid state: \(interruptionState)")
            return
        }
        interruptionState = .handled  // Mark handled after reading wasPlaying, before async work

        guard wasPlaying else {
            print("[PlayerManager] resumeAfterInterruption: wasPlaying=false, skipping resume")
            return
        }

        print("[PlayerManager] resumeAfterInterruption: reactivating session and resuming play")

        // Reactivate the audio session — must happen before play() attempts to use it
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            print("[PlayerManager] Audio session reactivated after interruption")
        } catch {
            print("[PlayerManager] FAILED to reactivate audio session: \(error)")
        }

        // Recalibrate lyrics time offset before resuming.
        // streamStartServerElapsed was set in a previous engine session; after interruption
        // the engine restarts with engineTime near 0. Reset offset so lyricsTime = currentTime
        // immediately, rather than jumping by the old engineTime offset.
        // The first queue_updated event after resume will do a precise recalibration.
        streamStartServerElapsed = currentTime
        fallbackWallClockRef = 0

        // Delegate entirely to play(), which already handles:
        //  - XonoraClient not connected → pendingPlayAfterReconnect = true + reconnectRequired notification
        //  - Sendspin not connected → reconnectIfNeeded() + 5s wait internally
        //  - optimistic state update, NowPlaying, server command
        // Both clients are now persistent-reconnect (no attempt cap), so they will be
        // available before or shortly after play() fires.
        play()
    }



    // MARK: - CXCallObserverDelegate

    nonisolated func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        let hasConnected = call.hasConnected
        let hasEnded = call.hasEnded
        let isOutgoing = call.isOutgoing
        let callUUID = call.uuid.uuidString
        Task { @MainActor in
            if hasConnected || (!hasEnded && !hasConnected && !isOutgoing) {
                // Call started or incoming call ringing - pause if playing
                // Only handle if we're not already in an interrupted state (AVAudioSession might have fired first)
                let wasPlaying = self.playbackState == .playing
                let stateBeforeUpdate = self.interruptionState

                // Update state machine: only set callInterrupted if not already interrupted
                if case .none = self.interruptionState {
                    self.interruptionState = .callInterrupted(wasPlaying: wasPlaying)
                }

                print("[PlayerManager] CallKit handler: call started (UUID: \(callUUID), hasConnected: \(hasConnected), isOutgoing: \(isOutgoing), wasPlaying: \(wasPlaying), stateBefore: \(stateBeforeUpdate))")

                if wasPlaying {
                    print("[PlayerManager] Phone call detected via CallKit - pausing playback")
                    self.playbackState = .paused
                    self.stopProgressTimer()
                    SendspinClient.shared.pausePlayback()
                    Task { try? await XonoraClient.shared.pause() }
                    self.updateNowPlayingInfo()
                }
            } else if hasEnded {
                // Call ended - attempt resume only if we were playing
                // State machine ensures we only resume once (both handlers check state before calling)
                let shouldResume: Bool
                let stateBeforeUpdate = self.interruptionState
                switch self.interruptionState {
                case .callInterrupted(let wasPlaying):
                    shouldResume = wasPlaying
                case .interrupted(_, let wasPlaying):
                    shouldResume = wasPlaying
                default:
                    shouldResume = false
                }

                if shouldResume && self.interruptionState != .handled {
                    print("[PlayerManager] CallKit handler: call ended (UUID: \(callUUID)) - RESUMING (stateBefore: \(stateBeforeUpdate), shouldResume: \(shouldResume))")
                    self.resumeAfterInterruption()
                } else {
                    print("[PlayerManager] CallKit handler: call ended (UUID: \(callUUID)) - SKIPPING RESUME (stateBefore: \(stateBeforeUpdate), shouldResume: \(shouldResume))")
                    self.interruptionState = .handled
                }
            }
        }
    }

    // MARK: - Playback Control

    func playTrack(_ track: Track, fromQueue tracks: [Track]? = nil, sourceName: String? = nil) {
        if let tracks = tracks {
            queue = tracks
            currentIndex = tracks.firstIndex(where: { $0.id == track.id }) ?? 0
        } else {
            // If no queue context provided, play just this track
            queue = [track]
            currentIndex = 0
        }
        
        self.currentSource = sourceName

        guard SendspinClient.shared.isConnected else {
            playbackState = .error("Sendspin not connected. Please enable it in Settings.")
            return
        }

        print("[PlayerManager] Playing: \(track.name)")

        // Force Shuffle OFF for direct track selection to ensure the selected track plays
        self.shuffleEnabled = false
        Task { try? await XonoraClient.shared.setShuffle(enabled: false) }

        // Sync Repeat Mode to ensure server matches client state (fixes stuck repeat issues)
        let modeString: String
        switch repeatMode {
        case .off: modeString = "off"
        case .all: modeString = "all"
        case .one: modeString = "one"
        }
        Task { try? await XonoraClient.shared.setRepeat(mode: modeString) }

        // Track local play command
        lastLocalCommandTime = Date()
        lastLocalCommand = "play"
        userPlayDebounceTask?.cancel()
        userPlayDebounceTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                self.lastLocalCommandTime = nil
                self.lastLocalCommand = nil
            }
        }

        currentTrack = track
        isCurrentTrackFavorited = track.favorite ?? false
        currentTime = 0
        duration = track.duration ?? 0
        loadingStartElapsed = 0
        playbackState = .loading
        loadingStartTime = Date()  // Track when loading started
        self.startLoadingTimeout()  // Start timeout safety net

        // Clear long-form state when playing regular tracks
        currentAudiobook = nil
        currentChapter = nil
        currentPodcast = nil
        
        // Update lock screen controls for music
        updateRemoteCommands()

        SendspinClient.shared.stopPlayback()
        stopProgressTimer()
        Task {
            await self.updateNowPlayingInfoAsync()
        }

        // Prepare URIs to play (current track + subsequent queue items)
        let uris: [String]
        if !queue.isEmpty && currentIndex < queue.count {
            // If we are replacing the queue, we generally send the whole list or starting from current
            // Logic: playMedia(uris) usually replaces queue. 
            // If we are starting a NEW queue context/album, we want to play all of them.
            // If we are just playing a track, we play [track].
            // If 'tracks' (queue context) was passed, we play that list.
            if let validTracks = tracks {
                 // Play full album/playlist starting at index
                 // We need to send ALL items to populate the queue, but start at index?
                 // Music Assistant 'playMedia' API adds items. If we want to start at index 5 of 10...
                 // The best way is likely to send all URIs, then seek/skip?
                 // Or just send the specific track if the queue is not relevant.
                 // HOWEVER: playAlbum implementation below calls playMedia with full track list.
                 // Implementation here: simple fallback is send the slice starting from current.
                 uris = Array(queue[currentIndex..<queue.count]).map { $0.uri }
            } else {
                uris = Array(queue[currentIndex..<queue.count]).map { $0.uri }
            }
        } else {
            uris = [track.uri]
        }

        // Tell server to play this track
        Task {
            do {
                try await XonoraClient.shared.playMedia(uris: uris)

                // Add track to playback history
                let historyItem = PlaybackHistoryItem(
                    contentType: .track,
                    itemId: track.itemId,
                    itemName: track.name,
                    itemUri: track.uri,
                    artistName: track.artistNames,
                    imageUrl: track.imageUrl
                )
                await PlaybackHistoryManager.shared.addToHistory(item: historyItem)
            } catch {
                print("[PlayerManager] Failed to send play command: \(error)")

                // Suppress "Request timeout" error if it happens, as it often means the server
                // processed the command but the acknowledgement was lost/delayed, while music plays fine.
                let nsError = error as NSError
                if nsError.domain == "MusicAssistant" && nsError.code == -1 {
                    print("[PlayerManager] Suppressing timeout error (server likely processed command).")
                    return
                }

                await MainActor.run {
                    self.playbackState = .error("Failed to play: \(error.localizedDescription)")
                }
            }
        }
    }

    func play() {
        // Check if we need to reconnect first
        let clientState = XonoraClient.shared.connectionState
        guard case .connected = clientState else {
            print("[PlayerManager] Cannot play - connection state is \(clientState), reconnection needed")
            pendingPlayAfterReconnect = true  // Queue the play command to retry after reconnection
            NotificationCenter.default.post(name: .reconnectRequired, object: nil)
            return
        }
        pendingPlayAfterReconnect = false  // Clear the flag since we're connected

        Task { @MainActor in
            // Only manage local audio session and SendspinClient for local player
            if self.isCurrentPlayerLocal {
                // CRITICAL FIX: Ensure audio session is active before playback
                // This is essential after interruptions (calls), backgrounding, or long pauses
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setActive(true)
                    print("[PlayerManager] Audio session activated for playback")
                } catch {
                    print("[PlayerManager] Failed to activate audio session: \(error)")
                    self.playbackState = .error("Audio session unavailable")
                    return
                }
            }

            if self.isCurrentPlayerLocal {
                // CRITICAL FIX: Ensure SendspinClient is connected before playback
                // After interruptions or backgrounding, it may be disconnected
                if !SendspinClient.shared.isConnected {
                    print("[PlayerManager] SendspinClient disconnected, reconnecting...")
                    SendspinClient.shared.reconnectIfNeeded()

                    // Wait up to 5 seconds for reconnection
                    var reconnected = false
                    for _ in 0..<50 {
                        guard !Task.isCancelled else { return }
                        try? await Task.sleep(for: .milliseconds(100))
                        if SendspinClient.shared.isConnected {
                            print("[PlayerManager] SendspinClient reconnected!")
                            reconnected = true
                            break
                        }
                    }

                    if !reconnected {
                        print("[PlayerManager] Failed to reconnect SendspinClient")
                        self.playbackState = .error("Audio connection unavailable")
                        return
                    }
                }
            }

            // Optimistic: update state immediately so UI reflects the change
            self.pausedAt = nil
            self.playbackState = .playing
            self.startProgressTimer()
            if self.isCurrentPlayerLocal {
                SendspinClient.shared.resumePlayback()
            }
            self.updateNowPlayingInfo()

            // Track local play command
            self.lastLocalCommandTime = Date()
            self.lastLocalCommand = "play"
            self.userPlayDebounceTask?.cancel()
            self.userPlayDebounceTask = Task {
                try? await Task.sleep(for: .seconds(1.5))
                await MainActor.run {
                    self.lastLocalCommandTime = nil
                    self.lastLocalCommand = nil
                }
            }

            do {
                try await XonoraClient.shared.play()
            } catch {
                print("[PlayerManager] Play command failed: \(error)")
                // Revert state if command failed
                self.playbackState = .paused
                self.stopProgressTimer()
                if self.isCurrentPlayerLocal {
                    SendspinClient.shared.pausePlayback()
                }
            }
        }
    }


    func pause() {
        // Optimistic: update state immediately so UI reflects the change
        savePlaybackPosition()
        pausedAt = Date()
        playbackState = .paused
        stopProgressTimer()
        if isCurrentPlayerLocal {
            SendspinClient.shared.pausePlayback()
        }
        updateNowPlayingInfo()

        // Track local pause command
        lastLocalCommandTime = Date()
        lastLocalCommand = "pause"
        userPlayDebounceTask?.cancel()
        userPlayDebounceTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                self.lastLocalCommandTime = nil
                self.lastLocalCommand = nil
            }
        }

        Task {
            try? await XonoraClient.shared.pause()
        }
    }

    func togglePlayPause() {
        if playbackState == .playing {
            // Pause immediately
            pause()
        } else if playbackState == .paused {
            // Resume immediately - this will handle audio session and SendspinClient
            play()
        } else if playbackState == .stopped && currentTrack != nil {
            // Re-initiate playback from stopped state
            Task { @MainActor in
                // CRITICAL FIX: Ensure audio session is active before playback
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setActive(true)
                    print("[PlayerManager] Audio session activated for resume")
                } catch {
                    print("[PlayerManager] Failed to activate audio session: \(error)")
                    self.playbackState = .error("Audio session unavailable")
                    return
                }

                // CRITICAL FIX: Ensure SendspinClient is connected
                if !SendspinClient.shared.isConnected {
                    print("[PlayerManager] SendspinClient disconnected, reconnecting...")
                    SendspinClient.shared.reconnectIfNeeded()

                    // Wait up to 5 seconds for reconnection
                    var reconnected = false
                    for _ in 0..<50 {
                        try? await Task.sleep(for: .milliseconds(100))
                        if SendspinClient.shared.isConnected {
                            print("[PlayerManager] SendspinClient reconnected!")
                            reconnected = true
                            break
                        }
                    }

                    if !reconnected {
                        print("[PlayerManager] Failed to reconnect SendspinClient")
                        self.playbackState = .error("Audio connection unavailable")
                        return
                    }
                }

                if let track = self.currentTrack {
                    print("[PlayerManager] Re-initiating playback of: \(track.name)")

                    if !self.queue.isEmpty {
                        self.playTrack(track, fromQueue: self.queue, sourceName: self.currentSource)
                    } else {
                        self.playTrack(track, sourceName: self.currentSource)
                    }

                    // Restore saved position if available
                    if let saved = self.restorePlaybackPosition(), saved.uri == track.uri {
                        let position = saved.position
                        print("[PlayerManager] Restoring saved position: \(position) seconds")
                        Task {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            try? await XonoraClient.shared.seek(position: position)
                            await MainActor.run {
                                self.currentTime = position
                            }
                        }
                    }
                }
            }
        } else {
            // Loading or other state: send toggle to server
            Task {
                try? await XonoraClient.shared.playPause()
            }
        }
    }

    func stop() {
        // Save position before stopping
        savePlaybackPosition()

        Task {
            try? await XonoraClient.shared.stop()
        }
        currentTrack = nil
        currentTime = 0
        duration = 0
        playbackState = .stopped
        stopProgressTimer()
        clearNowPlayingInfo()
    }

    func next() {
        guard !queue.isEmpty else { return }

        // Always advance sequentially. Shuffle is handled by reordering the queue itself.
        currentIndex = (currentIndex + 1) % queue.count

        let nextTrack = queue[currentIndex]
        playTrack(nextTrack, fromQueue: queue, sourceName: currentSource)
    }

    func previous() {
        // If we are more than 3 seconds into the track, restart it
        if currentTime > 3 {
            seek(to: 0)
            return
        }

        guard !queue.isEmpty else { return }

        // Check if we are at the start of the queue
        if currentIndex > 0 {
            currentIndex -= 1
        } else {
            // Wrap around to the last track
            currentIndex = queue.count - 1
        }

        let previousTrack = queue[currentIndex]
        playTrack(previousTrack, fromQueue: queue, sourceName: currentSource)
    }

    func seek(to time: TimeInterval) {
        if SendspinClient.shared.isConnected {
            Task { try? await XonoraClient.shared.seek(position: time) }
        }
        currentTime = time
        Task {
            await self.updateNowPlayingInfoAsync()
        }
    }

    func skipForward(seconds: TimeInterval = 15) {
        let newTime = min(currentTime + seconds, duration)
        seek(to: newTime)
    }

    func skipBackward(seconds: TimeInterval = 15) {
        let newTime = max(currentTime - seconds, 0)
        seek(to: newTime)
    }

    func setVolume(_ newVolume: Float) {
        volume = newVolume
        Task { try? await XonoraClient.shared.setVolume(Int(newVolume * 100)) }
    }

    func toggleShuffle() {
        shuffleEnabled.toggle()
        Task { try? await XonoraClient.shared.setShuffle(enabled: shuffleEnabled) }
        
        guard !queue.isEmpty else { return }
        
        if shuffleEnabled {
            // Shuffle the queue, ensuring current track stays playing
            var tracks = queue
            if let current = currentTrack, let idx = tracks.firstIndex(where: { $0.id == current.id }) {
                tracks.remove(at: idx)
                tracks.shuffle()
                tracks.insert(current, at: 0)
                currentIndex = 0
            } else {
                tracks.shuffle()
                currentIndex = 0
            }
            queue = tracks
        } else {
            // Restore album order (approximate by sorting)
            var tracks = queue
            tracks.sort {
                let disc1 = $0.discNumber ?? 1
                let disc2 = $1.discNumber ?? 1
                if disc1 != disc2 { return disc1 < disc2 }
                return ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0)
            }
            queue = tracks
            
            // Update currentIndex to match current track's new position
            if let current = currentTrack {
                currentIndex = queue.firstIndex(where: { $0.id == current.id }) ?? 0
            }
        }
    }

    func cycleRepeatMode() {
        let nextRaw = (repeatMode.rawValue + 1) % 3
        repeatMode = RepeatMode(rawValue: nextRaw) ?? .off
        
        let modeString: String
        switch repeatMode {
        case .off: modeString = "off"
        case .all: modeString = "all"
        case .one: modeString = "one"
        }
        
        Task { try? await XonoraClient.shared.setRepeat(mode: modeString) }
    }
    
    // MARK: - Playback Rate
    
    static let playbackRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    
    func setPlaybackRate(_ rate: Float) {
        print("[PlayerManager] Setting playback rate to \(rate)x")
        playbackRate = rate
        // Persist rate for audiobooks
        if isPlayingAudiobook {
            UserDefaults.standard.set(rate, forKey: "AudiobookPlaybackRate")
        }
        Task {
            print("[PlayerManager] Calling XonoraClient.setPlaybackRate(\(rate))")
            try? await XonoraClient.shared.setPlaybackRate(rate)
        }
        updateNowPlayingInfo()
    }
    
    func cyclePlaybackRate() {
        guard let currentIndex = Self.playbackRates.firstIndex(of: playbackRate) else {
            playbackRate = 1.0
            return
        }
        let nextIndex = (currentIndex + 1) % Self.playbackRates.count
        setPlaybackRate(Self.playbackRates[nextIndex])
    }
    
    // MARK: - Favorite Toggle
    
    func toggleCurrentTrackFavorite() {
        guard let track = currentTrack else { return }
        isCurrentTrackFavorited.toggle()
        
        // Light haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        Task {
            do {
                try await XonoraClient.shared.toggleItemFavorite(uri: track.uri, favorite: isCurrentTrackFavorited)
                
                // Update local model state
                await MainActor.run {
                    if var current = currentTrack {
                        current.favorite = isCurrentTrackFavorited
                        currentTrack = current
                    }
                    
                    // Update in queue
                    if let index = queue.firstIndex(where: { $0.id == track.id }) {
                        var updatedTrack = queue[index]
                        updatedTrack.favorite = isCurrentTrackFavorited
                        queue[index] = updatedTrack
                    }
                }
            } catch {
                // Revert on error
                await MainActor.run {
                    isCurrentTrackFavorited.toggle()
                }
                print("[PlayerManager] Failed to toggle favorite: \(error)")
            }
        }
    }

    // MARK: - Queue Management

    func addToQueue(_ track: Track) {
        Task {
            do {
                // Send to server with "add" option to append to queue
                try await XonoraClient.shared.playMedia(uris: [track.uri], queueOption: "add")
                // Local queue will be updated via queue_updated event from server
            } catch {
                print("[PlayerManager] Failed to add track to queue: \(error)")
            }
        }
    }

    func addToQueue(_ tracks: [Track]) {
        Task {
            do {
                let uris = tracks.map { $0.uri }
                try await XonoraClient.shared.playMedia(uris: uris, queueOption: "add")
            } catch {
                print("[PlayerManager] Failed to add tracks to queue: \(error)")
            }
        }
    }

    func playNext(_ track: Track) {
        Task {
            do {
                // Send to server with "next" option to play after current track
                try await XonoraClient.shared.playMedia(uris: [track.uri], queueOption: "next")
            } catch {
                print("[PlayerManager] Failed to add track to play next: \(error)")
            }
        }
    }

    func clearQueue() {
        Task {
            do {
                try await XonoraClient.shared.clearUpcomingQueue()
            } catch {
                print("[PlayerManager] Failed to clear queue: \(error)")
            }
        }
    }

    func playAlbum(_ tracks: [Track], startingAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        let albumName = tracks[index].album?.name
        queue = tracks
        currentIndex = index
        playTrack(tracks[index], fromQueue: tracks, sourceName: albumName)

        // Also track the album in history (if we have album info)
        if let albumRef = tracks[index].album {
            Task {
                // Construct URI from album reference
                let albumUri = "\(albumRef.provider)://album/\(albumRef.itemId)"

                let historyItem = PlaybackHistoryItem(
                    contentType: .album,
                    itemId: albumRef.itemId,
                    itemName: albumRef.name,
                    itemUri: albumUri,
                    artistName: tracks[index].artistNames,
                    imageUrl: albumRef.imageUrl
                )
                await PlaybackHistoryManager.shared.addToHistory(item: historyItem)
            }
        }
    }

    func playPodcast(_ podcast: Podcast, episode: PodcastEpisode) {
        guard SendspinClient.shared.isConnected else {
            playbackState = .error("Sendspin not connected. Please enable it in Settings.")
            return
        }

        // Store podcast info
        queue = []
        currentIndex = 0
        currentSource = podcast.name
        currentPodcast = podcast
        currentAudiobook = nil
        currentChapter = nil

        // Create a temporary Track representation of the podcast episode
        let trackMetadata: MediaItemMetadata? = {
            if let episodeMetadata = episode.metadata {
                return MediaItemMetadata(images: episodeMetadata.images)
            }
            return podcast.metadata
        }()

        let episodeAsTrack = Track(
            itemId: episode.itemId,
            provider: episode.provider,
            name: episode.name,
            version: nil,
            duration: episode.duration.map(TimeInterval.init),
            trackNumber: episode.position,
            discNumber: nil,
            uri: episode.uri,
            artists: [ArtistReference(itemId: nil, provider: nil, name: podcast.publisher ?? "Unknown Publisher")],
            album: AlbumReference(itemId: podcast.itemId, provider: podcast.provider, name: podcast.name, metadata: podcast.metadata),
            metadata: trackMetadata,
            providerMappings: nil,
            image: episode.image
        )

        currentTrack = episodeAsTrack
        isCurrentTrackFavorited = episodeAsTrack.favorite ?? false
        currentTime = 0
        duration = episodeAsTrack.duration ?? 0
        loadingStartElapsed = 0
        playbackState = .loading
        self.startLoadingTimeout()

        // Update lock screen controls for long-form content
        updateRemoteCommands()

        SendspinClient.shared.stopPlayback()
        stopProgressTimer()
        Task {
            await self.updateNowPlayingInfoAsync()
        }

        // Tell server to play the podcast episode
        Task {
            do {
                try await XonoraClient.shared.playMedia(uris: [episode.uri])

                // Add to playback history
                let historyItem = PlaybackHistoryItem(
                    contentType: .podcast,
                    itemId: episode.itemId,
                    itemName: episode.name,
                    itemUri: episode.uri,
                    artistName: podcast.publisher,
                    imageUrl: episode.imageUrl ?? podcast.imageUrl,
                    progress: 0,
                    duration: episode.duration.map(TimeInterval.init)
                )
                await PlaybackHistoryManager.shared.addToHistory(item: historyItem)
            } catch {
                let nsError = error as NSError
                if nsError.domain == "MusicAssistant" && nsError.code == -1 {
                    print("[PlayerManager] Suppressing timeout error (server likely processed command).")
                    return
                }
                await MainActor.run {
                    self.playbackState = .error("Failed to play: \(error.localizedDescription)")
                }
            }
        }
    }

    func playPlaylist(_ playlist: Playlist, tracks: [Track], startingAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        queue = tracks
        currentIndex = index
        playTrack(tracks[index], fromQueue: tracks, sourceName: playlist.name)

        // Track the playlist in history
        Task {
            let historyItem = PlaybackHistoryItem(
                contentType: .playlist,
                itemId: playlist.itemId,
                itemName: playlist.name,
                itemUri: playlist.uri,
                artistName: nil,
                imageUrl: playlist.imageUrl
                )
            await PlaybackHistoryManager.shared.addToHistory(item: historyItem)
        }
    }

    func playRadio(_ radio: Radio) {
        guard SendspinClient.shared.isConnected else {
            playbackState = .error("Sendspin not connected. Please enable it in Settings.")
            return
        }

        // Clear queue for radio (it's a live stream, no queue)
        queue = []
        currentIndex = 0
        currentSource = "Radio"
        currentAudiobook = nil
        currentPodcast = nil
        currentChapter = nil

        // Create a Track representation for the radio station
        let radioAsTrack = Track(
            itemId: radio.itemId,
            provider: radio.provider,
            name: radio.name,
            version: nil,
            duration: nil, // Radio streams have no duration
            trackNumber: nil,
            discNumber: nil,
            uri: radio.uri,
            artists: [],
            album: nil,
            metadata: radio.metadata,
            providerMappings: nil,
            image: radio.image
        )

        currentTrack = radioAsTrack
        currentTime = 0
        duration = 0 // Radio has no duration
        loadingStartElapsed = 0
        playbackState = .loading
        self.startLoadingTimeout()

        // Update lock screen controls for radio (disable skip/next/prev)
        updateRemoteCommands()

        SendspinClient.shared.stopPlayback()
        stopProgressTimer()
        Task {
            await self.updateNowPlayingInfoAsync()
        }

        // Tell server to play the radio station
        Task {
            do {
                try await XonoraClient.shared.playMedia(uris: [radio.uri])

                // Add radio to playback history
                let historyItem = PlaybackHistoryItem(
                    contentType: .radio,
                    itemId: radio.itemId,
                    itemName: radio.name,
                    itemUri: radio.uri,
                    artistName: nil,
                    imageUrl: radio.imageUrl
                )
                await PlaybackHistoryManager.shared.addToHistory(item: historyItem)
            } catch {
                let nsError = error as NSError
                if nsError.domain == "MusicAssistant" && nsError.code == -1 {
                    print("[PlayerManager] Suppressing timeout error (server likely processed command).")
                    return
                }
                await MainActor.run {
                    self.playbackState = .error("Failed to play: \(error.localizedDescription)")
                }
            }
        }
    }

    func playAudiobook(_ audiobook: Audiobook, startingAtChapter chapterPosition: Int? = nil, startingProgress: TimeInterval? = nil) {
        guard SendspinClient.shared.isConnected else {
            playbackState = .error("Sendspin not connected. Please enable it in Settings.")
            return
        }

        // Store audiobook info
        queue = []
        currentIndex = 0
        currentSource = audiobook.name
        currentAudiobook = audiobook
        currentPodcast = nil

        // Set initial chapter based on progress or position
        if let progress = startingProgress {
            currentChapter = audiobook.chapters.first(where: { progress >= $0.start && progress < $0.end })
        } else if let chapterPosition = chapterPosition {
            currentChapter = audiobook.chapters.first(where: { $0.position == chapterPosition })
        } else {
            currentChapter = audiobook.chapters.first
        }

        // Create a temporary Track representation of the audiobook for compatibility
        // Convert audiobook metadata to track metadata (for artwork)
        let trackMetadata: MediaItemMetadata? = {
            if let audiobookMetadata = audiobook.metadata {
                return MediaItemMetadata(images: audiobookMetadata.images)
            }
            return nil
        }()

        // Prefer narrators for display (shown as "artist"), fallback to authors
        let displayNames = audiobook.narrators ?? audiobook.authors ?? []

        let audiobookAsTrack = Track(
            itemId: audiobook.itemId,
            provider: audiobook.provider,
            name: audiobook.name,
            version: audiobook.version,
            duration: audiobook.duration,
            trackNumber: nil,
            discNumber: nil,
            uri: audiobook.uri,
            artists: displayNames.map { ArtistReference(itemId: nil, provider: nil, name: $0) },
            album: nil,
            metadata: trackMetadata,
            providerMappings: nil,
            image: audiobook.image
        )

        currentTrack = audiobookAsTrack
        currentTime = 0
        duration = audiobook.duration ?? 0
        loadingStartElapsed = 0
        playbackState = .loading
        self.startLoadingTimeout()

        // Update lock screen controls for audiobook
        updateRemoteCommands()

        SendspinClient.shared.stopPlayback()
        stopProgressTimer()
        Task {
            await self.updateNowPlayingInfoAsync()
        }

        // Tell server to play the audiobook
        Task {
            do {
                try await XonoraClient.shared.playMedia(uris: [audiobook.uri])

                // Add audiobook to playback history with initial progress
                let historyItem = PlaybackHistoryItem(
                    contentType: .audiobook,
                    itemId: audiobook.itemId,
                    itemName: audiobook.name, // Fix: Added missing comma on previous line
                    itemUri: audiobook.uri,
                    artistName: audiobook.narratorNames ?? audiobook.authorNames,
                    imageUrl: audiobook.imageUrl,
                    progress: startingProgress ?? 0,
                    duration: audiobook.duration
                )
                await PlaybackHistoryManager.shared.addToHistory(item: historyItem)

                // If a specific progress or chapter is requested, seek to it after playback starts
                if let progress = startingProgress {
                    try? await Task.sleep(for: .seconds(1))
                    await MainActor.run {
                        self.seek(to: progress)
                    }
                } else if let chapterPosition = chapterPosition,
                          let chapter = audiobook.chapters.first(where: { $0.position == chapterPosition }) {
                    // Wait for playback to initialize
                    try? await Task.sleep(for: .seconds(1))
                    await MainActor.run {
                        self.seek(to: chapter.start)
                    }
                }
            } catch {
                let nsError = error as NSError
                if nsError.domain == "MusicAssistant" && nsError.code == -1 {
                    print("[PlayerManager] Suppressing timeout error (server likely processed command).")
                    return
                }
                await MainActor.run {
                    self.playbackState = .error("Failed to play: \(error.localizedDescription)")
                }
            }
        }
    }

    private func updateCurrentChapter(for audiobook: Audiobook, at time: TimeInterval) {
        // Find which chapter we're currently in based on time
        let newChapter = audiobook.chapters.first { chapter in
            time >= chapter.start && time < chapter.end
        }

        if newChapter?.position != currentChapter?.position {
            currentChapter = newChapter
            print("[PlayerManager] Chapter changed to: \(newChapter?.name ?? "nil")")
        }
    }

    func seekToChapter(audiobook: Audiobook, chapter: Chapter) {
        print("[PlayerManager] Seeking to chapter \(chapter.position): \(chapter.name)")
        // If the audiobook is already playing, just seek to the chapter
        if currentTrack?.uri == audiobook.uri {
            seek(to: chapter.start)
        } else {
            // Otherwise, start playing from this chapter
            playAudiobook(audiobook, startingAtChapter: chapter.position)
        }
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        Task { await updateNowPlayingInfoAsync() }
    }

    private func clearNowPlayingInfo() {
        lastTrackId = nil
        cachedArtwork = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func updateNowPlayingInfoAsync() async {
        guard let track = currentTrack else { return }

        var nowPlayingInfo = [String: Any]()

        // For audiobooks with chapters, show chapter name as title
        if let chapter = currentChapter {
            nowPlayingInfo[MPMediaItemPropertyTitle] = chapter.name
            nowPlayingInfo[MPMediaItemPropertyArtist] = track.artistNames
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = track.name // Audiobook name
        } else {
            nowPlayingInfo[MPMediaItemPropertyTitle] = track.name
            nowPlayingInfo[MPMediaItemPropertyArtist] = track.artistNames
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = track.album?.name ?? ""
        }

        await MainActor.run {
            // Use chapter-aware duration and time
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = self.displayDuration
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.displayCurrentTime
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = self.playbackState == .playing ? Double(self.playbackRate) : 0.0
        }

        if track.id != lastTrackId {
            await MainActor.run {
                self.lastTrackId = track.id
                self.cachedArtwork = nil
            }

            if let imageURLString = track.imageUrl ?? track.album?.imageUrl,
               let imageURL = XonoraClient.shared.getImageURL(for: imageURLString, size: .medium) {
                let artwork = await loadArtworkAsync(from: imageURL, trackId: track.id)
                if let artwork = artwork {
                    nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                }
            }
        } else {
            let artwork = await MainActor.run { self.cachedArtwork }
            if let artwork = artwork {
                nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
            }
        }

        await MainActor.run {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        }
    }

    private func loadArtworkAsync(from url: URL, trackId: String) async -> MPMediaItemArtwork? {
        if let cachedImage = await ImageCache.shared.image(for: url) {
            let artwork = MPMediaItemArtwork(boundsSize: cachedImage.size) { _ in cachedImage }
            await MainActor.run {
                guard self.currentTrack?.id == trackId else { return }
                self.cachedArtwork = artwork
            }
            return artwork
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }

            await ImageCache.shared.setImage(image, for: url)

            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            await MainActor.run {
                guard self.currentTrack?.id == trackId else { return }
                self.cachedArtwork = artwork
            }
            return artwork
        } catch {
            print("[PlayerManager] Failed to load artwork: \(error)")
            return nil
        }
    }

    // MARK: - Playback Position Persistence

    private func savePlaybackPosition() {
        guard let track = currentTrack else { return }

        // Save current track URI and position
        UserDefaults.standard.set(track.uri, forKey: savedTrackURIKey)
        UserDefaults.standard.set(currentTime, forKey: savedPositionKey)
        UserDefaults.standard.set(currentSource, forKey: savedSourceKey)

        // Save queue as URIs
        let queueURIs = queue.map { $0.uri }
        UserDefaults.standard.set(queueURIs, forKey: savedQueueKey)
    }

    func restorePlaybackPosition() -> (uri: String, position: TimeInterval)? {
        guard let uri = UserDefaults.standard.string(forKey: savedTrackURIKey) else {
            return nil
        }
        let position = UserDefaults.standard.double(forKey: savedPositionKey)

        // Only restore if position is meaningful (> 3 seconds and not at the end)
        guard position > 3.0 else { return nil }

        return (uri, position)
    }

    func getSavedQueue() -> [String]? {
        return UserDefaults.standard.stringArray(forKey: savedQueueKey)
    }

    func getSavedSource() -> String? {
        return UserDefaults.standard.string(forKey: savedSourceKey)
    }

    func clearSavedPlaybackPosition() {
        UserDefaults.standard.removeObject(forKey: savedTrackURIKey)
        UserDefaults.standard.removeObject(forKey: savedPositionKey)
        UserDefaults.standard.removeObject(forKey: savedQueueKey)
        UserDefaults.standard.removeObject(forKey: savedSourceKey)
    }

    /// Resume playback after reconnection, verifying the server still has the correct track queued.
    /// If the server's queue has drifted (e.g. after a long pause), explicitly restore the saved track.
    /// Handles audio session + SendspinClient setup inline to avoid race conditions with play().
    private func resumeWithSavedTrackVerification() async {
        guard let player = XonoraClient.shared.currentPlayer else {
            print("[PlayerManager] No current player for resume verification")
            play()
            return
        }

        // Get saved track URI — need this even if position is < 3s to verify queue drift
        let savedURI = UserDefaults.standard.string(forKey: savedTrackURIKey)
        let savedPosition = UserDefaults.standard.double(forKey: savedPositionKey)

        guard let savedURI = savedURI else {
            print("[PlayerManager] No saved track URI — sending generic play")
            play()
            return
        }

        // Determine if this was a long pause (> 30 seconds = connection likely dropped and server may have changed state)
        let isLongPause: Bool
        if let pauseTime = pausedAt {
            isLongPause = Date().timeIntervalSince(pauseTime) > 30
        } else {
            isLongPause = true // No pause timestamp means we lost track — treat as long pause
        }

        guard isLongPause else {
            print("[PlayerManager] Short pause — sending generic play")
            play()
            return
        }

        print("[PlayerManager] Long pause detected — verifying server queue matches saved track: \(savedURI)")

        // Step 1: Prepare audio infrastructure for local players (same as play() does)
        if isCurrentPlayerLocal {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setActive(true)
                print("[PlayerManager] Audio session activated for verified resume")
            } catch {
                print("[PlayerManager] Failed to activate audio session: \(error)")
                playbackState = .error("Audio session unavailable")
                return
            }

            if !SendspinClient.shared.isConnected {
                print("[PlayerManager] SendspinClient disconnected, reconnecting...")
                SendspinClient.shared.reconnectIfNeeded()

                var reconnected = false
                for _ in 0..<50 {
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: .milliseconds(100))
                    if SendspinClient.shared.isConnected {
                        print("[PlayerManager] SendspinClient reconnected!")
                        reconnected = true
                        break
                    }
                }

                if !reconnected {
                    print("[PlayerManager] Failed to reconnect SendspinClient")
                    playbackState = .error("Audio connection unavailable")
                    return
                }
            }
        }

        // Step 2: Fetch server queue state and compare with saved track
        do {
            let (currentIndex, _, serverState) = try await XonoraClient.shared.fetchQueueState(for: player.playerId)
            let queueTracks = try await XonoraClient.shared.fetchQueueItems(for: player.playerId)

            let serverCurrentURI: String?
            if currentIndex >= 0 && currentIndex < queueTracks.count {
                serverCurrentURI = queueTracks[currentIndex].uri
            } else {
                serverCurrentURI = nil
            }

            if serverCurrentURI == savedURI {
                // Server still has the correct track — send generic play
                print("[PlayerManager] Server track matches saved track — resuming normally")

                pausedAt = nil
                playbackState = .playing
                startProgressTimer()
                if isCurrentPlayerLocal {
                    SendspinClient.shared.resumePlayback()
                }
                updateNowPlayingInfo()

                lastLocalCommandTime = Date()
                lastLocalCommand = "play"
                userPlayDebounceTask?.cancel()
                userPlayDebounceTask = Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    await MainActor.run {
                        self.lastLocalCommandTime = nil
                        self.lastLocalCommand = nil
                    }
                }

                try await XonoraClient.shared.play()

                // If server was stopped/idle (not just paused), position may have reset — restore it
                if serverState != "paused" && savedPosition > 3.0 {
                    try? await Task.sleep(for: .milliseconds(500))
                    try? await XonoraClient.shared.seek(position: savedPosition)
                    currentTime = savedPosition
                    print("[PlayerManager] Restored position to \(savedPosition)s after server state was: \(serverState)")
                }
            } else {
                // Server queue drifted — explicitly play the saved track
                print("[PlayerManager] Server track (\(serverCurrentURI ?? "nil")) != saved track (\(savedURI)) — restoring saved track via playMedia")

                pausedAt = nil
                playbackState = .loading
                loadingStartTime = Date()
                startLoadingTimeout()

                lastLocalCommandTime = Date()
                lastLocalCommand = "play"
                userPlayDebounceTask?.cancel()
                userPlayDebounceTask = Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    await MainActor.run {
                        self.lastLocalCommandTime = nil
                        self.lastLocalCommand = nil
                    }
                }

                try await XonoraClient.shared.playMedia(uris: [savedURI])

                // Wait for server to start playing, then seek to saved position
                if savedPosition > 3.0 {
                    try? await Task.sleep(for: .seconds(1.5))
                    try? await XonoraClient.shared.seek(position: savedPosition)
                    currentTime = savedPosition
                    print("[PlayerManager] Restored position to \(savedPosition)s after queue drift correction")
                }

                // Note: playbackState will transition from .loading to .playing
                // when the server sends back a queue_updated event via handleQueueUpdate()
            }
        } catch {
            print("[PlayerManager] Failed to verify server queue: \(error) — falling back to generic play")
            pausedAt = nil
            play()
        }
    }

    // MARK: - State Helpers

    var isPlaying: Bool {
        if case .playing = playbackState {
            return true
        }
        return false
    }
    
    var isLoading: Bool {
        if case .loading = playbackState {
            return true
        }
        return false
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    // MARK: - Player Transfer

    func transferPlayback(to player: MAPlayer, resumePlayback: Bool) {
        Task {
            // Save current state
            let savedTrack = currentTrack
            let savedPosition = currentTime > 2.0 ? currentTime : nil
            let savedQueue = queue
            let savedIndex = currentIndex
            let savedSource = currentSource

            print("[PlayerManager] Transferring playback to \(player.name)")
            isTransferringPlayback = true

            // Set user selection flag
            XonoraClient.shared.userSelectedPlayer = true

            // Switch player
            XonoraClient.shared.currentPlayer = player

            // Small delay to let server register the player switch
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s

            if resumePlayback, let track = savedTrack {
                do {
                    // Restore queue and play the track
                    if !savedQueue.isEmpty {
                        // Play the saved track (server will restore queue context)
                        try await XonoraClient.shared.playMedia(uris: [track.uri])

                        // If we had a meaningful position, seek to it after a delay
                        if let position = savedPosition {
                            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s for stream to start
                            try? await XonoraClient.shared.seek(position: position)
                            print("[PlayerManager] Seeked to saved position: \(position)s")
                        }
                    } else {
                        try await XonoraClient.shared.playMedia(uris: [track.uri])
                    }
                } catch {
                    print("[PlayerManager] Failed to resume playback on new player: \(error)")
                }
            } else {
                // Just fetch the new player's queue state without resuming
                await fetchQueueFromServer(for: player)
            }

            // Clear transfer flag after a delay
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
            isTransferringPlayback = false
        }
    }

    func fetchQueueFromServer(for player: MAPlayer) async {
        do {
            // Fetch queue items
            let tracks = try await XonoraClient.shared.fetchQueueItems(for: player.playerId)

            // Fetch queue state
            let (currentIndex, elapsedTime, state) = try await XonoraClient.shared.fetchQueueState(for: player.playerId)

            // Update local state
            queue = tracks
            self.currentIndex = currentIndex
            currentTime = elapsedTime

            // Set current track — only replace if track actually changed.
            // fetchQueueItems returns tracks without full metadata (images, etc.),
            // so blindly overwriting would lose rich metadata from queue_updated events
            // (e.g., mzstatic.com artwork URLs replaced by bare provider URIs).
            if currentIndex >= 0 && currentIndex < tracks.count {
                let fetchedTrack = tracks[currentIndex]
                if currentTrack?.uri != fetchedTrack.uri {
                    currentTrack = fetchedTrack
                }
            }

            // Update playback state based on server state
            switch state {
            case "playing":
                playbackState = .playing
                startProgressTimer()
            case "paused":
                playbackState = .paused
            default:
                playbackState = .stopped
            }

            print("[PlayerManager] Fetched queue for \(player.name): \(tracks.count) tracks, index \(currentIndex)")
        } catch {
            print("[PlayerManager] Failed to fetch queue from server: \(error)")
        }
    }

    // MARK: - Sleep Timer

    func setSleepTimer(minutes: Int) {
        setSleepTimer(seconds: TimeInterval(minutes * 60))
    }

    func setSleepTimer(seconds: TimeInterval) {
        // Cancel any existing timer
        cancelSleepTimer()

        // Set end time
        sleepTimerEndTime = Date().addingTimeInterval(seconds)
        sleepTimerRemaining = seconds

        // Request notification permission
        requestNotificationPermission()

        // Start update loop
        startSleepTimerUpdateLoop()

        print("[PlayerManager] Sleep timer set for \(seconds / 60) minutes")
    }

    func cancelSleepTimer() {
        sleepTimerUpdateTimer?.invalidate()
        sleepTimerUpdateTimer = nil
        sleepTimerEndTime = nil
        sleepTimerRemaining = 0

        // Cancel any scheduled notifications
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["sleepTimer"])
    }

    private func restoreSleepTimer() {
        if let savedEndTime = UserDefaults.standard.object(forKey: "sleepTimerEndTime") as? TimeInterval {
            let endTime = Date(timeIntervalSince1970: savedEndTime)
            let remaining = endTime.timeIntervalSinceNow

            if remaining > 0 {
                sleepTimerEndTime = endTime
                sleepTimerRemaining = remaining
                startSleepTimerUpdateLoop()
                print("[PlayerManager] Restored sleep timer with \(remaining / 60) minutes remaining")
            } else {
                // Timer expired while app was closed
                UserDefaults.standard.removeObject(forKey: "sleepTimerEndTime")
            }
        }
    }

    private func startSleepTimerUpdateLoop() {
        sleepTimerUpdateTimer?.invalidate()

        sleepTimerUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.updateSleepTimerRemaining()
            }
        }
    }

    private func updateSleepTimerRemaining() {
        guard let endTime = sleepTimerEndTime else {
            cancelSleepTimer()
            return
        }

        let remaining = endTime.timeIntervalSinceNow
        if remaining <= 0 {
            sleepTimerFired()
        } else {
            sleepTimerRemaining = remaining
        }
    }

    private func sleepTimerFired() {
        print("[PlayerManager] Sleep timer fired")

        // Stop playback with retry logic
        Task {
            await stopPlaybackWithRetry()
        }

        // Clear timer
        cancelSleepTimer()
    }

    private func stopPlaybackWithRetry(maxAttempts: Int = 3) async {
        for attempt in 1...maxAttempts {
            do {
                try await XonoraClient.shared.pause()
                print("[PlayerManager] Sleep timer paused playback (attempt \(attempt))")
                return
            } catch {
                print("[PlayerManager] Sleep timer pause failed (attempt \(attempt)): \(error)")
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
                }
            }
        }
    }

    private func checkSleepTimerOnForeground() {
        guard let endTime = sleepTimerEndTime else { return }

        let remaining = endTime.timeIntervalSinceNow
        if remaining <= 0 {
            // Timer expired while in background
            sleepTimerFired()
        } else {
            // Update remaining time
            sleepTimerRemaining = remaining
            startSleepTimerUpdateLoop()
        }
    }

    private func scheduleSleepTimerNotification() {
        guard let endTime = sleepTimerEndTime else { return }

        let remaining = endTime.timeIntervalSinceNow
        guard remaining > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Sleep Timer"
        content.body = "Playback has been paused"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
        let request = UNNotificationRequest(identifier: "sleepTimer", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[PlayerManager] Failed to schedule sleep timer notification: \(error)")
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("[PlayerManager] Notification permission error: \(error)")
            }
        }
    }
}

// MARK: - CallKit Integration

extension PlayerManager: CXCallObserverDelegate {
    // CallKit implementation already in main class
}

// MARK: - Lyrics Manager

struct LyricsResult: Codable {
    let lyrics: String?
    let lrcLyrics: String?
}

@MainActor
class LyricsManager: ObservableObject {
    static let shared = LyricsManager()

    // In-memory cache
    private var memoryCache: [String: LyricsResult] = [:]

    // Tasks tracking
    private var activeTasks: [String: Task<LyricsResult, Error>] = [:]

    private var cancellables = Set<AnyCancellable>()
    private let fileManager = FileManager.default

    private init() {
        createCacheDirectory()
        setupQueueObservation()
    }

    private var cacheDirectory: URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("LyricsCache")
    }

    private func createCacheDirectory() {
        guard let url = cacheDirectory else { return }
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Public API
    
    func getLyrics(for track: Track) async throws -> LyricsResult {
        // 1. Check Memory Cache
        if let cached = memoryCache[track.uri] {
            return cached
        }

        // 2. Check Disk Cache
        if let cached = loadFromDisk(for: track) {
            memoryCache[track.uri] = cached
            return cached
        }

        // 3. Check Active Requests (avoid duplicates)
        if let existingTask = activeTasks[track.uri] {
            return try await existingTask.value
        }

        // 4. Fetch from Network
        let task = Task {
            defer { activeTasks.removeValue(forKey: track.uri) }

            // This calls the existing API in XonoraClient
            let (plain, lrc) = try await XonoraClient.shared.fetchLyrics(for: track)

            let result = LyricsResult(lyrics: plain, lrcLyrics: lrc)

            // Only cache if we actually got something
            if plain != nil || lrc != nil {
                self.memoryCache[track.uri] = result
                self.saveToDisk(result, for: track)
            }

            return result
        }

        activeTasks[track.uri] = task
        return try await task.value
    }
    
    // MARK: - Prefetching

    private func setupQueueObservation() {
        // Observe PlayerManager queue changes to trigger prefetch
        // This fires when:
        // 1. currentTrack changes (track advancement)
        // 2. queue changes (new album/playlist loaded)
        PlayerManager.shared.$currentTrack
            .combineLatest(PlayerManager.shared.$queue)
            .removeDuplicates { old, new in
                // Only process if queue or track actually changed
                old.0?.uri == new.0?.uri && old.1.map(\.uri) == new.1.map(\.uri)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentTrack, queue in
                self?.handleQueueUpdate(currentTrack: currentTrack, queue: queue)
            }
            .store(in: &cancellables)

        // Also observe queue additions directly (when tracks are added to queue)
        PlayerManager.shared.$queue
            .removeDuplicates { $0.map(\.uri) == $1.map(\.uri) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] queue in
                self?.prefetchLyricsForQueue(queue)
            }
            .store(in: &cancellables)
    }

    /// Prefetch lyrics for the first N tracks in a queue (called when queue changes)
    private func prefetchLyricsForQueue(_ queue: [Track]) {
        guard !queue.isEmpty else { return }

        // Prefetch first 10 tracks in queue
        let tracksToPrefetch = Array(queue.prefix(10))

        print("[LyricsManager] Prefetching lyrics for \(tracksToPrefetch.count) tracks in queue")

        for track in tracksToPrefetch {
            Task(priority: .background) {
                // Ignore errors during prefetch
                try? await self.getLyrics(for: track)
            }
        }
    }

    private func handleQueueUpdate(currentTrack: Track?, queue: [Track]) {
        guard let currentTrack = currentTrack, !queue.isEmpty else { return }

        // Find current index
        guard let currentIndex = queue.firstIndex(where: { $0.uri == currentTrack.uri }) else { return }

        // Prefetch next 5 items (increased from 3 for better lookahead)
        let nextIndex = currentIndex + 1
        let endIndex = min(nextIndex + 5, queue.count)

        guard nextIndex < endIndex else { return }

        let tracksToPrefetch = Array(queue[nextIndex..<endIndex])

        print("[LyricsManager] Prefetching lyrics for next \(tracksToPrefetch.count) tracks")

        for track in tracksToPrefetch {
            Task(priority: .background) {
                // Ignore errors during prefetch
                try? await getLyrics(for: track)
            }
        }
    }
    
    // MARK: - Disk Cache Helpers

    private func cacheFileURL(for track: Track) -> URL? {
        // Use a safe filename based on URI hash
        let safeName = String(track.uri.hashValue)
        return cacheDirectory?.appendingPathComponent(safeName + ".json")
    }

    private func saveToDisk(_ result: LyricsResult, for track: Track) {
        guard let url = cacheFileURL(for: track) else { return }

        Task.detached(priority: .background) {
            do {
                let data = try JSONEncoder().encode(result)
                try data.write(to: url)
            } catch {
                print("[LyricsManager] Failed to save cache: \(error)")
            }
        }
    }

    private func loadFromDisk(for track: Track) -> LyricsResult? {
        guard let url = cacheFileURL(for: track),
              fileManager.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(LyricsResult.self, from: data)
        } catch {
            return nil
        }
    }

    func clearCache() {
        memoryCache.removeAll()
        guard let url = cacheDirectory else { return }
        try? fileManager.removeItem(at: url)
        createCacheDirectory()
    }
}
