//
//  WatchRootView.swift
//  XonoraWatch
//
//  Root TabView for the Watch app.
//

import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject var dataProvider: WatchConnectivityProvider

    var body: some View {
        TabView {
            NavigationStack {
                WatchNowPlayingView()
            }
            .tabItem {
                Label("Now Playing", systemImage: "play.circle.fill")
            }

            NavigationStack {
                WatchDevicesView()
            }
            .tabItem {
                Label("Devices", systemImage: "hifispeaker.2.fill")
            }

            NavigationStack {
                WatchLibraryView()
            }
            .tabItem {
                Label("Library", systemImage: "music.note.list")
            }
        }
    }
}

#if DEBUG
#Preview {
    WatchRootView()
        .environmentObject(WatchConnectivityProvider.previewPlaying)
}
#endif
