import SwiftUI
import AVFoundation
import UserNotifications

// MARK: - App Delegate for Notification Handling

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handleSleepTimerNotification(notification)
        completionHandler([]) // Don't show the notification
    }

    // Handle notification when user taps it (app was in background)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        handleSleepTimerNotification(response.notification)
        completionHandler()
    }

    private func handleSleepTimerNotification(_ notification: UNNotification) {
        if notification.request.identifier == "xonora.sleepTimer" {
            print("[AppDelegate] Sleep timer notification received - pausing playback")
            Task { @MainActor in
                // Pause playback
                try? await XonoraClient.shared.pause()
                PlayerManager.shared.playbackState = .paused

                // Clear the timer state
                PlayerManager.shared.cancelSleepTimer()
            }
        }
    }
}

@main
struct XonoraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
