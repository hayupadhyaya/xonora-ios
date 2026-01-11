// ABOUTME: WebSocket transport layer for Sendspin protocol communication
// ABOUTME: Provides AsyncStreams for text (JSON) and binary messages

import Foundation
import Starscream

// Delegate to handle WebSocket events and receiving
private final class StarscreamDelegate: WebSocketDelegate, @unchecked Sendable {
    let textContinuation: AsyncStream<String>.Continuation
    let binaryContinuation: AsyncStream<Data>.Continuation
    var connectionContinuation: CheckedContinuation<Void, Error>?

    init(textContinuation: AsyncStream<String>.Continuation, binaryContinuation: AsyncStream<Data>.Continuation) {
        self.textContinuation = textContinuation
        self.binaryContinuation = binaryContinuation
        // Logging disabled for TUI mode
    }

    func didReceive(event: WebSocketEvent, client _: any WebSocketClient) {
        // Verbose logging disabled for production - uncomment for debugging
        // print("[STARSCREAM] didReceive called with event: \(event)")
        switch event {
        case .connected:
            // Logging disabled for TUI mode
            connectionContinuation?.resume()
            connectionContinuation = nil

        case .disconnected:
            // Logging disabled for TUI mode
            // If we were waiting for connection, fail it
            if let continuation = connectionContinuation {
                continuation.resume(throwing: TransportError.connectionFailed)
                connectionContinuation = nil
            }
            textContinuation.finish()
            binaryContinuation.finish()

        case let .text(string):
            // High-frequency event - logging disabled
            textContinuation.yield(string)

        case let .binary(data):
            // High-frequency event - logging disabled
            binaryContinuation.yield(data)

        case .ping:
            // High-frequency event - logging disabled
            break

        case .pong:
            // High-frequency event - logging disabled
            break

        case .viabilityChanged:
            // Logging disabled for TUI mode
            break

        case .reconnectSuggested:
            // Logging disabled for TUI mode
            break

        case .cancelled:
            // Logging disabled for TUI mode
            if let continuation = connectionContinuation {
                continuation.resume(throwing: TransportError.connectionFailed)
                connectionContinuation = nil
            }
            textContinuation.finish()
            binaryContinuation.finish()

        case .error:
            // Logging disabled for TUI mode
            if let continuation = connectionContinuation {
                continuation.resume(throwing: TransportError.connectionFailed)
                connectionContinuation = nil
            }
            textContinuation.finish()
            binaryContinuation.finish()

        case .peerClosed:
            // Logging disabled for TUI mode
            if let continuation = connectionContinuation {
                continuation.resume(throwing: TransportError.connectionFailed)
                connectionContinuation = nil
            }
            textContinuation.finish()
            binaryContinuation.finish()
        }
    }
}

/// WebSocket transport for Sendspin protocol
public actor WebSocketTransport {
    private nonisolated let delegate: StarscreamDelegate
    private var webSocket: WebSocket?
    private let url: URL

    /// Stream of incoming text messages (JSON)
    public nonisolated let textMessages: AsyncStream<String>

    /// Stream of incoming binary messages (audio, artwork, etc.)
    public nonisolated let binaryMessages: AsyncStream<Data>

    public init(url: URL) {
        // Ensure URL has proper WebSocket path if not specified
        if url.path.isEmpty || url.path == "/" {
            // Append recommended Sendspin endpoint path
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            self.url = components.url ?? url
        } else {
            self.url = url
        }

        // Create streams and pass continuations to delegate
        let (textStream, textCont) = AsyncStream<String>.makeStream()
        let (binaryStream, binaryCont) = AsyncStream<Data>.makeStream()

        textMessages = textStream
        binaryMessages = binaryStream
        delegate = StarscreamDelegate(textContinuation: textCont, binaryContinuation: binaryCont)
    }

    /// Connect to the WebSocket server
    /// - Throws: TransportError if already connected or connection fails
    public func connect() async throws {
        // Prevent multiple connections
        guard webSocket == nil else {
            throw TransportError.alreadyConnected
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30  // Increased timeout for better reliability

        // Disable HTTP/3 (QUIC) to avoid parsing errors
        #if os(iOS) || os(macOS)
        if #available(iOS 15.0, macOS 12.0, *) {
            request.assumesHTTP3Capable = false
        }
        #endif

        // Create socket with delegate callbacks on background queue
        // Note: Cannot use DispatchQueue.main in CLI apps without RunLoop
        let socket = WebSocket(request: request)
        socket.callbackQueue = DispatchQueue(label: "com.sendspin.websocket", qos: .userInitiated)
        socket.delegate = delegate

        // Logging disabled for TUI mode
        webSocket = socket

        // Wait for connection to complete
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delegate.connectionContinuation = continuation
            socket.connect()
        }
    }

    /// Check if currently connected
    public var isConnected: Bool {
        return webSocket != nil
    }

    /// Send a text message (JSON)
    public func send<T: SendspinMessage>(_ message: T) async throws {
        guard let webSocket = webSocket else {
            throw TransportError.notConnected
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw TransportError.encodingFailed
        }
        // Logging disabled for TUI mode
        webSocket.write(string: text)
    }

    /// Send a binary message
    public func sendBinary(_ data: Data) async throws {
        guard let webSocket = webSocket else {
            throw TransportError.notConnected
        }
        webSocket.write(data: data)
    }

    /// Disconnect from server
    public func disconnect() async {
        webSocket?.disconnect()
        webSocket = nil
    }
}

/// Errors that can occur during WebSocket transport
public enum TransportError: Error {
    /// Failed to encode message to UTF-8 string
    case encodingFailed

    /// WebSocket is not connected - call connect() first
    case notConnected

    /// Already connected - call disconnect() before reconnecting
    case alreadyConnected

    /// Connection failed during handshake
    case connectionFailed
}
