//
//  WatchDevicesView.swift
//  XonoraWatch
//
//  Multi-device control view - key feature that allows controlling any player in the system.
//

import SwiftUI

struct WatchDevicesView: View {
    @EnvironmentObject var dataProvider: WatchConnectivityProvider

    var body: some View {
        List {
            if dataProvider.playersSnapshot.players.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "hifispeaker.2")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)

                    Text("No Devices")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredPlayers) { player in
                    PlayerRowView(player: player)
                }
            }
        }
        .navigationTitle("Devices")
    }

    // Filter out group members based on user preference
    // For now, showing all players (Option B: show members indented)
    private var filteredPlayers: [WatchPlayerInfo] {
        dataProvider.playersSnapshot.players
    }
}

struct PlayerRowView: View {
    @EnvironmentObject var dataProvider: WatchConnectivityProvider
    let player: WatchPlayerInfo

    var body: some View {
        Button {
            Task {
                await dataProvider.switchPlayer(playerId: player.playerId)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // Player name and status
                HStack {
                    Image(systemName: deviceIcon)
                        .foregroundColor(player.isSelected ? .accentColor : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(player.name)
                                .font(.headline)
                                .foregroundColor(player.isSelected ? .accentColor : .primary)

                            if player.isGroupLeader {
                                Text("GROUP")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor)
                                    .clipShape(Capsule())
                            }
                        }

                        // Group member indicator
                        if player.isGroupMember {
                            Text("Part of group")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }

                    Spacer()

                    // Playback state indicator
                    if player.isPlaying {
                        Image(systemName: "waveform")
                            .foregroundColor(.accentColor)
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                    }
                }

                // Currently playing track (if any)
                if let track = player.currentTrack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text(track.artistNames)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.leading, 24)
                } else if !player.available {
                    Text("Offline")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 24)
                } else if player.playbackState == "idle" {
                    Text("Idle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 24)
                }

                // Inline play/pause button for non-selected players (only if not a group member)
                if !player.isSelected && !player.isGroupMember && player.available {
                    HStack {
                        Spacer()

                        Button {
                            Task {
                                await dataProvider.sendCommand(.playPause, payload: ["playerId": player.playerId])
                            }
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var deviceIcon: String {
        switch player.provider.lowercased() {
        case let p where p.contains("sonos"):
            return "hifispeaker.fill"
        case let p where p.contains("airplay"):
            return "airplayaudio"
        case let p where p.contains("chromecast"):
            return "tv.fill"
        case let p where p.contains("sendspin"):
            return "iphone"
        default:
            if player.isGroupLeader {
                return "hifispeaker.2.fill"
            }
            return "speaker.wave.2.fill"
        }
    }
}

#if DEBUG
#Preview {
    WatchDevicesView()
        .environmentObject(WatchConnectivityProvider.previewPlaying)
}
#endif
