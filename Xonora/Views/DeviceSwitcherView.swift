import SwiftUI

struct DeviceSwitcherView: View {
    @ObservedObject private var xonoraClient = XonoraClient.shared
    @ObservedObject private var multiDeviceManager = MultiDeviceManager.shared
    @ObservedObject private var prefs = UserPreferences.shared
    @Environment(\.dismiss) private var dismiss

    // MARK: - Computed Properties for Hierarchy

    private var memberPlayerIds: Set<String> {
        let groupChildren = Set(xonoraClient.players.flatMap { $0.groupChilds ?? [] })
        let syncedMembers = Set(xonoraClient.players.compactMap { player in
            player.syncedTo != nil ? player.playerId : nil
        })
        return groupChildren.union(syncedMembers)
    }

    /// Returns member players for a given group leader
    private func members(of leader: MAPlayer) -> [MAPlayer] {
        let childIds = Set(leader.groupChilds ?? [])
        return xonoraClient.players.filter { player in
            childIds.contains(player.playerId) || player.syncedTo == leader.playerId
        }
    }

    /// Playback priority: active=0, idle/other=1, offline=2
    private func playbackPriority(_ player: MAPlayer) -> Int {
        guard player.available else { return 2 }
        switch multiDeviceManager.state(for: player.playerId)?.playbackState {
        case .playing, .paused, .loading: return 0  // loading = active, keep position stable
        default: return 1
        }
    }

    private var sortOrder: PlayerSortOrder {
        if prefs.playerSortOrder == "activefirst" || prefs.playerSortOrder == "alphabetical" {
            return .nameAsc
        }
        return PlayerSortOrder(rawValue: prefs.playerSortOrder) ?? .nameAsc
    }

    private func sorted(_ players: [MAPlayer]) -> [MAPlayer] {
        return players.sorted {
            let pa = playbackPriority($0)
            let pb = playbackPriority($1)

            if pa != pb {
                return pa < pb
            }

            // Same priority: use name sort order first
            let nameComp: Bool
            switch sortOrder {
            case .nameAsc:
                nameComp = $0.name < $1.name
            case .nameDesc:
                nameComp = $0.name > $1.name
            }

            if $0.name != $1.name {
                return nameComp
            }

            // Same priority + same name: stable sort by playerId
            return $0.playerId < $1.playerId
        }
    }

    /// Top-level players sorted: group leaders + sync leaders + standalone, ordered by preference
    private var topLevelPlayers: [MAPlayer] {
        let syncLeaderIds = Set(xonoraClient.players.compactMap { $0.syncedTo })
        let leaders = xonoraClient.players.filter {
            ($0.groupChilds?.count ?? 0) > 0 || syncLeaderIds.contains($0.playerId)
        }
        let standalones = xonoraClient.players.filter { player in
            !memberPlayerIds.contains(player.playerId) &&
            (player.groupChilds?.isEmpty ?? true) &&
            !syncLeaderIds.contains(player.playerId)  // not a sync leader either
        }
        return sorted(leaders + standalones)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if xonoraClient.players.isEmpty {
                    emptyStateView
                } else {
                    deviceListView
                }
            }
            .navigationTitle("Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        ForEach(PlayerSortOrder.allCases, id: \.rawValue) { option in
                            Button {
                                prefs.playerSortOrder = option.rawValue
                            } label: {
                                Label(option.label, systemImage: option.icon)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle\(sortOrder == .nameAsc ? "" : ".fill")")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Devices Available",
            systemImage: "speaker.slash.fill",
            description: Text("Connect to Music Assistant to see available players")
        )
    }

    private var deviceListView: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(topLevelPlayers) { player in
                    let isLeader = (player.groupChilds?.count ?? 0) > 0
                    if isLeader {
                        GroupLeaderRow(
                            player: player,
                            memberCount: player.groupChilds?.count ?? 0,
                            state: multiDeviceManager.state(for: player.playerId),
                            isSelected: player.playerId == xonoraClient.currentPlayer?.playerId,
                            onTap: { selectPlayer(player) }
                        )
                        ForEach(members(of: player)) { member in
                            GroupMemberRow(
                                player: member,
                                leaderName: player.name,
                                state: multiDeviceManager.state(for: member.playerId),
                                isSelected: member.playerId == xonoraClient.currentPlayer?.playerId,
                                onTap: { selectPlayer(member) }
                            )
                        }
                    } else {
                        DeviceRow(
                            player: player,
                            state: multiDeviceManager.state(for: player.playerId),
                            isSelected: player.playerId == xonoraClient.currentPlayer?.playerId,
                            onTap: { selectPlayer(player) }
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .animation(.none, value: multiDeviceManager.playerStates)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func selectPlayer(_ player: MAPlayer) {
        // Use setPreferredPlayer to save user's explicit choice
        xonoraClient.setPreferredPlayer(player)
    }
}

// MARK: - Device Row Component

struct DeviceRow: View {
    let player: MAPlayer
    let state: MultiDeviceManager.PlayerState?
    let isSelected: Bool
    let onTap: () -> Void

    private var deviceIcon: String {
        if player.provider == "sendspin" {
            return "iphone"
        } else if player.name.lowercased().contains("speaker") {
            return "hifispeaker.fill"
        } else if player.name.lowercased().contains("desktop") || player.name.lowercased().contains("mac") {
            return "desktopcomputer"
        } else {
            return "speaker.wave.2.fill"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Content
                HStack(spacing: 12) {
                    // Artwork / Icon
                    artworkView

                    // Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if let state = state, let track = state.currentTrack {
                            Text(track.name)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            Text(track.artistNames)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        } else {
                            Text(player.available ? "Idle" : "Offline")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    // Controls (only if track is loaded)
                    if let state = state, state.currentTrack != nil {
                        HStack(spacing: 16) {
                            Button {
                                Task { try? await XonoraClient.shared.previous(playerId: player.playerId) }
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                Task { try? await XonoraClient.shared.playPause(playerId: player.playerId) }
                            } label: {
                                Image(systemName: state.playbackState == .playing ? "pause.fill" : "play.fill")
                                    .font(.title3)
                                    .foregroundColor(.primary)
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                Task { try? await XonoraClient.shared.next(playerId: player.playerId) }
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.trailing, 8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                ZStack(alignment: .leading) {
                    // Background
                    if isSelected {
                        Color.accentColor.opacity(0.1)
                    } else {
                        Color.clear
                            .background(.ultraThinMaterial)
                    }

                    // Progress indicator
                    if let state = state, state.duration > 0 {
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: geometry.size.width * CGFloat(min(max(state.currentTime / state.duration, 0), 1.0)))
                                .animation(.linear(duration: 1.0), value: state.currentTime)
                        }
                    }
                }
            )
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var artworkView: some View {
        if let state = state, let track = state.currentTrack {
            let url = XonoraClient.shared.getImageURL(
                for: track.imageUrl ?? track.album?.imageUrl,
                size: .thumbnail
            )
            CachedAsyncImage(url: url) {
                Color.gray.opacity(0.3)
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundColor(.gray)
                    }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            ZStack {
                Color.gray.opacity(0.2)
                Image(systemName: deviceIcon)
                    .font(.title)
                    .foregroundColor(.secondary)
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Group Leader Row Component

struct GroupLeaderRow: View {
    let player: MAPlayer
    let memberCount: Int
    let state: MultiDeviceManager.PlayerState?
    let isSelected: Bool
    let onTap: () -> Void

    private var deviceIcon: String {
        if player.provider == "sendspin" {
            return "iphone"
        } else if player.name.lowercased().contains("speaker") {
            return "hifispeaker.2.fill"
        } else if player.name.lowercased().contains("desktop") || player.name.lowercased().contains("mac") {
            return "desktopcomputer"
        } else {
            return "speaker.wave.2.fill"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Content
                HStack(spacing: 12) {
                    // Artwork / Icon
                    artworkView

                    // Info
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(player.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            // GROUP badge
                            Text("GROUP")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .clipShape(Capsule())

                            // Member count
                            Text("\(memberCount) \(memberCount == 1 ? "member" : "members")")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if let state = state, let track = state.currentTrack {
                            Text(track.name)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Text(track.artistNames)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        } else {
                            Text(player.available ? "Idle" : "Offline")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Controls (only if track is loaded)
                    if let state = state, state.currentTrack != nil {
                        HStack(spacing: 16) {
                            Button {
                                Task { try? await XonoraClient.shared.previous(playerId: player.playerId) }
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            .buttonStyle(.plain)

                            Button {
                                Task { try? await XonoraClient.shared.playPause(playerId: player.playerId) }
                            } label: {
                                Image(systemName: state.playbackState == .playing ? "pause.fill" : "play.fill")
                                    .font(.title3)
                                    .foregroundColor(.primary)
                            }
                            .buttonStyle(.plain)

                            Button {
                                Task { try? await XonoraClient.shared.next(playerId: player.playerId) }
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.trailing, 8)
                    } else if isSelected {
                        // Show selection indicator when no track
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                            .padding(.trailing, 8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                ZStack(alignment: .leading) {
                    // Background
                    if isSelected {
                        Color.accentColor.opacity(0.1)
                    } else {
                        Color.clear
                            .background(.ultraThinMaterial)
                    }

                    // Progress indicator
                    if let state = state, state.duration > 0 {
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: geometry.size.width * CGFloat(min(max(state.currentTime / state.duration, 0), 1.0)))
                                .animation(.linear(duration: 1.0), value: state.currentTime)
                        }
                    }
                }
            )
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var artworkView: some View {
        if let state = state, let track = state.currentTrack {
            let url = XonoraClient.shared.getImageURL(
                for: track.imageUrl ?? track.album?.imageUrl,
                size: .thumbnail
            )
            CachedAsyncImage(url: url) {
                Color.gray.opacity(0.3)
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundColor(.gray)
                    }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            ZStack {
                Color.gray.opacity(0.2)
                Image(systemName: deviceIcon)
                    .font(.title)
                    .foregroundColor(.secondary)
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Group Member Row Component

struct GroupMemberRow: View {
    let player: MAPlayer
    let leaderName: String
    let state: MultiDeviceManager.PlayerState?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Tree structure indicator
                Text("└─")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 24)

                // Player icon (smaller, no artwork)
                ZStack {
                    Color.gray.opacity(0.15)
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text("Part of \(leaderName) group")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Selection indicator only (no playback controls)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .padding(.trailing, 8)
                }
            }
            .padding(.leading, 40) // Extra indent
            .padding(.vertical, 12)
            .padding(.trailing, 16)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Dark Mode") {
    DeviceSwitcherView()
        .preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    DeviceSwitcherView()
        .preferredColorScheme(.light)
}
