import SwiftUI
import AVFoundation

@main
struct XonoraApp: App {
    @StateObject private var playerViewModel = PlayerViewModel()
    @StateObject private var libraryViewModel = LibraryViewModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Configure tab bar to be transparent and floating
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)

        // Add blur effect
        let blurEffect = UIBlurEffect(style: .systemMaterial)
        appearance.backgroundEffect = blurEffect

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(playerViewModel)
                .environmentObject(libraryViewModel)
                .onAppear {
                    // Configure audio session asynchronously to avoid blocking startup
                    DispatchQueue.global(qos: .userInitiated).async {
                        self.configureAudioSession()
                    }
                }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                print("[XonoraApp] App became active, refreshing state...")
                if playerViewModel.isConnected {
                    Task {
                        await XonoraClient.shared.fetchPlayers()
                    }
                }
            } else if newPhase == .background {
                // Dismiss keyboard when going to background to prevent snapshotting errors
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
}
