# Changelog

All notable changes to ResonateKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **AudioScheduler**: Timestamp-based audio scheduling for precise synchronization
  - Priority queue maintains chunks sorted by playback time
  - 10ms timer loop checks for ready chunks
  - ±50ms playback window tolerates network jitter
  - Automatic dropping of late chunks (>50ms past playback time)
  - AsyncStream-based output pipeline for non-blocking playback
  - Detailed statistics tracking (received/played/dropped/queue size)
- **Clock Drift Compensation**: Kalman filter approach in ClockSynchronizer
  - Tracks both offset AND drift rate (μs/μs) for long-term accuracy
  - Predicts offset using drift between syncs
  - Residual-based updates with configurable smoothing rate
  - Outlier rejection for large residuals (>50ms)
- **Enhanced Logging**: Comprehensive debug output for troubleshooting
  - First 10 scheduled chunks with delay and queue size
  - First 10 dropped chunks with timing details
  - Periodic scheduler stats (every 5 seconds)
  - Clock sync convergence logging
- **Manual Testing Guide**: Complete testing documentation (docs/TESTING.md)
  - Testing checklist with success criteria
  - Debugging tips and network condition scenarios
  - Comparison guide for Go vs Swift clients
  - Test results template

### Changed
- **AudioPlayer**: Refactored for direct PCM playback
  - Added `playPCM(_:)` method for scheduled chunks
  - Simplified buffer management (removed timestamp queue)
  - Removed complexity around timestamp-based playback
- **ResonateClient**: Integrated AudioScheduler into pipeline
  - Audio chunks now flow: WebSocket → Decode → Scheduler → AudioPlayer
  - Scheduler starts/stops/clears with stream lifecycle
  - Proper cleanup on disconnect
- **AudioTest Example**: Updated to use new `playPCM()` API

### Deprecated
- `AudioPlayer.enqueue(chunk:)`: Use AudioScheduler for timestamp-based scheduling
  - This method bypassed the scheduler and played chunks immediately
  - Will be removed in future version after scheduler is proven in production

### Fixed
- **Audio Synchronization**: Chunks now play at server timeline, not network arrival time
  - Network jitter no longer affects playback timing directly
  - Late chunks dropped cleanly without audio glitches
- **Progressive Desync**: Clock drift compensation prevents desync over time
  - Drift rate tracked alongside offset for accurate long-term sync
  - Prediction + residual updates keep clocks aligned

## Implementation Details

### AudioScheduler Architecture

The AudioScheduler sits between the decoder and AudioPlayer:

```
WebSocket → BinaryMessage → Decode → AudioScheduler → AudioPlayer → Speakers
                                         ↓
                                   Priority Queue
                                   Timer (10ms)
                                   ClockSync
```

**Key Components:**
- `schedule(pcm:serverTimestamp:)` - Accepts decoded PCM with server timestamp
- `checkQueue()` - Timer callback that outputs ready chunks
- `scheduledChunks` - AsyncStream consumed by ResonateClient
- `stats` / `getDetailedStats()` - Performance monitoring

**Design Decisions:**
- Binary search for priority queue insertion (O(log n)) vs simpler partition
- ±50ms playback window matches Go implementation
- Max 100 chunks in queue (configurable) prevents unbounded growth
- First 10 logs for each event type balance debugging vs log spam

### Clock Synchronization Algorithm

Uses simplified Kalman filter with fixed gain (0.1):

1. **Initial Sync**: Set offset from first measurement
2. **Second Sync**: Calculate initial drift rate
3. **Subsequent Syncs**:
   - Predict offset: `predicted = offset + drift * Δt`
   - Calculate residual: `residual = measured - predicted`
   - Update offset: `offset = predicted + gain * residual`
   - Update drift: `drift = drift + gain * (residual / Δt)`

**Quality Checks:**
- Discard samples with negative RTT (timestamp issues)
- Discard samples with high RTT (>100ms, network congestion)
- Reject outliers with large residuals (>50ms, clock jumps)

### Testing Coverage

**Unit Tests (9 tests):**
- AudioScheduler: timestamp conversion, priority queue, output timing, late dropping, queue limits
- Tests use MockClockSynchronizer for predictable time offsets

**Integration Tests:**
- ResonateClient scheduler integration
- AudioPlayer playback methods

**Manual Testing:**
- CLIPlayer example for real server testing
- AudioTest example for local PCM playback
- Comprehensive testing guide (docs/TESTING.md)

### Future Enhancements

Potential improvements for future versions:

1. **Advanced Clock Sync**: Port full Resonate time-filter library
   - Covariance tracking for quality metrics
   - Adaptive forgetting factor
   - Better handling of asymmetric network delays

2. **Performance Optimizations**:
   - Use Swift Collections Heap for O(log n) operations
   - Batch chunk processing
   - Reduce memory allocations in hot path

3. **Audio Device Latency**: Compensate for device output latency
4. **Adaptive Playback Window**: Adjust window based on network conditions
5. **Playout Smoothing**: Buffer management for consistent playout

## References

- Go implementation: [resonate-go](https://github.com/harperreed/resonate-go)
- Resonate Protocol: [spec](https://github.com/Resonate-Protocol/spec)
- Time filter library: [time-filter](https://github.com/Resonate-Protocol/time-filter)
- Design docs:
  - [Audio Scheduler Design](plans/2025-10-24-audio-scheduler-design.md)
  - [Implementation Plan](plans/2025-10-24-audio-scheduler-implementation.md)
