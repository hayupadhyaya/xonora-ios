// ABOUTME: Specifies an audio format with codec, sample rate, channels, and bit depth
// ABOUTME: Used to negotiate audio format between client and server

/// Specification for an audio format
public struct AudioFormatSpec: Codable, Sendable, Hashable {
    /// Audio codec
    public let codec: AudioCodec
    /// Number of channels (1 = mono, 2 = stereo)
    public let channels: Int
    /// Sample rate in Hz (e.g., 44100, 48000)
    public let sampleRate: Int
    /// Bit depth (16, 24, or 32)
    public let bitDepth: Int

    enum CodingKeys: String, CodingKey {
        case codec
        case channels
        case sampleRate = "sample_rate"
        case bitDepth = "bit_depth"
    }

    public init(codec: AudioCodec, channels: Int, sampleRate: Int, bitDepth: Int) {
        precondition(channels > 0 && channels <= 32, "Channels must be between 1 and 32")
        precondition(sampleRate > 0 && sampleRate <= 384_000, "Sample rate must be between 1 and 384000 Hz")
        precondition(bitDepth == 16 || bitDepth == 24 || bitDepth == 32, "Bit depth must be 16, 24, or 32")

        self.codec = codec
        self.channels = channels
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
    }
}
