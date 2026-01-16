// ABOUTME: Core protocol message types for Sendspin client-server communication
// ABOUTME: All messages follow the pattern: { "type": "...", "payload": {...} }

import Foundation
#if canImport(UIKit)
    import UIKit
#endif

/// Base protocol for all Sendspin messages
public protocol SendspinMessage: Codable, Sendable {
    var type: String { get }
}

// MARK: - Auth Messages

/// Client auth message
public struct AuthMessage: SendspinMessage {
    public let type = "client/auth"
    public let payload: AuthPayload

    public init(payload: AuthPayload) {
        self.payload = payload
    }

    public init(token: String, clientId: String) {
        self.payload = AuthPayload(token: token, clientId: clientId)
    }
}

public struct AuthPayload: Codable, Sendable {
    public let token: String
    public let clientId: String

    enum CodingKeys: String, CodingKey {
        case token
        case clientId = "client_id"
    }

    public init(token: String, clientId: String) {
        self.token = token
        self.clientId = clientId
    }
}

/// Server auth OK message
public struct AuthOKMessage: SendspinMessage {
    public let type = "server/auth_ok"

    public init() {}
}

// MARK: - Client Messages

/// Client hello message sent after WebSocket connection
public struct ClientHelloMessage: SendspinMessage {
    public let type = "client/hello"
    public let payload: ClientHelloPayload

    public init(payload: ClientHelloPayload) {
        self.payload = payload
    }
}

public struct ClientHelloPayload: Codable, Sendable {
    public let clientId: String
    public let name: String
    public let deviceInfo: DeviceInfo?
    public let version: Int
    public let supportedRoles: [VersionedRole]
    public let playerV1Support: PlayerSupport?
    public let metadataV1Support: MetadataSupport?
    public let artworkV1Support: ArtworkSupport?
    public let visualizerV1Support: VisualizerSupport?

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case name
        case deviceInfo = "device_info"
        case version
        case supportedRoles = "supported_roles"
        case playerV1Support = "player_support"
        case metadataV1Support = "metadata_support"
        case artworkV1Support = "artwork_support"
        case visualizerV1Support = "visualizer_support"
    }

    public init(
        clientId: String,
        name: String,
        deviceInfo: DeviceInfo?,
        version: Int,
        supportedRoles: [VersionedRole],
        playerV1Support: PlayerSupport?,
        metadataV1Support: MetadataSupport?,
        artworkV1Support: ArtworkSupport?,
        visualizerV1Support: VisualizerSupport?
    ) {
        self.clientId = clientId
        self.name = name
        self.deviceInfo = deviceInfo
        self.version = version
        self.supportedRoles = supportedRoles
        self.playerV1Support = playerV1Support
        self.metadataV1Support = metadataV1Support
        self.artworkV1Support = artworkV1Support
        self.visualizerV1Support = visualizerV1Support
    }
}

public struct DeviceInfo: Codable, Sendable {
    public let productName: String?
    public let manufacturer: String?
    public let softwareVersion: String?

    public init(productName: String?, manufacturer: String?, softwareVersion: String?) {
        self.productName = productName
        self.manufacturer = manufacturer
        self.softwareVersion = softwareVersion
    }

    public static var current: DeviceInfo {
        #if os(iOS)
            return DeviceInfo(
                productName: UIDevice.current.model,
                manufacturer: "Apple",
                softwareVersion: UIDevice.current.systemVersion
            )
        #elseif os(macOS)
            return DeviceInfo(
                productName: "Mac",
                manufacturer: "Apple",
                softwareVersion: ProcessInfo.processInfo.operatingSystemVersionString
            )
        #else
            return DeviceInfo(productName: nil, manufacturer: "Apple", softwareVersion: nil)
        #endif
    }
}

public enum PlayerCommand: String, Codable, Sendable {
    case volume
    case mute
}

public struct PlayerSupport: Codable, Sendable {
    public let supportedFormats: [AudioFormatSpec]
    public let bufferCapacity: Int
    public let supportedCommands: [PlayerCommand]

    enum CodingKeys: String, CodingKey {
        case supportedFormats = "supported_formats"
        case bufferCapacity = "buffer_capacity"
        case supportedCommands = "supported_commands"
    }

    public init(supportedFormats: [AudioFormatSpec], bufferCapacity: Int, supportedCommands: [PlayerCommand]) {
        self.supportedFormats = supportedFormats
        self.bufferCapacity = bufferCapacity
        self.supportedCommands = supportedCommands
    }
}

public struct MetadataSupport: Codable, Sendable {
    public let supportedPictureFormats: [String]

    enum CodingKeys: String, CodingKey {
        case supportedPictureFormats = "supported_picture_formats"
    }

    public init(supportedPictureFormats: [String] = []) {
        self.supportedPictureFormats = supportedPictureFormats
    }
}

public struct ArtworkSupport: Codable, Sendable {
    // IMPLEMENTATION_NOTE: Implement when artwork role is added

    public init() {}

    // Explicit Codable implementation for empty struct
    public init(from _: Decoder) throws {}
    public func encode(to _: Encoder) throws {}
}

public struct VisualizerSupport: Codable, Sendable {
    // IMPLEMENTATION_NOTE: Implement when visualizer role is added

    public init() {}

    // Explicit Codable implementation for empty struct
    public init(from _: Decoder) throws {}
    public func encode(to _: Encoder) throws {}
}

// MARK: - Server Messages

/// Server hello response
public struct ServerHelloMessage: SendspinMessage {
    public let type = "server/hello"
    public let payload: ServerHelloPayload

    public init(payload: ServerHelloPayload) {
        self.payload = payload
    }
}

/// Connection reason for server/hello
public enum ConnectionReason: String, Codable, Sendable {
    /// Server connected for general availability/discovery
    case discovery
    /// Server connected for active playback
    case playback
}

public struct ServerHelloPayload: Codable, Sendable {
    public let serverId: String
    public let name: String
    public let version: Int
    public let activeRoles: [VersionedRole]
    public let connectionReason: ConnectionReason

    enum CodingKeys: String, CodingKey {
        case serverId = "server_id"
        case name
        case version
        case activeRoles = "active_roles"
        case connectionReason = "connection_reason"
    }

    public init(serverId: String, name: String, version: Int, activeRoles: [VersionedRole], connectionReason: ConnectionReason) {
        self.serverId = serverId
        self.name = name
        self.version = version
        self.activeRoles = activeRoles
        self.connectionReason = connectionReason
    }
}

/// Client time message for clock sync
public struct ClientTimeMessage: SendspinMessage {
    public let type = "client/time"
    public let payload: ClientTimePayload

    public init(payload: ClientTimePayload) {
        self.payload = payload
    }
}

public struct ClientTimePayload: Codable, Sendable {
    public let clientTransmitted: Int64

    enum CodingKeys: String, CodingKey {
        case clientTransmitted = "client_transmitted"
    }

    public init(clientTransmitted: Int64) {
        self.clientTransmitted = clientTransmitted
    }
}

/// Server time response for clock sync
public struct ServerTimeMessage: SendspinMessage {
    public let type = "server/time"
    public let payload: ServerTimePayload

    public init(payload: ServerTimePayload) {
        self.payload = payload
    }
}

public struct ServerTimePayload: Codable, Sendable {
    public let clientTransmitted: Int64
    public let serverReceived: Int64
    public let serverTransmitted: Int64

    enum CodingKeys: String, CodingKey {
        case clientTransmitted = "client_transmitted"
        case serverReceived = "server_received"
        case serverTransmitted = "server_transmitted"
    }

    public init(clientTransmitted: Int64, serverReceived: Int64, serverTransmitted: Int64) {
        self.clientTransmitted = clientTransmitted
        self.serverReceived = serverReceived
        self.serverTransmitted = serverTransmitted
    }
}

// MARK: - State Messages

/// Player state values per Sendspin protocol
public enum PlayerStateValue: String, Codable, Sendable {
    /// Normal operation, player maintains clock sync
    case synchronized
    /// Unable to keep up, issues keeping the clock in sync
    case error
}

/// Client state message (sent by clients to report current state)
public struct ClientStateMessage: SendspinMessage {
    public let type = "client/state"
    public let payload: ClientStatePayload

    public init(payload: ClientStatePayload) {
        self.payload = payload
    }
}

/// Client state payload containing role-specific state objects
public struct ClientStatePayload: Codable, Sendable {
    public let player: PlayerStateObject?

    public init(player: PlayerStateObject?) {
        self.player = player
    }
}

/// Player state object within client/state message
public struct PlayerStateObject: Codable, Sendable {
    /// Player state: "synchronized" or "error"
    public let state: PlayerStateValue
    /// Volume level (0-100), only if volume command is supported
    public let volume: Int?
    /// Mute state, only if mute command is supported
    public let muted: Bool?

    public init(state: PlayerStateValue, volume: Int? = nil, muted: Bool? = nil) {
        if let vol = volume {
            precondition(vol >= 0 && vol <= 100, "Volume must be between 0 and 100")
        }
        self.state = state
        self.volume = volume
        self.muted = muted
    }
}

// MARK: - Stream Messages

/// Stream start message
public struct StreamStartMessage: SendspinMessage {
    public let type = "stream/start"
    public let payload: StreamStartPayload

    public init(payload: StreamStartPayload) {
        self.payload = payload
    }
}

public struct StreamStartPayload: Codable, Sendable {
    public let player: StreamStartPlayer?
    public let artwork: StreamStartArtwork?
    public let visualizer: StreamStartVisualizer?

    public init(player: StreamStartPlayer?, artwork: StreamStartArtwork?, visualizer: StreamStartVisualizer?) {
        self.player = player
        self.artwork = artwork
        self.visualizer = visualizer
    }
}

public struct StreamStartPlayer: Codable, Sendable {
    public let codec: String
    public let sampleRate: Int
    public let channels: Int
    public let bitDepth: Int
    public let codecHeader: String?

    enum CodingKeys: String, CodingKey {
        case codec
        case sampleRate = "sample_rate"
        case channels
        case bitDepth = "bit_depth"
        case codecHeader = "codec_header"
    }

    public init(codec: String, sampleRate: Int, channels: Int, bitDepth: Int, codecHeader: String?) {
        self.codec = codec
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth
        self.codecHeader = codecHeader
    }
}

public struct StreamStartArtwork: Codable, Sendable {
    // IMPLEMENTATION_NOTE: Implement when artwork role is added

    public init() {}

    // Explicit Codable implementation for empty struct
    public init(from _: Decoder) throws {}
    public func encode(to _: Encoder) throws {}
}

public struct StreamStartVisualizer: Codable, Sendable {
    // IMPLEMENTATION_NOTE: Implement when visualizer role is added

    public init() {}

    // Explicit Codable implementation for empty struct
    public init(from _: Decoder) throws {}
    public func encode(to _: Encoder) throws {}
}

/// Stream end message
public struct StreamEndMessage: SendspinMessage {
    public let type = "stream/end"

    public init() {}
}

/// Group update message
public struct GroupUpdateMessage: SendspinMessage {
    public let type = "group/update"
    public let payload: GroupUpdatePayload

    public init(payload: GroupUpdatePayload) {
        self.payload = payload
    }
}

public struct GroupUpdatePayload: Codable, Sendable {
    public let playbackState: String?
    public let groupId: String?
    public let groupName: String?

    enum CodingKeys: String, CodingKey {
        case playbackState = "playback_state"
        case groupId = "group_id"
        case groupName = "group_name"
    }

    public init(playbackState: String?, groupId: String?, groupName: String?) {
        self.playbackState = playbackState
        self.groupId = groupId
        self.groupName = groupName
    }
}

// MARK: - Metadata Messages

/// Stream metadata message (basic track info)
public struct StreamMetadataMessage: SendspinMessage {
    public let type = "stream/metadata"
    public let payload: StreamMetadataPayload

    public init(payload: StreamMetadataPayload) {
        self.payload = payload
    }
}

public struct StreamMetadataPayload: Codable, Sendable {
    public let title: String?
    public let artist: String?
    public let album: String?
    public let artworkUrl: String?

    enum CodingKeys: String, CodingKey {
        case title
        case artist
        case album
        case artworkUrl = "artwork_url"
    }

    public init(title: String?, artist: String?, album: String?, artworkUrl: String?) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkUrl = artworkUrl
    }
}

/// Session update message (comprehensive session state including metadata)
public struct SessionUpdateMessage: SendspinMessage {
    public let type = "session/update"
    public let payload: SessionUpdatePayload

    public init(payload: SessionUpdatePayload) {
        self.payload = payload
    }
}

public struct SessionUpdatePayload: Codable, Sendable {
    public let groupId: String?
    public let playbackState: String?
    public let metadata: SessionMetadata?

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case playbackState = "playback_state"
        case metadata
    }

    public init(groupId: String?, playbackState: String?, metadata: SessionMetadata?) {
        self.groupId = groupId
        self.playbackState = playbackState
        self.metadata = metadata
    }
}

public struct SessionMetadata: Codable, Sendable {
    public let title: String?
    public let artist: String?
    public let album: String?
    public let albumArtist: String?
    public let track: Int?
    public let trackDuration: Int? // Duration in seconds (Go sends int, not float64)
    public let year: Int?
    public let playbackSpeed: Double?
    public let `repeat`: String? // "off", "track", "all" (Go sends string, not bool)
    public let shuffle: Bool?
    public let artworkUrl: String?
    public let timestamp: Int64?

    enum CodingKeys: String, CodingKey {
        case title
        case artist
        case album
        case albumArtist = "album_artist"
        case track
        case trackDuration = "track_duration"
        case year
        case playbackSpeed = "playback_speed"
        case `repeat`
        case shuffle
        case artworkUrl = "artwork_url"
        case timestamp
    }

    public init(
        title: String?,
        artist: String?,
        album: String?,
        albumArtist: String?,
        track: Int?,
        trackDuration: Int?,
        year: Int?,
        playbackSpeed: Double?,
        repeat: String?,
        shuffle: Bool?,
        artworkUrl: String?,
        timestamp: Int64?
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.track = track
        self.trackDuration = trackDuration
        self.year = year
        self.playbackSpeed = playbackSpeed
        self.repeat = `repeat`
        self.shuffle = shuffle
        self.artworkUrl = artworkUrl
        self.timestamp = timestamp
    }
}

// MARK: - Clear Messages

/// Stream clear message (clears current stream state)
public struct StreamClearMessage: SendspinMessage {
    public let type = "stream/clear"

    public init() {}
}

// MARK: - Command Messages

/// Command sent from client to server
public struct ClientCommandMessage: SendspinMessage {
    public let type = "client/command"
    public let payload: CommandPayload

    public init(payload: CommandPayload) {
        self.payload = payload
    }
}

/// Command sent from server to client
public struct ServerCommandMessage: SendspinMessage {
    public let type = "server/command"
    public let payload: CommandPayload

    public init(payload: CommandPayload) {
        self.payload = payload
    }
}

/// Command payload for client/command and server/command messages
public struct CommandPayload: Codable, Sendable {
    public let command: String
    public let value: CommandValue?

    public init(command: String, value: CommandValue? = nil) {
        self.command = command
        self.value = value
    }
}

/// Represents a command value that can be various types
public enum CommandValue: Codable, Sendable {
    case int(Int)
    case double(Double)
    case bool(Bool)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                CommandValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Int, Double, Bool, or String")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        }
    }
}

// MARK: - Goodbye Messages

/// Client goodbye message (graceful disconnect)
public struct ClientGoodbyeMessage: SendspinMessage {
    public let type = "client/goodbye"
    public let payload: GoodbyePayload?

    public init(payload: GoodbyePayload? = nil) {
        self.payload = payload
    }
}

/// Goodbye payload with optional reason
public struct GoodbyePayload: Codable, Sendable {
    public let reason: String?

    public init(reason: String? = nil) {
        self.reason = reason
    }
}
