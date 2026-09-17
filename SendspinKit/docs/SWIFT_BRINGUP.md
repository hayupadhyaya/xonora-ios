# Swift Client Bring-Up Guide

This document describes the Swift ResonateKit client implementation, focusing on codec negotiation, audio scheduling, clock synchronization, and testing procedures.

## Architecture Overview

The Swift client implements a timestamp-based audio playback pipeline:

```
WebSocket → Decode → AudioScheduler → AudioPlayer
```

### Key Components

1. **WebSocketTransport** - Handles protocol messages and binary audio frames
2. **ClockSynchronizer** - Maintains server-client time offset with drift compensation
3. **AudioDecoder** - Converts encoded audio to PCM
4. **AudioScheduler** - Schedules audio chunks for precise playback timing
5. **AudioPlayer** - Outputs PCM audio to the device

## Codec Negotiation

### Current Implementation (PCM Only)

**IMPORTANT**: The Swift client currently **only supports PCM codec**. Do not advertise Opus or FLAC until decoders are implemented.

#### Correct Configuration

```swift
let config = PlayerConfiguration(
    bufferCapacity: 2_097_152,  // 2MB buffer
    supportedFormats: [
        AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 48000, bitDepth: 16),
    ]
)
```

#### Negotiation Flow

1. Client sends `client/hello` with `support_formats` array containing only PCM
2. Server responds with `server/hello` acknowledgment
3. Server sends `stream/start` with negotiated format:
   ```json
   {
     "type": "stream/start",
     "payload": {
       "player": {
         "codec": "pcm",
         "sample_rate": 48000,
         "channels": 2,
         "bit_depth": 16
       }
     }
   }
   ```
4. Client initializes decoder and starts AudioScheduler

#### Why PCM Only?

- Opus/FLAC decoders are not yet implemented (`AudioDecoder.swift:34`)
- Advertising unsupported codecs causes crashes when server sends encoded audio
- PCM provides uncompressed audio quality at ~1.5 Mbps for stereo 48kHz/16-bit

## Audio Scheduling

### Timestamp-Based Playback

The `AudioScheduler` implements precise timestamp-based playback to prevent drift and maintain synchronization across multiple devices.

#### Scheduler Contract

**Input**: `(pcmData: Data, serverTimestamp: Int64)`
- `pcmData`: Decoded PCM audio samples
- `serverTimestamp`: Server time in microseconds when this chunk should play

**Processing**:
1. Convert server timestamp to local time using `ClockSynchronizer`
2. Calculate playback time as `Date` from local timestamp
3. Insert chunk into priority queue sorted by playback time
4. 10ms tick loop checks queue for ready chunks

**Output**: `AsyncStream<ScheduledChunk>` - Chunks ready for playback

#### Jitter Buffer

- **Target buffer**: 150ms (configurable via `playbackWindow`)
- **Window**: ±50ms tolerance for network jitter
- **Tick rate**: 10ms (checks queue every 10ms for ready chunks)

#### Late Frame Policy

Chunks are dropped if `current_time > scheduled_time + 50ms`:

```swift
if delay < -playbackWindow {
    // Too late, drop
    schedulerStats.droppedLate += 1
    print("[SCHEDULER] Dropped late chunk: \(Int(-delay * 1000))ms late")
}
```

**Acceptance Criteria**: Late-frame drop rate ≤ 1% on LAN

#### Queue Management

- **Max queue size**: 100 chunks (configurable)
- **Overflow policy**: Drop oldest chunks (FIFO)
- **Sort order**: Binary search insertion maintains sorted queue by `playTime`

### Frame vs. Time-Based Scheduling

The current implementation uses **time-based scheduling** (Date objects) rather than frame indices. This provides:
- Simpler integration with system audio APIs
- Automatic handling of clock drift via ClockSynchronizer
- No accumulation of floating-point rounding errors

## Clock Synchronization

### Algorithm

ResonateKit uses an **NTP-style clock sync** with drift compensation (Kalman filter approach).

#### Sync Message Exchange

1. Client sends `client/time` with `t1` (client transmit time in µs)
2. Server records `t2` (server receive time)
3. Server sends `server/time` with `t2`, `t3` (server transmit time)
4. Client records `t4` (client receive time)

#### Offset Calculation

```swift
rtt = (t4 - t1) - (t3 - t2)
offset = ((t2 - t1) + (t3 - t4)) / 2
```

#### Drift Compensation

After initial offset calculation, the synchronizer tracks **clock drift** (frequency difference):

```swift
drift = Δoffset / Δtime
predicted_offset = offset + drift * (current_time - last_sync_time)
```

This allows accurate conversion of server timestamps to local time even as clocks drift apart.

#### Timestamp Conversion

**Server → Local** (used for scheduling):
```swift
func serverTimeToLocal(_ serverTime: Int64) -> Int64 {
    let denominator = 1.0 + drift
    let numerator = Double(serverTime) - Double(offset) + drift * Double(lastSyncMicros)
    return Int64(numerator / denominator)
}
```

**Local → Server** (used for time messages):
```swift
func localTimeToServer(_ localTime: Int64) -> Int64 {
    let dt = localTime - lastSyncMicros
    return localTime + offset + Int64(drift * Double(dt))
}
```

#### Sync Quality

- **Good**: RTT < 50ms
- **Degraded**: RTT < 100ms
- **Lost**: No sync for > 5 seconds

**Acceptance Criteria**: Offset stddev < 5ms after first 10 seconds

#### Continuous Sync Loop

- Initial sync: 5 rounds at 100ms intervals to establish offset/drift
- Ongoing sync: Every 5 seconds to maintain quality

## Binary Message Format

### Audio Chunks

```
[type: 1 byte][timestamp: 8 bytes big-endian int64][audio_data: N bytes]
```

- **Type**: `1` for audio chunks (player role)
- **Timestamp**: Server time in microseconds (µs)
- **Audio Data**: Raw PCM samples or encoded audio (based on negotiated codec)

**CRITICAL**: The server uses message type **1** for audio chunks. This was corrected from an earlier implementation using type 0.

### PCM Encoding

PCM audio data is little-endian int16 samples:
```swift
for sample in pcmSamples {
    data.append(UInt8(sample & 0xFF))         // Low byte
    data.append(UInt8((sample >> 8) & 0xFF))  // High byte
}
```

For stereo audio, samples are interleaved: `[L, R, L, R, ...]`

## Telemetry

### Per-Second Logging

The client emits telemetry logs every second (when audio is playing):

```
[TELEMETRY] framesScheduled=50, framesPlayed=49, framesDroppedLate=1, framesDroppedOther=0, bufferFillMs=152.3, clockOffsetMs=2.45, rttMs=8.32, queueSize=7
```

**Fields**:
- `framesScheduled`: Chunks received this second
- `framesPlayed`: Chunks successfully played
- `framesDroppedLate`: Chunks dropped due to being >50ms late
- `framesDroppedOther`: Chunks dropped due to queue overflow
- `bufferFillMs`: Current buffer fill (time until next chunk plays)
- `clockOffsetMs`: Clock offset in milliseconds
- `rttMs`: Round-trip time in milliseconds
- `queueSize`: Current scheduler queue size

### Metrics for Quality

**Good playback**:
- `framesDroppedLate / framesScheduled < 0.01` (< 1% drop rate)
- `bufferFillMs` between 120-200ms
- `clockOffsetMs` stable (stddev < 5ms)
- `rttMs < 50ms`

## Testing

### 5-Minute PCM Stream Test

#### Prerequisites

1. Go server running with PCM test tone or MP3 file:
   ```bash
   cd /path/to/resonate-go
   make build
   ./resonate-go serve --source test-tone
   ```

2. Swift CLI player built:
   ```bash
   cd /path/to/ResonateKit/Examples/CLIPlayer
   swift build -c release
   ```

#### Running the Test

```bash
# Run for 5 minutes and capture logs
.build/release/CLIPlayer ws://localhost:8927 "Test Client" 2>&1 | tee 5min-test.log

# Let it run for at least 5 minutes
# Press 'q' to quit when done
```

#### Expected Output

```
🎵 Resonate CLI Player
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📡 Connecting to ws://localhost:8927...
✅ Connected! Listening for audio streams...
🔗 Connected to server: Resonate Server (v1)
[SYNC] Initial sync: offset=123μs, rtt=456μs
[SYNC] Sync #2: offset=125μs, drift=0.000000012, residual=2μs, rtt=450μs
▶️  Stream started:
   Codec: pcm
   Sample rate: 48000 Hz
   Channels: 2
   Bit depth: 16 bits
[TELEMETRY] framesScheduled=50, framesPlayed=50, framesDroppedLate=0, framesDroppedOther=0, bufferFillMs=148.2, clockOffsetMs=0.12, rttMs=0.45, queueSize=7
...
```

#### Acceptance Criteria

- ✅ Steady playback for ≥5 minutes with no audible drift or stutter
- ✅ `framesDroppedLate / framesScheduled ≤ 0.01` (≤1% drop rate)
- ✅ `clockOffsetMs` stable (stddev < 5ms after first 10s)
- ✅ No crashes or connection drops

### Analyzing Logs

Extract telemetry data:
```bash
grep "\[TELEMETRY\]" 5min-test.log > telemetry.txt
```

Calculate drop rate:
```bash
awk -F'[=,]' '{
    scheduled += $2
    late += $4
} END {
    print "Total scheduled:", scheduled
    print "Total dropped late:", late
    print "Drop rate:", (late / scheduled * 100) "%"
}' telemetry.txt
```

## Troubleshooting

### No Audio Playback

1. Check codec negotiation in logs:
   ```
   ▶️  Stream started:
      Codec: pcm
   ```
   If codec is not PCM, server negotiation failed.

2. Verify AudioScheduler started:
   ```
   [CLIENT] Starting AudioScheduler
   ```

3. Check for dropped chunks:
   ```
   [SCHEDULER] Dropped late chunk: 123ms late
   ```
   If many chunks are late, clock sync may be poor.

### Clock Sync Issues

1. High RTT (>100ms):
   ```
   [SYNC] Discarding sync sample: high RTT 150000μs
   ```
   **Solution**: Improve network conditions or increase playback buffer.

2. Clock drift:
   ```
   [SYNC] Drift initialized: drift=0.000012345 μs/μs
   ```
   High drift (>1e-6) indicates significant clock frequency mismatch.

### Audio Stuttering

1. **Underruns**: `bufferFillMs` frequently near 0
   - **Solution**: Increase `playbackWindow` (jitter buffer size)

2. **Late drops**: High `framesDroppedLate`
   - **Solution**: Verify clock sync quality, check network latency

3. **Queue overflow**: High `framesDroppedOther`
   - **Solution**: Increase `maxQueueSize` or reduce network bufferbloat

## Implementation Status

### Completed ✅

- [x] PCM-only codec negotiation
- [x] Binary message type 1 for audio chunks
- [x] Timestamp-based AudioScheduler
- [x] Clock synchronization with drift compensation
- [x] Late-frame dropping (>50ms)
- [x] Per-second telemetry logging
- [x] 5-minute PCM stream test procedure

### Pending ⏳

- [ ] Opus decoder implementation
- [ ] FLAC decoder implementation
- [ ] Pull-driven output (AVAudioEngine render callback)
- [ ] Adaptive jitter buffer (dynamic 120-200ms range)
- [ ] Device change detection (AirPods switching)

## References

- [Resonate Protocol Specification](https://github.com/Resonate-Protocol/spec)
- [Go Reference Implementation](https://github.com/harperreed/resonate-go)
- [Clock Sync Algorithm](Sources/ResonateKit/Synchronization/ClockSynchronizer.swift)
- [Audio Scheduler](Sources/ResonateKit/Audio/AudioScheduler.swift)
