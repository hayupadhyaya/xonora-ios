// ABOUTME: Integration tests for clock synchronization simulating real network conditions
// ABOUTME: Tests multiple sync rounds with varying network jitter and clock drift

import Foundation
@testable import SendspinKit
import Testing

@Suite("Clock Sync Integration Tests")
struct ClockSyncIntegrationTests {
    @Test("Sync converges over multiple rounds with network jitter")
    func syncConvergence() async {
        let sync = ClockSynchronizer()

        // Simulate 10 rounds of clock sync with varying network conditions
        // Server is consistently 50 microseconds ahead
        let serverOffset: Int64 = 50

        var offsets: [Int64] = []

        for round in 0 ..< 10 {
            let baseTime = Int64(round * 10000)

            // Simulate symmetric network delay with jitter
            let networkDelay: Int64 = 100
            let jitter = Int64.random(in: 0 ..< 20)

            let clientTx = baseTime
            let serverRx = baseTime + networkDelay + jitter + serverOffset // Client to server + offset
            let serverTx = serverRx + 5 // 5 microsecond server processing time
            let clientRx = serverTx + networkDelay + jitter - serverOffset // Server to client

            await sync.processServerTime(
                clientTransmitted: clientTx,
                serverReceived: serverRx,
                serverTransmitted: serverTx,
                clientReceived: clientRx
            )

            let currentOffset = await sync.currentOffset
            offsets.append(currentOffset)
        }

        // After multiple rounds, offset should be reasonably close to true offset
        let finalOffset = offsets.last!
        #expect(finalOffset > 0 && finalOffset < 150) // Should detect some offset

        // Verify median filtering is working (offsets should be relatively stable)
        let lastFive = Array(offsets.suffix(5))
        let maxVariation = lastFive.max()! - lastFive.min()!
        #expect(maxVariation < 200) // Low variation indicates good filtering
    }

    @Test("Time conversion maintains bidirectional accuracy")
    func bidirectionalTimeConversion() async {
        let sync = ClockSynchronizer()

        // Initialize with known offset
        await sync.processServerTime(
            clientTransmitted: 1000,
            serverReceived: 1500,
            serverTransmitted: 1505,
            clientReceived: 2005
        )

        let testServerTime: Int64 = 10000

        // Convert server time to local
        let localTime = await sync.serverTimeToLocal(testServerTime)

        // Convert back to server time
        let backToServer = await sync.localTimeToServer(localTime)

        // Should get back to original value (within rounding error)
        #expect(abs(backToServer - testServerTime) < 5)
    }

    @Test("Handles extreme network jitter gracefully")
    func extremeJitter() async {
        let sync = ClockSynchronizer()

        // Add samples with extreme outliers
        let samples: [(Int64, Int64, Int64, Int64)] = [
            (1000, 1100, 1105, 1205), // Normal: ~50us offset
            (2000, 2100, 2105, 2205), // Normal: ~50us offset
            (3000, 5000, 5005, 8005), // Extreme jitter: 2000us each way
            (4000, 4100, 4105, 4205), // Normal: ~50us offset
            (5000, 5100, 5105, 5205) // Normal: ~50us offset
        ]

        for (clientTransmitted, serverReceived, serverTransmitted, clientReceived) in samples {
            await sync.processServerTime(
                clientTransmitted: clientTransmitted,
                serverReceived: serverReceived,
                serverTransmitted: serverTransmitted,
                clientReceived: clientReceived
            )
        }

        let offset = await sync.currentOffset

        // Median should filter out the extreme outlier
        // Normal samples have ~50us offset, outlier has ~2500us offset
        #expect(offset < 200) // Should be close to normal samples, not outlier
    }

    @Test("Clock drift detection over time")
    func clockDrift() async {
        let sync = ClockSynchronizer()

        // Simulate clock drift: offset changes gradually over time
        for drift in stride(from: 0, through: 100, by: 10) {
            let baseTime = Int64(drift * 1000)
            let currentOffset = Int64(50 + drift) // Clock drifting apart

            let networkDelay: Int64 = 100

            let clientTx = baseTime
            let serverRx = baseTime + networkDelay + currentOffset
            let serverTx = serverRx + 5
            let clientRx = serverTx + networkDelay - currentOffset

            await sync.processServerTime(
                clientTransmitted: clientTx,
                serverReceived: serverRx,
                serverTransmitted: serverTx,
                clientReceived: clientRx
            )
        }

        let finalOffset = await sync.currentOffset

        // Should track the drift (offset increases from 50 to 150)
        #expect(finalOffset > 100) // Has tracked some of the drift
    }
}
