// ABOUTME: Clock synchronization with drift compensation using Kalman filter approach
// ABOUTME: Tracks both offset AND drift rate to handle clock frequency differences

import Foundation

/// Protocol for clock synchronization
public protocol ClockSyncProtocol: Actor {
    func serverTimeToLocal(_ serverTime: Int64) -> Int64
}

/// Quality of clock synchronization
public enum SyncQuality: Sendable {
    case good
    case degraded
    case lost
}

/// Clock synchronization statistics
public struct ClockStats: Sendable {
    public let offset: Int64
    public let rtt: Int64
    public let quality: SyncQuality
}

/// Synchronizes local clock with server clock using drift compensation
public actor ClockSynchronizer: ClockSyncProtocol {
    // Clock synchronization state
    private var offset: Int64 = 0 // Current offset in microseconds (server - client)
    private var drift: Double = 0.0 // Clock drift rate (dimensionless: μs/μs)
    private var rawOffset: Int64 = 0 // Latest raw offset measurement
    private var rtt: Int64 = 0 // Latest round-trip time
    private var quality: SyncQuality = .lost
    private var lastSyncTime: Date?
    private var lastSyncMicros: Int64 = 0 // Client time (μs) when offset/drift were last updated
    private var sampleCount: Int = 0
    private let smoothingRate: Double = 0.1 // 10% weight to new samples (Kalman gain)

    // Server loop origin tracking (when server's loop.time() == 0 in client's time domain)
    // This anchors the process-relative time domain to absolute time
    private let clientProcessStartAbsolute: Int64 // Absolute Unix epoch μs when client process started
    private var serverLoopOriginAbsolute: Int64 = 0 // Absolute Unix epoch μs when server loop started

    public init() {
        // Record absolute time when synchronizer is created (proxy for process start)
        clientProcessStartAbsolute = Int64(Date().timeIntervalSince1970 * 1_000_000)
    }

    /// Current clock offset in microseconds
    public var currentOffset: Int64 {
        return offset
    }

    /// Current sync quality
    public var currentQuality: SyncQuality {
        return quality
    }

    /// Get sync statistics
    public func getStats() -> ClockStats {
        return ClockStats(offset: offset, rtt: rtt, quality: quality)
    }

    /// Get individual stats for Sendable contexts
    public var statsOffset: Int64 { offset }
    public var statsRtt: Int64 { rtt }
    public var statsQuality: SyncQuality { quality }

    /// Process server time message to update offset and drift
    public func processServerTime(
        clientTransmitted: Int64, // t1
        serverReceived: Int64, // t2
        serverTransmitted: Int64, // t3
        clientReceived: Int64 // t4
    ) {
        // Calculate RTT and measured offset
        let (calculatedRtt, measuredOffset) = calculateOffset(
            clientTx: clientTransmitted,
            serverRx: serverReceived,
            serverTx: serverTransmitted,
            clientRx: clientReceived
        )

        rtt = calculatedRtt
        rawOffset = measuredOffset
        lastSyncTime = Date()

        // Debug logging for first few syncs
        if sampleCount < 3 {
            // Raw timestamps: t1=\(clientTransmitted), t2=\(serverReceived),
            // t3=\(serverTransmitted), t4=\(clientReceived)
            // Calculated: rtt=\(calculatedRtt)μs, measured_offset=\(measuredOffset)μs
        }

        // Discard samples with negative RTT (timestamp issues)
        if calculatedRtt < 0 {
            // print("[SYNC] Discarding sync sample: negative RTT \(calculatedRtt)μs (timestamp issue)")
            return
        }

        // Discard samples with high RTT (network congestion)
        if calculatedRtt > 100_000 { // 100ms
            // print("[SYNC] Discarding sync sample: high RTT \(calculatedRtt)μs")
            return
        }

        // First sync: initialize offset, no drift yet
        if sampleCount == 0 {
            offset = measuredOffset
            lastSyncMicros = clientReceived

            // Calculate server loop origin: when server loop.time() was 0
            // Since offset = server - client, when server = 0: client = -offset
            // Server loop origin in absolute time = client_process_start + (-offset)
            serverLoopOriginAbsolute = clientProcessStartAbsolute - offset

            sampleCount += 1
            quality = .good
            // Initial sync: offset=\(offset)μs, rtt=\(calculatedRtt)μs
            // Server loop origin: \(serverLoopOriginAbsolute)μs absolute
            // client process start: \(clientProcessStartAbsolute)μs
            return
        }

        // Second sync: calculate initial drift
        if sampleCount == 1 {
            let deltaTime = Double(clientReceived - lastSyncMicros)
            if deltaTime > 0 {
                // Drift = change in offset over time
                drift = Double(measuredOffset - offset) / deltaTime
                // Drift initialized: drift=\(String(format: "%.9f", drift)) μs/μs
                // over Δt=\(Int(deltaTime))μs
            }
            offset = measuredOffset
            lastSyncMicros = clientReceived

            // Update server loop origin with new offset
            serverLoopOriginAbsolute = clientProcessStartAbsolute - offset

            sampleCount += 1
            quality = .good
            // Second sync: offset=\(offset)μs, drift=\(String(format: "%.9f", drift)),
            // rtt=\(calculatedRtt)μs
            return
        }

        // Subsequent syncs: predict offset using drift, then update both
        let deltaTime = Double(clientReceived - lastSyncMicros)
        if deltaTime <= 0 {
            // Discarding sync sample: non-monotonic time
            return
        }

        // Predict what offset should be based on drift
        let predictedOffset = offset + Int64(drift * deltaTime)

        // Residual = how much our prediction was off
        let residual = measuredOffset - predictedOffset

        // Reject outliers (residual > 50ms suggests network issue or clock jump)
        if abs(residual) > 50000 {
            // Discarding sync sample: large residual \(residual)μs (possible clock jump)
            return
        }

        // Update offset from PREDICTED offset plus gain * residual
        // This is the Kalman filter update formula (simplified with fixed gain)
        offset = predictedOffset + Int64(smoothingRate * Double(residual))

        // Update drift: drift correction is residual / deltaTime
        // This estimates how much the drift rate needs to change
        let driftCorrection = Double(residual) / deltaTime
        drift += smoothingRate * driftCorrection

        lastSyncMicros = clientReceived
        sampleCount += 1

        // Update server loop origin with refined offset (accounting for drift)
        serverLoopOriginAbsolute = clientProcessStartAbsolute - offset

        // Update quality based on RTT
        if calculatedRtt < 50000 { // <50ms
            quality = .good
        } else {
            quality = .degraded
        }

        if sampleCount < 10 {
            // Sync #\(sampleCount): offset=\(offset)μs, drift=\(String(format: "%.9f", drift)),
            // residual=\(residual)μs, rtt=\(calculatedRtt)μs
        }
    }

    /// Calculate RTT and clock offset from timestamps
    private func calculateOffset(
        clientTx: Int64,
        serverRx: Int64,
        serverTx: Int64,
        clientRx: Int64
    ) -> (rtt: Int64, offset: Int64) {
        // Round-trip time
        // RTT = (receive_time - send_time) - (server_transmit - server_receive)
        let rtt = (clientRx - clientTx) - (serverTx - serverRx)

        // Estimated offset (positive = server ahead of client)
        // offset = ((server_receive - client_transmit) + (server_transmit - client_receive)) / 2
        let offset = ((serverRx - clientTx) + (serverTx - clientRx)) / 2

        return (rtt, offset)
    }

    /// Convert server timestamp to local time
    /// Server timestamps are in server's loop.time() domain (microseconds since server started)
    /// Returns absolute Unix epoch time in microseconds (suitable for Date conversion)
    public func serverTimeToLocal(_ serverTime: Int64) -> Int64 {
        // If we haven't synced yet, estimate using current process time
        // Assume server and client started at roughly the same time
        if sampleCount == 0 {
            return clientProcessStartAbsolute + serverTime
        }

        // Simple conversion using server loop origin
        // Server loop origin is the absolute time when server's loop.time() was 0
        // Due to how we calculate it (clientProcessStartAbsolute - offset), and offset
        // is continuously updated with drift compensation, the origin already accounts
        // for drift implicitly.
        //
        // Therefore: absolute_time = server_loop_origin + server_time
        return serverLoopOriginAbsolute + serverTime
    }

    /// Convert local timestamp to server time
    /// Takes absolute Unix epoch time in microseconds (from Date)
    /// Returns server loop.time() in microseconds (time since server started)
    public func localTimeToServer(_ localTime: Int64) -> Int64 {
        // If we haven't synced yet, estimate by subtracting process start
        if sampleCount == 0 {
            return localTime - clientProcessStartAbsolute
        }

        // Inverse of serverTimeToLocal:
        // serverTimeToLocal: absolute_time = serverLoopOriginAbsolute + server_time
        // Therefore: server_time = absolute_time - serverLoopOriginAbsolute
        return localTime - serverLoopOriginAbsolute
    }

    /// Check and update quality based on time since last sync
    public func checkQuality() -> SyncQuality {
        if let lastSync = lastSyncTime, Date().timeIntervalSince(lastSync) > 5.0 {
            quality = .lost
        }
        return quality
    }

    /// Reset clock synchronization (e.g., after reconnection)
    public func reset() {
        offset = 0
        drift = 0.0
        rawOffset = 0
        rtt = 0
        quality = .lost
        lastSyncTime = nil
        lastSyncMicros = 0
        serverLoopOriginAbsolute = 0
        sampleCount = 0
        // print("[SYNC] Clock synchronization reset")
    }
}
