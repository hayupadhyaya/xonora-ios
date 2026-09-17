// ABOUTME: Unit tests for Opus audio decoder
// ABOUTME: Validates Opus frame decoding and int32 PCM output format

import XCTest
@testable import SendspinKit

final class OpusDecoderTests: XCTestCase {
    func testOpusDecoderCreation() throws {
        // Opus standard format: 48kHz stereo
        let decoder = try AudioDecoderFactory.create(
            codec: .opus,
            sampleRate: 48000,
            channels: 2,
            bitDepth: 16,
            header: nil
        )

        XCTAssertNotNil(decoder)
    }

    func testOpusDecodeProducesInt32Output() throws {
        let decoder = try OpusDecoder(sampleRate: 48000, channels: 2, bitDepth: 16)

        // Create a minimal valid Opus packet (silence frame)
        // Opus TOC byte for 20ms SILK frame: 0x3C
        let silencePacket = Data([0x3C, 0xFC, 0xFF, 0xFE])

        let decoded = try decoder.decode(silencePacket)

        // Should output int32 samples (4 bytes per sample)
        XCTAssertTrue(decoded.count % 4 == 0, "Output should be int32 samples")
        XCTAssertGreaterThan(decoded.count, 0, "Should decode some samples")
    }

    func testOpusDecoderSampleRates() throws {
        // Test all standard Opus sample rates
        for sampleRate in [8000, 12000, 16000, 24000, 48000] {
            let decoder = try OpusDecoder(
                sampleRate: sampleRate,
                channels: 2,
                bitDepth: 16
            )
            XCTAssertNotNil(decoder)
        }
    }
}
