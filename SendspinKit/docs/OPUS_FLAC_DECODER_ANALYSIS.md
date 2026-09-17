# Go Resonate-Go Implementation: Opus and FLAC Decoder Analysis

## Overview
This document describes how the Go `resonate-go` implementation handles Opus and FLAC decoding, with specific details on codec header handling, integration with the audio pipeline, and the approach needed for Swift implementation.

---

## 1. Codec Libraries Used

### Dependencies (from go.mod)
```
gopkg.in/hraban/opus.v2 v2.0.0-20230925203106-0188a62cb302
github.com/mewkiz/flac v1.0.13
github.com/hajimehoshi/go-mp3 v0.3.4
```

**Key Libraries:**
- **Opus**: `gopkg.in/hraban/opus.v2` - Go bindings to libopus
- **FLAC**: `github.com/mewkiz/flac` - Pure Go FLAC decoder (but streaming support not yet fully implemented in resonate-go)
- **MP3**: `github.com/hajimehoshi/go-mp3` - Go MP3 decoder

---

## 2. Audio Format Definition

### Format Struct (pkg/audio/types.go)
```go
type Format struct {
	Codec       string
	SampleRate  int
	Channels    int
	BitDepth    int
	CodecHeader []byte // For FLAC, Opus, etc.
}
```

**Key Points:**
- `CodecHeader` field stores any codec-specific header data (base64-encoded in protocol messages)
- Audio output is always normalized to **int32 samples** for internal processing
- Buffer timestamps are in **microseconds** (server time domain)

### Audio Buffer
```go
type Buffer struct {
	Timestamp int64     // Server timestamp (microseconds)
	PlayAt    time.Time // Local play time
	Samples   []int32   // PCM samples (int32 for 16-bit and 24-bit)
	Format    Format
}
```

---

## 3. Opus Decoder Implementation

### File Location
`/Users/harper/workspace/personal/ma-interface/resonate-go/pkg/audio/decode/opus.go`

### Implementation
```go
type OpusDecoder struct {
	decoder *opus.Decoder
	format  audio.Format
}

func NewOpus(format audio.Format) (Decoder, error) {
	if format.Codec != "opus" {
		return nil, fmt.Errorf("invalid codec for Opus decoder: %s", format.Codec)
	}

	dec, err := opus.NewDecoder(format.SampleRate, format.Channels)
	if err != nil {
		return nil, fmt.Errorf("failed to create opus decoder: %w", err)
	}

	return &OpusDecoder{
		decoder: dec,
		format:  format,
	}, nil
}

func (d *OpusDecoder) Decode(data []byte) ([]int32, error) {
	// Opus decoder outputs to int16 buffer
	pcmSize := 5760 * d.format.Channels // Max frame size
	pcm16 := make([]int16, pcmSize)

	n, err := d.decoder.Decode(data, pcm16)
	if err != nil {
		return nil, fmt.Errorf("opus decode failed: %w", err)
	}

	// Convert int16 to int32 (Opus is always 16-bit)
	actualSamples := n * d.format.Channels
	pcm32 := make([]int32, actualSamples)
	for i := 0; i < actualSamples; i++ {
		pcm32[i] = audio.SampleFromInt16(pcm16[i])
	}
	return pcm32, nil
}
```

### Key Characteristics
- **Decoder Creation**: Initialized with `sampleRate` and `channels` from the Format
- **Frame Size**: 5760 samples per channel (maximum Opus frame size at 48kHz)
- **Output**: int16 PCM decoded to int32 (left-shifted for 24-bit compatibility)
- **Sample Conversion**: Uses `SampleFromInt16()` which left-shifts by 8 bits: `int32(sample) << 8`
- **Error Handling**: Wraps errors with context ("opus decode failed")

### Supported Sample Rates
- Standard Opus sample rates: 8000, 12000, 16000, 24000, 48000 Hz
- Library handles sample rate validation

---

## 4. FLAC Decoder Implementation

### File Location
`/Users/harper/workspace/personal/ma-interface/resonate-go/pkg/audio/decode/flac.go`

### Current Implementation Status
**NOTE**: FLAC streaming decoder is **NOT YET FULLY IMPLEMENTED** in resonate-go.

```go
type FLACDecoder struct {
	format audio.Format
}

func NewFLAC(format audio.Format) (Decoder, error) {
	if format.Codec != "flac" {
		return nil, fmt.Errorf("invalid codec for FLAC decoder: %s", format.Codec)
	}
	// FLAC decoder will be created per-chunk if needed
	return &FLACDecoder{
		format: format,
	}, nil
}

func (d *FLACDecoder) Decode(data []byte) ([]int32, error) {
	// For streaming FLAC, we need to handle frame-by-frame decoding
	// This is a simplified implementation
	// In production, would use mewkiz/flac's streaming API
	return nil, fmt.Errorf("FLAC streaming not yet implemented")
}
```

### Status
- Decoder can be created but returns "not yet implemented" error on decode
- Comment references `mewkiz/flac` streaming API for future implementation
- Library (`github.com/mewkiz/flac`) is already a dependency but not integrated

---

## 5. Codec Header Handling

### Protocol Message Format (pkg/protocol/messages.go)
```go
type StreamStartPlayer struct {
	Codec       string `json:"codec"`
	SampleRate  int    `json:"sample_rate"`
	Channels    int    `json:"channels"`
	BitDepth    int    `json:"bit_depth"`
	CodecHeader string `json:"codec_header,omitempty"` // Base64-encoded
}
```

### Codec Header in Audio Format
```go
type Format struct {
	Codec       string
	SampleRate  int
	Channels    int
	BitDepth    int
	CodecHeader []byte // Raw bytes from base64 decode
}
```

### Codec Header Decoding
```go
func DecodeBase64Header(encoded string) ([]byte, error) {
	return base64.StdEncoding.DecodeString(encoded)
}
```

### Usage Pattern
1. Server sends `StreamStartPlayer` message with codec header in Base64
2. Client decodes Base64 to bytes: `DecodeBase64Header(codecHeaderString)`
3. Stores in `Format.CodecHeader`
4. Passed to decoder during initialization (if needed)

### When CodecHeader is Required
- **Opus**: Typically not required in streaming frames (already decoded from frames)
- **FLAC**: Would contain FLAC metadata blocks (STREAMINFO, etc.)
- **PCM**: Not applicable

---

## 6. Decoder Factory Pattern

### File Location
`/Users/harper/workspace/personal/ma-interface/resonate-go/internal/audio/decoder.go`

### Factory Implementation
```go
func NewDecoder(format Format) (Decoder, error) {
	switch format.Codec {
	case "pcm":
		return &PCMDecoder{bitDepth: format.BitDepth}, nil
	case "opus":
		return NewOpusDecoder(format)
	case "flac":
		return NewFLACDecoder(format)
	default:
		return nil, fmt.Errorf("unsupported codec: %s", format.Codec)
	}
}
```

### Decoder Interface
```go
type Decoder interface {
	Decode(data []byte) ([]int32, error)
	Close() error
}
```

---

## 7. Audio Pipeline Integration

### Stream Processing Flow
1. **StreamStart Message** → Provides format (codec, sample rate, channels, bit depth, codec header)
2. **Create Decoder** → Factory creates appropriate decoder based on codec
3. **Audio Chunks (Binary Messages)** → Encoded audio frames arrive
4. **Decode** → Decoder.Decode(frame) → int32 PCM samples
5. **Schedule** → Scheduler assigns playback time based on server timestamp
6. **Output** → Send to audio output device

### Encoder Side (for reference)
- `internal/server/opus_encoder.go`: Encodes PCM to Opus
- Frame size: `SampleRate / 50` (20ms frames)
- Bitrate: 128 kbps × channels
- Output: Opus packets (max 4000 bytes)

---

## 8. Sample Conversion Utilities

### int16 ↔ int32 Conversion (pkg/audio/types.go)
```go
// SampleFromInt16 converts int16 sample to int32 (left-justified)
func SampleFromInt16(sample int16) int32 {
	return int32(sample) << 8
}

// SampleToInt16 converts int32 sample to int16
func SampleToInt16(sample int32) int16 {
	return int16(sample >> 8)
}
```

### 24-bit PCM Utilities
```go
// SampleFrom24Bit converts 24-bit packed bytes to int32 (little-endian)
func SampleFrom24Bit(b [3]byte) int32 {
	val := int32(b[0]) | int32(b[1])<<8 | int32(b[2])<<16
	// Sign extend from 24-bit to 32-bit
	if val&0x800000 != 0 {
		val |= ^0xFFFFFF
	}
	return val
}

// SampleTo24Bit converts int32 to 24-bit packed bytes (little-endian)
func SampleTo24Bit(sample int32) [3]byte {
	return [3]byte{
		byte(sample),
		byte(sample >> 8),
		byte(sample >> 16),
	}
}
```

---

## 9. Implementation Notes for Swift

### Key Design Decisions in Go
1. **Unified int32 Format**: All decoded audio converted to int32 (24-bit left-justified)
2. **Factory Pattern**: Single entry point for decoder creation by codec type
3. **Codec Header Storage**: Passed through Format struct, available to decoder if needed
4. **Error Wrapping**: All errors wrapped with codec context for debugging
5. **Frame-Based Decoding**: Each Decode() call processes one complete encoded frame

### Recommended Swift Approach
1. **Use AVAudioConverter or AudioToolbox**
   - Opus: `AVAudioConverter` with Opus input format
   - FLAC: `AVAudioConverter` with FLAC input format
   - Both output to PCM int16 or int32

2. **Codec Header Integration**
   - Store codec header from `StreamStartPlayer.codecHeader`
   - Pass to AVAudioConverter during initialization
   - May be needed for FLAC metadata, optional for Opus

3. **Sample Conversion Strategy**
   - Keep internal format as int32 (24-bit left-justified like Go)
   - Opus output (int16) → shift left 8 bits
   - FLAC output (varies) → normalize to int32

4. **Error Handling**
   - Wrap codec errors with format context
   - Distinguish between format initialization errors and frame decode errors

---

## 10. Testing References

### Opus Decoder Tests
`/Users/harper/workspace/personal/ma-interface/resonate-go/pkg/audio/decode/opus_test.go`

Tests cover:
- Valid decoder creation with standard formats
- Invalid codec rejection
- Mono and stereo channels
- Sample rate variations
- Resource cleanup (Close)

### FLAC Decoder Tests
`/Users/harper/workspace/personal/ma-interface/resonate-go/pkg/audio/decode/flac_test.go`

Tests cover:
- Decoder creation
- Invalid codec rejection
- "Not yet implemented" error on decode attempt
- Resource cleanup (Close)

---

## 11. Current Limitations & Known Issues

### Go Implementation
1. **FLAC Streaming Not Complete**: Library available but frame-by-frame streaming not integrated
2. **No Codec Header Validation**: CodecHeader field exists but not validated during decoder creation
3. **Max Frame Size Hardcoded**: Opus max 5760 samples per channel (proper approach)

### Swift Implementation Status (from Swift source)
1. **Opus/FLAC Not Implemented**: AudioDecoderFactory calls `fatalError()` for Opus/FLAC
2. **PCM Only Supported**: Current implementation handles 16-bit and 24-bit PCM only
3. **Header Parameter Unused**: AudioDecoderFactory accepts `header` parameter but ignores it

---

## 12. Critical Implementation Path for Swift

1. **Audio Format Reception**
   - ✅ Receive StreamStart message with codec and codecHeader
   - ✅ Store codecHeader (Base64 → decode to bytes)

2. **Decoder Creation** 
   - Create appropriate decoder based on codec
   - For Opus: Use AVAudioConverter with Opus input format
   - For FLAC: Use AVAudioConverter with FLAC input format
   - Pass codecHeader if provided

3. **Frame Decoding**
   - Each audio binary message = one encoded frame
   - Call decoder on frame → get PCM samples
   - Convert to int32 (24-bit format like Go)

4. **Scheduler Integration**
   - Timestamp still in server microseconds
   - Clock sync converts to local time base
   - Scheduler determines playback time

5. **Output to Audio System**
   - Feed int32 PCM to CoreAudio
   - Timestamp-based playback (not FIFO)

---

## Summary

The Go implementation uses:
- **Opus**: `gopkg.in/hraban/opus.v2` (libopus bindings) - ✅ Fully working
- **FLAC**: `github.com/mewkiz/flac` (pure Go) - ⚠️ Available but streaming not integrated
- **Codec Headers**: Base64-encoded, stored in Format, passed to decoder (future extension)
- **Unified Output**: All decoders output int32 PCM (24-bit left-justified)
- **Factory Pattern**: Single NewDecoder() factory for codec dispatch

For Swift, the analogous approach would use:
- **AVAudioConverter** for both Opus and FLAC decoding
- **AudioToolbox** framework for lower-level codec handling if needed
- **Matching int32 sample format** for consistency across codec types
- **Factory pattern** mirroring the Go approach
