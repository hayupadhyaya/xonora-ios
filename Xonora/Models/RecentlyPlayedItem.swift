import Foundation

struct RecentlyPlayedItem: Identifiable, Codable, Hashable {
    let itemId: String
    let provider: String
    let name: String
    let uri: String
    let mediaType: String
    let timestamp: Date
    let artists: [ArtistReference]?
    let album: String?
    let imageUrl: String?

    var id: String { itemId }

    var artistNames: String {
        artists?.map { $0.name }.joined(separator: ", ") ?? "Unknown Artist"
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider
        case name
        case uri
        case mediaType = "media_type"
        case timestamp
        case artists
        case album
        case imageUrl = "image_url"
    }

    // Custom decoder to handle flexible API responses
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        itemId = try container.decode(String.self, forKey: .itemId)
        provider = try container.decode(String.self, forKey: .provider)
        name = try container.decode(String.self, forKey: .name)
        uri = try container.decode(String.self, forKey: .uri)
        mediaType = try container.decode(String.self, forKey: .mediaType)

        // Decode timestamp - handle both Double and String formats
        if let timestampDouble = try? container.decode(Double.self, forKey: .timestamp) {
            timestamp = Date(timeIntervalSince1970: timestampDouble)
        } else if let timestampString = try? container.decode(String.self, forKey: .timestamp),
                  let timestampDouble = Double(timestampString) {
            timestamp = Date(timeIntervalSince1970: timestampDouble)
        } else {
            timestamp = Date()
        }

        // Handle artists - can be array of ArtistReference or comma-separated string
        if let artistsArray = try? container.decode([ArtistReference].self, forKey: .artists) {
            artists = artistsArray
        } else if let artistsString = try? container.decode(String.self, forKey: .artists) {
            // Parse comma-separated string into ArtistReference array
            let artistNames = artistsString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            artists = artistNames.isEmpty ? nil : artistNames.map { name in
                ArtistReference(itemId: nil, provider: nil, name: name)
            }
        } else {
            artists = nil
        }

        album = try? container.decode(String.self, forKey: .album)

        // Handle imageUrl - can be String or ImageInfo object
        if let imageString = try? container.decode(String.self, forKey: .imageUrl) {
            imageUrl = imageString
        } else if let imageObject = try? container.decode(MediaItemImage.self, forKey: .imageUrl) {
            // Construct URL from provider and path
            let path = imageObject.path
            if path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("data:image") {
                imageUrl = path
            } else if !imageObject.provider.isEmpty {
                imageUrl = "\(imageObject.provider)://\(path)"
            } else {
                imageUrl = path
            }
        } else {
            imageUrl = nil
        }
    }

    // Standard encoder
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemId, forKey: .itemId)
        try container.encode(provider, forKey: .provider)
        try container.encode(name, forKey: .name)
        try container.encode(uri, forKey: .uri)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encode(timestamp.timeIntervalSince1970, forKey: .timestamp)
        try container.encodeIfPresent(artists, forKey: .artists)
        try container.encodeIfPresent(album, forKey: .album)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
    }
}
