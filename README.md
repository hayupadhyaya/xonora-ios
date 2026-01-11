# Xonora: Music Assistant Player for iOS

Xonora is a high-performance, native iOS client for Music Assistant. Built with SwiftUI and the custom **SendspinKit** audio engine, it delivers gapless, synchronized, and high-fidelity playback from your self-hosted server directly to your iOS device.

## Screenshots

<p align="center">
  <img src="V1.0.3 Screenshots/LoginView.PNG" width="200" alt="Login Screen"/>
  <img src="V1.0.3 Screenshots/SettingsView.PNG" width="200" alt="Settings"/>
  <img src="V1.0.3 Screenshots/Library View_Album.PNG" width="200" alt="Library View"/>
</p>

<p align="center">
  <img src="V1.0.3 Screenshots/AlbumView.PNG" width="200" alt="Album Detail"/>
  <img src="V1.0.3 Screenshots/NowPlayingView.PNG" width="200" alt="Now Playing"/>
  <img src="V1.0.3 Screenshots/SearchView.PNG" width="200" alt="Search"/>
</p>

## Release Notes

### Version 1.0.3

This release focuses on library management, network stability, and bug fixes.

#### Library Features
- **Songs Tab:** Added a dedicated "Songs" tab in the Library to view individual tracks separately from albums
- **Track Management:** You can now add individual tracks to your library and view them independently
  - Adding a single track shows only that track in the Songs section
  - Opening the album from a track displays all tracks in the album, not just the ones in your library
  - This behavior matches how Music Assistant handles library items on the server side (applies when using providers like Apple Music)
- **Improved Track Display:** Track numbers now appear before artwork in the Songs view for easier navigation
- **Fixed Library Playback:** Resolved issues that prevented playing random tracks from the Library

#### API & Network Improvements
- **Music Assistant API:** Fixed incorrect API commands (now using `music/library/add_item` and `music/favorites/add_item`)
- **Network Stability:** Eliminated "Reporter disconnected" errors by implementing a shared URLSession with connection pooling
- **Timeout Handling:** Increased WebSocket timeout from 5 to 30 seconds for more reliable connections
- **HTTP/3 Disable:** Disabled QUIC protocol for local servers to prevent packet parsing errors
- **Reduced Stuttering:** Optimized image loading and network requests to eliminate audio interruptions during playback

#### UI & UX Fixes
- **Full-Screen Views:** Fixed black rectangles that appeared at the top and bottom of library scroll views
- **Dynamic Version Display:** App version now reads directly from bundle info
- **Metadata Caching:** Added track caching with 1-hour expiry for faster library loading

#### Technical Improvements
- **Color Management:** Resolved duplicate color definition build errors
- **URLSession Optimization:** Single shared session with ephemeral configuration and 4 concurrent connections per host
- **Memory Efficiency:** Improved image cache with better resource management

### Version 1.0.1 alpha

This release introduces significant architectural improvements to the audio subsystem and network layer.

#### Audio Engine (SendspinKit)
- **New Audio Architecture:** Fully integrated **SendspinKit**, a custom audio engine built on `AVAudioEngine` and `Accelerate` (vDSP).
- **Stutter-Free Playback:** Implemented a new timestamp-based audio scheduler with a tight 5ms processing loop and a 400ms jitter buffer window.
- **Improved Buffer Management:** Added a critical drop threshold of 600ms and burst clock synchronization to handle network variances without audible artifacts.
- **Thread Safety:** Rewrote the client core using `os_unfair_lock` and strict thread isolation. Audio processing now runs on a dedicated high-priority serial queue, completely decoupled from the UI thread.
- **Volume Processing:** Implemented hardware-accelerated (vDSP) volume scaling for high-efficiency PCM manipulation.

#### Connectivity & Stability
- **Connection Timeout:** Added a 5-second strict timeout for server connections. The app now fails fast if the server is unreachable, preventing indefinite UI hangs.
- **Authentication Handshake:** Fixed the Sendspin protocol handshake (`AuthMessage` -> `AuthOKMessage`) to correctly pass and validate access tokens.
- **Proxy Bypass:** Implemented strict proxy bypass for local network connections to ensure low-latency discovery and streaming.
- **Deployment Target:** Updated minimum deployment target to iOS 17.0 to leverage modern concurrency features.

## Features

- **Native Interface:** A clean, Apple Music-inspired UI built entirely with SwiftUI.
- **Sendspin Streaming:** Stream lossless PCM/FLAC audio directly from your Music Assistant server.
- **CarPlay Support:** Full CarPlay integration for browsing and playback in the vehicle.
- **Library Management:** Browse albums, artists, songs, and playlists with search capabilities and individual track management.
- **Background Playback:** Robust background audio support with Lock Screen and Control Center integration (`MPNowPlayingInfoCenter`).
- **Real-time Updates:** Persistent WebSocket connection for instant state synchronization across devices.

## Requirements

- iOS 17.0 or later
- Music Assistant Server (Schema 28+)
- Sendspin Player Provider enabled in Music Assistant

## Installation

1. Clone the repository.
2. Open `Xonora.xcodeproj` in Xcode 15+.
3. Configure your signing team in project settings.
4. Build and run on a physical device (Sendspin audio streaming requires a real network interface).

## Configuration

1. **Server Connection:** On first launch, enter your Music Assistant server URL (e.g., `http://192.168.1.50:8095`) and a valid access token.
2. **Audio Setup:**
   - Ensure the **Sendspin** provider is installed and enabled in Music Assistant.
   - In Xonora settings, enable "Sendspin Streaming".
   - The app will automatically advertise itself as a player to the server.

## Architecture

The project follows a strict MVVM (Model-View-ViewModel) pattern with a clear separation of concerns:

- **XonoraClient:** Singleton responsible for the persistent WebSocket control connection and Music Assistant API calls.
- **SendspinClient / SendspinKit:** A dedicated subsystem for handling the high-speed binary audio stream, clock synchronization, and audio rendering.
- **PlayerManager:** Central coordinator for playback state, UI updates, and remote command handling.

## License

This project is open-source software for personal use with Music Assistant.
