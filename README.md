# Xonora: Music Assistant Player for iOS

Xonora is a high-performance, native iOS client for Music Assistant. Built with SwiftUI and the custom **SendspinKit** audio engine, it delivers gapless, synchronized, and high-fidelity playback from your self-hosted server directly to your iOS device.

## Release Notes

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
- **Library Management:** Browse albums, artists, and audiobooks with search capabilities.
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