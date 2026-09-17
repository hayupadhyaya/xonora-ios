// ABOUTME: Handles decoding of binary messages from WebSocket (audio chunks, artwork, visualizer data)
// ABOUTME: Format: [type: uint8][timestamp: int64 big-endian][data: bytes...]

import Foundation

/// Binary message type ID allocation per Sendspin spec:
/// - 0-3: Reserved
/// - 4-7: Player role (audio chunks)
/// - 8-11: Artwork role (channels 0-3)
/// - 16-23: Visualizer role
/// - 24-191: Reserved for future roles
/// - 192-255: Application-specific roles
public enum BinaryMessageType: UInt8, Sendable {
    // Player role (4-7)
    case audioChunk = 4

    // Artwork role (8-11) - channels 0-3
    case artworkChannel0 = 8
    case artworkChannel1 = 9
    case artworkChannel2 = 10
    case artworkChannel3 = 11

    // Visualizer role (16-23)
    case visualizerData = 16
}

/// Binary message from server
public struct BinaryMessage: Sendable {
    /// Message type
    public let type: BinaryMessageType
    /// Server timestamp in microseconds when this should be played/displayed
    public let timestamp: Int64
    /// Message payload (audio data, image data, etc.)
    public let data: Data

    /// Decode binary message from WebSocket data
    /// - Parameter data: Raw WebSocket binary frame
    /// - Returns: Decoded message or nil if invalid
    public init?(data: Data) {
        guard data.count >= 9 else {
            // print("[BinaryMessage] ❌ Data too short: \(data.count) bytes")
            return nil
        }

        let typeValue = data[0]
        // print("[BinaryMessage] Type byte: \(typeValue)")

        guard let type = BinaryMessageType(rawValue: typeValue) else {
            // print("[BinaryMessage] ❌ Unknown type: \(typeValue)")
            return nil
        }

        self.type = type

        // Extract big-endian int64 from bytes 1-8
        let extractedTimestamp = data[1 ..< 9].withUnsafeBytes { buffer in
            buffer.loadUnaligned(as: Int64.self).bigEndian
        }

        // Validate timestamp is non-negative (server should never send negative)
        guard extractedTimestamp >= 0 else {
            // print("[BinaryMessage] ❌ Negative timestamp: \(extractedTimestamp)")
            return nil
        }

        timestamp = extractedTimestamp
        self.data = data.subdata(in: 9 ..< data.count)
        // print("[BinaryMessage] ✅ Parsed: type=\(type), timestamp=\(timestamp), data=\(self.data.count) bytes")
    }
}
