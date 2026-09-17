import SwiftUI

// MARK: - Mini Player Bottom Padding

private struct MiniPlayerBottomPaddingKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var miniPlayerBottomPadding: CGFloat {
        get { self[MiniPlayerBottomPaddingKey.self] }
        set { self[MiniPlayerBottomPaddingKey.self] = newValue }
    }
}

struct ContentView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @StateObject private var globalNav = GlobalNavigationViewModel()
    @State private var selectedTab = 2 // Start with Home tab (center)
    @State private var isPlayerExpanded = false
    @ObservedObject private var preferences = UserPreferences.shared
    @Namespace private var playerAnimation
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var barManager = BarVisibilityManager()
    @State private var showPlayerSwitcher = false
    @ObservedObject private var xonoraClient = XonoraClient.shared
    @ObservedObject private var multiDeviceManager = MultiDeviceManager.shared

    private var showMiniPlayer: Bool {
        playerViewModel.playerManager.currentTrack != nil && !isPlayerExpanded
    }

    private func shouldShowTab(_ tag: Int) -> Bool {
        preferences.isTabEnabled(tag)
    }

    // MARK: - Now Playing Tab View

    @ViewBuilder
    private var nowPlayingTab: some View {
        if playerViewModel.playerManager.currentTrack != nil {
            // Show full Now Playing view (non-modal)
            NowPlayingView(isPresentedModally: false, namespace: nil, onDismiss: nil)
                .environmentObject(playerViewModel)
                .environmentObject(libraryViewModel)
        } else {
            // Show empty state
            EmptyNowPlayingView()
        }
    }

    private func iconForTab(_ tag: Int) -> String {
        if tag == 5 { return "play.circle.fill" }
        return UserPreferences.allTabs.first(where: { $0.tag == tag })?.icon ?? "questionmark"
    }

    private var visibleTabs: [Int] {
        preferences.tabBarOrder.filter { shouldShowTab($0) }
    }

    private var miniPlayerBottomPaddingValue: CGFloat {
        guard verticalSizeClass != .compact else { return 0 }
        // Always use expanded padding when mini player is shown to avoid layout thrashing
        // during scroll transitions. The visual bar compacting is separate from layout padding.
        return showMiniPlayer ? 130 : 68
    }

    var body: some View {
        GeometryReader { outerGeometry in
        let bottomSafe = outerGeometry.safeAreaInsets.bottom
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                // Always register all enabled tabs to avoid SwiftUI TabView
                // dynamic tab issues -- visibility is controlled by FloatingTabBar
                ForEach(preferences.tabBarOrder, id: \.self) { tag in
                    if preferences.isTabEnabled(tag) {
                        switch tag {
                        case 0:
                            LibraryView()
                                .tabItem { Label("Music", systemImage: "music.note") }
                                .tag(0)
                        case 1:
                            PodcastsView()
                                .tabItem { Label("Podcasts", systemImage: "mic.fill") }
                                .tag(1)
                        case 2:
                            HomeView()
                                .tabItem { Label("Home", systemImage: "house.fill") }
                                .tag(2)
                        case 3:
                            AudiobooksView()
                                .tabItem { Label("Audiobooks", systemImage: "book.fill") }
                                .tag(3)
                        case 4:
                            RadiosView()
                                .tabItem { Label("Radio", systemImage: "antenna.radiowaves.left.and.right") }
                                .tag(4)
                        case 5:
                            nowPlayingTab
                                .tabItem { Label("Now Playing", systemImage: "play.circle.fill") }
                                .tag(5)
                        default:
                            EmptyView()
                        }
                    }
                }
            }
            .environmentObject(globalNav)
            .environment(\.miniPlayerBottomPadding, miniPlayerBottomPaddingValue)
            .environment(barManager)

            // Custom floating bottom bar (portrait) or side bar (landscape)
            if verticalSizeClass != .compact {
                // PORTRAIT: Bottom bar with smooth layout transitions
                VStack(spacing: 6) {
                    if barManager.barsCompact {
                        // COMPACT: single row -- compact tab pill + mini player side by side
                        HStack(spacing: 6) {
                            if showMiniPlayer {
                                miniPlayerWithGesture
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }

                            // Compact tab button
                            Button {
                                barManager.resetBars()
                            } label: {
                                Image(systemName: iconForTab(selectedTab))
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 52, height: 56)
                                    .background(.bar)
                                    .clipShape(Capsule())
                                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                    } else {
                        // EXPANDED: mini player on top, tab bar on bottom
                        if showMiniPlayer {
                            miniPlayerWithGesture
                                .padding(.horizontal, 12)
                                .transition(.scale(scale: 0.95).combined(with: .opacity))
                        }

                        FloatingTabBar(
                            selectedTab: $selectedTab,
                            visibleTabs: visibleTabs,
                            iconForTab: iconForTab
                        )
                        .padding(.horizontal, 12)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }
                }
                .padding(.bottom, bottomSafe > 0 ? 0 : 8)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: barManager.barsCompact)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            } else {
                // LANDSCAPE: Horizontal responsive layout - mini player + expandable tab bar
                GeometryReader { geo in
                    let availableWidth = geo.size.width - 24 // Account for padding
                    let tabCount = CGFloat(visibleTabs.count)
                    let tabBarCompactWidth: CGFloat = 52 // Compact pill size
                    let tabButtonWidth: CGFloat = 48 // Width per tab button in expanded state
                    let spacingBetweenTabs: CGFloat = 4
                    let tabBarExpandedWidth = tabCount * tabButtonWidth + (tabCount - 1) * spacingBetweenTabs
                    let miniPlayerMinWidth: CGFloat = 60

                    let isTabBarExpanded = !barManager.barsCompact
                    let currentTabBarWidth = isTabBarExpanded ? tabBarExpandedWidth : tabBarCompactWidth
                    let currentMiniPlayerWidth = max(miniPlayerMinWidth, availableWidth - currentTabBarWidth - 6)

                    HStack(spacing: 6) {
                        // Mini player - takes remaining space, animates width change
                        if showMiniPlayer {
                            miniPlayerWithGesture
                                .frame(width: currentMiniPlayerWidth, height: 48)
                                .clipShape(Capsule())
                                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isTabBarExpanded)
                        }

                        // Tab bar - compact or expanded
                        if isTabBarExpanded {
                            // EXPANDED: Show all tabs
                            HStack(spacing: spacingBetweenTabs) {
                                ForEach(visibleTabs, id: \.self) { tag in
                                    Button {
                                        selectedTab = tag
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            barManager.resetBars()
                                        }
                                    } label: {
                                        Image(systemName: iconForTab(tag))
                                            .font(.title3)
                                            .foregroundStyle(selectedTab == tag ? Color.accentColor : .secondary)
                                            .frame(width: tabButtonWidth, height: 48)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .background(.bar)
                            .clipShape(Capsule())
                            .frame(width: currentTabBarWidth, height: 48)
                        } else {
                            // COMPACT: Just icon pill
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    barManager.resetBars()
                                }
                            } label: {
                                Image(systemName: iconForTab(selectedTab))
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 48, height: 48)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(.bar)
                            .clipShape(Capsule())
                            .frame(width: tabBarCompactWidth, height: 48)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, bottomSafe > 0 ? 0 : 8)
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
                .frame(height: 48 + (bottomSafe > 0 ? 0 : 8))
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }

            // Player Switcher Popup
            if showPlayerSwitcher {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            showPlayerSwitcher = false
                        }
                    }
                    .zIndex(1.4)

                PlayerSwitcherPopup(isPresented: $showPlayerSwitcher)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, miniPlayerBottomPaddingValue + 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1.5)
            }

            // Full Now Playing View
            if isPlayerExpanded {
                NowPlayingView(isPresentedModally: true, namespace: playerAnimation, onDismiss: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        isPlayerExpanded = false
                    }
                })
                .environmentObject(playerViewModel)
                .environmentObject(libraryViewModel)
                .transition(.move(edge: .bottom))
                .zIndex(2)
            }

        }
        .onChange(of: selectedTab) { _, _ in
            barManager.resetBars()
        }
        .onChange(of: isPlayerExpanded) { _, expanded in
            if expanded {
                barManager.resetBars()
            }
        }
        .sheet(isPresented: $globalNav.showingSearch) {
            GlobalSearchSheet()
                .environmentObject(globalNav)
                .environmentObject(libraryViewModel)
                .environmentObject(playerViewModel)
                .environment(barManager)
        }
        .sheet(isPresented: $globalNav.showingSettings) {
            SettingsView()
                .environmentObject(playerViewModel)
                .environmentObject(libraryViewModel)
        }
        .sheet(isPresented: $playerViewModel.showingServerSetup) {
            ServerSetupView()
                .environmentObject(playerViewModel)
        }
        .onAppear {
            // Hide the system tab bar completely -- our custom FloatingTabBar replaces it
            UITabBar.appearance().isHidden = true
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
        .toastView()
        .onReceive(NotificationCenter.default.publisher(for: .playerChanged)) { notification in
            if let playerName = notification.userInfo?["playerName"] as? String {
                ToastManager.shared.show(String(localized: "Now playing on \(playerName)"), type: .info)
            }
        }
        } // GeometryReader
    }

    @ViewBuilder
    private var miniPlayerWithGesture: some View {
        MiniPlayerView(namespace: playerAnimation) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                isPlayerExpanded = true
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showPlayerSwitcher = true
                    }
                }
        )
    }
}

// MARK: - Floating Tab Bar

private struct FloatingTabBar: View {
    @Binding var selectedTab: Int
    let visibleTabs: [Int]
    let iconForTab: (Int) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs, id: \.self) { tag in
                Button {
                    selectedTab = tag
                } label: {
                    Image(systemName: iconForTab(tag))
                        .font(.title3)
                        .foregroundStyle(selectedTab == tag ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(.bar)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
}

struct ServerSetupView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @State private var serverURL: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var accessToken: String = ""
    @State private var useTokenAuth: Bool = false
    @State private var showPassword: Bool = false
    @State private var isScanning: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "hifispeaker.2.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.xonoraGradient)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Welcome to Xonora")
                                .font(.headline)
                            Text("Connect to your Music Assistant server to get started.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                
                Section {
                    Button {
                        isScanning = true
                        playerViewModel.startDiscovery()
                        // Auto-stop scanning after 5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            isScanning = false
                        }
                    } label: {
                        HStack {
                            Image(systemName: isScanning ? "antenna.radiowaves.left.and.right" : "magnifyingglass")
                                .symbolEffect(.variableColor.iterative, isActive: isScanning)
                            Text(isScanning ? "Scanning..." : "Scan for Servers")
                            if isScanning {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isScanning)
                } header: {
                    Text("Auto-Discovery")
                } footer: {
                    Text("Scan your local network for Music Assistant servers")
                }
                .listRowSeparator(.hidden)
                
                if !playerViewModel.discoveredServers.isEmpty {
                    Section("Discovered Servers") {
                        ForEach(playerViewModel.discoveredServers) { server in
                            Button {
                                let host = server.hostname
                                let port = server.port
                                serverURL = "http://\(host):\(port)"
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(server.name)
                                            .foregroundStyle(.primary)
                                        Text(server.url.absoluteString)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if serverURL.contains(server.hostname) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                        .listRowSeparator(.hidden)
                    }
                } else if isScanning {
                    Section {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                                .padding(.trailing, 8)
                            Text("Looking for servers...")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowSeparator(.hidden)
                }
                
                Section {
                    TextField("Server Address", text: $serverURL, prompt: Text("Example: http://192.168.1.100:8095")
                        .foregroundColor(.gray))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundColor(.primary)
                    
                    if useTokenAuth {
                        HStack {
                            if showPassword {
                                TextField("Access Token", text: $accessToken)
                            } else {
                                SecureField("Access Token", text: $accessToken)
                            }
                            
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    } else {
                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        
                        HStack {
                            if showPassword {
                                TextField("Password", text: $password)
                            } else {
                                SecureField("Password", text: $password)
                            }
                            
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }
                    
                    Button(useTokenAuth ? "Use Username/Password instead" : "Use Access Token instead") {
                        useTokenAuth.toggle()
                    }
                    .font(.caption)
                    .foregroundStyle(.blue)
                } header: {
                    Text("Server Details")
                } footer: {
                    if useTokenAuth {
                        Text("Enter the full URL including port number. Access tokens can be generated in Music Assistant settings.")
                    } else {
                        Text("Enter the full URL including port number. Login using your Music Assistant username and password.")
                    }
                }
                .listRowSeparator(.hidden)
                
                if let error = playerViewModel.connectionError {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .listRowSeparator(.hidden)
                }
                
                Section {
                    Button {
                         var urlToUse = serverURL
                        if !urlToUse.lowercased().hasPrefix("http://") && !urlToUse.lowercased().hasPrefix("https://") {
                            urlToUse = "http://" + urlToUse
                        }
                        playerViewModel.updateServerURL(urlToUse)
                        if useTokenAuth {
                            playerViewModel.authMode = .token
                            playerViewModel.updateCredentials(accessToken: accessToken)
                            playerViewModel.connectToServer()
                        } else {
                            playerViewModel.authMode = .credentials
                            playerViewModel.username = username
                            playerViewModel.connectToServer(password: password)
                        }
                    } label: {
                        if playerViewModel.isConnecting || playerViewModel.isAuthenticating {
                            HStack {
                                Text("Connecting...")
                                Spacer()
                                ProgressView()
                                    .tint(.white)
                            }
                        } else {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(serverURL.isEmpty || (useTokenAuth ? accessToken.isEmpty : (username.isEmpty || password.isEmpty)) || playerViewModel.isConnecting || playerViewModel.isAuthenticating)
                    .foregroundStyle((serverURL.isEmpty || (useTokenAuth ? accessToken.isEmpty : (username.isEmpty || password.isEmpty)) || playerViewModel.isConnecting || playerViewModel.isAuthenticating) ? Color.secondary : Color.white)
                }
                .listRowBackground(
                    (serverURL.isEmpty || (useTokenAuth ? accessToken.isEmpty : (username.isEmpty || password.isEmpty)) || playerViewModel.isConnecting || playerViewModel.isAuthenticating)
                    ? Color(UIColor.secondarySystemGroupedBackground)
                    : Color.accentColor
                )
                .listRowSeparator(.hidden)
            }
            .navigationTitle("Connect Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !playerViewModel.serverURL.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                // Clear any stale errors when showing the setup view
                playerViewModel.connectionError = nil
                
                serverURL = playerViewModel.serverURL
                username = playerViewModel.username
                accessToken = playerViewModel.accessToken
                useTokenAuth = playerViewModel.authMode == .token
                
                // Auto-start discovery on appear
                isScanning = true
                playerViewModel.startDiscovery()
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    isScanning = false
                }
            }
            .onDisappear {
                playerViewModel.stopDiscovery()
            }
            .onChange(of: playerViewModel.isConnected) { _, connected in
                if connected {
                    dismiss()
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @ObservedObject private var client = XonoraClient.shared
    @ObservedObject private var sendspinClient = SendspinClient.shared
    @ObservedObject private var preferences = UserPreferences.shared
    @State private var localPlayerName: String = ""
    @State private var showingClearCacheAlert = false
    @State private var showingServerSetupSheet = false
    @State private var metadataCacheSizeString: String = "Calculating..."
    @State private var imageCacheSizeString: String = "Calculating..."

    var body: some View {
        NavigationStack {
            List {
                // Header Section
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "hifispeaker.2.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(Color.xonoraGradient)
                        
                        if let user = client.currentUser {
                            let displayName = user.displayName ?? user.username
                            if !displayName.isEmpty {
                                let firstName = displayName.components(separatedBy: .whitespaces).first ?? displayName
                                Text("\(firstName)'s Xonora")
                                    .font(.title2.bold())
                            } else {
                                Text("Xonora")
                                    .font(.title2.bold())
                            }
                        } else {
                            Text("Xonora")
                                .font(.title2.bold())
                        }
                        
                        if playerViewModel.isConnected {
                            Text("Connected to \(serverDisplayName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let version = client.serverInfo?.serverVersion {
                                Text(version)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)
                
                // Personalization Section
                Section("Personalization") {
                    NavigationLink(destination: CustomizeHomeView()) {
                        Label("Customize Home Tab", systemImage: "square.grid.2x2")
                    }
                    
                    NavigationLink(destination: TabBarOrderView()) {
                        Label("Tab Bar Order", systemImage: "square.stack")
                    }
                    
                    NavigationLink(destination: AppearanceView()) {
                        Label("Appearance", systemImage: "paintbrush")
                    }

                    NavigationLink(destination: LibraryGridSettingsView()) {
                        Label("Grid Columns", systemImage: "square.grid.3x3")
                    }
                    
                    NavigationLink(destination: LanguageView()) {
                        Label("Language", systemImage: "globe")
                    }
                }
                
                // Playback Section
                Section("Playback") {
                    HStack {
                        Label("Default Speed", systemImage: "gauge.with.dots.needle.bottom.50percent")
                        Spacer()
                        Picker("", selection: $preferences.defaultPlaybackSpeed) {
                            Text("0.5x").tag(0.5)
                            Text("0.75x").tag(0.75)
                            Text("1.0x").tag(1.0)
                            Text("1.25x").tag(1.25)
                            Text("1.5x").tag(1.5)
                            Text("1.75x").tag(1.75)
                            Text("2.0x").tag(2.0)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    Toggle(isOn: $preferences.crossfadeEnabled) {
                        Label("Crossfade", systemImage: "waveform")
                    }

                    if preferences.crossfadeEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Crossfade Duration", systemImage: "timer")
                                Spacer()
                                Text("\(Int(preferences.crossfadeDuration))s")
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }

                            Slider(value: $preferences.crossfadeDuration, in: 1...12, step: 1)
                        }
                    }
                }

                // Lyrics Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Lyrics Offset", systemImage: "text.alignleft")
                            Spacer()
                            Text(formatLyricsOffset(preferences.lyricsOffset))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }

                        Slider(value: $preferences.lyricsOffset, in: -2.0...2.0, step: 0.1)

                        if preferences.lyricsOffset != 0 {
                            Button("Reset to Default") {
                                preferences.lyricsOffset = 0
                            }
                            .font(.caption)
                        }
                    }
                } header: {
                    Text("Lyrics")
                } footer: {
                    Text("Adjust if lyrics appear too early (negative) or too late (positive) compared to audio.")
                }

                // Advanced Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Max Tracked Players", systemImage: "music.note.list")
                            Spacer()
                            Stepper(
                                value: $preferences.maxTrackedPlayers,
                                in: 1...20,
                                step: 1
                            ) {
                                Text("\(preferences.maxTrackedPlayers)")
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Number of other players tracked simultaneously. Higher values use more memory.")
                }

                // Connection Section
                Section("Connection") {
                    HStack {
                        Label("Server", systemImage: "server.rack")
                        Spacer()
                        Text(serverDisplayName)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    HStack {
                        Label("Status", systemImage: playerViewModel.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                        Spacer()
                        Text(connectionStatusText)
                            .foregroundColor(connectionStatusColor)
                    }

                    Button {
                        playerViewModel.disconnect()
                        showingServerSetupSheet = true
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
                    
                    if !client.providers.isEmpty {
                        NavigationLink {
                            ProvidersView(providers: client.providers)
                        } label: {
                            Label("Available Providers", systemImage: "puzzlepiece")
                        }
                    }
                }

                // Sendspin Section
                Section {
                    Toggle("Enable Sendspin", isOn: Binding(
                        get: { playerViewModel.sendspinEnabled },
                        set: { playerViewModel.toggleSendspin($0) }
                    ))

                    if playerViewModel.sendspinEnabled {
                        HStack {
                            Label("Status", systemImage: playerViewModel.sendspinConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                            Spacer()
                            Text(playerViewModel.sendspinConnected ? "Connected" : "Disconnected")
                                .foregroundColor(playerViewModel.sendspinConnected ? .green : .red)
                        }

                        HStack {
                            Label("Player Name", systemImage: "pencil")
                            TextField("Name", text: $localPlayerName)
                                .multilineTextAlignment(.trailing)
                                .submitLabel(.done)
                                .onSubmit {
                                    sendspinClient.updatePlayerName(localPlayerName)
                                }
                        }
                    }
                } header: {
                    Text("Local Audio (Sendspin)")
                } footer: {
                    Text("Enable to receive audio streams via Sendspin on the same server.")
                }
                .onAppear {
                    localPlayerName = sendspinClient.playerName
                    calculateCacheSizes()
                }

                // Remote Player Section
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
                            set: { newPlayer in
                                // Use setPreferredPlayer for explicit user selection
                                if let player = newPlayer {
                                    client.setPreferredPlayer(player)
                                }
                            }
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
                
                // Storage Section
                Section("Storage") {
                    HStack {
                        Label("Image Cache", systemImage: "photo.stack")
                        Spacer()
                        Text(imageCacheSizeString)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    
                    HStack {
                        Label("Metadata Cache", systemImage: "doc.text")
                        Spacer()
                        Text(metadataCacheSizeString)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    
                    Button(role: .destructive) {
                        showingClearCacheAlert = true
                    } label: {
                        Label("Clear All Caches", systemImage: "trash")
                    }
                }

                // About Section
                Section("About") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                           let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                            Text("\(version) (\(build))")
                                .foregroundColor(.secondary)
                        }
                    }

                    Link(destination: URL(string: "https://music-assistant.io")!) {
                        Label("Music Assistant", systemImage: "link")
                    }

                    Button {
                        // TODO: Show acknowledgements
                    } label: {
                        Label("Acknowledgements", systemImage: "heart")
                    }

                    Link(destination: URL(string: "https://discord.gg/x6cWh4AjNG")!) {
                        Label("Join Discord", systemImage: "bubble.left.and.bubble.right")
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .sheet(isPresented: $showingServerSetupSheet) {
            ServerSetupView()
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .alert("Clear All Caches?", isPresented: $showingClearCacheAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearAllCaches()
            }
        } message: {
            Text("This will clear all cached images and metadata. The app will re-download content as needed.")
        }
    }
    
    // MARK: - Computed Properties
    
    private var serverDisplayName: String {
        guard let url = URL(string: playerViewModel.serverURL),
              let host = url.host else {
            return playerViewModel.serverURL
        }
        return host
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
    
    private func calculateCacheSizes() {
        Task {
            // Metadata Cache (Disk)
            let metadataBytes = await MetadataCache.shared.getDiskUsage()
            let metadataFormatter = ByteCountFormatter()
            metadataFormatter.countStyle = .file
            metadataFormatter.allowedUnits = [.useMB, .useKB]
            await MainActor.run {
                metadataCacheSizeString = metadataFormatter.string(fromByteCount: Int64(metadataBytes))
            }

            // Image Cache (Disk)
            let imageBytes = await ImageCache.shared.getDiskUsage()
            let imageFormatter = ByteCountFormatter()
            imageFormatter.countStyle = .file
            imageFormatter.allowedUnits = [.useMB, .useKB]
            await MainActor.run {
                imageCacheSizeString = imageFormatter.string(fromByteCount: Int64(imageBytes))
            }
        }
    }
    
    // MARK: - Helpers

    private func formatLyricsOffset(_ offset: Double) -> String {
        if offset == 0 {
            return "0.0s"
        } else if offset > 0 {
            return String(format: "+%.1fs", offset)
        } else {
            return String(format: "%.1fs", offset)
        }
    }

    // MARK: - Actions

    private func clearAllCaches() {
        Task {
            await ImageCache.shared.clearCache()
            await MetadataCache.shared.clearCache()
            calculateCacheSizes()
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
// MARK: - Player Switcher Popup

struct PlayerSwitcherPopup: View {
    @Binding var isPresented: Bool
    @ObservedObject private var xonoraClient = XonoraClient.shared
    @ObservedObject private var multiDeviceManager = MultiDeviceManager.shared

    /// Active players excluding the currently selected one (already shown in mini player)
    private var otherActivePlayers: [MAPlayer] {
        let currentId = xonoraClient.currentPlayer?.playerId
        return xonoraClient.players
            .filter { $0.available && $0.playerId != currentId }
            .filter { player in
                let state = multiDeviceManager.state(for: player.playerId)
                let hasTrack = state?.currentTrack != nil || player.currentMedia?.title != nil
                let isActive = state?.playbackState == .playing || state?.playbackState == .paused
                return hasTrack && isActive
            }
            .sorted { a, b in
                let stateA = multiDeviceManager.state(for: a.playerId)?.playbackState
                let stateB = multiDeviceManager.state(for: b.playerId)?.playbackState
                if stateA != stateB {
                    if stateA == .playing { return true }
                    if stateB == .playing { return false }
                }
                return a.name < b.name
            }
    }

    var body: some View {
        VStack(spacing: 6) {
            if otherActivePlayers.isEmpty {
                Text("No Other Active Players")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(.bar)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            } else {
                ForEach(otherActivePlayers) { player in
                    PlayerMiniCard(
                        player: player,
                        state: multiDeviceManager.state(for: player.playerId),
                        onSelect: {
                            xonoraClient.setPreferredPlayer(player)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                isPresented = false
                            }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Player Mini Card

private struct PlayerMiniCard: View {
    let player: MAPlayer
    let state: MultiDeviceManager.PlayerState?
    let onSelect: () -> Void

    private var trackName: String {
        state?.currentTrack?.name ?? player.currentMedia?.title ?? "Unknown"
    }

    private var artistName: String {
        state?.currentTrack?.artistNames ?? player.currentMedia?.artist ?? ""
    }

    private var imageUrlString: String? {
        state?.currentTrack?.imageUrl ?? state?.currentTrack?.album?.imageUrl ?? player.currentMedia?.imageUrlResolved
    }

    private var isPlaying: Bool {
        state?.playbackState == .playing
    }

    private var progress: Double {
        guard let s = state, s.duration > 0 else { return 0 }
        return min(max(s.currentTime / s.duration, 0), 1)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Artwork
            artworkView

            // Track info + player name
            VStack(alignment: .leading, spacing: 2) {
                Text(trackName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if !artistName.isEmpty {
                        Text(artistName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Text("--")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    Text(player.name)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Playback controls
            HStack(spacing: 14) {
                Button {
                    Task {
                        try? await XonoraClient.shared.playPause(playerId: player.playerId)
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        try? await XonoraClient.shared.next(playerId: player.playerId)
                    }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.bar)

                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: geometry.size.width * progress)
                }
            }
        )
        .frame(height: 56)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        .contentShape(Capsule())
        .onTapGesture {
            onSelect()
        }
    }

    private var artworkView: some View {
        let url = XonoraClient.shared.getImageURL(for: imageUrlString, size: .thumbnail)
        return CachedAsyncImage(url: url) {
            Color.gray.opacity(0.3)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundColor(.gray)
                }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    var namespace: Namespace.ID
    var expandAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Artwork with shared element transition
            artworkView
                .matchedGeometryEffect(id: "playerArtwork", in: namespace)

            // Track Info
            VStack(alignment: .leading, spacing: 2) {
                Text(playerManager.currentTrack?.name ?? "Not Playing")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(playerManager.currentTrack?.artistNames ?? "")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if playerManager.isLoading {
                        Text("Loading...")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                }
            }

            Spacer()

            // Controls
            HStack(spacing: 16) {
                Button {
                    if playerManager.isPlayingAudiobook {
                        playerManager.skipBackward(seconds: 15)
                    } else {
                        playerManager.previous()
                    }
                } label: {
                    Image(systemName: playerManager.isPlayingAudiobook ? "gobackward.15" : "backward.fill")
                        .font(.body)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)

                Button {
                    playerManager.togglePlayPause()
                } label: {
                    if playerManager.isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(playerManager.isLoading)

                Button {
                    if playerManager.isPlayingAudiobook {
                        playerManager.skipForward(seconds: 15)
                    } else {
                        playerManager.next()
                    }
                } label: {
                    Image(systemName: playerManager.isPlayingAudiobook ? "goforward.15" : "forward.fill")
                        .font(.body)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.bar)

                if playerManager.isLoading {
                    LoadingProgressBar()
                } else {
                    TimelineView(.animation(minimumInterval: 0.1, paused: !playerManager.isPlaying)) { timeline in
                        GeometryReader { geometry in
                            let animatedProgress = calculateAnimatedProgress(at: timeline.date)
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: geometry.size.width * animatedProgress)
                        }
                    }
                }
            }
        )
        .frame(height: 56)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .onTapGesture {
            expandAction()
        }
    }

    private func calculateAnimatedProgress(at date: Date) -> Double {
        guard !playerManager.isLoading else { return 0 }
        guard playerManager.displayDuration > 0 else { return 0 }

        var current = playerManager.displayCurrentTime

        if playerManager.isPlaying {
            let elapsedSinceLastUpdate = date.timeIntervalSince(playerManager.lastUpdateTime)
            current += max(0, elapsedSinceLastUpdate)
        }

        return min(max(current / playerManager.displayDuration, 0), 1)
    }

    private var artworkView: some View {
        let url = XonoraClient.shared.getImageURL(
            for: playerManager.currentTrack?.imageUrl ?? playerManager.currentTrack?.album?.imageUrl,
            size: .thumbnail
        )

        return CachedAsyncImage(url: url) {
            Color.gray.opacity(0.3)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundColor(.gray)
                }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Loading Progress Bar

struct LoadingProgressBar: View {
    @State private var animationOffset: CGFloat = -1.0

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0),
                            Color.accentColor.opacity(0.3),
                            Color.accentColor.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: geometry.size.width * 0.4)
                .offset(x: geometry.size.width * animationOffset)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                        animationOffset = 1.5
                    }
                }
        }
    }
}

struct ProvidersView: View {
    let providers: [ProviderInstance]
    
    var body: some View {
        List(providers, id: \.id) { provider in
            VStack(alignment: .leading, spacing: 4) {
                Text(provider.displayName)
                    .font(.headline)
                HStack {
                    Text(provider.type.capitalized)
                    if let isStreaming = provider.isStreamingProvider, isStreaming {
                        Text("• Streaming")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Available Providers")
        .navigationBarTitleDisplayMode(.inline)
    }
}

