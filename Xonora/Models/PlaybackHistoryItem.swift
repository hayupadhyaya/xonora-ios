import Foundation

struct PlaybackHistoryItem: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let contentType: ContentType
    let itemId: String
    let itemName: String
    let itemUri: String
    let artistName: String?
    let imageUrl: String?

    // Continue Listening specific
    let progress: TimeInterval?
    let duration: TimeInterval?

    enum ContentType: String, Codable {
        case album
        case playlist
        case audiobook
        case podcast
        case radio
        case track
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        contentType: ContentType,
        itemId: String,
        itemName: String,
        itemUri: String,
        artistName: String? = nil,
        imageUrl: String? = nil,
        progress: TimeInterval? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.contentType = contentType
        self.itemId = itemId
        self.itemName = itemName
        self.itemUri = itemUri
        self.artistName = artistName
        self.imageUrl = imageUrl
        self.progress = progress
        self.duration = duration
    }
}
