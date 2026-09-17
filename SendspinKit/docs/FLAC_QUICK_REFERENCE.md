# FLAC Decoder Testing - Quick Reference

## Running the Test

```bash
cd /Users/harper/Public/src/personal/ma-interface/ResonateKit/Examples/CLIPlayer
swift run FLACTest
```

## Test Results Summary

**Status:** ⚠️ **Decoder works but returns no audio data**

### What Works ✅
- Decoder initialization (all sample rates, bit depths, channel configs)
- Memory management (pendingData leak fix verified)
- Callback mechanism (read/write/error callbacks connected)
- Crash resistance (handles invalid data without crashing)

### What Doesn't Work ❌
- **Audio decoding**: Returns 0 samples from valid FLAC streams
- Invalid data rejection (accepts garbage data)

## Root Cause

**`FLAC__stream_decoder_process_single()` only processes ONE unit per call:**
- Call 1: Processes STREAMINFO metadata → 0 audio samples
- Call 2: Would process first frame → audio samples
- Call 3: Would process second frame → audio samples

**Current implementation only calls it once → No audio output**

## Recommended Fix

Replace line 216 in `AudioDecoder.swift`:

```swift
// OLD (processes one unit - metadata OR frame):
let success = FLAC__stream_decoder_process_single(decoder)

// NEW (processes entire stream):
let success = FLAC__stream_decoder_process_until_end_of_stream(decoder)
```

## Test Files

| File | Purpose |
|------|---------|
| `Sources/FLACTest/main.swift` | Test program source |
| `Sources/FLACTest/test_silence.flac` | Real FLAC file (9.5KB, 0.1sec, 440Hz) |
| `FLAC_TEST_RESULTS.md` | Detailed test report |
| `flac_test_output.txt` | Complete test output |

## Key Test Cases

1. **Real FLAC File**: 9,518 bytes → 0 samples decoded
2. **Synthetic Stream**: 85 bytes → 0 samples decoded
3. **Multiple Calls**: 3 calls → all return 0 samples
4. **Memory Leak**: Fixed ✅ (pendingData cleared properly)
5. **Callbacks**: Working ✅ (read invoked, write never invoked)

## Implementation Status

```
FLACDecoder Architecture: ✅ SOUND
Callback Mechanism:       ✅ WORKING
Memory Management:        ✅ FIXED
Audio Output:             ❌ BROKEN (0 samples)
Error Handling:           ⚠️  PARTIAL
```

## Next Actions

1. **Fix decode logic**: Use `process_until_end_of_stream`
2. **Add state checking**: Verify decoder state after processing
3. **Improve error handling**: Reject invalid data properly
4. **Add integration tests**: Test with real FLAC files in CI

## Decoder Comparison

| Feature | OpusDecoder | FLACDecoder |
|---------|-------------|-------------|
| Input | Packets (frames only) | Streams (metadata + frames) |
| Processing | One packet = audio data | One call = metadata OR frame |
| Output | ✅ Returns PCM | ❌ Returns 0 bytes |
| Use Case | Streaming (Resonate) | File/stream playback |

**Note:** Consider if FLACDecoder should also accept frame-only data like OpusDecoder.

---

**Last Updated:** October 26, 2025
**Test Coverage:** 9 test cases, 47 assertions
**Decoder Version:** ResonateKit (commit: 7a498f0)
