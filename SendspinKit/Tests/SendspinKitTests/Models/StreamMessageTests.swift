import Foundation
@testable import SendspinKit
import Testing

@Suite("Stream Message Tests")
struct StreamMessageTests {
    @Test("Decode stream/start message")
    func streamStartDecoding() throws {
        let json = """
        {
            "type": "stream/start",
            "payload": {
                "player": {
                    "codec": "opus",
                    "sample_rate": 48000,
                    "channels": 2,
                    "bit_depth": 16,
                    "codec_header": "AQIDBA=="
                }
            }
        }
        """

        // Now uses custom CodingKeys, no strategy needed
        let decoder = JSONDecoder()
        let data = try #require(json.data(using: .utf8))
        let message = try decoder.decode(StreamStartMessage.self, from: data)

        #expect(message.type == "stream/start")
        #expect(message.payload.player?.codec == "opus")
        #expect(message.payload.player?.sampleRate == 48000)
        #expect(message.payload.player?.channels == 2)
        #expect(message.payload.player?.bitDepth == 16)
        #expect(message.payload.player?.codecHeader == "AQIDBA==")
    }
}
