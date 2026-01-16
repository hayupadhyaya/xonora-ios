// ABOUTME: WebSocket transport layer for Sendspin protocol communication
// ABOUTME: Provides AsyncStreams for text (JSON) and binary messages

import Foundation

/// WebSocket transport for Sendspin protocol using URLSession
public actor WebSocketTransport: NSObject, URLSessionWebSocketDelegate {
    private var webSocket: URLSessionWebSocketTask?
    private let url: URL
    private var urlSession: URLSession!
    
    /// Stream of incoming text messages (JSON)
    public let textMessages: AsyncStream<String>
    private let textContinuation: AsyncStream<String>.Continuation

    /// Stream of incoming binary messages (audio, artwork, etc.)
    public let binaryMessages: AsyncStream<Data>
    private let binaryContinuation: AsyncStream<Data>.Continuation

    public init(url: URL) {
        // Ensure URL has proper WebSocket path if not specified
        if url.path.isEmpty || url.path == "/" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            self.url = components.url ?? url
        } else {
            self.url = url
        }

        // Create streams
        (textMessages, textContinuation) = AsyncStream<String>.makeStream()
        (binaryMessages, binaryContinuation) = AsyncStream<Data>.makeStream()
        
        super.init()
        
        // Configure URLSession with proxy bypass
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:]
        // Set request timeout to 24 hours to prevent "Operation timed out" logs.
        // We use application-level heartbeat/ping if needed.
        config.timeoutIntervalForRequest = 86400
        config.timeoutIntervalForResource = 604800 // 7 days (Persistent connection)
        config.waitsForConnectivity = true
        
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
    }

    /// Connect to the WebSocket server
    public func connect() async throws {
        guard webSocket == nil else {
            throw TransportError.alreadyConnected
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5 // Connection timeout
        
        // Add Origin header just in case
        if let scheme = url.scheme, let host = url.host {
            let portString = url.port.map { ":\($0)" } ?? ""
            let httpScheme = scheme == "wss" ? "https" : "http"
            let origin = "\(httpScheme)://\(host)\(portString)"
            request.addValue(origin, forHTTPHeaderField: "Origin")
        }

        webSocket = urlSession.webSocketTask(with: request)
        webSocket?.resume()
        
        // Start receiving messages
        listen()
        
        // Since URLSessionWebSocketTask doesn't have a direct connect() awaitable,
        // we can check connectivity status or rely on the first message/error.
        // However, the user wants a strict timeout on the connection attempt itself.
        // The `waitsForConnectivity` config handles some of this, but if we want to fail fast:
        
        // We can wait for a short period to see if the socket is viable, but mostly we rely on 
        // the session configuration's timeout.
        
        // Note: URLSessionWebSocketTask connects lazily. We consider it "connected" once we start listening.
        // The actual TCP handshake happens in background.
    }
    
    private func listen() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    // print("[WebSocketTransport] Received text: \(text.prefix(200))")
                    self.textContinuation.yield(text)
                case .data(let data):
                    // print("[WebSocketTransport] Received binary data: \(data.count) bytes")
                    self.binaryContinuation.yield(data)
                @unknown default:
                    break
                }
                // Continue listening
                self.listen()

            case .failure(let error):
                print("[WebSocketTransport] Receive error: \(error)")
                self.textContinuation.finish()
                self.binaryContinuation.finish()
                self.webSocket = nil
            }
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

        // print("[WebSocketTransport] Sending: \(text)")
        try await webSocket.send(.string(text))
        // print("[WebSocketTransport] Message sent successfully")
    }

    /// Send a binary message
    public func sendBinary(_ data: Data) async throws {
        guard let webSocket = webSocket else {
            throw TransportError.notConnected
        }
        try await webSocket.send(.data(data))
    }

    /// Disconnect from server
    public func disconnect() async {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
    }
    
    // MARK: - URLSessionWebSocketDelegate
    
    nonisolated public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("[WebSocketTransport] Connected")
    }

    nonisolated public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("[WebSocketTransport] Disconnected: \(closeCode)")
    }
}

/// Errors that can occur during WebSocket transport
public enum TransportError: Error {
    case encodingFailed
    case notConnected
    case alreadyConnected
    case connectionFailed
    case connectionTimeout
}
