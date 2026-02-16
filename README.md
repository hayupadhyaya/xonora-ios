# Xonora: Music Assistant Player for iOS & watchOS

Xonora is a high-performance, native iOS and Apple Watch client for [Music Assistant](https://music-assistant.io/). Built with SwiftUI and the custom **SendspinKit** audio engine, it delivers gapless, synchronized, and high-fidelity playback from your self-hosted server directly to your devices.

## Join the Community

**[Join our Discord Server](https://discord.gg/x6cWh4AjNG)** - Get support, share feedback, and connect with other users!

## Beta Testing

Xonora is currently in open beta. Join the public TestFlight to help test the app:

**[Join the Xonora TestFlight](https://testflight.apple.com/join/5rUk1uqN)**

> **Note:** Due to Apple's review process, new updates and builds may be delayed for up to **48 hours** before becoming available in TestFlight.

## What's New in v1.0.6

### Apple Watch Companion App
- **Full WatchConnectivity Integration**: Control playback, browse library, and switch players from your wrist
- **Now Playing**: Track info, artwork, and playback controls
- **Library Access**: Browse albums, artists, and playlists
- **Multi-Device Manager**: View and switch between all available players
- **Real-time Sync**: Instant updates via iPhone relay with 4/sec throttling

### Multi-Player Management
- **Seamless Player Transfer**: Switch between players with automatic position restoration
- **Enhanced Player Controls**: Inline menu showing all available players with active indicator
- **"Play on..." Context Menu**: Quick player selection directly from track rows
- **Toast Notifications**: Visual feedback when switching players
- **State Protection**: Robust queue event filtering prevents corruption when multiple players are active

### Content & Discovery
- **Podcasts**: Full support with dedicated view, grid layout, and chapter navigation
- **Radio Stations**: Browse and play internet radio streams
- **Provider Branding**: Visual identification of streaming services (Spotify, Apple Music, Tidal, Qobuz, etc.) with colored icons throughout the app
- **Enhanced Search**: Universal search with filter chips (All, Songs, Albums, Artists, Playlists, Audiobooks, Podcasts, Radio)
- **Recently Played**: Server-side recently played items on Home screen

### Playback & Audio
- **Consolidated Sleep Timer**: Integrated sleep timer (5/15/30/45/60 min) with background notifications and persistence
- **Improved Reliability**: Proactive reconnection (up to 5 retries), lock screen stability, keep-alive logic
- **Enhanced Error Handling**: Graceful playback failure recovery, better state synchronization
- **Interruption Handling**: Automatic resume after phone calls and other audio interruptions

### User Experience
- **Customization**: Appearance settings (tint color, dark/light mode), customize Home sections, reorder/hide tabs
- **Marquee Text**: Auto-scrolling for long track titles in player
- **Lyrics Engine**: Dual-layer cache (memory + disk) with adjustable offset for sync correction
- **Playback History**: Persistent "Recently Played" and "Continue Listening" sections

### Under the Hood
- **Critical Bug Fixes**: Player state decoding, playlist favorites, queue synchronization
- **Performance Improvements**: Lazy metadata loading, memory leak fixes, optimized image caching
- **Architecture Refinements**: Removed standalone SleepTimerManager, enhanced XonoraClient with new API methods
- **AppDelegate Integration**: Proper notification handling for sleep timer and background events

## Core Features

### Audio Streaming
- **Sendspin Protocol**: Lossless PCM/FLAC audio streaming with dynamic buffering
- **Gapless Playback**: Seamless transitions between tracks
- **Hardware Acceleration**: vDSP/SIMD audio processing with Accelerate framework
- **Background Audio**: Continuous playback with lock screen controls
- **Remote Controls**: Lock screen, Control Center, and Bluetooth hardware button support
- **CarPlay**: Full library browsing and Now Playing screen

### Library & Content
- **Music**: Albums, Artists, Tracks, Playlists with full browsing and search
- **Audiobooks**: Dedicated view with chapter support and playback controls
- **Podcasts**: Browse episodes with grid layout
- **Radio**: Internet radio station support
- **Favorites**: Heart/favorite any media type
- **Add to Library**: Search and add content from streaming services

### Metadata & Caching
- **Local Metadata Cache**: Disk-backed cache with 1-hour expiry for instant library loads
- **Image Cache**: In-memory caching with size-aware URLs for optimal performance
- **Intelligent Artwork**: Seamless handling of local (Plex/SMB) and CDN (Apple Music, TheAudioDB) images

### Server Integration
- **mDNS Discovery**: Automatic local network scanning for Music Assistant servers
- **Access Token Auth**: Secure authentication (Schema 28+)
- **WebSocket Protocol**: Efficient real-time communication with Music Assistant API
- **Event-Driven Updates**: Real-time sync of library changes, queue updates, and player states

## Completed Features from Development Plan

### Phase 1: Core Library Enhancements ✅
- ✅ **Playlists Support**: Full browsing and playback
- ✅ **Favorites (Hearting)**: Toggle favorites for tracks, albums, artists, playlists, audiobooks
- ✅ **Radio Integration**: Browse and play radio stations

### Phase 2: Player & Queue Improvements 🟡
- ✅ **Player Transfer**: Seamless switching with position restoration
- ✅ **Advanced Queue**: Drag-to-reorder, swipe-to-delete, "Play Next" and "Add to Queue" context menus
- ⏳ **Player Grouping**: (Partially implemented) Improvements in future releases

### Phase 3: Content & Sync ✅
- ✅ **Podcasts**: Dedicated view with full support
- ✅ **Real-time Sync**: Event-driven library and queue updates
- ✅ **Enhanced Search**: Multi-type search with filtering

### Phase 4: UI/UX Polish 🟡
- ✅ **Customization**: Appearance settings, Home customization, Tab reordering
- ✅ **Provider Branding**: Service-specific icons and colors
- ✅ **Toast Notifications**: System-wide toast manager
- ⏳ **Adaptive Theming**: Album art color extraction (planned)
- ⏳ **Letter Scrollbar**: Fast navigation (planned)

## Requirements

### iOS App
- **iOS**: 17.0 or later
- **Music Assistant Server**: Version 2.0 (Schema 28) or later
- **Sendspin**: The Sendspin player provider must be enabled on your server

### Apple Watch App
- **watchOS**: 10.0 or later
- **iPhone**: Must be running Xonora iOS app for WatchConnectivity relay
- **Network**: Watch uses iPhone as relay (WiFi/cellular not required on Watch)

## Architecture

### Design Pattern
- **MVVM**: Strict separation between views, view models, and data models
- **SwiftUI**: Modern declarative UI framework
- **Combine**: Reactive data flow for state management

### Key Components
- **SendspinKit**: Standalone Swift Package for Sendspin protocol and audio engine
  - WebSocket transport layer
  - AVAudioEngine-based playback
  - Hardware-accelerated audio processing (vDSP/SIMD)
  - Multi-codec support (PCM, FLAC, Opus)
  - Burst clock synchronization
- **XonoraClient**: Music Assistant WebSocket API client
- **PlayerManager**: Playback state, remote controls, lock screen integration
- **MetadataCache & ImageCache**: Actor-based caching with disk persistence
- **WatchSessionManager**: WatchConnectivity bridge between iOS and watchOS

### Service Layer
- **MultiDeviceManager**: Tracks state for all Music Assistant players
- **PlaybackHistoryManager**: Persistent playback history
- **LibraryViewModel**: Global library data access
- **CarPlaySceneDelegate**: CarPlay integration

## Release History

### Version 1.0.6 (Current)
- Apple Watch companion app
- Multi-player management with seamless transfer
- Podcasts and Radio support
- Provider branding throughout the app
- Consolidated sleep timer
- Enhanced search with filters
- Critical bug fixes and performance improvements

### Version 1.0.5
- mDNS Discovery for automatic server scanning
- Hardware volume control
- Artist navigation fixes
- Shuffle logic overhaul
- Intelligent artwork handling
- Auto-reconnection with exponential backoff
- Background library decoding

### Version 1.0.4
- TabView categories for library
- Persistent mini player
- Auto-player selection
- Search UX improvements
- Queue fixes
- Stability improvements

### Version 1.0.3
- Songs tab
- Track management
- Metadata caching

## License

This project is open-source software for personal use with Music Assistant.

---

**Enjoy your music with Xonora! 🎶**

For support, feature requests, or to report bugs, join our [Discord community](https://discord.gg/x6cWh4AjNG) or open an issue on GitHub.
