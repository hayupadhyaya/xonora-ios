// ABOUTME: Simple test to verify AudioPlayer can play audio through speakers
// ABOUTME: Plays a local PCM file to test basic audio output functionality

import Foundation
import SendspinKit

@main
struct AudioTest {
    static func main() async throws {
        print("🔊 Audio Player Test")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Load PCM file
        let fileURL = URL(fileURLWithPath: "sample-3s.pcm")
        guard let audioData = try? Data(contentsOf: fileURL) else {
            print("❌ Failed to load sample-3s.pcm")
            print("Make sure the file exists in the current directory")
            return
        }

        print("✅ Loaded \(audioData.count) bytes of PCM audio")

        // Create audio player
        let bufferManager = BufferManager(capacity: 2_097_152)
        let clockSync = ClockSynchronizer()
        let audioPlayer = AudioPlayer(
            bufferManager: bufferManager,
            clockSync: clockSync
        )

        // Configure for PCM 48kHz stereo 16-bit
        let format = AudioFormatSpec(
            codec: .pcm,
            channels: 2,
            sampleRate: 48000,
            bitDepth: 16
        )

        print("🎵 Starting audio playback...")
        try await audioPlayer.start(format: format, codecHeader: Data?.none)

        // Feed audio in chunks using new playPCM API
        let chunkSize = 4096 // bytes
        var offset = 0
        var chunkIndex = 0

        while offset < audioData.count {
            let remainingBytes = audioData.count - offset
            let bytesToRead = min(chunkSize, remainingBytes)
            let chunk = audioData.subdata(in: offset ..< (offset + bytesToRead))

            // Use new direct PCM playback method
            try await audioPlayer.playPCM(chunk)
            chunkIndex += 1

            if chunkIndex % 10 == 0 {
                print("  Playing chunk \(chunkIndex) (\(offset) / \(audioData.count) bytes)")
            }

            offset += bytesToRead

            // Small delay to avoid overwhelming the buffer
            try await Task.sleep(for: .milliseconds(10))
        }

        print("✅ All audio enqueued, waiting for playback to finish...")

        // Wait for audio to finish playing (3 seconds + buffer)
        try await Task.sleep(for: .seconds(4))

        await audioPlayer.stop()
        print("✅ Playback complete!")
    }
}
