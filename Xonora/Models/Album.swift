import Foundation

struct Album: Identifiable, Codable, Hashable {
    let itemId: String
    let provider: String
    let name: String
    let version: String?
    let year: Int?
    let artists: [ArtistReference]?
    let uri: String
    let metadata: MediaItemMetadata?
    var favorite: Bool?

    var id: String { itemId }

    var artistNames: String {
        artists?.map { $0.name }.joined(separator: ", ") ?? "Unknown Artist"
    }
    
    var imageUrl: String? {
        metadata?.images?.first(where: { $0.type == "thumb" })?.path ?? 
        metadata?.images?.first?.path
    }

    var displayYear: String {
        if let year = year {
            return String(year)
        }
        return ""
    }

    /// Returns the source provider (e.g., apple_music, spotify) extracted from URI
    var sourceProvider: String {
        if let scheme = URL(string: uri)?.scheme,
           !scheme.isEmpty && scheme != "library" && scheme != "file" {
            return scheme
        }
        return provider
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider
        case name
        case version
        case year
        case artists
        case uri
        case metadata
    }
}

struct ImageInfo: Codable, Hashable {
    let url: String
    let type: String?
    let size: Int?
}
