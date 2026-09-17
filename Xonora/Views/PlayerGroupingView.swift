import SwiftUI

struct PlayerGroupingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var xonoraClient: XonoraClient

    let leaderPlayer: MAPlayer
    @State private var selectedPlayerIds: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var currentlyGrouped: Set<String> = []
    
    var body: some View {
        NavigationStack {
            VStack {
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                }
                
                List {
                    Section {
                        HStack {
                            Image(systemName: "music.note.house.fill")
                                .foregroundColor(.accentColor)
                            Text(leaderPlayer.name)
                                .font(.headline)
                            Spacer()
                            Text("Leader")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    } header: {
                        Text("Group Leader")
                    } footer: {
                        Text("Audio will play on this device and sync to selected members.")
                    }
                    
                    Section("Group Members") {
                        if availablePlayers.isEmpty {
                            Text("No other players available to group.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(availablePlayers) { player in
                                Button {
                                    toggleSelection(for: player)
                                } label: {
                                    HStack {
                                        Image(systemName: getIconName(for: player))
                                            .foregroundColor(.secondary)

                                        VStack(alignment: .leading) {
                                            HStack {
                                                Text(player.name)
                                                    .foregroundColor(.primary)
                                                if currentlyGrouped.contains(player.id) {
                                                    Image(systemName: "checkmark.seal.fill")
                                                        .font(.caption2)
                                                        .foregroundColor(.green)
                                                    Text("Currently grouped")
                                                        .font(.caption2)
                                                        .foregroundColor(.green)
                                                }
                                            }
                                            if let syncedTo = player.syncedTo, syncedTo != leaderPlayer.id {
                                                Text("Synced to another group")
                                                    .font(.caption)
                                                    .foregroundColor(.orange)
                                            }
                                        }

                                        Spacer()

                                        if selectedPlayerIds.contains(player.id) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.accentColor)
                                                .font(.title3)
                                        } else {
                                            Image(systemName: "circle")
                                                .foregroundColor(.secondary)
                                                .font(.title3)
                                        }
                                    }
                                }
                                .disabled(isLoading)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Speaker Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                if !currentlyGrouped.isEmpty {
                    ToolbarItem(placement: .secondaryAction) {
                        Button(role: .destructive) {
                            ungroupAll()
                        } label: {
                            Label("Ungroup All", systemImage: "xmark.circle.fill")
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Apply") {
                            applyGroupChanges()
                        }
                        .disabled(selectedPlayerIds == Set(leaderPlayer.groupChilds ?? []))
                    }
                }
            }
            .onAppear {
                // Initialize selection with current group members
                // Get fresh player state from xonoraClient to ensure we have latest groupChilds
                let freshLeader = xonoraClient.players.first { $0.id == leaderPlayer.id } ?? leaderPlayer
                let groupedMembers = freshLeader.groupChilds ?? []
                selectedPlayerIds = Set(groupedMembers)
                currentlyGrouped = Set(groupedMembers)
            }
        }
    }
    
    // Filter out the leader and unavailable players
    var availablePlayers: [MAPlayer] {
        xonoraClient.players.filter { player in
            player.id != leaderPlayer.id && player.available
        }
    }
    
    private func getIconName(for player: MAPlayer) -> String {
        // Simple icon logic based on name or provider, can be improved
        if player.name.lowercased().contains("tv") { return "tv" }
        if player.name.lowercased().contains("homepod") { return "hifispeaker.fill" }
        if player.name.lowercased().contains("sonos") { return "speaker.wave.2.fill" }
        if player.name.lowercased().contains("phone") { return "iphone" }
        return "speaker.fill"
    }
    
    private func toggleSelection(for player: MAPlayer) {
        if selectedPlayerIds.contains(player.id) {
            selectedPlayerIds.remove(player.id)
        } else {
            selectedPlayerIds.insert(player.id)
        }
    }

    private func ungroupAll() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await xonoraClient.ungroupPlayer(playerId: leaderPlayer.id)

                // Wait briefly and refresh player state
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                await xonoraClient.fetchPlayers(isSilent: false)

                // Clear selections
                await MainActor.run {
                    selectedPlayerIds.removeAll()
                    currentlyGrouped.removeAll()
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Failed to ungroup: \(error.localizedDescription)"
                }
            }
        }
    }

    private func applyGroupChanges() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                // Filter out leader from selection (safety check - shouldn't happen with UI but be defensive)
                let validMembers = Array(selectedPlayerIds.filter { $0 != leaderPlayer.id })

                // If the list is empty, ungroup the leader
                if validMembers.isEmpty {
                    if (leaderPlayer.groupChilds ?? []).isEmpty == false {
                         try await xonoraClient.ungroupPlayer(playerId: leaderPlayer.id)
                    }
                } else {
                    try await xonoraClient.groupPlayers(leaderId: leaderPlayer.id, memberIds: validMembers)

                    // Wait briefly and refresh player state
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    await xonoraClient.fetchPlayers(isSilent: false)
                }

                // Success
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Failed to update group: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    PlayerGroupingView(leaderPlayer: MAPlayer(
        playerId: "1",
        provider: "sonos",
        name: "Living Room",
        type: "speaker",
        available: true,
        state: nil,
        volume: 50,
        currentMedia: nil,
        queueId: nil,
        groupChilds: ["2"],
        syncedTo: nil
    ))
    .environmentObject(XonoraClient.shared)
}
