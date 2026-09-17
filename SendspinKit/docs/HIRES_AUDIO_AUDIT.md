# High-Resolution Audio Support Audit - Swift ResonateKit

**Audit Date**: 2025-10-25
**Reference Implementation**: [resonate-go](https://github.com/harperreed/resonate-go)

## Executive Summary

The Swift ResonateKit library **partially supports** high-resolution audio but is missing critical components to match the Go implementation. While the data structures can handle hi-res formats, the implementation only advertises and uses 48kHz 16-bit audio.

### Current State: ⚠️ LOW-RES ONLY (48kHz 16-bit)
### Target State: ✅ FULL HI-RES (up to 192kHz 24-bit)

---

## Critical Gaps Identified

### 🔴 **GAP #1: Limited Format Advertisement**

**Location**: `Examples/CLIPlayer/Sources/CLIPlayer/CLIPlayer.swift:29-34`

**Current Code**:
```swift
let config = PlayerConfiguration(
    bufferCapacity: 2_097_152, // 2MB buffer
    supportedFormats: [
        AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 48000, bitDepth: 16)
    ]
)
```

**Go Implementation** advertises (in priority order):
```go
// From: /Users/harper/workspace/personal/ma-interface/resonate-go/internal/app/player.go:153-164
supportFormats: []protocol.AudioFormatSpec{
    {Codec: "pcm", Channels: 2, SampleRate: 192000, BitDepth: 24},  // Hi-res
    {Codec: "pcm", Channels: 2, SampleRate: 176400, BitDepth: 24},
    {Codec: "pcm", Channels: 2, SampleRate: 96000, BitDepth: 24},
    {Codec: "pcm", Channels: 2, SampleRate: 88200, BitDepth: 24},
    {Codec: "pcm", Channels: 2, SampleRate: 48000, BitDepth: 16},   // Standard
    {Codec: "pcm", Channels: 2, SampleRate: 44100, BitDepth: 16},
    {Codec: "opus", Channels: 2, SampleRate: 48000, BitDepth: 16},  // Fallback
},
```

**Impact**: Server cannot negotiate hi-res formats because client doesn't advertise support.

**Fix Required**: Add full format list to `PlayerConfiguration` with priority ordering.

---

### 🔴 **GAP #2: Hardcoded Default Format (48kHz 16-bit)**

**Location**: `Sources/ResonateKit/Client/ResonateClient.swift:675-680`

**Current Code**:
```swift
let defaultFormat = AudioFormatSpec(
    codec: .pcm,
    channels: 2,
    sampleRate: 48000,  // ❌ HARDCODED - Should use negotiated format
    bitDepth: 16        // ❌ HARDCODED - Should use negotiated format
)
```

**Go Implementation**:
```go
// No hardcoded default - always uses format from StreamStart message
// From: /Users/harper/workspace/personal/ma-interface/resonate-go/internal/app/player.go:293-315
```

**Impact**: Even if server sends hi-res stream, client auto-starts with 48kHz 16-bit.

**Context**: This fallback is used when binary audio arrives before `stream/start` message.

**Fix Required**:
1. Either buffer binary messages until `stream/start` arrives
2. Or parse format from binary message header (if possible)
3. Or default to highest advertised format instead of hardcoded 48kHz

---

### 🟡 **GAP #3: PCM Decoder Bit Depth Handling**

**Location**: `Sources/ResonateKit/Audio/AudioDecoder.swift:13-18`

**Current Code**:
```swift
public class PCMDecoder: AudioDecoder {
    public init() {}

    public func decode(_ data: Data) throws -> Data {
        return data // No decoding needed for PCM
    }
}
```

**Issue**: PCMDecoder is format-agnostic. It doesn't know if it's handling 16-bit or 24-bit data.

**Go Implementation**:
```go
// From: /Users/harper/workspace/personal/ma-interface/resonate-go/internal/audio/decoder.go:33-62
type PCMDecoder struct {
    bitDepth int  // ✅ Knows bit depth
}

func (d *PCMDecoder) Decode(data []byte) ([]int32, error) {
    if d.bitDepth == 24 {
        // 24-bit PCM: 3 bytes per sample (little-endian)
        numSamples := len(data) / 3
        samples := make([]int32, numSamples)
        for i := 0; i < numSamples; i++ {
            b := [3]byte{data[i*3], data[i*3+1], data[i*3+2]}
            samples[i] = SampleFrom24Bit(b)  // Unpacks with sign extension
        }
        return samples, nil
    }
    // 16-bit case...
}
```

**Impact**:
- Currently works for 16-bit (pass-through is correct)
- **Will fail for 24-bit** - AudioQueue expects different byte packing

**Fix Required**:
1. PCMDecoder needs to know `bitDepth` and `channels`
2. For 24-bit input, need to unpack 3-byte little-endian to proper format
3. May need conversion depending on what AudioQueue expects

---

### 🟡 **GAP #4: AudioQueue Format Configuration**

**Location**: `Sources/ResonateKit/Audio/AudioPlayer.swift:63-72`

**Current Code**:
```swift
var audioFormat = AudioStreamBasicDescription()
audioFormat.mSampleRate = Float64(format.sampleRate)  // ✅ Dynamic
audioFormat.mFormatID = kAudioFormatLinearPCM
audioFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked
audioFormat.mBytesPerPacket = UInt32(format.channels * format.bitDepth / 8)  // ✅ Dynamic
audioFormat.mFramesPerPacket = 1
audioFormat.mBytesPerFrame = UInt32(format.channels * format.bitDepth / 8)   // ✅ Dynamic
audioFormat.mChannelsPerFrame = UInt32(format.channels)                      // ✅ Dynamic
audioFormat.mBitsPerChannel = UInt32(format.bitDepth)                        // ✅ Dynamic
```

**Good News**: AudioQueue configuration is already dynamic! ✅

**Potential Issue**: For 24-bit audio on macOS/iOS, need to verify:
- Does AudioQueue natively support 24-bit packed?
- Or should we use 32-bit format with `kLinearPCMFormatFlagIsNonInterleaved`?

**Investigation Needed**: Test with real 24-bit stream to verify byte packing.

---

### 🟢 **WORKING: Data Structure Support**

**Location**: `Sources/ResonateKit/Models/AudioFormatSpec.swift:12-18`

```swift
/// Sample rate in Hz (e.g., 44100, 48000)
public let sampleRate: Int
/// Bit depth (16, 24, or 32)
public let bitDepth: Int

public init(codec: AudioCodec, channels: Int, sampleRate: Int, bitDepth: Int) {
    precondition(sampleRate > 0 && sampleRate <= 384_000, "Sample rate must be between 1 and 384000 Hz")  // ✅ Supports up to 384kHz!
    precondition(bitDepth == 16 || bitDepth == 24 || bitDepth == 32, "Bit depth must be 16, 24, or 32")   // ✅ Supports 24-bit!
}
```

**Status**: ✅ Data model already supports hi-res formats.

---

### 🟢 **WORKING: Protocol Message Support**

The `StreamStartMessage` and related protocol types correctly handle all format fields:

```swift
// From: Sources/ResonateKit/Models/ResonateMessage.swift
public struct StreamStartPlayer: Codable, Sendable {
    public let codec: String
    public let sampleRate: Int      // ✅ Can carry 192000
    public let channels: Int
    public let bitDepth: Int        // ✅ Can carry 24
    public let codecHeader: String?
}
```

**Status**: ✅ Protocol layer ready for hi-res.

---

## Implementation Comparison: Go vs Swift

### Sample Data Type

| Aspect | Go Implementation | Swift Implementation | Status |
|--------|-------------------|---------------------|---------|
| **Internal Type** | `int32` (even for 24-bit) | `Data` (raw bytes) | ⚠️ Different |
| **Wire Format** | 3 bytes per sample (24-bit LE) | Not specified | ❓ Unknown |
| **Conversion** | Explicit pack/unpack functions | Pass-through only | ❌ Missing |

**Go Code**:
```go
// From: /Users/harper/workspace/personal/ma-interface/resonate-go/internal/audio/types.go
type Buffer struct {
    Timestamp int64
    PlayAt    time.Time
    Samples   []int32  // ✅ Always int32 internally
    Format    Format
}

// 24-bit range constants
const (
    Max24Bit = 8388607   // 2^23 - 1
    Min24Bit = -8388608  // -2^23
)

// Conversion functions
func SampleFrom24Bit(b [3]byte) int32 {
    // Unpack 3-byte little-endian to int32 with sign extension
    val := int32(b[0]) | int32(b[1])<<8 | int32(b[2])<<16
    if val&0x800000 != 0 {  // Sign bit set
        val |= ^0xffffff  // Sign extend
    }
    return val
}

func SampleTo24Bit(sample int32) [3]byte {
    return [3]byte{
        byte(sample),
        byte(sample >> 8),
        byte(sample >> 16),
    }
}
```

**Swift Needs**: Similar conversion utilities for 24-bit handling.

---

### Chunk Size Calculations

| Sample Rate | Chunk Duration | Samples/Chunk | Total Samples (Stereo) | Wire Bytes (24-bit) |
|-------------|----------------|---------------|------------------------|---------------------|
| 192 kHz     | 20 ms          | 3,840         | 7,680                  | 23,040              |
| 176.4 kHz   | 20 ms          | 3,528         | 7,056                  | 21,168              |
| 96 kHz      | 20 ms          | 1,920         | 3,840                  | 11,520              |
| 88.2 kHz    | 20 ms          | 1,764         | 3,528                  | 10,584              |
| 48 kHz      | 20 ms          | 960           | 1,920                  | 5,760 (16-bit: 3,840) |
| 44.1 kHz    | 20 ms          | 882           | 1,764                  | 5,292 (16-bit: 3,528) |

**Go Code**:
```go
// From: /Users/harper/workspace/personal/ma-interface/resonate-go/internal/server/audio_engine.go:14-25
const (
    DefaultSampleRate = 192000  // ✅ Hi-res default
    DefaultChannels   = 2
    DefaultBitDepth   = 24      // ✅ Hi-res default
    ChunkDurationMs   = 20
    BufferAheadMs     = 500
)
```

**Swift Implementation**: Uses same 20ms chunks, but currently only at 48kHz.

---

### Buffer Sizing

**Go Implementation**:
```go
// From: /Users/harper/workspace/personal/ma-interface/resonate-go/internal/app/player.go:144
BufferCapacity: 2 * 1024 * 1024,  // 2MB
```

**Swift Implementation**:
```swift
// From: Examples/CLIPlayer/Sources/CLIPlayer/CLIPlayer.swift:30
bufferCapacity: 2_097_152, // 2MB buffer  ✅ Same as Go
```

**Status**: ✅ Buffer capacity matches.

**Buffer Fill Time at Different Rates** (2MB capacity, 24-bit stereo):
- 192 kHz: 2,097,152 / 23,040 = **91 chunks = 1.82 seconds**
- 96 kHz: 2,097,152 / 11,520 = **182 chunks = 3.64 seconds**
- 48 kHz (16-bit): 2,097,152 / 3,840 = **546 chunks = 10.92 seconds**

---

## Critical Implementation Details from Go

### 1. Format Negotiation Priority

**Go Logic** (`/Users/harper/workspace/personal/ma-interface/resonate-go/internal/server/audio_engine.go:186-230`):
```go
func (e *AudioEngine) negotiateCodec(client *Client) string {
    sourceRate := e.source.SampleRate()

    // 1. HIGHEST PRIORITY: PCM at native sample rate (best for hi-res)
    for _, format := range client.Capabilities.SupportFormats {
        if format.Codec == "pcm" &&
           format.SampleRate == sourceRate &&
           format.BitDepth == DefaultBitDepth {
            return "pcm"
        }
    }

    // 2. Consider compressed codecs (Opus only at 48kHz)
    for _, format := range client.Capabilities.SupportFormats {
        if format.Codec == "opus" && sourceRate == 48000 {
            return "opus"
        }
    }

    // 3. Fallback to PCM (may need resampling)
    return "pcm"
}
```

**Key Insight**: Server prioritizes **PCM at native source rate**. No resampling unless absolutely necessary.

**Swift Status**: Protocol supports this, but client must advertise all PCM rates to participate.

---

### 2. Wire Protocol Encoding (24-bit)

**Go Server Encoding** (`/Users/harper/workspace/personal/ma-interface/resonate-go/internal/server/audio_engine.go:309-320`):
```go
// encodePCM encodes int32 samples as 24-bit PCM bytes (little-endian, 3 bytes per sample)
func encodePCM(samples []int32) []byte {
    output := make([]byte, len(samples)*3)
    for i, sample := range samples {
        // Pack 24-bit value (little-endian)
        output[i*3] = byte(sample)
        output[i*3+1] = byte(sample >> 8)
        output[i*3+2] = byte(sample >> 16)
    }
    return output
}
```

**Wire Format**: 3 bytes per sample, little-endian, signed

**Example 24-bit value** (decimal 1,000,000):
```
int32:  0x000F4240
bytes:  [0x40, 0x42, 0x0F]  (little-endian)
        byte0  byte1  byte2
```

**Swift Needs**: Decoder must unpack this 3-byte format.

---

### 3. Volume Control with 24-bit Clipping

**Go Implementation** (`/Users/harper/workspace/personal/ma-interface/resonate-go/internal/player/output.go:169-188`):
```go
func applyVolume(samples []int32, volume int, muted bool) []int32 {
    multiplier := getVolumeMultiplier(volume, muted)

    result := make([]int32, len(samples))
    for i, sample := range samples {
        scaled := int64(float64(sample) * multiplier)

        // ✅ Clamp to 24-bit range to prevent overflow
        if scaled > audio.Max24Bit {
            scaled = audio.Max24Bit
        } else if scaled < audio.Min24Bit {
            scaled = audio.Min24Bit
        }

        result[i] = int32(scaled)
    }

    return result
}
```

**Swift Implementation**: Uses AudioQueue native volume control (simpler, but less control).

---

### 4. Jitter Buffer Timing

**Go Scheduler** (`/Users/harper/workspace/personal/ma-interface/resonate-go/internal/player/scheduler.go:90-130`):
```go
// Buffer 25 chunks (500ms at 20ms/chunk) to match server's 500ms lead time
bufferTarget := 25

// Scheduler processes every 10ms
ticker := time.NewTicker(10 * time.Millisecond)

// Ready to play within ±50ms window
if delay > 50*time.Millisecond {
    // Too early, wait
} else if delay < -50*time.Millisecond {
    // Too late (>50ms), drop
    s.stats.Dropped++
} else {
    // Ready to play
    s.stats.Played++
}
```

**Swift Status**: Has `AudioScheduler` - need to verify timing parameters match.

---

## Recommended Implementation Plan

### Phase 1: Format Advertisement (CRITICAL)

**Files to modify**:
1. `Examples/CLIPlayer/Sources/CLIPlayer/CLIPlayer.swift`

**Changes**:
```swift
let config = PlayerConfiguration(
    bufferCapacity: 2_097_152,
    supportedFormats: [
        // Hi-res formats (priority order)
        AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 192_000, bitDepth: 24),
        AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 176_400, bitDepth: 24),
        AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 96_000, bitDepth: 24),
        AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 88_200, bitDepth: 24),
        // Standard formats (fallback)
        AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 48_000, bitDepth: 16),
        AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 44_100, bitDepth: 16),
        // Compressed fallback (if Opus decoder added)
        // AudioFormatSpec(codec: .opus, channels: 2, sampleRate: 48000, bitDepth: 16),
    ]
)
```

**Testing**: Connect to server with hi-res source (192kHz FLAC). Verify `stream/start` message shows negotiated hi-res format.

---

### Phase 2: 24-bit PCM Decoder (CRITICAL)

**Files to create/modify**:
1. `Sources/ResonateKit/Audio/PCMUtilities.swift` (new)
2. `Sources/ResonateKit/Audio/AudioDecoder.swift`

**New utilities file**:
```swift
// Sources/ResonateKit/Audio/PCMUtilities.swift
import Foundation

/// PCM sample conversion utilities
public enum PCMUtilities {
    /// 24-bit sample range constants
    public static let max24Bit: Int32 = 8_388_607   // 2^23 - 1
    public static let min24Bit: Int32 = -8_388_608  // -2^23

    /// Unpack 3-byte little-endian to Int32 with sign extension
    public static func unpack24Bit(_ bytes: [UInt8], offset: Int) -> Int32 {
        let b0 = Int32(bytes[offset])
        let b1 = Int32(bytes[offset + 1])
        let b2 = Int32(bytes[offset + 2])

        var value = b0 | (b1 << 8) | (b2 << 16)

        // Sign extend if negative (bit 23 set)
        if value & 0x800000 != 0 {
            value |= ~0xffffff
        }

        return value
    }

    /// Pack Int32 to 3-byte little-endian
    public static func pack24Bit(_ sample: Int32) -> [UInt8] {
        return [
            UInt8(sample & 0xFF),
            UInt8((sample >> 8) & 0xFF),
            UInt8((sample >> 16) & 0xFF)
        ]
    }

    /// Convert int32 samples to 16-bit (right-shift 8 bits)
    public static func convertTo16Bit(_ sample: Int32) -> Int16 {
        return Int16(sample >> 8)
    }

    /// Convert int16 samples to 24-bit range (left-shift 8 bits)
    public static func convertFrom16Bit(_ sample: Int16) -> Int32 {
        return Int32(sample) << 8
    }
}
```

**Modified decoder**:
```swift
// Sources/ResonateKit/Audio/AudioDecoder.swift
public class PCMDecoder: AudioDecoder {
    private let bitDepth: Int
    private let channels: Int

    public init(bitDepth: Int, channels: Int) {
        self.bitDepth = bitDepth
        self.channels = channels
    }

    public func decode(_ data: Data) throws -> Data {
        if bitDepth == 24 {
            // Decode 24-bit PCM (3 bytes per sample)
            return try decode24Bit(data)
        } else if bitDepth == 16 {
            // 16-bit PCM - pass through
            return data
        } else {
            throw AudioDecoderError.unsupportedBitDepth(bitDepth)
        }
    }

    private func decode24Bit(_ data: Data) throws -> Data {
        let bytesPerSample = 3
        guard data.count % bytesPerSample == 0 else {
            throw AudioDecoderError.invalidDataSize
        }

        let sampleCount = data.count / bytesPerSample
        let bytes = [UInt8](data)

        // OPTION A: Unpack to int32 samples for AudioQueue
        var samples = [Int32]()
        samples.reserveCapacity(sampleCount)

        for i in 0..<sampleCount {
            let sample = PCMUtilities.unpack24Bit(bytes, offset: i * bytesPerSample)
            samples.append(sample)
        }

        // Convert to Data (4 bytes per sample for int32)
        return samples.withUnsafeBytes { Data($0) }

        // OPTION B: Keep as 24-bit packed if AudioQueue supports it
        // return data  // Pass through
    }
}

public enum AudioDecoderFactory {
    public static func create(
        codec: AudioCodec,
        sampleRate: Int,
        channels: Int,
        bitDepth: Int,
        header: Data?
    ) throws -> AudioDecoder {
        switch codec {
        case .pcm:
            return PCMDecoder(bitDepth: bitDepth, channels: channels)
        case .opus, .flac:
            fatalError("Opus/FLAC decoding not yet implemented")
        }
    }
}

public enum AudioDecoderError: Error {
    case unsupportedBitDepth(Int)
    case invalidDataSize
}
```

**Testing**:
1. Send test 24-bit PCM chunks manually
2. Verify decoder unpacks correctly
3. Verify AudioQueue accepts the format

---

### Phase 3: Remove Hardcoded Default Format (CRITICAL)

**File**: `Sources/ResonateKit/Client/ResonateClient.swift:670-698`

**Options**:

**Option A**: Buffer binary messages until stream/start arrives
```swift
// Add to ResonateClient actor
private var pendingBinaryMessages: [BinaryMessage] = []
private var streamStartReceived = false

// In handleBinaryMessage:
if !streamStartReceived {
    pendingBinaryMessages.append(message)
    return
}

// In handleStreamStart:
streamStartReceived = true
// Process pending messages with correct format
for msg in pendingBinaryMessages {
    await processBinaryMessage(msg)
}
pendingBinaryMessages.removeAll()
```

**Option B**: Use highest advertised format as default
```swift
let defaultFormat = playerConfig.supportedFormats.first ?? AudioFormatSpec(
    codec: .pcm, channels: 2, sampleRate: 48000, bitDepth: 16
)
```

**Recommendation**: Option A is safer - matches Go behavior of waiting for stream/start.

---

### Phase 4: Verify AudioQueue 24-bit Support (TESTING REQUIRED)

**Investigation needed**:
1. Does AudioQueue natively support 24-bit packed format?
2. Or should we convert to 32-bit `kAudioFormatLinearPCM`?

**Test code** (in AudioPlayer.swift):
```swift
// For 24-bit, try packed format first
if format.bitDepth == 24 {
    audioFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked
    audioFormat.mBytesPerPacket = UInt32(format.channels * 3)  // 3 bytes per sample
    audioFormat.mBytesPerFrame = UInt32(format.channels * 3)
    audioFormat.mBitsPerChannel = 24
} else if format.bitDepth == 32 {
    // Alternative: Unpack to 32-bit
    audioFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger
    audioFormat.mBytesPerPacket = UInt32(format.channels * 4)
    audioFormat.mBytesPerFrame = UInt32(format.channels * 4)
    audioFormat.mBitsPerChannel = 32
}
```

**Testing**: Connect to server, play 24-bit stream, verify audio quality and no glitches.

---

## Testing Strategy

### Unit Tests to Add

1. **PCMUtilities Tests** (new file `Tests/ResonateKitTests/Audio/PCMUtilitiesTests.swift`):
   - Test 24-bit pack/unpack
   - Test sign extension for negative values
   - Test 16-bit ↔ 24-bit conversion
   - Test edge cases (min/max values)

2. **PCMDecoder Tests** (modify `Tests/ResonateKitTests/Audio/AudioDecoderTests.swift`):
   - Test 24-bit decoding
   - Test 16-bit pass-through
   - Test invalid data size handling

3. **Format Negotiation Tests** (new):
   - Verify highest advertised format is used
   - Verify format priority order

### Integration Tests

1. **Real Server Test** (192kHz FLAC source):
   ```bash
   swift run CLIPlayer ws://192.168.1.100:8927/resonate "HiResTest"
   ```
   - Verify `stream/start` shows 192kHz 24-bit
   - Verify audio plays without glitches
   - Check stats for dropped chunks (should be 0)

2. **Multiple Format Test**:
   - Test with 192kHz source
   - Test with 96kHz source
   - Test with 48kHz source
   - Verify correct format selected each time

3. **Buffer Fill Test**:
   - Monitor buffer usage at different sample rates
   - Verify 2MB buffer provides adequate headroom

---

## Performance Implications

### Memory Usage

**16-bit stereo @ 48kHz**:
- 20ms chunk = 960 samples × 2 channels × 2 bytes = 3,840 bytes
- 2MB buffer = 546 chunks = 10.92 seconds

**24-bit stereo @ 192kHz**:
- 20ms chunk = 3,840 samples × 2 channels × 3 bytes = 23,040 bytes
- 2MB buffer = 91 chunks = 1.82 seconds

**Impact**: Hi-res audio fills buffer 6x faster. 2MB is still adequate (Go uses same size).

### CPU Usage

- **24-bit unpacking**: Minimal overhead (simple bit shifts)
- **No resampling**: PCM at native rate avoids expensive resampling
- **AudioQueue**: Hardware-accelerated playback

**Expected**: <5% CPU increase for 24-bit unpacking.

---

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| AudioQueue rejects 24-bit packed format | HIGH | Test early; fall back to 32-bit conversion |
| Endianness issues on different architectures | MEDIUM | Add unit tests for byte order |
| Buffer underruns at 192kHz | MEDIUM | Monitor stats; increase buffer if needed |
| Clock sync drift at high sample rates | LOW | Existing ClockSynchronizer handles this |

---

## Success Criteria

### Definition of Done

- ✅ Client advertises all hi-res formats (up to 192kHz 24-bit)
- ✅ Server negotiates highest available format
- ✅ 24-bit PCM decoder correctly unpacks 3-byte samples
- ✅ AudioQueue accepts and plays 24-bit audio
- ✅ No hardcoded 48kHz 16-bit fallback
- ✅ All unit tests pass
- ✅ Integration test with 192kHz FLAC source plays correctly
- ✅ No audio glitches or dropouts
- ✅ Stats show 0% dropped chunks

### Verification Commands

```bash
# Build and run
swift build
swift run CLIPlayer ws://192.168.1.100:8927/resonate "HiResAudit"

# Expected output in stream info:
# "pcm 192000Hz 2ch 24bit"

# Run tests
swift test

# Check for SwiftLint issues
swiftlint lint --strict
```

---

## References

### Go Implementation Files
- `/Users/harper/workspace/personal/ma-interface/resonate-go/internal/app/player.go` - Format advertisement
- `/Users/harper/workspace/personal/ma-interface/resonate-go/internal/audio/types.go` - 24-bit utilities
- `/Users/harper/workspace/personal/ma-interface/resonate-go/internal/audio/decoder.go` - PCM decoder
- `/Users/harper/workspace/personal/ma-interface/resonate-go/internal/server/audio_engine.go` - Format negotiation, encoding
- `/Users/harper/workspace/personal/ma-interface/resonate-go/internal/player/output.go` - Volume control, 24-bit clamping
- `/Users/harper/workspace/personal/ma-interface/resonate-go/internal/player/scheduler.go` - Jitter buffer timing

### Swift Implementation Files
- `Sources/ResonateKit/Client/PlayerConfiguration.swift` - Format advertisement
- `Sources/ResonateKit/Models/AudioFormatSpec.swift` - Format data model
- `Sources/ResonateKit/Audio/AudioDecoder.swift` - Decoder factory
- `Sources/ResonateKit/Audio/AudioPlayer.swift` - AudioQueue configuration
- `Sources/ResonateKit/Client/ResonateClient.swift` - Default format fallback
- `Examples/CLIPlayer/Sources/CLIPlayer/CLIPlayer.swift` - Example usage

---

## Conclusion

The Swift ResonateKit implementation has **solid foundations** for hi-res audio:
- ✅ Data structures support up to 384kHz and 32-bit
- ✅ Protocol messages carry full format information
- ✅ AudioQueue configuration is dynamic

**However**, three critical gaps prevent hi-res from working:
1. 🔴 Client only advertises 48kHz 16-bit
2. 🔴 Hardcoded 48kHz 16-bit fallback
3. 🔴 No 24-bit PCM unpacking

**Estimated implementation time**: 4-6 hours
- Phase 1 (format advertisement): 30 min
- Phase 2 (24-bit decoder): 2 hours
- Phase 3 (remove hardcoded default): 1 hour
- Phase 4 (testing & verification): 2-3 hours

**Recommendation**: Implement all phases sequentially with testing at each step. Hi-res audio is a differentiating feature worth investing in! 🎵
