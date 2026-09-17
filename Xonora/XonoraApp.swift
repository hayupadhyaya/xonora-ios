import SwiftUI
import AVFoundation
import UserNotifications
import Intents

// AppDelegate for handling notifications
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self
        // Request Siri authorization for media playback
        let currentStatus = INPreferences.siriAuthorizationStatus()
        print("[Siri] Current authorization status: \(currentStatus.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")
        INPreferences.requestSiriAuthorization { status in
            print("[Siri] Authorization result: \(status.rawValue)")
            if status == .denied {
                print("[Siri] Siri access denied. User must enable in Settings > Siri & Search > Xonora")
            }
        }
        return true
    }

    func application(_ application: UIApplication, handle intent: INIntent, completionHandler: @escaping (INIntentResponse) -> Void) {
        if let playIntent = intent as? INPlayMediaIntent {
            let handler = SiriIntentHandler()
            handler.handle(intent: playIntent, completion: { response in
                completionHandler(response)
            })
        }
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard let interaction = userActivity.interaction,
              let intent = interaction.intent as? INPlayMediaIntent else {
            return false
        }
        let handler = SiriIntentHandler()
        handler.handle(intent: intent) { _ in }
        return true
    }

    // Handle notification while app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Sleep timer fired while app is in foreground
        if notification.request.identifier == "sleepTimer" {
            Task { @MainActor in
                // Silently fire pause and cancel timer
                PlayerManager.shared.cancelSleepTimer()
                try? await XonoraClient.shared.pause()
            }
        }
        // Don't show notification banner if app is in foreground
        completionHandler([])
    }

    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // User tapped the sleep timer notification
        if response.notification.request.identifier == "sleepTimer" {
            // Already handled by willPresent
        }
        completionHandler()
    }
}

@main
struct XonoraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var playerViewModel = PlayerViewModel()
    @StateObject private var libraryViewModel = LibraryViewModel()
    @ObservedObject private var preferences = UserPreferences.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if os(iOS)
        // Configure tab bar to be transparent and floating
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)

        // Add blur effect
        let blurEffect = UIBlurEffect(style: .systemMaterial)
        appearance.backgroundEffect = blurEffect

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, preferences.appLanguage == "system" ? .current : Locale(identifier: preferences.appLanguage))
                .environmentObject(playerViewModel)
                .environmentObject(libraryViewModel)
                .preferredColorScheme(preferences.preferredColorScheme)
                .tint(preferences.accentColor)
                .onAppear {
                    ShaderPrewarmer.shared.prewarm()

                    // Initialize LyricsManager to start observing queue
                    _ = LyricsManager.shared

                    // Activate Watch Connectivity
                    #if !os(watchOS)
                    WatchSessionManager.shared.activate()
                    #endif

                    // Note: Audio session is now configured in PlayerManager.init()
                    // This ensures it's set up before any playback attempts
                }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                print("[XonoraApp] App became active, refreshing state...")

                // Step 1: Clean up any dangling audio interruption state
                PlayerManager.shared.checkForegroundRecovery()

                // Invalidate metadata timestamps so stale library data is not served after backgrounding
                Task { await MetadataCache.shared.invalidateLibrary() }

                // Step 2: Verify and restore XonoraClient connection
                Task { @MainActor in
                    switch XonoraClient.shared.connectionState {
                    case .connected:
                        // Already connected, send ping to verify socket is alive (not zombie)
                        print("[XonoraApp] Server connected, verifying connection health...")
                        XonoraClient.shared.sendPing()

                    case .disconnected, .error:
                        // Not connected, trigger reconnection
                        print("[XonoraApp] Server not connected, triggering reconnection...")
                        XonoraClient.shared.reconnectAttempts = 0
                        XonoraClient.shared.reconnect()

                    case .connecting, .authenticating:
                        // Already attempting to connect, wait a moment
                        print("[XonoraApp] Connection in progress, will monitor...")
                    }
                }

                // Step 3: Verify Sendspin connection
                if !SendspinClient.shared.isConnected {
                    print("[XonoraApp] Sendspin not connected, attempting reconnection...")
                    SendspinClient.shared.reconnectIfNeeded()
                }

            } else if scenePhase == .background {
                print("[XonoraApp] App entering background with audio playback")

                #if os(iOS)
                // Request extended background time for audio playback
                var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
                backgroundTaskId = UIApplication.shared.beginBackgroundTask {
                    // Expiration handler - clean up if iOS needs to reclaim resources
                    print("[XonoraApp] Background task expiring")
                    if backgroundTaskId != .invalid {
                        UIApplication.shared.endBackgroundTask(backgroundTaskId)
                        backgroundTaskId = .invalid
                    }
                }

                // Dismiss keyboard to prevent snapshotting issues
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )

                // End background task explicitly to prevent resource leak
                // iOS will automatically keep the app alive for background audio
                Task {
                    // Brief delay to ensure state is saved
                    try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)

                    // Always end task since audio mode handles background lifecycle
                    if backgroundTaskId != .invalid {
                        print("[XonoraApp] State saved, ending background task")
                        UIApplication.shared.endBackgroundTask(backgroundTaskId)
                        backgroundTaskId = .invalid
                    }
                }
                #endif
            } else if scenePhase == .inactive {
                // App is transitioning (e.g., control center, notification)
                // Don't interrupt playback
                print("[XonoraApp] App became inactive (transitioning)")
            }
        }
    }
}
