# Metadata Architecture in ResonateKit

## Overview

Metadata in the Resonate protocol flows through multiple message types, and understanding the architecture is critical to avoid breaking it (which we've done multiple times!).

## How Metadata Works

### Message Flow

```
Server → session/update → Client → SessionUpdateMessage → TrackMetadata → Event
```

### Key Components

1. **Server sends `session/update` messages** containing track metadata
2. **Client receives JSON** with `{"type": "session/update", "payload": {...}}`
3. **Message decoder** attempts to decode as various message types
4. **SessionUpdateMessage** matches and extracts metadata from payload
5. **TrackMetadata event** is yielded to application layer
6. **UI displays** the metadata (title, artist, album, etc.)

## Critical Implementation Details

### Message Decoder Order

**Location:** `Sources/ResonateKit/Client/ResonateClient.swift:456-471`

The message decoder uses a chain of `if-else` statements with `try?` to decode messages:

```swift
if let message = try? decoder.decode(ServerHelloMessage.self, from: data), message.type == msgType {
    await handleServerHello(message)
} else if let message = try? decoder.decode(StreamStartMessage.self, from: data), message.type == msgType {
    await handleStreamStart(message)
} else if let message = try? decoder.decode(SessionUpdateMessage.self, from: data), message.type == msgType {
    await handleSessionUpdate(message)
}
```

### The Type Validation Bug (Fixed in v0.2.0)

**CRITICAL:** Swift's `Codable` with `try?` does NOT validate the `type` field automatically!

#### Why This Happens

In our message structs, the `type` field is defined as a constant:

```swift
public struct SessionUpdateMessage: ResonateMessage {
    public let type = "session/update"  // ← This is a CONSTANT, not validated during decode!
    public let payload: SessionUpdatePayload
}
```

When Swift decodes JSON, it:
1. ✅ Checks that all required fields exist
2. ✅ Validates that optional fields match expected types
3. ❌ **DOES NOT** validate that constant fields match their values!

This means if you decode `{"type": "session/update", "payload": {...}}` as `StreamStartMessage`, it will SUCCEED if all the payload fields are optional!

#### The Fix

**ALWAYS** validate `message.type == msgType` after decoding:

```swift
if let message = try? decoder.decode(SessionUpdateMessage.self, from: data), message.type == msgType {
    // ✅ This is correct - validates type matches
    await handleSessionUpdate(message)
}
```

**NEVER** just check if decode succeeded:

```swift
if let message = try? decoder.decode(SessionUpdateMessage.self, from: data) {
    // ❌ This is WRONG - will match ANY message with compatible payload!
    await handleSessionUpdate(message)
}
```

### Message Structs with All-Optional Payloads

**These are dangerous and require extra care:**

1. **`StreamStartMessage`**
   ```swift
   public struct StreamStartPayload: Codable, Sendable {
       public let player: StreamStartPlayer?      // Optional!
       public let artwork: StreamStartArtwork?    // Optional!
       public let visualizer: StreamStartVisualizer?  // Optional!
   }
   ```

2. **`SessionUpdateMessage`**
   ```swift
   public struct SessionUpdatePayload: Codable, Sendable {
       public let groupId: String?           // Optional!
       public let groupName: String?         // Optional!
       public let metadata: SessionMetadata? // Optional! ← Metadata lives here
       public let playbackState: String?     // Optional!
   }
   ```

Because all fields are optional, these messages will successfully decode from almost ANY JSON that has a `type` and `payload` field!

## Common Ways We Break Metadata

### 1. **Decoder Ordering Bug**

❌ **WRONG:** Checking all-optional messages before specific ones
```swift
if let message = try? decoder.decode(SessionUpdateMessage.self, from: data) {
    // This will match stream/start, stream/end, and everything else!
    await handleSessionUpdate(message)
} else if let message = try? decoder.decode(StreamStartMessage.self, from: data) {
    // Never reached because SessionUpdateMessage already matched!
    await handleStreamStart(message)
}
```

✅ **CORRECT:** Check specific messages first, with type validation
```swift
if let message = try? decoder.decode(StreamStartMessage.self, from: data), message.type == msgType {
    await handleStreamStart(message)
} else if let message = try? decoder.decode(SessionUpdateMessage.self, from: data), message.type == msgType {
    await handleSessionUpdate(message)
}
```

### 2. **Missing Type Validation**

❌ **WRONG:** No type check after decode
```swift
if let message = try? decoder.decode(SessionUpdateMessage.self, from: data) {
    await handleSessionUpdate(message)  // Might be handling wrong message!
}
```

✅ **CORRECT:** Always validate type matches
```swift
if let message = try? decoder.decode(SessionUpdateMessage.self, from: data), message.type == msgType {
    await handleSessionUpdate(message)  // Guaranteed to be session/update
}
```

### 3. **Removing Metadata Role**

❌ **WRONG:** Not advertising metadata support
```swift
let client = ResonateClient(
    clientId: id,
    name: "My Client",
    roles: [.player],  // ← Missing .metadata!
    playerConfig: config
)
```

✅ **CORRECT:** Include metadata role
```swift
let client = ResonateClient(
    clientId: id,
    name: "My Client",
    roles: [.player, .metadata],  // ← Advertises metadata support
    playerConfig: config
)
```

### 4. **Not Handling SessionUpdateMessage**

The server sends metadata via `session/update`, NOT `stream/metadata`!

- `stream/metadata` → Basic metadata (title, artist, album only)
- `session/update` → **Rich metadata** (includes album artist, track number, duration, year, etc.)

Most servers send `session/update`, so if you only handle `stream/metadata`, you'll miss most metadata!

## Debugging Metadata Issues

### Step 1: Check Message Reception

Add logging to see what messages are arriving:

```swift
print("[RX] \(msgType)")  // Add this before the decoder chain
```

Look for `[RX] session/update` messages. If you don't see them:
- Server isn't sending metadata
- WebSocket connection issue
- Client not advertising `.metadata` role

### Step 2: Check Message Decoding

Add logging after each decode attempt:

```swift
if let message = try? decoder.decode(SessionUpdateMessage.self, from: data), message.type == msgType {
    print("[DEBUG] Successfully decoded SessionUpdateMessage")
    print("[DEBUG] Metadata: \(message.payload.metadata)")
    await handleSessionUpdate(message)
}
```

If `session/update` arrives but doesn't decode:
- Type validation failing (wrong message type constant)
- Missing `message.type == msgType` check (will match wrong messages)

### Step 3: Check Handler Logic

Verify metadata is being extracted and yielded:

```swift
private func handleSessionUpdate(_ message: SessionUpdateMessage) async {
    if let sessionMetadata = message.payload.metadata {
        print("[DEBUG] Yielding metadata event: \(sessionMetadata.title)")
        let metadata = TrackMetadata(...)
        eventsContinuation.yield(.metadataReceived(metadata))
    } else {
        print("[DEBUG] session/update had no metadata field")
    }
}
```

### Step 4: Check Event Consumption

Verify the application is consuming metadata events:

```swift
for await event in client.events {
    switch event {
    case .metadataReceived(let metadata):
        print("[APP] Got metadata: \(metadata.title)")
        // Update UI here
    }
}
```

## Message Type Reference

### Messages That Carry Metadata

| Message Type | Metadata Fields | When Sent | Priority |
|--------------|----------------|-----------|----------|
| `session/update` | Full metadata (title, artist, album, albumArtist, track, duration, year) | On track change, periodic updates | **PRIMARY** |
| `stream/metadata` | Basic metadata (title, artist, album only) | On track change | Fallback |

### Metadata Flow Example

```
1. Track changes on server
2. Server sends: {"type": "session/update", "payload": {"metadata": {...}}}
3. Client receives message
4. Decoder tries each message type in order
5. SessionUpdateMessage matches (if type validation passes!)
6. handleSessionUpdate() extracts metadata from payload
7. TrackMetadata event yielded to application
8. Application updates UI
```

## Testing Metadata

### Manual Testing Checklist

- [ ] Start music playback on server
- [ ] Connect client with `.metadata` role
- [ ] Verify `[RX] session/update` messages appear
- [ ] Verify metadata displays in UI
- [ ] Skip to next track
- [ ] Verify metadata updates

### Common Test Scenarios

1. **Connect after playback started** → Should receive metadata immediately
2. **Connect before playback** → Should receive metadata when track starts
3. **Skip to next track** → Metadata should update
4. **Pause/resume** → Metadata should persist
5. **Reconnect** → Should receive current metadata

## Historical Bugs

### Bug #1: "Next Song Not Playing" (Pre-v0.2.0)

**Symptom:** When skipping to next track, `stream/start` messages were consumed by `SessionUpdateMessage` decoder, preventing playback from starting.

**Root Cause:** No type validation - `SessionUpdateMessage` matched `stream/start` because all fields optional.

**Fix:** Added `message.type == msgType` validation to all decoders.

### Bug #2: "Metadata Disappeared" (Pre-v0.2.0)

**Symptom:** `session/update` messages were being received but metadata wasn't displayed.

**Root Cause:** `StreamStartMessage` decoder was consuming `session/update` messages because:
1. `StreamStartMessage` was checked before `SessionUpdateMessage` in decoder chain
2. All `StreamStartPayload` fields are optional
3. No type validation, so decode succeeded even though type didn't match
4. `handleStreamStart()` silently returned because `payload.player` was nil

**Fix:** Added `message.type == msgType` validation to prevent wrong message type from matching.

## Best Practices

1. **ALWAYS** validate `message.type == msgType` after decoding
2. **ALWAYS** check messages with required fields BEFORE messages with all-optional fields
3. **ALWAYS** include `.metadata` role when creating client
4. **ALWAYS** handle `SessionUpdateMessage` (not just `StreamMetadataMessage`)
5. **ALWAYS** yield metadata events even if some fields are nil
6. **NEVER** remove type validation to "fix" a bug
7. **NEVER** assume decode success means correct message type

## Code Review Checklist

When reviewing metadata-related code changes:

- [ ] All decoder branches have `message.type == msgType` validation
- [ ] Messages with all-optional payloads are checked AFTER specific messages
- [ ] Client creation includes `.metadata` role
- [ ] `handleSessionUpdate()` extracts and yields metadata
- [ ] No debugging logs left in production code
- [ ] Metadata events are consumed by application layer

## See Also

- `Sources/ResonateKit/Client/ResonateClient.swift` - Message decoder implementation
- `Sources/ResonateKit/Models/ResonateMessage.swift` - Message type definitions
- `Examples/CLIPlayer/Sources/CLIPlayer/CLIPlayer.swift` - Metadata display example
