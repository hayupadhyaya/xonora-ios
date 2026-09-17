import Foundation

struct MAPlayer: Identifiable, Codable, Hashable {
    let playerId: String
    let provider: String
    let name: String
    let type: String
    let available: Bool
    let state: PlayerState?
    let volume: Int?
    let currentMedia: CurrentMedia?
    let queueId: String?
    let groupChilds: [String]?
    let syncedTo: String?

    var id: String { playerId }

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case provider
        case name
        case type
        case available
        case state = "playback_state"
        case volume = "volume_level"
        case currentMedia = "current_media"
        case queueId = "active_source"
        case groupChilds = "group_childs"
        case syncedTo = "synced_to"
    }
}

enum PlayerState: String, Codable {
    case idle = "idle"
    case playing = "playing"
    case paused = "paused"
    case off = "off"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = PlayerState(rawValue: rawValue) ?? .unknown
    }
}

struct CurrentMedia: Codable, Hashable {
    let title: String?
    let artist: String?
    let album: String?
    let imageUrl: String?
    let image: String?
    let duration: TimeInterval?
    let position: TimeInterval?
    let uri: String?

    var imageUrlResolved: String? {
        // Try imageUrl first, then fall back to image field
        return imageUrl ?? image
    }

    enum CodingKeys: String, CodingKey {
        case title
        case artist
        case album
        case imageUrl = "image_url"
        case image
        case duration
        case position
        case uri
    }
}

struct QueueItem: Identifiable, Codable, Hashable {
    let queueItemId: String
    let name: String
    let artist: String?
    let album: String?
    let imageUrl: String?
    let duration: TimeInterval?
    let uri: String?
    let mediaItem: QueueMediaItem?

    var id: String { queueItemId }
    
    var artistNames: String {
        artist ?? "Unknown Artist"
    }
    
    var formattedDuration: String {
        guard let duration = duration else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    enum CodingKeys: String, CodingKey {
        case queueItemId = "queue_item_id"
        case name
        case artist
        case album
        case imageUrl = "image"
        case duration
        case uri
        case mediaItem = "media_item"
    }
}

/// Embedded media item within a queue item
struct QueueMediaItem: Codable, Hashable {
    let itemId: String?
    let provider: String?
    let name: String?
    let metadata: MediaItemMetadata?
    
    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider
        case name
        case metadata
    }
}

/// Full queue response from server
struct PlayerQueue {
    let queueId: String
    let currentIndex: Int?
    let items: [QueueItem]
    let shuffleEnabled: Bool?
    let repeatMode: String?
}
