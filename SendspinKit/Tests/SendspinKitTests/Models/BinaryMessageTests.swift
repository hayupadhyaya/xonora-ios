import Foundation
@testable import SendspinKit
import Testing

@Suite("Binary Message Tests")
struct BinaryMessageTests {
    @Test("Decode audio chunk binary message with type 4")
    func audioChunkDecoding() throws {
        var data = Data()
        data.append(4) // Type: audio chunk (per spec, player role uses type 4)

        // Timestamp: 1234567890 microseconds (big-endian int64)
        let timestamp: Int64 = 1_234_567_890
        withUnsafeBytes(of: timestamp.bigEndian) { data.append(contentsOf: $0) }

        // Audio data
        let audioData = Data([0x01, 0x02, 0x03, 0x04])
        data.append(audioData)

        let message = try #require(BinaryMessage(data: data))

        #expect(message.type == .audioChunk)
        #expect(message.timestamp == 1_234_567_890)
        #expect(message.data == audioData)
    }

    @Test("Decode artwork binary message")
    func artworkDecoding() throws {
        var data = Data()
        data.append(8) // Type: artwork channel 0 (per spec, artwork role uses types 8-11)

        let timestamp: Int64 = 9_876_543_210
        withUnsafeBytes(of: timestamp.bigEndian) { data.append(contentsOf: $0) }

        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0]) // JPEG header
        data.append(imageData)

        let message = try #require(BinaryMessage(data: data))

        #expect(message.type == .artworkChannel0)
        #expect(message.timestamp == 9_876_543_210)
        #expect(message.data == imageData)
    }

    @Test("Decode all artwork channels")
    func allArtworkChannels() throws {
        for (channelNum, expectedType) in [
            (0, BinaryMessageType.artworkChannel0),
            (1, BinaryMessageType.artworkChannel1),
            (2, BinaryMessageType.artworkChannel2),
            (3, BinaryMessageType.artworkChannel3),
        ] {
            var data = Data()
            data.append(UInt8(8 + channelNum)) // Types 8-11 for channels 0-3

            let timestamp: Int64 = 1_000_000
            withUnsafeBytes(of: timestamp.bigEndian) { data.append(contentsOf: $0) }

            data.append(Data([0x00])) // Minimal payload

            let message = try #require(BinaryMessage(data: data))
            #expect(message.type == expectedType)
        }
    }

    @Test("Decode visualizer data message")
    func visualizerDecoding() throws {
        var data = Data()
        data.append(16) // Type: visualizer data (per spec, visualizer role uses type 16)

        let timestamp: Int64 = 5_000_000
        withUnsafeBytes(of: timestamp.bigEndian) { data.append(contentsOf: $0) }

        let fftData = Data([0x10, 0x20, 0x30, 0x40])
        data.append(fftData)

        let message = try #require(BinaryMessage(data: data))

        #expect(message.type == .visualizerData)
        #expect(message.timestamp == 5_000_000)
        #expect(message.data == fftData)
    }

    @Test("Reject message with invalid type")
    func invalidType() {
        var data = Data()
        data.append(255) // Invalid type

        let timestamp: Int64 = 1000
        withUnsafeBytes(of: timestamp.bigEndian) { data.append(contentsOf: $0) }

        #expect(BinaryMessage(data: data) == nil)
    }

    @Test("Reject reserved type IDs")
    func reservedTypes() {
        // Types 0-3 are reserved per spec
        for reservedType: UInt8 in [0, 1, 2, 3] {
            var data = Data()
            data.append(reservedType)

            let timestamp: Int64 = 1000
            withUnsafeBytes(of: timestamp.bigEndian) { data.append(contentsOf: $0) }

            #expect(BinaryMessage(data: data) == nil)
        }
    }

    @Test("Reject message that is too short")
    func tooShort() {
        let data = Data([0, 1, 2, 3]) // Only 4 bytes, need at least 9

        #expect(BinaryMessage(data: data) == nil)
    }
}
