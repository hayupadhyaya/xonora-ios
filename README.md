# Xonora: Music Assistant Player for iOS

Xonora is a high-performance, native iOS client for [Music Assistant](https://music-assistant.io/). Built with SwiftUI and the custom **SendspinKit** audio engine, it delivers gapless, synchronized, and high-fidelity playback from your self-hosted server directly to your iOS device.

## Beta Testing

Xonora is currently in open alpha. You can join the public TestFlight to help test the app on your device:

**[Join the Xonora TestFlight](https://testflight.apple.com/join/5rUk1uqN)**

> **Note:** Due to Apple's review process, new updates and builds may be delayed for up to **48 hours** before becoming available in TestFlight.

## Screenshots

<p align="center">
  <img src="V1.0.4 Screenshots/AlbumsView.PNG" width="200" alt="Albums View"/>
  <img src="V1.0.4 Screenshots/SongsView.PNG" width="200" alt="Songs View"/>
  <img src="V1.0.4 Screenshots/PlaylistsView.PNG" width="200" alt="Playlists View"/>
</p>

<p align="center">
  <img src="V1.0.4 Screenshots/ArtistView.PNG" width="200" alt="Artists View"/>
  <img src="V1.0.4 Screenshots/NowPlayingView.PNG" width="200" alt="Now Playing"/>
  <img src="V1.0.4 Screenshots/SettingsView.PNG" width="200" alt="Settings"/>
</p>

## Key Features

### **Initially Implemented**
*   **Native SwiftUI Interface:** Clean, Apple Music-inspired UI.
*   **Sendspin Streaming:** Lossless PCM/FLAC audio streaming via the Sendspin protocol.
*   **Library Browsing:** Access to Albums, Artists, and Playlists.
*   **Remote Command Center:** Support for Lock Screen controls and Bluetooth hardware buttons.

### **Major Improvements (v1.0.4)**
*   **mDNS Discovery:** Automatic local network scanning for Music Assistant servers—no more manual IP entry.
*   **Hardware Volume Control:** The in-app volume slider now directly controls the device/player volume.
*   **Artist Navigation:** Fixed the artist list functionality. Tapping an artist now correctly navigates to an Artist Detail View featuring top tracks and albums.
*   **Shuffle Logic Overhaul:** Fully redesigned shuffle behavior. Skips now strictly follow the shuffled queue order, and toggling shuffle actively randomizes the current session.
*   **Intelligent Artwork:** Seamlessly handles local Plex/SMB art via proxy while fast-loading public CDN images (Apple Music, TheAudioDB) directly.
*   **Robust Connectivity:** Added auto-reconnection with exponential backoff and instant foreground recovery if the connection drops during background suspension.
*   **Performance Engine:** Background library decoding and optimized rendering to eliminate the 15-second startup "hang" for large libraries.

## Upcoming Features
*   **Audiobooks:** Dedicated support for browsing and streaming your audiobook collection.
*   **Podcasts:** Full integration for discovering and listening to your favorite podcasts.
*   **Radio:** Access to live radio stations and internet radio streams via Music Assistant.

## Release Notes

### Version 1.0.4
*   **TabView Categories:** Refactored the Library category pane (Albums, Songs, Playlists, Artists) into a system-managed TabView. Switch categories by tapping the top bar or swiping horizontally.
*   **Persistent Mini Player:** Added a Mini Player bar that overlays the Library and Search tabs for quick access to controls while browsing.
*   **Auto-Player Selection:** The app now proactively selects your iPhone as the active player as soon as the Sendspin connection is established.
*   **Search UX:** Added automatic keyboard dismissal when scrolling through search results.
*   **"Playing From" Context:** Improved the player labels to accurately show the playback source (e.g., "Songs," "Search," or specific Album).
*   **Queue Fixes:** Resolved an issue where the queue button was unresponsive and fixed a bug where skipping tracks would occasionally clear the remaining queue.
*   **Stability:** Increased WebSocket timeouts to 24 hours and implemented safe log truncation to prevent system-level crashes.

### Version 1.0.3
*   **Songs Tab:** Added a dedicated view for individual tracks in the library.
*   **Track Management:** Ability to add or remove individual tracks to/from your library.
*   **Metadata Caching:** Added local persistence with 1-hour expiry for instant subsequent library loads.

## Requirements
*   **iOS:** 17.0 or later.
*   **Music Assistant Server:** Version 2.0 (Schema 28) or later.
*   **Sendspin:** The Sendspin player provider must be enabled on your server.

## Architecture
*   **MVVM Design:** Strict separation of concerns between views, logic, and data.
*   **SendspinKit:** A dedicated audio subsystem handling binary streams, clock synchronization, and vDSP-accelerated volume scaling.
*   **URLSession WebSocket:** Modern, efficient networking using system-standard protocols for long-lived connections.

## License
This project is open-source software for personal use with Music Assistant.

---

**Enjoy your music with Xonora! 🎶**