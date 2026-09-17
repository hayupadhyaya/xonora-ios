import Foundation
@testable import SendspinKit
import Testing

@Suite("AudioPlayer Tests")
struct AudioPlayerTests {
    @Test("Initialize AudioPlayer")
    func initialization() async {
        let player = AudioPlayer()

        let isPlaying = player.isPlaying
        #expect(isPlaying == false)
    }

    @Test("Configure audio format")
    func formatSetup() async throws {
        let player = AudioPlayer()

        let format = AudioFormatSpec(
            codec: .pcm,
            channels: 2,
            sampleRate: 48000,
            bitDepth: 16
        )

        try player.start(format: format, codecHeader: nil)

        let isPlaying = player.isPlaying
        #expect(isPlaying == true)

        player.stop()
    }

    @Test("Play PCM data directly")
    func testPlayPCM() async throws {
        let player = AudioPlayer()

        let format = AudioFormatSpec(
            codec: .pcm,
            channels: 2,
            sampleRate: 48000,
            bitDepth: 16
        )

        try player.start(format: format, codecHeader: nil)

        // Create 1 second of silence
        let bytesPerSample = format.channels * format.bitDepth / 8
        let samplesPerSecond = format.sampleRate
        let pcmData = Data(repeating: 0, count: samplesPerSecond * bytesPerSample)

        // Should not throw
        player.playPCM(pcmData)

        player.stop()
    }

    @Test("Decode method still available")
    func decodeMethod() async throws {
        let player = AudioPlayer()

        let format = AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 48000, bitDepth: 16)
        try player.start(format: format, codecHeader: nil)

        // Decode should work for PCM passthrough
        let inputData = Data(repeating: 0, count: 1024)
        let decoded = try player.decode(inputData)

        #expect(decoded.count == 1024) // PCM passthrough should return same size

        player.stop()
    }
}
