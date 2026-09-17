// ABOUTME: Represents a discovered Music Assistant server from mDNS
// ABOUTME: Contains server name, URL, and metadata from TXT records

import Foundation

/// A Music Assistant server discovered via mDNS
public struct DiscoveredServer: Sendable, Identifiable {
    /// Unique identifier for this server instance
    public let id: String

    /// Human-readable server name
    public let name: String

    /// HTTP URL to connect to this server
    public let url: URL

    /// Server hostname
    public let hostname: String

    /// Server port
    public let port: Int

    /// Additional metadata from TXT records
    public let metadata: [String: String]

    public init(
        id: String,
        name: String,
        url: URL,
        hostname: String,
        port: Int,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.hostname = hostname
        self.port = port
        self.metadata = metadata
    }
}
