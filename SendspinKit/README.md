> This is a very early proof of concept of the Sendspin protocol. The protocol will likely change. This does work today (10/26), but may not work tomorrow.

# SendspinKit

> **Modified copy.** This directory is a fork of [Sendspin/SendspinKit](https://github.com/Sendspin/SendspinKit) (Apache-2.0), vendored into Xonora from an October 2025 snapshot of upstream and modified extensively since (audio player and decoder, client, clock sync, discovery, message models, an added WebSocket transport). It has not tracked upstream after that point. The original licence and copyright apply; see the [License](#license) section and the top-level `NOTICE`.

A Swift client library for the [Sendspin Protocol](https://github.com/Sendspin/spec) - enabling synchronized multi-room audio playback on Apple platforms.

## Features

- 🎵 **Player Role**: Synchronized audio playback with microsecond precision
- 🎛️ **Controller Role**: Control playback across device groups
- 📝 **Metadata Role**: Display track information and progress
- 🔍 **Auto-discovery**: mDNS/Bonjour server discovery
- 🎵 **Multi-codec**: PCM, Opus, and FLAC support for flexible streaming
- ⏱️ **Clock Sync**: NTP-style time synchronization

## Requirements

- iOS 17.0+ / macOS 14.0+ / watchOS 10.0+
- Swift 6.0+

## Installation

### Swift Package Manager

In this repository SendspinKit is consumed as a local package (`Xonora.xcodeproj` references `SendspinKit/` directly). To use it elsewhere, add it as a local or path dependency:

```swift
dependencies: [
    .package(path: "../SendspinKit")
]
```

## Quick Start

```swift
import SendspinKit

// Create client with player role
let client = SendspinClient(
    clientId: "my-device",
    name: "Living Room Speaker",
    roles: [.player],
    playerConfig: PlayerConfiguration(
        bufferCapacity: 1_048_576, // 1MB
        supportedFormats: [
            AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 48000, bitDepth: 16),
            AudioFormatSpec(codec: .opus, channels: 2, sampleRate: 48000, bitDepth: 16),
            AudioFormatSpec(codec: .flac, channels: 2, sampleRate: 48000, bitDepth: 16),
        ]
    )
)

// Discover servers
let discovery = SendspinDiscovery()
await discovery.startDiscovery()

for await server in discovery.discoveredServers {
    if let url = await discovery.resolveServer(server) {
        try await client.connect(to: url)
        break
    }
}

// Client automatically handles:
// - WebSocket connection
// - Clock synchronization
// - Audio stream reception
// - Synchronized playback
```

## Codec Support

SendspinKit supports multiple audio codecs for high-quality streaming:

- **PCM** - Uncompressed audio up to 192kHz 32-bit (zero-copy passthrough)
- **Opus** - Low-latency lossy compression (8-48kHz, optimized for real-time)
- **FLAC** - Lossless compression with hi-res support (up to 192kHz 24-bit)

All codecs output normalized int32 PCM for consistent pipeline processing. See [docs/CODEC_SUPPORT.md](docs/CODEC_SUPPORT.md) for detailed codec documentation, performance characteristics, and implementation guide.

## Audio Synchronization

SendspinKit uses timestamp-based audio scheduling to ensure precise synchronization:

- **AudioScheduler**: Maintains priority queue of audio chunks sorted by playback time
- **Clock Sync**: Compensates for clock drift using Kalman filter approach
- **Playback Window**: ±50ms tolerance for network jitter
- **Late Chunk Handling**: Automatically drops chunks >50ms late to maintain sync
- **AsyncStream Pipeline**: Non-blocking chunk output for smooth playback

The scheduler converts server timestamps to local playback times and ensures chunks play at their intended moment, not when they arrive from the network.

## Testing

- **Swift Bring-Up Guide**: See [docs/SWIFT_BRINGUP.md](docs/SWIFT_BRINGUP.md) for codec negotiation, scheduler architecture, clock sync details, and the 5-minute PCM stream test procedure.
- **Manual Testing**: See [docs/TESTING.md](docs/TESTING.md) for manual testing procedures and validation checklist.

## TODO

- [ ] Verify hi-res audio (192kHz/24-bit) end-to-end with real hardware
- [ ] Test compatibility with other Sendspin Protocol server implementations
- [ ] Update implementation as Sendspin Protocol spec solidifies
- [ ] Comprehensive audit and bug fixes

Upstream tracking lives at [Sendspin/SendspinKit](https://github.com/Sendspin/SendspinKit); this copy is archived with the rest of the repository.

## License

Apache License 2.0 — see [LICENSE](LICENSE). This applies to the whole `SendspinKit/` directory, including the modifications made for Xonora. The Xonora app code outside this directory is licensed under GPL-3.0-only (see the top-level `LICENSE`).

Bundled dependencies: swift-opus (BSD-3-Clause), flac-binary-xcframework and ogg-binary-xcframework (BSD-3-Clause); Starscream (MIT) is used only by the `Examples/CLIPlayer` sample.
