# AudioScheduler Manual Testing Guide

This document describes how to test the AudioScheduler implementation to verify synchronized audio playback.

## Test Environment

**Date:** 2025-10-24
**ResonateKit Version:** Main branch with AudioScheduler implementation
**Test Platform:** macOS

## Prerequisites

1. A running Resonate server (Go implementation or compatible)
2. Swift toolchain installed
3. ResonateKit built successfully

## Running the Tests

### Test 1: CLI Player with Real Server

The CLIPlayer example demonstrates the full AudioScheduler integration.

**Build:**
```bash
cd Examples/CLIPlayer
swift build
```

**Run:**
```bash
# Auto-discover servers on the network
.build/debug/CLIPlayer

# Or connect to specific server
.build/debug/CLIPlayer ws://localhost:8927 "Test Client"
```

**What to observe:**
```
[SYNC] Initial sync: offset=XXXμs, rtt=XXXμs
[SYNC] Drift initialized: drift=X.XXXXXXXXX μs/μs over Δt=XXXXXXμs
[SCHEDULER] Chunk #0: server_ts=XXXXXXXXXXXμs, delay=XXms, queue_size=X
[SCHEDULER] Chunk #1: server_ts=XXXXXXXXXXXμs, delay=XXms, queue_size=X
...
[CLIENT] Scheduler stats: received=XXX, played=XXX, dropped=X, queue_size=X
```

### Test 2: Audio Player Test (Local PCM)

Tests direct PCM playback without network (simpler test).

**Run:**
```bash
cd Examples/CLIPlayer
.build/debug/AudioTest
```

**Expected:**
- Loads sample-3s.pcm file
- Plays audio through speakers
- No dropped chunks (local playback has no network jitter)

## Manual Testing Checklist

Copy this checklist and mark items as you test:

### Connection & Initialization
- [ ] Connection to server succeeds
- [ ] Initial clock sync completes (5 rounds)
- [ ] Clock offset calculated and logged
- [ ] Drift rate initialized after second sync
- [ ] Sync quality reported as "good"

### Audio Playback
- [ ] Stream start message received
- [ ] AudioScheduler started
- [ ] First 10 chunks logged with timestamps
- [ ] Audio plays through speakers
- [ ] Audio sounds smooth (no glitches)
- [ ] Audio stays synchronized over time (compare with Go client if available)

### Scheduler Statistics
- [ ] Stats logged every 5 seconds
- [ ] `received` count increases as chunks arrive
- [ ] `played` count increases as chunks play
- [ ] `dropped` count remains low (<5%) under normal network conditions
- [ ] `queue_size` stays within reasonable bounds (0-20 chunks typically)

### Late Chunk Handling
- [ ] Late chunks (>50ms) are dropped
- [ ] Drop events are logged (first 10)
- [ ] Dropped chunks don't cause audio glitches
- [ ] Playback continues smoothly after drops

### Stream Lifecycle
- [ ] Stream end message handled correctly
- [ ] AudioScheduler stopped and cleared
- [ ] Can restart stream without issues
- [ ] Multiple start/stop cycles work correctly

### Cleanup & Disconnect
- [ ] Disconnect stops all tasks
- [ ] AudioScheduler cleaned up
- [ ] No memory leaks (check with Instruments if available)
- [ ] No zombie tasks after disconnect

### Network Conditions

Test under various conditions:

**Good Network:**
- [ ] Low RTT (<10ms) → sync quality "good"
- [ ] Minimal drops (0-1%)
- [ ] Tight sync (<10ms variance)

**Moderate Network:**
- [ ] Medium RTT (10-50ms) → sync quality "good" or "degraded"
- [ ] Some drops (1-5%)
- [ ] Acceptable sync (<50ms variance)

**Poor Network:**
- [ ] High RTT (>50ms) → sync quality "degraded"
- [ ] More drops (5-10%)
- [ ] Graceful degradation (audio continues)

## Success Criteria

✅ **Pass Criteria:**
1. Chunks play at correct server timestamps (±50ms)
2. Late chunks dropped cleanly without glitches
3. Audio quality maintained under normal network conditions
4. Stats accurately reflect scheduler behavior
5. No crashes or hangs during extended playback
6. Memory usage remains stable

❌ **Fail Criteria:**
1. Chunks play immediately (not scheduled)
2. Progressive desync over time
3. Audio glitches from timing issues
4. Stats don't match actual behavior
5. Crashes or memory leaks
6. Queue grows unbounded

## Comparing with Go Client

If you have the Go implementation available, run both clients simultaneously:

```bash
# Terminal 1: Go client
cd /tmp/resonate-go
go run cmd/player/main.go

# Terminal 2: Swift client
cd /path/to/ResonateKit/Examples/CLIPlayer
.build/debug/CLIPlayer
```

**Compare:**
- Do both clients start audio at the same time?
- Do they stay synchronized throughout playback?
- Do they handle drops similarly?
- Are clock sync stats comparable?

## Test Results Template

Copy and fill this out after testing:

```markdown
## Test Results - [Date]

**Tester:** [Name]
**Server:** [Server info]
**Network:** [LAN/WiFi/Remote/etc]

### Connection
- Connection: [PASS/FAIL]
- Clock sync: [PASS/FAIL]
- Initial RTT: [XXms]
- Initial offset: [XXXμs]

### Playback
- Audio plays: [PASS/FAIL]
- Audio quality: [Good/Fair/Poor]
- Synchronization: [PASS/FAIL]
- Drops: [X%]

### Scheduler Stats (after 60s)
- Received: [XXX chunks]
- Played: [XXX chunks]
- Dropped: [XX chunks]
- Average queue size: [X chunks]

### Issues Found
- [List any issues or unexpected behavior]

### Notes
- [Additional observations]
```

## Debugging Tips

If you see issues:

1. **Check clock sync logs:**
   - Look for "negative RTT" warnings → timestamp issues
   - Look for "large residual" warnings → clock jumps
   - Look for "pathological drift" → clock sync problems

2. **Check scheduler logs:**
   - First 10 chunks should show reasonable delays (-50ms to +50ms)
   - Dropped chunks should have negative delays
   - Queue size shouldn't grow unbounded

3. **Check audio player:**
   - PCM buffer should not overflow/underflow
   - Volume and mute controls should work
   - Format changes should clear scheduler queue

4. **Network analysis:**
   - Use Wireshark to capture WebSocket traffic
   - Measure actual RTT vs. calculated RTT
   - Check for packet loss or reordering

## Known Limitations

- ±50ms playback window (matches Go implementation)
- Simplified Kalman filter (good enough for MVP, but time-filter library would be better)
- No compensation for audio device latency
- Binary search priority queue (could use Heap for O(log n) instead of O(n))
