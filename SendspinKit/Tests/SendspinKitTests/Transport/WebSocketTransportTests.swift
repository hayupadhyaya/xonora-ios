import Foundation
@testable import SendspinKit
import Testing

@Suite("WebSocket Transport Tests")
struct WebSocketTransportTests {
    @Test("Creates AsyncStreams for messages")
    func streamCreation() async {
        let url = URL(string: "ws://localhost:8927/sendspin")!
        let transport = WebSocketTransport(url: url)

        // Verify streams exist
        _ = await transport.textMessages.makeAsyncIterator()
        _ = await transport.binaryMessages.makeAsyncIterator()

        // Streams should be ready but have no data yet
        // (This is a basic structure test - full WebSocket testing requires mock server)
    }
}
