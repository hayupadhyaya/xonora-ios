import SwiftUI

struct ContentView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                LibraryView()
                    .tabItem {
                        Label("Library", systemImage: "rectangle.stack.fill")
                    }
                    .tag(0)

                SearchView()
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(1)

                NowPlayingView(isPresentedModally: false)
                    .tabItem {
                        Label("Now Playing", systemImage: "play.circle.fill")
                    }
                    .tag(2)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(3)
            }
        }
        .sheet(isPresented: $playerViewModel.showingServerSetup) {
            ServerSetupView()
        }
        .onAppear {
            if playerViewModel.serverURL.isEmpty {
                playerViewModel.showingServerSetup = true
            } else {
                playerViewModel.connectToServer()
            }
        }
        .alert("Playback Error", isPresented: Binding(
            get: { playerViewModel.playbackError != nil },
            set: { _ in playerViewModel.playbackError = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = playerViewModel.playbackError {
                Text(error)
            }
        }
    }
}

struct ServerSetupView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @State private var serverURL: String = ""
    @State private var accessToken: String = ""
    @State private var showPassword: Bool = false
    @State private var animateGradient: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Animated gradient background
            backgroundView
                .ignoresSafeArea()

            // Content
            ScrollView {
                VStack(spacing: 32) {
                    // Dismiss handle for modal
                    if !playerViewModel.serverURL.isEmpty {
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 40, height: 5)
                            .padding(.top, 8)
                    }

                    // Header with animated icon
                    headerView
                        .padding(.top, playerViewModel.serverURL.isEmpty ? 60 : 20)

                    // Input fields
                    VStack(spacing: 20) {
                        serverURLField
                        accessTokenField
                    }
                    .padding(.horizontal, 24)

                    // Status indicator
                    statusView
                        .padding(.horizontal, 24)

                    Spacer(minLength: 40)

                    // Connect button
                    connectButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                }
            }

            // Cancel button overlay
            if !playerViewModel.serverURL.isEmpty {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.7))
                                .padding()
                        }
                    }
                    Spacer()
                }
            }
        }
        .onAppear {
            serverURL = playerViewModel.serverURL
            accessToken = playerViewModel.accessToken
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animateGradient = true
            }
        }
        .onChange(of: playerViewModel.isConnected) { connected in
            if connected {
                dismiss()
            }
        }
    }

    // MARK: - Background

    private var backgroundView: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [
                    Color.xonoraPurple.opacity(0.8),
                    Color.black,
                    Color.xonoraCyan.opacity(0.4)
                ],
                startPoint: animateGradient ? .topLeading : .bottomLeading,
                endPoint: animateGradient ? .bottomTrailing : .topTrailing
            )

            // Animated orbs
            Circle()
                .fill(Color.xonoraPurple.opacity(0.5))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: animateGradient ? -100 : -150, y: animateGradient ? -200 : -250)

            Circle()
                .fill(Color.xonoraCyan.opacity(0.4))
                .frame(width: 250, height: 250)
                .blur(radius: 70)
                .offset(x: animateGradient ? 120 : 150, y: animateGradient ? 300 : 350)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 20) {
            // App icon with glow effect
            ZStack {
                // Glow
                Image(systemName: "hifispeaker.2.fill")
                    .font(.system(size: 70, weight: .medium))
                    .foregroundStyle(Color.xonoraGradient)
                    .blur(radius: 20)
                    .opacity(0.6)

                // Icon
                Image(systemName: "hifispeaker.2.fill")
                    .font(.system(size: 70, weight: .medium))
                    .foregroundStyle(Color.xonoraGradient)
            }
            .scaleEffect(animateGradient ? 1.05 : 1.0)

            VStack(spacing: 8) {
                Text("Xonora")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Connect to Music Assistant")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Server URL Field

    private var serverURLField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Server Address", systemImage: "server.rack")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.9))

            HStack(spacing: 12) {
                Image(systemName: "link")
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 20)

                TextField("", text: $serverURL, prompt: Text("http://192.168.1.100:8095").foregroundColor(.white.opacity(0.3)))
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
            .padding()
            .background(glassBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )

            Text("Your Music Assistant server URL with port")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .padding(.leading, 4)
        }
    }

    // MARK: - Access Token Field

    private var accessTokenField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Access Token", systemImage: "key.fill")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.9))

            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 20)

                Group {
                    if showPassword {
                        TextField("", text: $accessToken, prompt: Text("Paste your token here").foregroundColor(.white.opacity(0.3)))
                    } else {
                        SecureField("", text: $accessToken, prompt: Text("Paste your token here").foregroundColor(.white.opacity(0.3)))
                    }
                }
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding()
            .background(glassBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )

            Text("Create a token in Music Assistant → Settings → Users")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .padding(.leading, 4)
        }
    }

    // MARK: - Status View

    @ViewBuilder
    private var statusView: some View {
        if playerViewModel.isConnecting || playerViewModel.isAuthenticating {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text(playerViewModel.isAuthenticating ? "Authenticating..." : "Connecting...")
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(glassBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        } else if let error = playerViewModel.connectionError {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.leading)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.red.opacity(0.4), lineWidth: 1)
            )
        }
    }

    // MARK: - Connect Button

    private var connectButton: some View {
        Button {
            playerViewModel.updateServerURL(serverURL)
            playerViewModel.updateCredentials(accessToken: accessToken)
            playerViewModel.connectToServer()
        } label: {
            HStack(spacing: 10) {
                if playerViewModel.isConnecting || playerViewModel.isAuthenticating {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                }
                Text(buttonText)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Group {
                    if isButtonDisabled {
                        Color.gray.opacity(0.3)
                    } else {
                        LinearGradient(
                            colors: [Color.xonoraPurple, Color.xonoraCyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: isButtonDisabled ? .clear : Color.xonoraPurple.opacity(0.5), radius: 20, y: 10)
        }
        .disabled(isButtonDisabled)
        .scaleEffect(isButtonDisabled ? 1.0 : (playerViewModel.isConnecting ? 0.98 : 1.0))
        .animation(.spring(response: 0.3), value: playerViewModel.isConnecting)
    }

    // MARK: - Helpers

    private var glassBackground: some View {
        Color.white.opacity(0.1)
            .background(.ultraThinMaterial.opacity(0.5))
    }

    private var isButtonDisabled: Bool {
        serverURL.isEmpty || playerViewModel.isConnecting || playerViewModel.isAuthenticating
    }

    private var buttonText: String {
        if playerViewModel.isAuthenticating {
            return "Authenticating"
        } else if playerViewModel.isConnecting {
            return "Connecting"
        } else {
            return "Connect"
        }
    }
}

struct SearchView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    var body: some View {
        NavigationStack {
            VStack {
                if libraryViewModel.searchQuery.isEmpty {
                    if #available(iOS 17.0, *) {
                        ContentUnavailableView(
                            "Search Music",
                            systemImage: "magnifyingglass",
                            description: Text("Search for albums, artists, and tracks")
                        )
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("Search Music")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("Search for albums, artists, and tracks")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                } else if libraryViewModel.isSearching {
                    ProgressView()
                } else if libraryViewModel.searchResults.albums.isEmpty &&
                          libraryViewModel.searchResults.artists.isEmpty &&
                          libraryViewModel.searchResults.tracks.isEmpty {
                    if #available(iOS 17.0, *) {
                        ContentUnavailableView.search(text: libraryViewModel.searchQuery)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("No Results")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("No results for \"\(libraryViewModel.searchQuery)\"")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                } else {
                    searchResultsList
                }
            }
            .navigationTitle("Search")
            .searchable(text: $libraryViewModel.searchQuery, prompt: "Albums, Artists, Songs")
        }
    }

    private var searchResultsList: some View {
        List {
            if !libraryViewModel.searchResults.tracks.isEmpty {
                Section("Songs") {
                    ForEach(libraryViewModel.searchResults.tracks) { track in
                        TrackRow(
                            track: track,
                            showArtwork: true,
                            isPlaying: playerViewModel.playerManager.currentTrack?.id == track.id,
                            onTap: {
                                playerViewModel.playTrack(track, fromQueue: libraryViewModel.searchResults.tracks)
                            }
                        )
                    }
                }
            }

            if !libraryViewModel.searchResults.albums.isEmpty {
                Section("Albums") {
                    ForEach(libraryViewModel.searchResults.albums) { album in
                        NavigationLink(destination: AlbumDetailView(album: album)) {
                            HStack(spacing: 12) {
                                AsyncImage(url: XonoraClient.shared.getImageURL(for: album.imageUrl)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay {
                                            Image(systemName: "music.note")
                                                .foregroundColor(.gray)
                                        }
                                }
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                                VStack(alignment: .leading) {
                                    Text(album.name)
                                        .lineLimit(1)
                                    Text(album.artistNames)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }

            if !libraryViewModel.searchResults.artists.isEmpty {
                Section("Artists") {
                    ForEach(libraryViewModel.searchResults.artists) { artist in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 50, height: 50)
                                .overlay {
                                    Image(systemName: "person.fill")
                                        .foregroundColor(.gray)
                                }

                            Text(artist.name)
                        }
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @ObservedObject private var client = XonoraClient.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label("Server", systemImage: "server.rack")
                        Spacer()
                        Text(playerViewModel.serverURL)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if !playerViewModel.accessToken.isEmpty {
                        HStack {
                            Label("Token", systemImage: "key.fill")
                            Spacer()
                            Text(playerViewModel.accessToken.prefix(8) + "...")
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Label("Status", systemImage: playerViewModel.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                        Spacer()
                        Text(connectionStatusText)
                            .foregroundColor(connectionStatusColor)
                    }

                    Button {
                        // Stop any ongoing connection attempts before showing settings
                        playerViewModel.stopAndShowSettings()
                    } label: {
                        Label("Change Server", systemImage: "pencil")
                    }

                    Button {
                        if playerViewModel.isConnected {
                            playerViewModel.disconnect()
                        } else {
                            playerViewModel.connectToServer()
                        }
                    } label: {
                        Label(playerViewModel.isConnected ? "Disconnect" : "Reconnect",
                              systemImage: playerViewModel.isConnected ? "wifi.slash" : "wifi")
                    }
                } header: {
                    Text("Connection")
                }

                Section {
                    Toggle("Enable Sendspin", isOn: Binding(
                        get: { playerViewModel.sendspinEnabled },
                        set: { playerViewModel.toggleSendspin($0) }
                    ))

                    if playerViewModel.sendspinEnabled {
                        HStack {
                            Label("Sendspin Status", systemImage: playerViewModel.sendspinConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                            Spacer()
                            Text(playerViewModel.sendspinConnected ? "Connected" : "Disconnected")
                                .foregroundColor(playerViewModel.sendspinConnected ? .green : .red)
                        }

                        if playerViewModel.sendspinConnected {
                            Text("iOS device connected via Sendspin protocol. Audio will stream directly to this device.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Local Audio (Sendspin)")
                } footer: {
                    Text("Enable to receive audio streams via Sendspin.")
                }

                Section {
                    if client.players.isEmpty {
                        if playerViewModel.isConnected {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .padding(.trailing, 8)
                                Text("Loading players...")
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("No players found (not connected)")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Picker("Active Player", selection: Binding(
                            get: { client.currentPlayer },
                            set: { client.currentPlayer = $0 }
                        )) {
                            ForEach(client.players) { player in
                                HStack {
                                    Image(systemName: player.provider == "sendspin" ? "iphone" : "speaker.wave.2")
                                    Text(player.name)
                                }
                                .tag(player as MAPlayer?)
                            }
                        }

                        if let selected = client.currentPlayer {
                            Text("Playback will be sent to: \(selected.name)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Remote Player")
                } footer: {
                    Text("Select a player to send playback commands to.")
                }

                Section {
                    HStack {
                        Label("App Version", systemImage: "info.circle")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var connectionStatusText: String {
        if playerViewModel.isConnecting {
            return "Connecting..."
        } else if playerViewModel.isAuthenticating {
            return "Authenticating..."
        } else if playerViewModel.isConnected {
            return "Connected"
        } else {
            return "Disconnected"
        }
    }

    private var connectionStatusColor: Color {
        if playerViewModel.isConnected {
            return .green
        } else if playerViewModel.isConnecting || playerViewModel.isAuthenticating {
            return .orange
        } else {
            return .red
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(PlayerViewModel())
            .environmentObject(LibraryViewModel())
    }
}
