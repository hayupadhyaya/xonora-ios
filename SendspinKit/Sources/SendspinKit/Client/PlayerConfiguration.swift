// ABOUTME: Configuration for player role capabilities
// ABOUTME: Specifies buffer capacity and supported audio formats

import Foundation

/// Configuration for player role
public struct PlayerConfiguration: Sendable {
    /// Buffer capacity in bytes
    public let bufferCapacity: Int

    /// Supported audio formats in priority order
    public let supportedFormats: [AudioFormatSpec]

    public init(bufferCapacity: Int, supportedFormats: [AudioFormatSpec]) {
        assert(bufferCapacity > 0, "Buffer capacity must be positive")
        assert(!supportedFormats.isEmpty, "Must support at least one audio format")

        self.bufferCapacity = bufferCapacity
        self.supportedFormats = supportedFormats
    }
}
