// ABOUTME: Integration tests for binary message handling simulating real audio/artwork data
// ABOUTME: Tests binary message creation, encoding, and decoding with realistic payloads

import Foundation
@testable import SendspinKit
import Testing

@Suite("Binary Message Integration Tests")
struct BinaryMessageIntegrationTests {
    @Test("Audio chunk with real PCM data")
    func realAudioChunk() throws {
        // Simulate 1ms of 48kHz stereo 16-bit PCM audio
        let sampleRate = 48000
        let channels = 2
        let bytesPerSample = 2
        let duration = 0.001 // 1 millisecond

        let sampleCount = Int(Double(sampleRate) * duration)
        let dataSize = sampleCount * channels * bytesPerSample

        // Generate simple sine wave test tone (440 Hz A note)
        var audioData = Data()
        for sampleIndex in 0 ..< sampleCount {
            let time = Double(sampleIndex) / Double(sampleRate)
            let amplitude = sin(2.0 * .pi * 440.0 * time)
            let sample = Int16(amplitude * Double(Int16.max))

            // Stereo: same sample for both channels
            withUnsafeBytes(of: sample.littleEndian) { audioData.append(contentsOf: $0) }
            withUnsafeBytes(of: sample.littleEndian) { audioData.append(contentsOf: $0) }
        }

        // Create binary message
        var messageData = Data()
        messageData.append(4) // Audio chunk type (per spec, player role uses type 4)

        let timestamp: Int64 = 1_000_000 // 1 second in microseconds
        withUnsafeBytes(of: timestamp.bigEndian) { messageData.append(contentsOf: $0) }

        messageData.append(audioData)

        // Decode message
        let message = try #require(BinaryMessage(data: messageData))

        #expect(message.type == .audioChunk)
        #expect(message.timestamp == 1_000_000)
        #expect(message.data.count == dataSize)
    }

    @Test("Multiple audio chunks in sequence")
    func audioChunkSequence() throws {
        let chunkDuration: Int64 = 25000 // 25ms in microseconds
        var chunks: [BinaryMessage] = []

        // Create 10 sequential chunks
        for chunkIndex in 0 ..< 10 {
            var data = Data()
            data.append(4) // Audio chunk type (per spec, player role uses type 4)

            let timestamp = Int64(chunkIndex) * chunkDuration
            withUnsafeBytes(of: timestamp.bigEndian) { data.append(contentsOf: $0) }

            // Add some dummy audio data
            let audioData = Data(repeating: UInt8(chunkIndex), count: 2048)
            data.append(audioData)

            let message = try #require(BinaryMessage(data: data))
            chunks.append(message)
        }

        // Verify chunks are in order
        for (index, chunk) in chunks.enumerated() {
            #expect(chunk.timestamp == Int64(index) * chunkDuration)
            #expect(chunk.data.count == 2048)
            #expect(chunk.data.first == UInt8(index))
        }

        // Verify time span
        let totalDuration = chunks.last!.timestamp - chunks.first!.timestamp
        #expect(totalDuration == 9 * chunkDuration) // 9 intervals between 10 chunks
    }

    @Test("Artwork JPEG with realistic image data")
    func artworkJPEG() throws {
        // Create realistic JPEG header + minimal data
        var jpegData = Data()

        // JPEG SOI (Start of Image) marker
        jpegData.append(contentsOf: [0xFF, 0xD8])

        // JFIF APP0 marker
        jpegData.append(contentsOf: [0xFF, 0xE0])

        // Segment length
        jpegData.append(contentsOf: [0x00, 0x10])

        // JFIF identifier
        jpegData.append(contentsOf: [0x4A, 0x46, 0x49, 0x46, 0x00]) // "JFIF\0"

        // Version 1.1
        jpegData.append(contentsOf: [0x01, 0x01])

        // Density units, X density, Y density, thumbnail
        jpegData.append(contentsOf: [0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00])

        // Add some fake image data
        jpegData.append(Data(repeating: 0xFF, count: 1000))

        // EOI (End of Image) marker
        jpegData.append(contentsOf: [0xFF, 0xD9])

        // Create artwork message for channel 0
        var messageData = Data()
        messageData.append(8) // Artwork channel 0 (per spec, artwork role uses types 8-11)

        let timestamp: Int64 = 5_000_000 // 5 seconds
        withUnsafeBytes(of: timestamp.bigEndian) { messageData.append(contentsOf: $0) }

        messageData.append(jpegData)

        // Decode
        let message = try #require(BinaryMessage(data: messageData))

        #expect(message.type == .artworkChannel0)
        #expect(message.timestamp == 5_000_000)
        #expect(message.data.count == jpegData.count)

        // Verify JPEG header is intact
        #expect(message.data[0] == 0xFF)
        #expect(message.data[1] == 0xD8)
        #expect(message.data[message.data.count - 2] == 0xFF)
        #expect(message.data[message.data.count - 1] == 0xD9)
    }

    @Test("All artwork channels simultaneously")
    func multipleArtworkChannels() throws {
        var channels: [BinaryMessage] = []

        // Create messages for all 4 artwork channels
        for channelNum in 0 ..< 4 {
            var data = Data()
            data.append(UInt8(8 + channelNum)) // Channels 8-11 (per spec)

            let timestamp: Int64 = 1_000_000
            withUnsafeBytes(of: timestamp.bigEndian) { data.append(contentsOf: $0) }

            // Different image data for each channel
            let imageData = Data(repeating: UInt8(channelNum * 10), count: 512)
            data.append(imageData)

            let message = try #require(BinaryMessage(data: data))
            channels.append(message)
        }

        // Verify all channels decoded correctly
        #expect(channels[0].type == .artworkChannel0)
        #expect(channels[1].type == .artworkChannel1)
        #expect(channels[2].type == .artworkChannel2)
        #expect(channels[3].type == .artworkChannel3)

        // All have same timestamp (simultaneous update)
        for channel in channels {
            #expect(channel.timestamp == 1_000_000)
        }
    }

    @Test("Empty artwork message (clear artwork command)")
    func emptyArtworkMessage() throws {
        // Per spec, empty artwork message clears the display
        var data = Data()
        data.append(8) // Artwork channel 0 (per spec, type 8)

        let timestamp: Int64 = 2_000_000
        withUnsafeBytes(of: timestamp.bigEndian) { data.append(contentsOf: $0) }

        // No image data - just header

        let message = try #require(BinaryMessage(data: data))

        #expect(message.type == .artworkChannel0)
        #expect(message.timestamp == 2_000_000)
        #expect(message.data.isEmpty) // Empty payload signals "clear"
    }

    @Test("Visualizer data with FFT spectrum")
    func testVisualizerData() throws {
        // Simulate FFT spectrum data (32 frequency bins)
        let binCount = 32
        var fftData = Data()

        for binIndex in 0 ..< binCount {
            // Simulate decreasing amplitude at higher frequencies
            let amplitude = Float(255 - (binIndex * 8))
            withUnsafeBytes(of: amplitude) { fftData.append(contentsOf: $0) }
        }

        // Create visualizer message
        var messageData = Data()
        messageData.append(16) // Visualizer data type (per spec, type 16)

        let timestamp: Int64 = 3_000_000
        withUnsafeBytes(of: timestamp.bigEndian) { messageData.append(contentsOf: $0) }

        messageData.append(fftData)

        // Decode
        let message = try #require(BinaryMessage(data: messageData))

        #expect(message.type == .visualizerData)
        #expect(message.timestamp == 3_000_000)
        #expect(message.data.count == binCount * 4) // 32 bins * 4 bytes per float
    }

    @Test("Large audio chunk near buffer limit")
    func largeAudioChunk() throws {
        // Simulate large compressed audio chunk (100 KB Opus frame)
        let chunkSize = 100_000
        let audioData = Data(repeating: 0xAB, count: chunkSize)

        var messageData = Data()
        messageData.append(4) // Audio chunk (per spec, player role uses type 4)

        let timestamp: Int64 = 10_000_000
        withUnsafeBytes(of: timestamp.bigEndian) { messageData.append(contentsOf: $0) }

        messageData.append(audioData)

        let message = try #require(BinaryMessage(data: messageData))

        #expect(message.type == .audioChunk)
        #expect(message.data.count == chunkSize)
        #expect(messageData.count == 9 + chunkSize) // 1 type + 8 timestamp + data
    }
}
