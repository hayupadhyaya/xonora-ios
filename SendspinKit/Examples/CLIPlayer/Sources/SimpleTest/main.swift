// ABOUTME: Simple non-interactive test client for SendspinKit
// ABOUTME: Connects and runs for a specified duration without requiring user input

import Foundation
import SendspinKit

@main
struct SimpleTest {
    static func main() async {
        print("🎵 Simple SendspinKit Test")
        print("━━━━━━━━━━━━━━━━━━━━━━━━")

        let args = CommandLine.arguments
        let serverURL = args.count > 1 ? args[1] : "ws://localhost:8927/sendspin"
        let duration = args.count > 2 ? Int(args[2]) ?? 30 : 30

        guard let url = URL(string: serverURL) else {
            print("❌ Invalid URL: \(serverURL)")
            exit(1)
        }

        print("Connecting to: \(serverURL)")
        print("Duration: \(duration) seconds")
        print("")

        // Create player configuration (PCM only)
        let config = PlayerConfiguration(
            bufferCapacity: 2_097_152,
            supportedFormats: [
                AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 48000, bitDepth: 16)
            ]
        )

        // Create client
        let client = SendspinClient(
            clientId: UUID().uuidString,
            name: "Simple Test Client",
            roles: [.player, .metadata],  // Added .metadata role to test metadata delivery
            playerConfig: config
        )

        // Monitor events in background
        Task {
            for await event in client.events {
                switch event {
                case let .serverConnected(info):
                    print("🔗 Connected to: \(info.name) (v\(info.version))")
                case let .streamStarted(format):
                    let formatStr = "\(format.codec.rawValue) \(format.sampleRate)Hz \(format.channels)ch \(format.bitDepth)bit"
                    print("▶️  Stream: \(formatStr)")
                case .streamEnded:
                    print("⏹  Stream ended")
                case let .groupUpdated(info):
                    if let state = info.playbackState {
                        print("📻 Group \(info.groupName): \(state)")
                    }
                case let .metadataReceived(metadata):
                    print("🎵 Metadata:")
                    print("   Title:  \(metadata.title ?? "none")")
                    print("   Artist: \(metadata.artist ?? "none")")
                    print("   Album:  \(metadata.album ?? "none")")
                case let .error(message):
                    print("⚠️  Error: \(message)")
                default:
                    break
                }
            }
        }

        // Connect
        do {
            try await client.connect(to: url)
            print("✅ Connected!")
            print("")

            // Run for specified duration
            try await Task.sleep(for: .seconds(duration))

            print("")
            print("⏱️  Test duration complete")
            await client.disconnect()
            print("👋 Disconnected")

        } catch {
            print("❌ Error: \(error)")
            exit(1)
        }
    }
}
