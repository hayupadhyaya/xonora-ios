# Sendspin CLI Player

A simple command-line audio player demonstrating how to use SendspinKit to connect to a Sendspin Protocol server and play synchronized audio.

## Features

- Connects to Sendspin server via WebSocket
- Supports PCM, Opus, and FLAC audio formats
- Real-time clock synchronization for multi-room audio
- Interactive volume and mute controls
- Event monitoring (connection, streams, groups)

## Building

```bash
cd Examples/CLIPlayer
swift build -c release
```

## Usage

The CLI player supports both automatic discovery and manual connection:

### Automatic Discovery (Recommended)

```bash
# Auto-discover servers on the network
swift run CLIPlayer

# Auto-discover with custom client name
swift run CLIPlayer "Living Room"
```

The player will:
1. Scan the network for Sendspin servers via mDNS
2. Display all found servers
3. Automatically connect to the first server

### Manual Connection

```bash
# Connect to specific server URL
# Note: The /sendspin path is automatically appended if not provided
swift run CLIPlayer ws://192.168.1.100:8927

# Connect with explicit path
swift run CLIPlayer ws://192.168.1.100:8927/sendspin

# Connect with custom client name
swift run CLIPlayer ws://192.168.1.100:8927 "Living Room"
```

## Interactive Commands

Once connected, you can use these commands:

- `v <0-100>` - Set volume (e.g., `v 75` for 75%)
- `m` - Mute audio
- `u` - Unmute audio
- `q` - Quit

## Example Output

### With Discovery

```
🔍 Discovering Sendspin servers...
📡 Found 2 server(s):
  [1] Music Assistant - ws://192.168.1.100:8927
  [2] Living Room Server - ws://192.168.1.105:8927
✅ Connecting to: Music Assistant
🎵 Sendspin CLI Player
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📡 Connecting to ws://192.168.1.100:8927...
✅ Connected! Listening for audio streams...

Commands:
  v <0-100>  - Set volume
  m          - Toggle mute
  q          - Quit
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔗 Connected to server: My Sendspin Server (v1)
📻 Group: Living Room [playing]
▶️  Stream started:
   Codec: flac
   Sample rate: 44100 Hz
   Channels: 2
   Bit depth: 24 bits
```

## Code Structure

The example demonstrates:

1. **Client creation** - Configuring buffer size and supported formats
2. **Event handling** - Monitoring server events via AsyncStream
3. **Connection management** - Connecting, disconnecting, handling errors
4. **Playback control** - Volume and mute commands
5. **Interactive CLI** - Reading user input while maintaining event stream

## Key SendspinKit APIs Used

```swift
// Discover servers on network
let servers = await SendspinClient.discoverServers()
// Returns: [DiscoveredServer(name: "Music Assistant", url: ws://..., ...)]

// Create player configuration
let config = PlayerConfiguration(
    bufferCapacity: 2_097_152,
    supportedFormats: [...]
)

// Create client
let client = SendspinClient(
    clientId: UUID().uuidString,
    name: "My Player",
    roles: [.player],
    playerConfig: config
)

// Connect to discovered server
try await client.connect(to: servers[0].url)

// Monitor events
for await event in client.events {
    switch event {
    case .serverConnected(let info): ...
    case .streamStarted(let format): ...
    // ...
    }
}

// Control playback
await client.setVolume(0.75)
await client.setMute(true)
```

## Requirements

- macOS 14.0 or later
- Swift 6.0 or later
- A running Sendspin Protocol server

## Notes

This is a minimal example for demonstration purposes. A production player might add:

- Better error handling and recovery
- Audio level meters / visualizers
- Persistent client ID storage
- Configuration file support
- More sophisticated command parsing
