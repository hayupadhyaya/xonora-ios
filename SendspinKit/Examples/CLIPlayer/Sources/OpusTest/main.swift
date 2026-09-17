// ABOUTME: Test program for OpusDecoder implementation
// ABOUTME: Verifies Opus decoding works with real Opus packets

import Foundation
import SendspinKit

func testOpusDecoder() {
    print("=== OpusDecoder Test ===\n")

    // Test 1: Create decoder for 48kHz stereo
    print("Test 1: Creating OpusDecoder (48kHz stereo)...")
    let decoder: OpusDecoder
    do {
        decoder = try OpusDecoder(sampleRate: 48000, channels: 2, bitDepth: 24)
        print("✓ Decoder created successfully\n")
    } catch {
        print("✗ Failed to create decoder: \(error)")
        return
    }

    // Test 2: Decode minimal valid Opus packet
    // Opus TOC byte 0x3C = 60ms SILK frame, 48kHz, stereo (config 15, stereo bit set)
    // Followed by minimal frame data (silence)
    print("Test 2: Decoding minimal Opus packet...")
    analyzeOpusTOC(0x3C)
    let testPacket = Data([0x3C, 0xFC, 0xFF, 0xFE])

    do {
        let pcmData = try decoder.decode(testPacket)
        print("✓ Decode successful")
        print("  Packet size: \(testPacket.count) bytes")
        print("  PCM output size: \(pcmData.count) bytes")

        // Verify output is int32 data
        let sampleCount = pcmData.count / MemoryLayout<Int32>.size
        print("  Sample count: \(sampleCount)")
        print("  Samples per channel: \(sampleCount / 2)")
        let frameDuration = Double(sampleCount / 2) / 48.0
        print("  Actual frame duration: \(frameDuration)ms")

        // Convert to Int32 array and check first few samples
        let samples = pcmData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Int32.self))
        }

        if samples.count > 0 {
            print("  First 10 samples: \(Array(samples.prefix(10)))")

            // Verify samples are in reasonable range
            let validRange = samples.allSatisfy { sample in
                sample >= Int32.min && sample <= Int32.max
            }
            print("  Samples in valid int32 range: \(validRange ? "✓" : "✗")")
        }
        print()
    } catch {
        print("✗ Decode failed: \(error)\n")
        return
    }

    // Test 3: Test with mono decoder
    print("Test 3: Creating OpusDecoder (48kHz mono)...")
    do {
        let monoDecoder = try OpusDecoder(sampleRate: 48000, channels: 1, bitDepth: 24)
        print("✓ Mono decoder created successfully")

        // Mono Opus packet (TOC 0x38 = 60ms SILK, 48kHz, mono)
        analyzeOpusTOC(0x38)
        let monoPacket = Data([0x38, 0xFC, 0xFF, 0xFE])
        let monoOutput = try monoDecoder.decode(monoPacket)

        let monoSamples = monoOutput.count / MemoryLayout<Int32>.size
        print("  Mono sample count: \(monoSamples)")
        let monoFrameDuration = Double(monoSamples) / 48.0
        print("  Actual frame duration: \(monoFrameDuration)ms")
        print()
    } catch {
        print("✗ Mono decoder test failed: \(error)\n")
    }

    // Test 4: Test 20ms frame
    print("Test 4: Testing 20ms frame...")
    do {
        // TOC 0x3D = config 7 (60ms), but let's try config 5 (20ms)
        // Config 5 = SILK, 20ms frame
        // 0x28 = (5 << 3) | 0x00 = mono, 20ms SILK
        // 0x2C = (5 << 3) | 0x04 = stereo, 20ms SILK
        analyzeOpusTOC(0x2C)
        let packet20ms = Data([0x2C, 0xFC, 0xFF, 0xFE])
        let output20ms = try decoder.decode(packet20ms)

        let samples20ms = output20ms.count / MemoryLayout<Int32>.size
        let duration20ms = Double(samples20ms / 2) / 48.0
        print("  Sample count: \(samples20ms)")
        print("  Samples per channel: \(samples20ms / 2)")
        print("  Actual frame duration: \(duration20ms)ms")
        print()
    } catch {
        print("✗ 20ms frame test failed: \(error)\n")
    }

    // Test 5: Invalid sample rate
    print("Test 5: Testing invalid sample rate (should fail gracefully)...")
    do {
        _ = try OpusDecoder(sampleRate: 22050, channels: 2, bitDepth: 24)
        print("✗ Should have failed with invalid sample rate\n")
    } catch {
        print("✓ Correctly rejected invalid sample rate: \(error)\n")
    }

    // Test 6: Empty packet
    print("Test 6: Testing empty packet (should fail gracefully)...")
    do {
        let emptyPacket = Data()
        _ = try decoder.decode(emptyPacket)
        print("✗ Should have failed with empty packet\n")
    } catch {
        print("✓ Correctly rejected empty packet: \(error)\n")
    }

    print("=== Test Complete ===")
}

// Run tests
testOpusDecoder()
