// ABOUTME: mDNS/Bonjour discovery for finding Music Assistant servers on the local network
// ABOUTME: Uses Network framework NWBrowser to discover _music-assistant._tcp services

import Foundation
import Network

/// Discovers Music Assistant servers on the local network via mDNS
public actor ServerDiscovery {
    private var browser: NWBrowser?
    private var discoveries: [String: DiscoveredServer] = [:]
    private var updateContinuation: AsyncStream<[DiscoveredServer]>.Continuation?

    /// Stream of discovered servers (updates whenever servers appear/disappear)
    public let servers: AsyncStream<[DiscoveredServer]>

    public init() {
        var continuation: AsyncStream<[DiscoveredServer]>.Continuation?
        servers = AsyncStream { continuation = $0 }
        updateContinuation = continuation
    }

    /// Start discovering servers
    public func startDiscovery() {
        // Don't restart if already running
        guard browser == nil else { return }

        // Create browser for _music-assistant._tcp service
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_music-assistant._tcp", domain: nil),
            using: parameters
        )
        self.browser = browser

        // Handle state changes
        browser.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleStateChange(state) }
        }

        // Handle browse results
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { await self?.handleBrowseResults(results, changes: changes) }
        }

        // Start browsing
        browser.start(queue: .global(qos: .userInitiated))
    }

    /// Stop discovering servers
    public func stopDiscovery() {
        browser?.cancel()
        browser = nil
        discoveries.removeAll()
        updateContinuation?.yield([])
    }

    private func handleStateChange(_ state: NWBrowser.State) {
        switch state {
        case .setup:
            break
        case .ready:
            break
        case let .failed(error):
            // print("Discovery failed: \(error)")
            stopDiscovery()
        case .cancelled:
            break
        case .waiting:
            break
        @unknown default:
            break
        }
    }

    private func handleBrowseResults(_: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case let .added(result):
                resolveAndAdd(result)

            case let .removed(result):
                removeServer(for: result)

            case .changed(old: _, new: let result, flags: _):
                // Re-resolve on changes
                resolveAndAdd(result)

            case .identical:
                break

            @unknown default:
                break
            }
        }
    }

    private func resolveAndAdd(_ result: NWBrowser.Result) {
        guard case let .service(name, type, domain, interface) = result.endpoint else {
            return
        }

        // Create connection to resolve endpoint
        let descriptor = NWEndpoint.service(name: name, type: type, domain: domain, interface: interface)
        let connection = NWConnection(to: descriptor, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                Task {
                    await self?.extractServerInfo(from: connection, result: result, name: name)
                }
            }
            connection.cancel()
        }

        connection.start(queue: .global(qos: .userInitiated))
    }

    private func extractServerInfo(from connection: NWConnection, result: NWBrowser.Result, name: String) {
        guard case .service = result.endpoint else { return }

        // Extract hostname and port from connection
        var hostname = "localhost"
        var port = 8095 // Default Music Assistant HTTP port

        if case let .hostPort(host, portValue) = connection.currentPath?.remoteEndpoint {
            switch host {
            case let .name(hostName, _):
                hostname = hostName
            case let .ipv4(address):
                hostname = address.debugDescription
            case let .ipv6(address):
                hostname = address.debugDescription
            @unknown default:
                break
            }
            port = Int(portValue.rawValue)
        }

        // Extract TXT record metadata if available
        var metadata: [String: String] = [:]
        var path = "" // Music Assistant uses root path

        if case let .bonjour(txtRecord) = result.metadata {
            // TXT record dictionary is [String: String] in newer APIs
            metadata = txtRecord.dictionary
            // Check for custom path in TXT record
            if let customPath = metadata["path"] {
                path = customPath
            }
        }

        // Create discovered server URL (HTTP endpoint for Music Assistant)
        guard let url = URL(string: "http://\(hostname):\(port)\(path)") else { return }
        let server = DiscoveredServer(
            id: "\(hostname):\(port)",
            name: name,
            url: url,
            hostname: hostname,
            port: port,
            metadata: metadata
        )

        // Add to discoveries
        discoveries[server.id] = server
        updateContinuation?.yield(Array(discoveries.values))
    }

    private func removeServer(for result: NWBrowser.Result) {
        guard case let .service(name, _, _, _) = result.endpoint else { return }

        // Remove all servers matching this service name
        let removed = discoveries.filter { $0.value.name == name }
        for (id, _) in removed {
            discoveries.removeValue(forKey: id)
        }

        updateContinuation?.yield(Array(discoveries.values))
    }

    deinit {
        browser?.cancel()
        updateContinuation?.finish()
    }
}
