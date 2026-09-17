# Codec Support in ResonateKit

## Supported Audio Codecs

ResonateKit supports the following audio codecs for streaming playback over the Resonate Protocol:

### PCM (Uncompressed)
- **Bit Depths:** 16-bit, 24-bit, 32-bit
- **Sample Rates:** Up to 192kHz (determined by server)
- **Channels:** Mono, Stereo
- **Performance:** Zero-copy passthrough for 16/32-bit, unpacking for 24-bit
- **Compression:** None (uncompressed audio)
- **Use Case:** Highest quality, no decoding overhead, larger bandwidth requirements

**Implementation Details:**
- 16-bit and 32-bit: Direct passthrough (no conversion needed)
- 24-bit: Unpacks 3-byte samples to 4-byte Int32 format for consistent pipeline processing

### Opus (Lossy Compressed)
- **Bit Depth:** 16-bit (decoded output, normalized to int32)
- **Sample Rates:** 8kHz, 12kHz, 16kHz, 24kHz, 48kHz
- **Channels:** Mono, Stereo
- **Library:** [alta/swift-opus](https://github.com/alta/swift-opus) v0.0.2+ (libopus 1.3+)
- **Performance:** ~0.5ms decode time per 20ms frame on Apple Silicon
- **Compression:** Lossy, optimized for low latency
- **Use Case:** Real-time streaming with low bandwidth (ideal for voice and music)

**Implementation Details:**
- Decodes Opus packets to float32 PCM via AVAudioPCMBuffer
- Converts float32 samples [-1.0, 1.0] to int32 [Int32.min, Int32.max]
- Handles both mono and stereo channel interleaving
- Standard 20ms frame size (960 samples @ 48kHz)

### FLAC (Lossless Compressed)
- **Bit Depths:** 16-bit, 24-bit
- **Sample Rates:** Up to 192kHz (supports hi-res audio)
- **Channels:** Mono, Stereo
- **Library:** [sbooth/flac-binary-xcframework](https://github.com/sbooth/flac-binary-xcframework) v0.2.0+ (libFLAC 1.4+)
- **Performance:** ~1-2ms decode time per frame on Apple Silicon
- **Compression:** Lossless (bit-perfect audio recovery)
- **Use Case:** Archival quality streaming, hi-res audio, bandwidth-constrained lossless

**Implementation Details:**
- Uses libFLAC stream decoder with custom read/write callbacks
- Accumulates incoming FLAC frames and processes via stream decoder
- Right-aligned int32 samples normalized to 24-bit position for consistency
- 16-bit samples shifted left 8 bits to match 24-bit alignment
- Efficient memory management with read offset tracking to prevent accumulation bugs

## Output Format

All decoders output **int32 PCM samples** in interleaved format to ensure a consistent audio pipeline:

- **16-bit sources:** Left-shifted 8 bits (24-bit aligned in int32)
- **24-bit sources:** Native 24-bit position in int32
- **32-bit sources:** Pass-through (full int32 range)

This normalization ensures:
- Consistent processing regardless of source codec
- Optimal dynamic range utilization
- Simple downstream pipeline (always int32)
- Matches the Go reference implementation's audio handling

**Sample Layout:**
```
Stereo interleaved: [L0, R0, L1, R1, L2, R2, ...]
Mono: [M0, M1, M2, M3, ...]
```

Each sample is 4 bytes (Int32), little-endian on Apple platforms.

## Performance Characteristics

### Memory Usage
- **PCM:** Zero-copy for 16/32-bit, single allocation for 24-bit unpacking
- **Opus:** One AVAudioPCMBuffer per frame, temporary float32 conversion buffer
- **FLAC:** Pending data buffer, decoded sample accumulator, stream decoder state

### CPU Usage (Apple Silicon M1/M2)
- **PCM 16/32-bit:** <0.01ms per frame (passthrough)
- **PCM 24-bit:** ~0.1ms per frame (unpacking)
- **Opus 48kHz stereo:** ~0.5ms per 20ms frame
- **FLAC 48kHz stereo:** ~1-2ms per frame (variable by compression level)

### Latency
All decoders are designed for real-time streaming with minimal latency:
- Frame-based processing (no buffering beyond single frame)
- Synchronous decode calls (no async overhead)
- Direct integration with AudioScheduler for timestamp-based playback

## Codec Selection

The server controls codec selection via the `StreamStart` message. ResonateKit advertises supported codecs during connection negotiation:

```swift
PlayerConfiguration(
    bufferCapacity: 1_048_576,
    supportedFormats: [
        AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 48000, bitDepth: 16),
        AudioFormatSpec(codec: .opus, channels: 2, sampleRate: 48000, bitDepth: 16),
        AudioFormatSpec(codec: .flac, channels: 2, sampleRate: 48000, bitDepth: 16),
    ]
)
```

The server selects the best codec based on:
- Client capabilities
- Network bandwidth
- Audio source format
- Quality preferences

## Adding New Codecs

To add support for a new codec:

### 1. Add Swift Package Dependency

Edit `Package.swift`:
```swift
dependencies: [
    .package(url: "https://github.com/example/swift-newcodec.git", from: "1.0.0")
],
targets: [
    .target(
        name: "ResonateKit",
        dependencies: [
            .product(name: "NewCodec", package: "swift-newcodec")
        ]
    )
]
```

### 2. Create Decoder Class

Implement `AudioDecoder` protocol in `Sources/ResonateKit/Audio/AudioDecoder.swift`:

```swift
import NewCodec

public class NewCodecDecoder: AudioDecoder {
    private let decoder: NewCodec.Decoder
    private let channels: Int

    public init(sampleRate: Int, channels: Int, bitDepth: Int) throws {
        // Initialize codec-specific decoder
        self.channels = channels
        self.decoder = try NewCodec.Decoder(
            sampleRate: sampleRate,
            channels: channels
        )
    }

    public func decode(_ data: Data) throws -> Data {
        // Decode compressed data
        let pcmBuffer = try decoder.decode(data)

        // Convert to int32 PCM format
        // (Implementation depends on codec's output format)
        let int32Samples = convertToInt32(pcmBuffer)

        return int32Samples.withUnsafeBytes { Data($0) }
    }
}
```

### 3. Update AudioCodec Enum

Add codec to `Sources/ResonateKit/Protocol/AudioCodec.swift`:

```swift
public enum AudioCodec: String, Codable, Sendable {
    case pcm
    case opus
    case flac
    case newcodec  // Add new codec
}
```

### 4. Update AudioDecoderFactory

Add factory case in `AudioDecoderFactory.create()`:

```swift
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
    case .opus:
        return try OpusDecoder(sampleRate: sampleRate, channels: channels, bitDepth: bitDepth)
    case .flac:
        return try FLACDecoder(sampleRate: sampleRate, channels: channels, bitDepth: bitDepth)
    case .newcodec:
        return try NewCodecDecoder(sampleRate: sampleRate, channels: channels, bitDepth: bitDepth)
    }
}
```

### 5. Write Tests

Create `Tests/ResonateKitTests/Audio/NewCodecDecoderTests.swift`:

```swift
import XCTest
@testable import ResonateKit

final class NewCodecDecoderTests: XCTestCase {
    func testNewCodecDecoderCreation() throws {
        let decoder = try AudioDecoderFactory.create(
            codec: .newcodec,
            sampleRate: 48000,
            channels: 2,
            bitDepth: 16,
            header: nil
        )
        XCTAssertNotNil(decoder)
    }

    func testNewCodecDecodeProducesInt32Output() throws {
        let decoder = try NewCodecDecoder(sampleRate: 48000, channels: 2, bitDepth: 16)

        // Create test packet
        let testPacket = Data([/* test data */])
        let decoded = try decoder.decode(testPacket)

        // Verify int32 output (4 bytes per sample)
        XCTAssertTrue(decoded.count % 4 == 0)
        XCTAssertGreaterThan(decoded.count, 0)
    }
}
```

### 6. Integration Testing

Test with real server streams:
1. Configure server to stream new codec format
2. Run CLIPlayer with new codec support
3. Verify audio playback quality
4. Check for glitches, dropouts, synchronization issues
5. Test format switching between codecs

### 7. Update Documentation

- Add codec to this document
- Update README.md
- Document any codec-specific configuration
- Note performance characteristics
- Add to CHANGELOG.md

## Troubleshooting

### Codec Not Recognized
- Verify codec is listed in `AudioCodec` enum
- Check server is sending correct codec name in `StreamStart` message
- Ensure client advertises codec in `supportedFormats`

### Decoding Errors
- Check codec library version compatibility
- Verify incoming data is valid codec format
- Look for buffer size mismatches
- Enable debug logging to see decoder error messages

### Audio Quality Issues
- Verify bit depth normalization is correct
- Check sample rate matches between encoder/decoder
- Ensure channel interleaving is proper
- Monitor for buffer underruns in AudioScheduler

### Performance Problems
- Profile decoder with Instruments
- Check for excessive memory allocations
- Consider buffer pooling for frequently allocated buffers
- Optimize sample format conversions with vDSP/Accelerate

## References

- [Resonate Protocol Specification](https://github.com/Resonate-Protocol/spec)
- [swift-opus Documentation](https://github.com/alta/swift-opus)
- [FLAC Binary Framework](https://github.com/sbooth/flac-binary-xcframework)
- [AudioDecoder Implementation](../Sources/ResonateKit/Audio/AudioDecoder.swift)
- [Go Reference Implementation](https://github.com/harperreed/resonate-go)
