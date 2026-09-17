import SwiftUI
import MediaPlayer

struct PlayerControls: View {
    @ObservedObject var playerManager: PlayerManager
    @ObservedObject private var xonoraClient = XonoraClient.shared
    @ObservedObject private var sendspinClient = SendspinClient.shared
    @Environment(\.npScale) private var scale

    @State private var showDeviceSwitcher = false
    @State private var isDraggingVolume = false
    @State private var localVolume: Double = 0

    let size: ControlSize
    var showDestination: Bool = true

    enum ControlSize {
        case compact
        case full
    }

    var body: some View {
        switch size {
        case .compact:
            compactControls
        case .full:
            fullControls
        }
    }

    private var isLocalPlayer: Bool {
        guard let currentId = xonoraClient.currentPlayer?.playerId,
              let localId = sendspinClient.clientId else {
            return false
        }
        return currentId == localId
    }

    private var playerDisplayName: String {
        guard let player = xonoraClient.currentPlayer else { return "Unknown" }
        if let memberCount = player.groupChilds?.count, memberCount > 0 {
            return "\(player.name) + \(memberCount)"
        }
        if let syncedTo = player.syncedTo,
           let leader = xonoraClient.players.first(where: { $0.playerId == syncedTo }) {
            return "\(player.name) (\u{2192} \(leader.name))"
        }
        return player.name
    }

    // MARK: - Compact Controls (mini-bar, unchanged)

    private var compactControls: some View {
        HStack(spacing: 24) {
            if playerManager.isPlayingRadio {
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    playerManager.stop()
                } label: {
                    if playerManager.isLoading {
                        ProgressView().scaleEffect(0.9).frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "stop.fill").font(.title2)
                    }
                }
                .disabled(playerManager.isLoading)
            } else {
                Button {
                    if playerManager.isPlayingAudiobook { playerManager.skipBackward(seconds: 15) }
                    else { playerManager.previous() }
                } label: {
                    Image(systemName: playerManager.isPlayingAudiobook ? "gobackward.15" : "backward.fill")
                        .font(.title3)
                }

                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    playerManager.togglePlayPause()
                } label: {
                    if playerManager.isLoading {
                        ProgressView().scaleEffect(0.9).frame(width: 28, height: 28)
                    } else {
                        Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                    }
                }
                .disabled(playerManager.isLoading)

                Button {
                    if playerManager.isPlayingAudiobook { playerManager.skipForward(seconds: 15) }
                    else { playerManager.next() }
                } label: {
                    Image(systemName: playerManager.isPlayingAudiobook ? "goforward.15" : "forward.fill")
                        .font(.title3)
                }
            }
        }
        .foregroundColor(.primary)
    }

    // MARK: - Full Controls (scales with npScale)

    private var fullControls: some View {
        let s = scale
        let playBtnSize: CGFloat = max(44, 64 * s)
        let skipIconSize: CGFloat = max(18, 24 * s)
        let sideIconSize: CGFloat = max(14, 18 * s)
        let timeFont: Font = .system(size: max(10, 12 * s))
        let sectionSpacing: CGFloat = max(12, 24 * s)

        return VStack(spacing: sectionSpacing) {
            // Progress bar (hidden for radio)
            if !playerManager.isPlayingRadio {
                VStack(spacing: 4) {
                    if playerManager.isLoading {
                        LoadingProgressSlider()
                    } else {
                        ProgressSlider(
                            value: Binding(
                                get: {
                                    if let chapter = playerManager.currentChapter {
                                        return chapter.start + playerManager.displayCurrentTime
                                    }
                                    return playerManager.displayCurrentTime
                                },
                                set: { playerManager.seek(to: $0) }
                            ),
                            range: {
                                if let chapter = playerManager.currentChapter {
                                    return chapter.start...chapter.end
                                }
                                return 0...max(playerManager.displayDuration, 1)
                            }()
                        )
                    }

                    HStack {
                        if playerManager.isLoading {
                            Text("Loading...")
                                .font(timeFont)
                                .foregroundColor(.accentColor)
                        } else {
                            Text(formatTime(playerManager.displayCurrentTime))
                                .font(timeFont)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if !playerManager.isLoading {
                            Text("-\(formatTime(playerManager.displayDuration - playerManager.displayCurrentTime))")
                                .font(timeFont)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Main controls
            if playerManager.isPlayingRadio {
                HStack {
                    Spacer()
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        playerManager.stop()
                    } label: {
                        if playerManager.isLoading {
                            ProgressView()
                                .scaleEffect(s > 0.9 ? 1.5 : 1.2)
                                .frame(width: playBtnSize, height: playBtnSize)
                        } else {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: playBtnSize))
                                .foregroundColor(.primary)
                        }
                    }
                    .disabled(playerManager.isLoading)
                    .accessibilityLabel("Stop radio")
                    Spacer()
                }
            } else {
                HStack(spacing: max(20, 40 * s)) {
                    // Shuffle
                    if !playerManager.isPlayingAudiobook {
                        Button { playerManager.toggleShuffle() } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: sideIconSize))
                                .foregroundColor(playerManager.shuffleEnabled ? .accentColor : .secondary)
                        }
                    } else {
                        Color.clear.frame(width: sideIconSize, height: sideIconSize)
                    }

                    // Previous / Skip back
                    Button {
                        if playerManager.isPlayingAudiobook { playerManager.skipBackward(seconds: 15) }
                        else { playerManager.previous() }
                    } label: {
                        Image(systemName: playerManager.isPlayingAudiobook ? "gobackward.15" : "backward.fill")
                            .font(.system(size: skipIconSize))
                            .foregroundColor(.primary)
                    }

                    // Play / Pause
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        playerManager.togglePlayPause()
                    } label: {
                        if playerManager.isLoading {
                            ProgressView()
                                .scaleEffect(s > 0.9 ? 1.5 : 1.2)
                                .frame(width: playBtnSize, height: playBtnSize)
                        } else {
                            Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: playBtnSize))
                                .foregroundColor(.primary)
                        }
                    }
                    .disabled(playerManager.isLoading)

                    // Next / Skip forward
                    Button {
                        if playerManager.isPlayingAudiobook { playerManager.skipForward(seconds: 15) }
                        else { playerManager.next() }
                    } label: {
                        Image(systemName: playerManager.isPlayingAudiobook ? "goforward.15" : "forward.fill")
                            .font(.system(size: skipIconSize))
                            .foregroundColor(.primary)
                    }

                    // Repeat
                    if !playerManager.isPlayingAudiobook {
                        Button { playerManager.cycleRepeatMode() } label: {
                            repeatModeIcon
                                .font(.system(size: sideIconSize))
                                .foregroundColor(playerManager.repeatMode != .off ? .accentColor : .secondary)
                        }
                    } else {
                        Color.clear.frame(width: sideIconSize, height: sideIconSize)
                    }
                }
            }

            // Volume + destination
            VStack(spacing: max(12, 20 * s)) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: max(9, 11 * s)))
                        .foregroundColor(.secondary)
                        .frame(height: 20)

                    if isLocalPlayer {
                        VolumeView().frame(height: 20)
                    } else {
                        Slider(
                            value: Binding(
                                get: { isDraggingVolume ? localVolume : Double(playerManager.volume) },
                                set: { localVolume = $0 }
                            ),
                            in: 0...1,
                            onEditingChanged: { editing in
                                if editing { localVolume = Double(playerManager.volume) }
                                else { playerManager.setVolume(Float(localVolume)) }
                                isDraggingVolume = editing
                            }
                        )
                        .tint(.secondary)
                        .frame(height: 20)
                    }

                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: max(9, 11 * s)))
                        .foregroundColor(.secondary)
                        .frame(height: 20)
                }

                // Playback Destination
                if showDestination, xonoraClient.currentPlayer != nil {
                    Button { showDeviceSwitcher = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isLocalPlayer ? "iphone" : "speaker.wave.2.fill")
                                .font(.system(size: max(10, 12 * s)))
                            Text(playerDisplayName)
                                .font(.system(size: max(10, 12 * s), weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: max(8, 10 * s)))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 14 * s)
                        .padding(.vertical, 8 * s)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showDeviceSwitcher) {
                        DeviceSwitcherView()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var repeatModeIcon: some View {
        switch playerManager.repeatMode {
        case .off:  Image(systemName: "repeat")
        case .all:  Image(systemName: "repeat")
        case .one:  Image(systemName: "repeat.1")
        }
    }

}

// MARK: - Progress Slider

struct ProgressSlider: View {
    @Binding var value: TimeInterval
    let range: ClosedRange<TimeInterval>

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 4)
                Capsule()
                    .fill(Color.primary)
                    .frame(width: progressWidth(in: geometry.size.width), height: 4)
                Circle()
                    .fill(Color.primary)
                    .frame(width: isDragging ? 12 : 0, height: isDragging ? 12 : 0)
                    .offset(x: thumbOffset(in: geometry.size.width))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let pct = gesture.location.x / geometry.size.width
                        value = range.lowerBound + (range.upperBound - range.lowerBound) * max(0, min(1, Double(pct)))
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: 20)
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return max(0, min(totalWidth, CGFloat((value - range.lowerBound) / span) * totalWidth))
    }

    private func thumbOffset(in totalWidth: CGFloat) -> CGFloat {
        progressWidth(in: totalWidth) - 6
    }
}

// MARK: - System Volume

struct VolumeView: UIViewRepresentable {
    #if os(iOS)
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView()
        v.showsVolumeSlider = true
        return v
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
    #else
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ uiView: UIView, context: Context) {}
    #endif
}

// MARK: - Loading Progress Slider

struct LoadingProgressSlider: View {
    @State private var animationOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 4)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.primary.opacity(0), .primary.opacity(0.6), .primary.opacity(0)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * 0.3, height: 4)
                    .offset(x: geometry.size.width * animationOffset)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    animationOffset = 0.7
                }
            }
        }
        .frame(height: 20)
    }
}

// MARK: - Standalone Destination Pill (for bottom-anchored placement)

struct PlayerDestinationButton: View {
    @ObservedObject private var xonoraClient = XonoraClient.shared
    @ObservedObject private var sendspinClient = SendspinClient.shared
    @Environment(\.npScale) private var scale
    @State private var showDeviceSwitcher = false

    private var isLocalPlayer: Bool {
        guard let currentId = xonoraClient.currentPlayer?.playerId,
              let localId = sendspinClient.clientId else {
            return false
        }
        return currentId == localId
    }

    private var playerDisplayName: String {
        guard let player = xonoraClient.currentPlayer else { return "Unknown" }
        if let memberCount = player.groupChilds?.count, memberCount > 0 {
            return "\(player.name) + \(memberCount)"
        }
        if let syncedTo = player.syncedTo,
           let leader = xonoraClient.players.first(where: { $0.playerId == syncedTo }) {
            return "\(player.name) (\u{2192} \(leader.name))"
        }
        return player.name
    }

    var body: some View {
        let s = scale
        if xonoraClient.currentPlayer != nil {
            Button { showDeviceSwitcher = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: isLocalPlayer ? "iphone" : "speaker.wave.2.fill")
                        .font(.system(size: max(10, 12 * s)))
                    Text(playerDisplayName)
                        .font(.system(size: max(10, 12 * s), weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: max(8, 10 * s)))
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 14 * s)
                .padding(.vertical, 8 * s)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDeviceSwitcher) {
                DeviceSwitcherView()
            }
        }
    }
}

struct PlayerControls_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            PlayerControls(playerManager: PlayerManager.shared, size: .compact)
            PlayerControls(playerManager: PlayerManager.shared, size: .full)
                .padding()
        }
    }
}
