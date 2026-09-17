# Architecture

Technical notes for anyone reading or building on this code. See the top-level [README](README.md) for the archived-repo notice — this describes the original Swift-only Xonora app (v1.0.8).

## Build & Test

**Requirements**: Xcode 26, Swift 6 toolchain (SendspinKit is a swift-tools 6.0 package), deployment targets iOS 18.0 / watchOS 26.2 (see `project.pbxproj`)

```bash
# Build iOS app for simulator
xcodebuild -project Xonora.xcodeproj -scheme Xonora -destination 'generic/platform=iOS Simulator' build

# Build companion app
xcodebuild -project Xonora.xcodeproj -scheme "XonoraWatch Watch App" build

# Build SendspinKit on its own
cd SendspinKit && swift build

# Run SendspinKit tests
cd SendspinKit && swift test

# Run a single test class
cd SendspinKit && swift test --filter SendspinKitTests.AudioPlayerTests

# Lint SendspinKit (config: SendspinKit/.swiftlint.yml)
cd SendspinKit && swiftlint

# Clean build
xcodebuild clean -project Xonora.xcodeproj -scheme Xonora

# Fix SPM "Conflicting identity" errors
xcodebuild -project Xonora.xcodeproj -scheme Xonora -resolvePackageDependencies
```

## Architecture

Xonora is a **multi-platform Music Assistant client** (iOS, watchOS, CarPlay) built with **MVVM + SwiftUI + Combine**.

### Project Structure

```
Xonora/
├─ Views/             SwiftUI views organized by feature
├─ Views/Components/  Reusable UI components
├─ ViewModels/        ObservableObject view models with @Published state
├─ Models/            Codable data objects (Track, Album, Artist, Playlist, etc.)
├─ Services/          Singletons (.shared pattern) for business logic

SendspinKit/          Local SPM package — audio engine (AVAudioEngine + vDSP/SIMD)
XonoraWatch/          watchOS companion (WatchConnectivity relay)
Shared/               Types shared between iOS and watchOS targets
```

### Data Flow

```
View → ViewModel → XonoraClient (WebSocket) → Music Assistant Server
                                                      ↓
                                    PlayerManager → SendspinKit (AVAudioEngine)
                                                      ↓
                                    Lock Screen / Remote Controls
```

### Key Singletons

| Service | Purpose |
|---------|---------|
| `XonoraClient.shared` | Music Assistant WebSocket API, player selection, commands |
| `SendspinClient.shared` | Audio streaming (Sendspin protocol, port 8927) |
| `PlayerManager.shared` | Playback state, progress, remote controls, lock screen |
| `MetadataCache.shared` | Albums/artists/playlists/tracks (memory + disk, 1-hour expiry) |
| `ImageCache.shared` | In-memory artwork cache with size-aware URL generation |
| `LibraryViewModel.shared` | Global library data (used by views and CarPlay) |
| `MultiDeviceManager.shared` | State for all connected MA players |
| `UserPreferences.shared` | `@AppStorage` persistence (home layout, appearance, lyrics) |
| `WatchSessionManager.shared` | iOS <-> watchOS Combine bridge |

### Targets & Schemes

| Scheme | Platform | Purpose |
|--------|----------|---------|
| `Xonora` | iOS 18+ | Main iPhone/iPad app (CarPlay + Siri intents) |
| `XonoraIntents` | iOS 18+ | Siri intents extension |
| `XonoraWatch Watch App` | watchOS 26.2+ | Apple Watch companion |
| `SendspinKit` | iOS/watchOS/macOS | Audio streaming library (local SPM package, Apache-2.0 — see `NOTICE`) |

## Localization

**Localizable.xcstrings** supports **34 languages** covering all iOS-supported locales:
- **Germanic/Nordic** (5): Dutch (nl), Danish (da), Norwegian Bokmål (nb), Swedish (sv), Finnish (fi)
- **Central/Eastern European** (6): Polish (pl), Czech (cs), Slovak (sk), Croatian (hr), Hungarian (hu), Romanian (ro)
- **Eastern European/Mediterranean** (4): Ukrainian (uk), Greek (el), Turkish (tr), Catalan (ca)
- **RTL** (2): Arabic (ar), Hebrew (he)
- **Asian/Southeast Asian** (5): Hindi (hi), Thai (th), Vietnamese (vi), Indonesian (id), Malay (ms)
- **Portuguese variant** (1): Portuguese (Portugal) (pt-PT)
- **Existing** (11): German (de), English (en), Spanish (es), French (fr), Italian (it), Japanese (ja), Korean (ko), Portuguese (Brazil) (pt-BR), Russian (ru), Simplified Chinese (zh-Hans), Traditional Chinese (zh-Hant)

**Language Selection**: Settings > Personalization > `LanguageView` (dedicated full-page list with native names, English subtitles, and checkmarks). Uses dynamic locale override via `@Environment(\.locale)` set at app root in `XonoraApp.swift`. Coverage: 100% for all 34 languages (290 keys each). Translation source files stored in `Locales/*.json`.

**Notes on translation implementation**:
- Format specifiers (%@, %lld, %%) and positional formats (%1$@, %2$@) must be preserved exactly
- RTL languages (Arabic, Hebrew): string content only, no special xcstrings handling required
- Portuguese variants (PT vs BR) differ in specific terminology (e.g., "Definições" vs "Configurações")
- Transcription accuracy for brand names (e.g., "Guns N' Roses" normalization) is handled in code, not translations

## Critical Patterns & Pitfalls

- **URLSession proxy bypass**: Both `XonoraClient` and `ImageCache` must set `connectionProxyDictionary = [:]` to bypass iCloud Private Relay for local MA server connections
- **Shared models**: `Shared/WatchModels.swift` must be in **both** Xonora and XonoraWatch target memberships
- **CarPlay list items**: `createListItem()` must always include `imageUrl:` parameter; omitting causes placeholder-only display
- **CarPlay reconnection**: `didDisconnect` must be internal (not private) for iOS protocol dispatch. In `didConnect`, check connection state and post `.reconnectRequired` if disconnected, then subscribe to reconnection
- **Combine `.dropFirst()`**: Must be applied per-publisher **before** merging/debouncing, not after
- **Audio thread safety**: SendspinKit uses `os_unfair_lock` for critical audio paths where actor overhead is too high
- **Concurrency model**: Actors for caches (`MetadataCache`, `ImageCache`), `@MainActor` for `UserPreferences`, dedicated high-priority serial queue for audio processing
- **SwiftLint**: Only enforced in SendspinKit (`SendspinKit/.swiftlint.yml`) -- run before committing audio-critical changes
- **Lyrics time source**: LyricsView uses `TimelineView` at 10Hz polling `PlayerManager.lyricsTime + UserPreferences.shared.lyricsOffset` (live AVAudioPlayerNode hardware time). The offset is user-adjustable (−2.0 to +2.0s) in Settings. Do NOT use `audioSyncedTime` or `currentTime` for lyrics -- they are progress-timer-driven and too coarse
- **Loading state calibration**: During `.loading` state, server `elapsed_time` advances while audio buffers. `streamStartServerElapsed` must NOT be recalibrated during loading -- use `loadingStartElapsed` (captured when loading begins) as the baseline when transitioning to `.playing`
- **Now Playing dynamic padding**: Uses `GeometryReader` scale factor (`height / 812`, clamped 0.7-1.15). Player destination pill is anchored via `safeAreaInset(edge: .bottom)` on the portrait ScrollView, not inline with PlayerControls
- **Now Playing menu flicker prevention**: `_TrackOptionsMenu`, `_SleepTimerMenu`, and `_SpeedMenu` are extracted as `Equatable`-conforming view structs. This prevents the 0.25s progress timer (`@Published var currentTime`) from tearing down open Menu popovers
- **Siri playback**: Matching uses a unified `matchScore()` with article stripping (`"Beatles"` == `"The Beatles"`), word-overlap tiers (≥75%/≥50% of query words), and reverse-contains. Generic `bestMatch<T>()` ranks all candidates by score — do NOT revert to unranked `first(where:==) ?? first(where:contains)` chains. Vocabulary registers playlists, artists, albums (`.mediaAudiobookTitle`), and podcasts (`.mediaShowTitle`) — call signature is `updateSiriVocabulary(playlists:artists:albums:podcasts:)`. Add 5-second connection wait loop for cold Siri launches. Prefer tracks over artists in fallthrough
- **Image URL expiry (imageproxy auth tokens)**: `ImageCache` forcibly clears its in-memory cache when app comes to foreground via `scenePhase` change in `XonoraApp.swift`. Reason: MA's imageproxy embeds auth tokens in URLs that expire during backgrounding. Without the clear, the app serves stale URLs from cache that produce silent 404s. HTTP 404 responses from imageproxy are silently swallowed in `ImageCache.swift` — do NOT treat them as hard errors
- **Search result navigation (overlay pattern)**: `GlobalNavigationViewModel` exposes one optional `@Published` property per navigable type (`selectedAlbum`, `selectedArtist`, `selectedPlaylist`, `selectedAudiobook`, `selectedPodcast`). `ContentView` renders each as a fullscreen overlay at `zIndex 3` with slide-from-trailing transition. Detail views must NOT be NavigationLinks inside `GlobalSearchSheet` — this trapped users inside the modal. Navigation is triggered by setting the property (not NavigationLink), which simultaneously dismisses the search sheet
- **BarVisibilityManager scroll behavior**: `BarVisibilityManager` (@Observable, not singleton — one per view context) controls scroll-to-compact tab bar. Compacts only after accumulating 80pt of downward scroll (`compactThreshold`). Never compacts within 200pt of scroll bottom (`bottomBuffer`) — prevents rubber-band bounce from toggling. Expands only when offset returns to 0 (top). Use `trackScrollForBars()` View extension to wire it up
- **Grouped player time source**: `PlayerManager` checks if active player has `syncedTo` or `groupChilds` fields in the server player object. If grouped or remote (`!isCurrentPlayerLocal`): use `elapsed_time` from server queue updates directly. If local single player: use `streamStartServerElapsed + engineTime` hardware time. Never use hardware time for grouped or remote players
- **Phone call interruption state machine**: `InterruptionState` in `PlayerManager` tracks `wasPlaying` across duplicate AVAudioSession `.began` notifications (which fire after CallKit already pauses playback). The `.began` handler preserves `wasPlaying: true` from any existing `.interrupted`/`.callInterrupted` state — do NOT overwrite with `playbackState == .playing` unconditionally. `resumeAfterInterruption()` reads `wasPlaying` then immediately sets `.handled` before delegating to `play()` — do NOT set `.handled` at the call site before calling the function
- **Persistent reconnection**: `XonoraClient.reconnect()` and `SendspinClient.attemptReconnect()` never give up — delay is `min(attempts × 2, 60s)`. The only stop condition is `userInitiatedDisconnect = true` (set by explicit `disconnect()` calls). Do NOT add a `maxReconnectAttempts` cap — long phone calls exhaust capped retry counts and leave clients in permanent `.error` state
- **Resume after long interruption**: `resumeAfterInterruption()` reactivates the audio session then calls `play()` directly. `play()` sets `pendingPlayAfterReconnect = true` if XonoraClient is disconnected; the `$connectionState` observer fires `resumeWithSavedTrackVerification()` when connection restores. Do NOT add sleep-poll loops inside `resumeAfterInterruption()` — they race against connection timing and silently drop the resume intent when they time out
- **Long-pause resume (queue drift protection)**: When `pendingPlayAfterReconnect` fires on reconnection, `resumeWithSavedTrackVerification()` fetches the server's current queue and compares it against the locally saved track URI (from `savePlaybackPosition()` in `pause()`). If the server's queue cursor drifted (common after long pauses — MA server may auto-advance or start a "continue listening" item), it explicitly calls `playMedia(uris: [savedURI])` + `seek()` to restore the correct track at the correct position. For short pauses (<30s), it falls through to generic `play()`. The method handles audio session activation and SendspinClient reconnection inline — do NOT delegate to `play()` from the drift path, as that introduces race conditions between the Task `play()` spawns and the seek call
- **Remote player isolation**: ALL `SendspinClient` calls and `AVAudioSession` activation must be gated behind `isCurrentPlayerLocal` (compares `XonoraClient.currentPlayer.playerId == SendspinClient.clientId`). This applies in `play()`, `pause()`, AND `handleQueueUpdate()` — the queue event handler has SendspinClient calls in every state branch (playing/paused/idle/stopped). Without this guard, controlling a remote player also controls the local audio engine. Remote players use server time directly for time calibration (no engine time)
- **Queue event dual notifications**: `XonoraClient` posts two notifications for `queue_updated` server events: `.allQueuesUpdated` (unfiltered — every player's events) and `.queueUpdated` (filtered to current player only). `MultiDeviceManager` subscribes to `.allQueuesUpdated` to track all players. `PlayerManager` subscribes to `.queueUpdated` for current-player state. Do NOT filter `.allQueuesUpdated` by player ID — that was the original bug that prevented `MultiDeviceManager` from seeing remote player state changes
- **Player switcher (long-press mini player)**: `PlayerSwitcherPopup` shows only active players (playing/paused with a track) **excluding** the current player (already visible in the mini player). Each player renders as a mini-player-style capsule card with artwork, progress bar, and inline play/pause + next controls. Controls use `XonoraClient.shared.playPause(playerId:)` to target the specific player. Tapping the card itself switches `setPreferredPlayer`. Cards stack upward with 6pt spacing (matching tab bar gap)

## Safety & Stability

**Crash Prevention**:
- XonoraClient: Fixed double continuation resume (guaranteed crash)
- SendspinClient: Added safe continuation helper to prevent double-resume on rapid reconnects
- CarPlaySceneDelegate: Replaced IUO properties with optionals + guard-let guards
- MetadataCache/ImageCache: Fallback from fatalError to temporaryDirectory
- PlayerViewModel: Added deinit to clean up NotificationCenter observers
- AudioPlayer: Added bounds validation for interleaved sample access
- All polling loops: Added Task.isCancelled checks

**Memory Safety**:
- Keychain operations: Status checking + logging for SecItemAdd/SecItemDelete
- WatchSessionManager: Replaced 12 force unwraps with if-let bindings
- WebSocketTransport/ServerDiscovery: Guard-let for URL/URLComponents parsing
- AudioDecoder: Guarded baseAddress instead of force unwrap

**Configuration**:
- ImageCache: Switched from ephemeral to default URLSessionConfiguration
- HomeViewModel: Heavy dictionary creation moved to Task.detached (off main thread)
- GlobalNavigationViewModel: Added @MainActor annotation

## Known Issues

- Player selection: players jump to bottom of active list when paused (`MultiDeviceManager`)
- Background play: after very long pauses (hours), the server may start a different track than what was paused if `playMedia` restore fails (e.g. track removed from library)
- CarPlay crashes loading large track lists (needs pagination)
- Player grouping: drift between synced players fixed (server time sync), but ungroup action has edge cases — group state in PlayerGroupingView may be stale if view was loaded before grouping event
- Queue management has edge cases
