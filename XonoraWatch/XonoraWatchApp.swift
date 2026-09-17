//
//  XonoraWatchApp.swift
//  XonoraWatch
//
//  Apple Watch app entry point for Xonora companion app.
//

import SwiftUI

@main
struct XonoraWatchApp: App {
    @StateObject private var dataProvider = WatchConnectivityProvider()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(dataProvider as WatchConnectivityProvider)
        }
    }
}
