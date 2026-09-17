import Foundation
@testable import SendspinKit
import Testing

@Suite("Message Encoding Tests")
struct MessageEncodingTests {
    @Test("ClientHello encodes with versioned roles")
    func clientHelloEncoding() throws {
        let payload = ClientHelloPayload(
            clientId: "test-client",
            name: "Test Client",
            deviceInfo: nil,
            version: 1,
            supportedRoles: [.playerV1],
            playerV1Support: PlayerSupport(
                supportedFormats: [
                    AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 48000, bitDepth: 16)
                ],
                bufferCapacity: 1024,
                supportedCommands: [.volume, .mute]
            ),
            metadataV1Support: nil,
            artworkV1Support: nil,
            visualizerV1Support: nil
        )

        let message = ClientHelloMessage(payload: payload)

        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        let json = try #require(String(data: data, encoding: .utf8))

        // Swift escapes forward slashes in JSON, so we check for both possibilities
        #expect(json.contains("\"type\":\"client/hello\"") || json.contains("\"type\":\"client\\/hello\""))
        #expect(json.contains("\"client_id\":\"test-client\""))
        #expect(json.contains("\"supported_roles\":[\"player@v1\"]"))
        #expect(json.contains("\"player@v1_support\""))
    }

    @Test("ServerHello decodes with active_roles and connection_reason")
    func serverHelloDecoding() throws {
        let json = """
        {
            "type": "server/hello",
            "payload": {
                "server_id": "test-server",
                "name": "Test Server",
                "version": 1,
                "active_roles": ["player@v1", "metadata@v1"],
                "connection_reason": "playback"
            }
        }
        """

        let decoder = JSONDecoder()
        let data = try #require(json.data(using: .utf8))
        let message = try decoder.decode(ServerHelloMessage.self, from: data)

        #expect(message.type == "server/hello")
        #expect(message.payload.serverId == "test-server")
        #expect(message.payload.name == "Test Server")
        #expect(message.payload.version == 1)
        #expect(message.payload.activeRoles.count == 2)
        #expect(message.payload.activeRoles.contains(.playerV1))
        #expect(message.payload.activeRoles.contains(.metadataV1))
        #expect(message.payload.connectionReason == .playback)
    }

    @Test("ClientState encodes with player state object")
    func clientStateEncoding() throws {
        let playerState = PlayerStateObject(state: .synchronized, volume: 80, muted: false)
        let payload = ClientStatePayload(player: playerState)
        let message = ClientStateMessage(payload: payload)

        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"type\":\"client/state\"") || json.contains("\"type\":\"client\\/state\""))
        #expect(json.contains("\"state\":\"synchronized\""))
        #expect(json.contains("\"volume\":80"))
        #expect(json.contains("\"muted\":false"))
    }
}
