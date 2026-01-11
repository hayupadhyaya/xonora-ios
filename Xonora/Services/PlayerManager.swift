import Foundation
import AVFoundation
import MediaPlayer
import Combine

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
class PlayerManager: ObservableObject {
    @Published var playbackState: PlaybackState = .stopped
    @Published var currentTrack: Track?
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var queue: [Track] = []
    @Published var currentIndex: Int = 0
    @Published var shuffleEnabled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Float = 1.0

    private var progressTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastTrackId: String?
    private var cachedArtwork: MPMediaItemArtwork?

    // Prevent queue advancement race conditions
    private var isUserInitiatedPlay = false
    private var userPlayDebounceTask: Task<Void, Never>?

    static let shared = PlayerManager()

    init() {
        setupRemoteCommandCenter()
        setupNotifications()

        SendspinClient.shared.$isBuffering
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isBuffering in
                guard let self = self else { return }
                if !isBuffering && self.playbackState == .loading {
                    self.playbackState = .playing
                    self.startProgressTimer()
                    print("[PlayerManager] Playback started, progress timer enabled")
                }
            }
            .store(in: &cancellables)
    }
    
    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.playbackState == .playing {
                    self.currentTime += 1
                    if self.duration > 0 && self.currentTime >= self.duration {
                        // Handle end? Server usually sends event.
                    }
                    // Only update now playing info periodically (every 5 seconds) to reduce lock screen thrashing
                    // or when the track changes. The system handles the elapsed time advancement if we set the rate.
                    if Int(self.currentTime) % 5 == 0 {
                        self.updateNowPlayingInfo()
                    }
                }
            }
        }
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
                self?.pause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
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

    // MARK: - Notifications

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .queueUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self, let userInfo = notification.userInfo else { return }

                // Ignore events during user-initiated play to prevent race conditions
                if self.isUserInitiatedPlay {
                    // Still update duration if available
                    if let currentItem = userInfo["current_item"] as? [String: Any],
                       let duration = currentItem["duration"] as? Int {
                        self.duration = TimeInterval(duration)
                    }
                    return
                }

                if let elapsed = userInfo["elapsed_time"] as? Double {
                    self.currentTime = elapsed
                }

                if let stateStr = userInfo["state"] as? String {
                    if stateStr == "playing" {
                        self.playbackState = .playing
                        self.startProgressTimer()
                        SendspinClient.shared.resumePlayback()
                    } else if stateStr == "paused" {
                        self.playbackState = .paused
                        self.stopProgressTimer()
                        SendspinClient.shared.pausePlayback()
                    } else if stateStr == "idle" {
                        // Only handle track ended if we were actually playing
                        if self.playbackState == .playing {
                            self.handleTrackEnded()
                            SendspinClient.shared.stopPlayback()
                        }
                    } else {
                        self.playbackState = .stopped
                        self.stopProgressTimer()
                        SendspinClient.shared.stopPlayback()
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
                            let track = try JSONDecoder().decode(Track.self, from: data)
                            if self.currentTrack?.uri != track.uri {
                                print("[PlayerManager] Server advanced to next track: \(track.name)")
                                self.currentTrack = track
                                self.currentTime = 0
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
            .store(in: &cancellables)
    }

    private func handleTrackEnded() {
        // Don't auto-advance - let server handle queue
        // We only update UI state here
        playbackState = .stopped
        stopProgressTimer()
        print("[PlayerManager] Track ended")
    }



    // MARK: - Playback Control

    func playTrack(_ track: Track, fromQueue tracks: [Track]? = nil) {
        if let tracks = tracks {
            queue = tracks
            currentIndex = tracks.firstIndex(where: { $0.id == track.id }) ?? 0
        }

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

        // Set debounce flag to ignore server events temporarily
        isUserInitiatedPlay = true
        userPlayDebounceTask?.cancel()
        userPlayDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            await MainActor.run {
                self.isUserInitiatedPlay = false
            }
        }

        currentTrack = track
        currentTime = 0
        duration = track.duration ?? 0
        playbackState = .loading

        SendspinClient.shared.stopPlayback()
        stopProgressTimer()
        Task {
            await self.updateNowPlayingInfoAsync()
        }

        // Prepare URIs to play (current track + subsequent queue items)
        let uris: [String]
        if !queue.isEmpty && currentIndex < queue.count {
            uris = Array(queue[currentIndex..<queue.count]).map { $0.uri }
        } else {
            uris = [track.uri]
        }

        // Tell server to play this track
        Task {
            do {
                try await XonoraClient.shared.playMedia(uris: uris)
            } catch {
                print("[PlayerManager] Failed to send play command: \(error)")
                await MainActor.run {
                    self.playbackState = .error("Failed to play: \(error.localizedDescription)")
                }
            }
        }
    }

    func play() {
        Task {
            try? await XonoraClient.shared.play()
        }
    }

    func pause() {
        Task {
            try? await XonoraClient.shared.pause()
        }
    }

    func togglePlayPause() {
        Task {
            try? await XonoraClient.shared.playPause()
        }
    }

    func stop() {
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

        if shuffleEnabled {
            currentIndex = Int.random(in: 0..<queue.count)
        } else {
            currentIndex = (currentIndex + 1) % queue.count
        }

        let nextTrack = queue[currentIndex]
        playTrack(nextTrack)
    }

    func previous() {
        guard !queue.isEmpty else { return }

        if shuffleEnabled {
            currentIndex = Int.random(in: 0..<queue.count)
        }
        else {
            currentIndex = currentIndex > 0 ? currentIndex - 1 : queue.count - 1
        }

        let previousTrack = queue[currentIndex]
        playTrack(previousTrack)
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

    func setVolume(_ newVolume: Float) {
        volume = newVolume
        if SendspinClient.shared.isConnected {
            Task { try? await XonoraClient.shared.setVolume(Int(newVolume * 100)) }
        }
    }

    func toggleShuffle() {
        shuffleEnabled.toggle()
        Task { try? await XonoraClient.shared.setShuffle(enabled: shuffleEnabled) }
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

    // MARK: - Queue Management

    func addToQueue(_ track: Track) {
        queue.append(track)
    }

    func addToQueue(_ tracks: [Track]) {
        queue.append(contentsOf: tracks)
    }

    func playNext(_ track: Track) {
        queue.insert(track, at: currentIndex + 1)
    }

    func clearQueue() {
        queue.removeAll()
        currentIndex = 0
    }

    func playAlbum(_ tracks: [Track], startingAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        queue = tracks
        currentIndex = index
        playTrack(tracks[index])
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
        nowPlayingInfo[MPMediaItemPropertyTitle] = track.name
        nowPlayingInfo[MPMediaItemPropertyArtist] = track.artistNames
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = track.album?.name ?? ""

        await MainActor.run {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = self.duration
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.currentTime
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = self.playbackState == .playing ? 1.0 : 0.0
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

    // MARK: - State Helpers

    var isPlaying: Bool {
        if case .playing = playbackState {
            return true
        }
        return false
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
}
