import SwiftUI
import MediaPlayer

struct PlayerControls: View {
    @ObservedObject var playerManager: PlayerManager
    @ObservedObject private var xonoraClient = XonoraClient.shared
    @ObservedObject private var sendspinClient = SendspinClient.shared
    
    let size: ControlSize

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
        // If we are playing on this device (Sendspin), show system volume slider
        guard let currentId = xonoraClient.currentPlayer?.playerId,
              let localId = sendspinClient.clientId else {
            return false
        }
        return currentId == localId
    }

    private var compactControls: some View {
        HStack(spacing: 24) {
            Button {
                playerManager.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title3)
            }

            Button {
                playerManager.togglePlayPause()
            } label: {
                Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }

            Button {
                playerManager.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
            }
        }
        .foregroundColor(.primary)
    }

    private var fullControls: some View {
        VStack(spacing: 24) {
            // Progress bar
            VStack(spacing: 4) {
                ProgressSlider(
                    value: Binding(
                        get: { playerManager.currentTime },
                        set: { playerManager.seek(to: $0) }
                    ),
                    range: 0...max(playerManager.duration, 1)
                )

                HStack {
                    Text(formatTime(playerManager.currentTime))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("-\(formatTime(playerManager.duration - playerManager.currentTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Main controls
            HStack(spacing: 40) {
                Button {
                    playerManager.toggleShuffle()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.title3)
                        .foregroundColor(playerManager.shuffleEnabled ? .accentColor : .secondary)
                }

                Button {
                    playerManager.previous()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title)
                        .foregroundColor(.primary)
                }

                Button {
                    playerManager.togglePlayPause()
                } label: {
                    Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.primary)
                }

                Button {
                    playerManager.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title)
                        .foregroundColor(.primary)
                }

                Button {
                    playerManager.cycleRepeatMode()
                } label: {
                    repeatModeIcon
                        .font(.title3)
                        .foregroundColor(playerManager.repeatMode != .off ? .accentColor : .secondary)
                }
            }

            // Volume slider and destination
            VStack(spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "speaker.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if isLocalPlayer {
                        VolumeView()
                            .frame(height: 30) // Match standard slider height
                    } else {
                        Slider(
                            value: Binding(
                                get: { Double(playerManager.volume) },
                                set: { playerManager.setVolume(Float($0)) }
                            ),
                            in: 0...1
                        )
                        .tint(.secondary)
                    }

                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Playback Destination
                if !xonoraClient.players.filter({ $0.available }).isEmpty {
                    Menu {
                        ForEach(xonoraClient.players.filter { $0.available }) { player in
                            Button {
                                print("[PlayerControls] User selected player: \(player.name) (id: \(player.playerId))")
                                // Use transferPlayback to properly switch players and continue playback
                                playerManager.transferPlayback(to: player, resumePlayback: true)
                            } label: {
                                HStack {
                                    Image(systemName: player.provider == "sendspin" ? "iphone" : "speaker.wave.2")
                                    Text(player.name)
                                    if player.playerId == xonoraClient.currentPlayer?.playerId {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isLocalPlayer ? "iphone" : "speaker.wave.2.fill")
                                .font(.caption)
                            Text(xonoraClient.currentPlayer?.name ?? "Select Player")
                                .font(.caption)
                                .fontWeight(.medium)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                    }
                } else if xonoraClient.connectionState == .connected {
                    Text("No players available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var repeatModeIcon: some View {
        switch playerManager.repeatMode {
        case .off:
            Image(systemName: "repeat")
        case .all:
            Image(systemName: "repeat")
        case .one:
            Image(systemName: "repeat.1")
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && !time.isNaN else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct ProgressSlider: View {
    @Binding var value: TimeInterval
    let range: ClosedRange<TimeInterval>

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 4)

                // Progress track
                Capsule()
                    .fill(Color.primary)
                    .frame(width: progressWidth(in: geometry.size.width), height: 4)

                // Thumb (only visible when dragging)
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
                        let percentage = gesture.location.x / geometry.size.width
                        let newValue = range.lowerBound + (range.upperBound - range.lowerBound) * max(0, min(1, Double(percentage)))
                        value = newValue
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(height: 20)
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        let rangeSpan = range.upperBound - range.lowerBound
        guard rangeSpan > 0 else { return 0 }
        let percentage = (value - range.lowerBound) / rangeSpan
        return max(0, min(totalWidth, CGFloat(percentage) * totalWidth))
    }

    private func thumbOffset(in totalWidth: CGFloat) -> CGFloat {
        progressWidth(in: totalWidth) - 6
    }
}

struct VolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView()
        volumeView.showsVolumeSlider = true
        // Tinting is handled by system appearance mostly, but we can try to style if needed
        return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
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
