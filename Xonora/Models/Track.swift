import Foundation

struct Track: Identifiable, Codable, Hashable {
    let itemId: String
    let provider: String
    let name: String
    let version: String?
    let duration: TimeInterval?
    let trackNumber: Int?
    let discNumber: Int?
    let uri: String
    let artists: [ArtistReference]?
    let album: AlbumReference?
    let metadata: MediaItemMetadata?
    let providerMappings: [ProviderMapping]?
    var favorite: Bool?

    var id: String { itemId }

    var artistNames: String {
        artists?.map { $0.name }.joined(separator: ", ") ?? "Unknown Artist"
    }

    var imageUrl: String? {
        metadata?.images?.first(where: { $0.type == "thumb" })?.path ?? 
        metadata?.images?.first?.path
    }

    var formattedDuration: String {
        guard let duration = duration else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Returns the source provider (e.g., apple_music, spotify) extracted from URI or provider mappings
    /// This is useful when items are in the library but originally come from a streaming service
    var sourceProvider: String {
        // First try to extract from URI (e.g., "apple_music://track/123" -> "apple_music")
        if let scheme = URL(string: uri)?.scheme,
           !scheme.isEmpty && scheme != "library" && scheme != "file" {
            return scheme
        }
        // Then try provider mappings
        if let mapping = providerMappings?.first(where: { $0.providerDomain != "library" && $0.providerDomain != "filesystem" }) {
            return mapping.providerDomain
        }
        // Fall back to main provider
        return provider
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider
        case name
        case version
        case duration
        case trackNumber = "track_number"
        case discNumber = "disc_number"
        case uri
        case artists
        case album
        case metadata
        case providerMappings = "provider_mappings"
    }
}

struct MediaItemMetadata: Codable, Hashable {
    let images: [MediaItemImage]?
}

struct MediaItemImage: Codable, Hashable {
    let type: String
    let path: String
    let provider: String
}

struct ProviderMapping: Codable, Hashable {
    let itemId: String
    let providerDomain: String
    let providerInstance: String

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case providerDomain = "provider_domain"
        case providerInstance = "provider_instance"
    }
}

struct ArtistReference: Codable, Hashable {
    let itemId: String?
    let provider: String?
    let name: String

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider
        case name
    }
}

struct AlbumReference: Codable, Hashable {
    let itemId: String
    let provider: String
    let name: String
    let metadata: MediaItemMetadata?
    
    var imageUrl: String? {
        metadata?.images?.first(where: { $0.type == "thumb" })?.path ?? 
        metadata?.images?.first?.path
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider
        case name
        case metadata
    }
}
