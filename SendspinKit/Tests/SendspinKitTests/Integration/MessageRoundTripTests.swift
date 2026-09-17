// ABOUTME: Integration tests for full message encoding/decoding round trips
// ABOUTME: Tests that messages can be encoded to JSON, decoded back, and maintain data integrity

import Foundation
@testable import SendspinKit
import Testing

@Suite("Message Round Trip Integration Tests")
struct MessageRoundTripTests {
    @Test("ClientHello round trip maintains all data")
    func clientHelloRoundTrip() throws {
        // Create complete ClientHello with all fields populated
        let originalPayload = ClientHelloPayload(
            clientId: "test-client-123",
            name: "Test Speaker",
            deviceInfo: DeviceInfo(
                productName: "HomePod",
                manufacturer: "Apple",
                softwareVersion: "17.0"
            ),
            version: 1,
            supportedRoles: [.playerV1, .controllerV1, .metadataV1],
            playerV1Support: PlayerSupport(
                supportedFormats: [
                    AudioFormatSpec(codec: .opus, channels: 2, sampleRate: 48000, bitDepth: 16),
                    AudioFormatSpec(codec: .flac, channels: 2, sampleRate: 44100, bitDepth: 24),
                    AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 48000, bitDepth: 16)
                ],
                bufferCapacity: 1_048_576,
                supportedCommands: [.volume, .mute]
            ),
            metadataV1Support: MetadataSupport(),
            artworkV1Support: nil,
            visualizerV1Support: nil
        )

        let message = ClientHelloMessage(payload: originalPayload)

        // Encode to JSON (using custom CodingKeys, not convertToSnakeCase)
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(message)

        // Decode back
        let decoder = JSONDecoder()
        let decodedMessage = try decoder.decode(ClientHelloMessage.self, from: jsonData)

        // Verify all fields match
        #expect(decodedMessage.type == "client/hello")
        #expect(decodedMessage.payload.clientId == "test-client-123")
        #expect(decodedMessage.payload.name == "Test Speaker")
        #expect(decodedMessage.payload.version == 1)
        #expect(decodedMessage.payload.supportedRoles == [.playerV1, .controllerV1, .metadataV1])

        // Verify device info
        let deviceInfo = try #require(decodedMessage.payload.deviceInfo)
        #expect(deviceInfo.productName == "HomePod")
        #expect(deviceInfo.manufacturer == "Apple")
        #expect(deviceInfo.softwareVersion == "17.0")

        // Verify player support
        let playerSupport = try #require(decodedMessage.payload.playerV1Support)
        #expect(playerSupport.bufferCapacity == 1_048_576)
        #expect(playerSupport.supportedCommands == [.volume, .mute])
        #expect(playerSupport.supportedFormats.count == 3)

        // Verify first format
        let firstFormat = playerSupport.supportedFormats[0]
        #expect(firstFormat.codec == .opus)
        #expect(firstFormat.channels == 2)
        #expect(firstFormat.sampleRate == 48000)
        #expect(firstFormat.bitDepth == 16)
    }

    @Test("StreamStart round trip with codec header")
    func streamStartRoundTrip() throws {
        let codecHeaderData = Data([0x66, 0x4C, 0x61, 0x43]) // "fLaC" FLAC signature
        let codecHeaderB64 = codecHeaderData.base64EncodedString()

        let originalPayload = StreamStartPayload(
            player: StreamStartPlayer(
                codec: "flac",
                sampleRate: 44100,
                channels: 2,
                bitDepth: 24,
                codecHeader: codecHeaderB64
            ),
            artwork: nil,
            visualizer: nil
        )

        let message = StreamStartMessage(payload: originalPayload)

        // Encode (now uses custom CodingKeys, no strategy needed)
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(message)

        // Decode
        let decoder = JSONDecoder()
        let decodedMessage = try decoder.decode(StreamStartMessage.self, from: jsonData)

        // Verify
        let player = try #require(decodedMessage.payload.player)
        #expect(player.codec == "flac")
        #expect(player.sampleRate == 44100)
        #expect(player.channels == 2)
        #expect(player.bitDepth == 24)
        #expect(player.codecHeader == codecHeaderB64)

        // Verify codec header can be decoded back
        let decodedHeader = Data(base64Encoded: player.codecHeader!)
        #expect(decodedHeader == codecHeaderData)
    }

    // Helper function to verify ClientHello message encoding/decoding
    private func verifyClientHello(encoder: JSONEncoder, decoder: JSONDecoder) throws {
        let helloMessage = ClientHelloMessage(
            payload: ClientHelloPayload(
                clientId: "client-1",
                name: "Client",
                deviceInfo: nil,
                version: 1,
                supportedRoles: [.playerV1],
                playerV1Support: PlayerSupport(
                    supportedFormats: [
                        AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 48000, bitDepth: 16)
                    ],
                    bufferCapacity: 512_000,
                    supportedCommands: []
                ),
                metadataV1Support: nil,
                artworkV1Support: nil,
                visualizerV1Support: nil
            )
        )

        let helloData = try encoder.encode(helloMessage)
        let helloDecoded = try decoder.decode(ClientHelloMessage.self, from: helloData)
        #expect(helloDecoded.payload.clientId == "client-1")
    }

    // Helper function to verify ServerHello message decoding
    private func verifyServerHello(decoder: JSONDecoder) throws {
        let serverHelloData = Data("""
        {
            "type": "server/hello",
            "payload": {
                "server_id": "server-1",
                "name": "Music Server",
                "version": 1,
                "active_roles": ["player@v1"],
                "connection_reason": "discovery"
            }
        }
        """.utf8)

        let serverHello = try decoder.decode(ServerHelloMessage.self, from: serverHelloData)
        #expect(serverHello.payload.serverId == "server-1")
    }

    // Helper function to verify ClientTime message encoding/decoding
    private func verifyClientTime(encoder: JSONEncoder, decoder: JSONDecoder) throws {
        let timeMessage = ClientTimeMessage(
            payload: ClientTimePayload(clientTransmitted: 123_456_789)
        )

        let timeData = try encoder.encode(timeMessage)
        let timeDecoded = try decoder.decode(ClientTimeMessage.self, from: timeData)
        #expect(timeDecoded.payload.clientTransmitted == 123_456_789)
    }

    // Helper function to verify StreamStart message decoding
    private func verifyStreamStart(decoder: JSONDecoder) throws {
        let streamData = Data("""
        {
            "type": "stream/start",
            "payload": {
                "player": {
                    "codec": "opus",
                    "sample_rate": 48000,
                    "channels": 2,
                    "bit_depth": 16
                }
            }
        }
        """.utf8)

        let streamStart = try decoder.decode(StreamStartMessage.self, from: streamData)
        #expect(streamStart.payload.player?.codec == "opus")
    }

    @Test("Multiple message types in sequence")
    func messageSequence() throws {
        // ClientHello now uses custom CodingKeys, no strategy needed
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Verify each message type in sequence
        try verifyClientHello(encoder: encoder, decoder: decoder)
        try verifyServerHello(decoder: decoder)
        try verifyClientTime(encoder: encoder, decoder: decoder)
        try verifyStreamStart(decoder: decoder)

        // All messages decoded successfully in sequence
    }

    @Test("GroupUpdate with null fields")
    func groupUpdateWithNulls() throws {
        // Test partial updates with null fields (common in delta updates)
        let jsonWithNulls = Data("""
        {
            "type": "group/update",
            "payload": {
                "playback_state": "playing",
                "group_id": "group-123",
                "group_name": null
            }
        }
        """.utf8)

        // Now uses custom CodingKeys, no strategy needed
        let decoder = JSONDecoder()

        let message = try decoder.decode(GroupUpdateMessage.self, from: jsonWithNulls)

        #expect(message.type == "group/update")
        #expect(message.payload.playbackState == "playing")
        #expect(message.payload.groupId == "group-123")
        #expect(message.payload.groupName == nil)
    }
}
