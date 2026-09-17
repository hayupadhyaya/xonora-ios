// ABOUTME: Defines versioned roles for Sendspin protocol negotiation
// ABOUTME: Roles use format "role@version" (e.g., "player@v1") for capability negotiation

/// Versioned role identifier for Sendspin protocol
/// Format: "role@version" (e.g., "player@v1", "metadata@v1")
public struct VersionedRole: Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    /// Role name (e.g., "player", "metadata", "artwork")
    public let role: String
    /// Version string (e.g., "v1", "v2")
    public let version: String

    /// Full role identifier (e.g., "player@v1")
    public var identifier: String {
        "\(role)@\(version)"
    }

    public init(role: String, version: String) {
        self.role = role
        self.version = version
    }

    public init(stringLiteral value: String) {
        let components = value.split(separator: "@", maxSplits: 1)
        if components.count == 2 {
            self.role = String(components[0])
            self.version = String(components[1])
        } else {
            self.role = value
            self.version = "v1"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self.init(stringLiteral: value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(identifier)
    }

    // Common role constants
    public static let playerV1: VersionedRole = "player@v1"
    public static let controllerV1: VersionedRole = "controller@v1"
    public static let metadataV1: VersionedRole = "metadata@v1"
    public static let artworkV1: VersionedRole = "artwork@v1"
    public static let visualizerV1: VersionedRole = "visualizer@v1"
}

/// Legacy ClientRole enum for backward compatibility
@available(*, deprecated, renamed: "VersionedRole", message: "Use VersionedRole with version strings like 'player@v1'")
public enum ClientRole: String, Codable, Sendable, Hashable {
    case player
    case controller
    case metadata
    case artwork
    case visualizer

    /// Convert to versioned role (defaults to v1)
    public var versioned: VersionedRole {
        VersionedRole(role: rawValue, version: "v1")
    }
}
