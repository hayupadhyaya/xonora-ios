# Xonora: Music Assistant Player for iOS, watchOS & CarPlay

Xonora is a high-performance, native client for [Music Assistant](https://music-assistant.io/) running on iPhone, Apple Watch, and CarPlay. Built with SwiftUI and the custom **SendspinKit** audio engine, it delivers gapless, synchronized, and high-fidelity playback from your self-hosted server directly to your devices.

## Join the Community

**[Join our Discord Server](https://discord.gg/x6cWh4AjNG)** - Get support, share feedback, and connect with other users!

## Beta Testing

Xonora is currently in open alpha. Join the public TestFlight to help test the app:

**[Join the Xonora TestFlight](https://testflight.apple.com/join/5rUk1uqN)**

> **Note:** Due to Apple's review process, new updates and builds may be delayed for up to **48 hours** before becoming available in TestFlight.

## What's New in v1.0.7

### CarPlay — Major Overhaul

The CarPlay experience has been rebuilt from the ground up. This is the centerpiece of v1.0.7

- **Tab Bar Navigation**: Dedicated Home, Library, Queue, and Now Playing tabs
- **Home Tab**: Horizontal scrolling artwork rows for Continue Listening, Recently Played, and Recommendations — synced with your iOS home screen
- **Library Drill-Down**: Browse Artists -> Albums -> Tracks directly from the dashboard
- **Queue Tab**: Live queue with current-track indicator; tap any item to jump playback
- **Now Playing Favorites**: Heart tracks directly from the CarPlay Now Playing screen
- **Siri Integration**: "Hey Siri, play..." media intent support (Will not play anything yetTo Do)
- **Template & Image Caching**: Album and playlist track templates cached in memory — no artwork reload on back/re-enter. Disk-cached 240x240 resized images for smooth scrolling (Super slow on initial load)
- **Performance**: Debounced home rebuilds (300ms) to prevent UI freezes; stable reconnect behavior with persistent cancellables

### Authentication — Username & Password

Gone are the days of hunting for access tokens, copying them from browser dev tools, and praying you didn't accidentally grab an expired one. Xonora now supports proper **username and password login** as the default authentication method. Credentials are stored securely in the Keychain. Token auth is still available as a fallback for the nostalgic.

- **Server Setup**: New toggle between Username/Password and Token auth modes
- **Keychain Storage**: Credentials stored securely via `KeychainHelper`
- **User & Provider Info**: Settings page now shows your logged-in user and connected providers

### Library Sort & View Modes

- **Sort Options**: Sort any library section by name (A-Z, Z-A) or date added (newest/oldest)
- **View Mode Toggle**: Switch between grid and list view per category
- **Grid Column Customization**: Configurable column counts for portrait and landscape, with separate settings per category — moved to Settings > Personalization
- **Device-Aware Layouts**: Accurate iPhone vs iPad detection for proper column defaults (Still no officail iPad support, only tested on my Mac as an iPad app)

### Audio & Lyrics

- **Hardware-Anchored Lyrics**: Lyrics timing now syncs automatically with the hardware audio clock — is it is out of sync pause and resume to fix it
- **Playback Drift Fix**: Eliminated time drift by using hardware engine time for both `currentTime` and `audioSyncedTime`
- **Larger Audio Buffer**: Increased from ~4.8s to ~30s
- **Volume Debounce**: Single command on slider release prevents Cast device (Nest Hub) volume fluctuations (Needs to be verified)

### watchOS Fixes

- **Player Switch**: Clearing stale state before restoring on player switch
- **Interactive Player Pill**: Tappable player indicator navigates to device switcher

### Other

- **Large Library Pagination**: Count-based pagination with concurrent category loading for libraries exceeding API limits (Needs to be verified)
- **Response Format Handling**: Graceful parsing of multiple JSON response structures from the server

## Core Features

### Audio Streaming

- **Sendspin Protocol**: Lossless PCM/FLAC audio streaming with dynamic buffering
- **Gapless Playback**: Seamless transitions between tracks
- **Hardware Acceleration**: vDSP/SIMD audio processing with Accelerate framework
- **Background Audio**: Continuous playback with lock screen controls
- **Remote Controls**: Lock screen, Control Center, and Bluetooth hardware button support
- **CarPlay**: Full tab bar with Home, Library, Queue, and Now Playing; drill-down browsing, template caching, Siri intent

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
- **Username/Password Auth**: Secure login with Keychain storage (token fallback available)
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
- ✅ **Library Sort & View Modes**: Sort options, list/grid toggle, column count customization
- ✅ **Adaptive Theming**: Album art color extraction (planned)
- ⏳ **Letter Scrollbar**: Fast navigation (planned)

### Phase 5: Platform Expansion ✅

- ✅ **Apple Watch**: Full WatchConnectivity companion app
- ✅ **CarPlay**: Tab bar with Home/Library/Queue, artwork, drill-down browsing, Siri intent, template caching

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
- **CarPlaySceneDelegate**: CarPlay integration with tab bar, cached templates, and image caching

## Release History

### Version 1.0.7 (Current)

- CarPlay rebuilt: tab bar with Home/Library/Queue/Now Playing, drill-down browsing, template caching, performance fixes
- Username/password authentication with Keychain storage (token fallback)
- Library sort options and grid/list view toggle per category
- Hardware-anchored lyrics timing and playback drift fix
- Larger audio buffer (~30s) for stutter-free playback
- Queue: swipe-to-delete
- watchOS album views with full-screen artwork
- Large library pagination support

### Version 1.0.6

- Apple Watch companion app
- Multi-player management with seamless transfer
- Podcasts and Radio support
- Provider branding throughout the app
- Consolidated sleep timer
- Enhanced search with filters
- Critical bug fixes and performance improvements
- Updated app icon

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
