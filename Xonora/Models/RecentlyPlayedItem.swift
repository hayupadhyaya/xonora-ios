import Foundation

/// Represents a recently played item from Music Assistant
/// The API returns an ItemMapping which contains media_type and item details
struct RecentlyPlayedItem: Identifiable, Decodable, Hashable {
    let itemId: String
    let provider: String
    let name: String
    let mediaType: String
    let uri: String
    private let metadata: MediaItemMetadata?
    private let _imageUrl: String?

    // Optional nested item details (for tracks, albums, etc.)
    let artist: String?
    let album: String?
    let duration: TimeInterval?

    var id: String { "\(mediaType)_\(itemId)_\(provider)" }

    /// Returns the image URL from metadata.images or direct image field
    var imageUrl: String? {
        // First try metadata.images array (like Album/Track models)
        if let path = metadata?.images?.first(where: { $0.type == "thumb" })?.path {
            return path
        }
        if let path = metadata?.images?.first?.path {
            return path
        }
        // Fall back to direct image field
        return _imageUrl
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider
        case name
        case mediaType = "media_type"
        case uri
        case metadata
        case _imageUrl = "image"
        case artists
        case album
        case duration
    }

    // Custom decoder to handle flexible API responses
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        itemId = try container.decode(String.self, forKey: .itemId)
        provider = try container.decode(String.self, forKey: .provider)
        name = try container.decode(String.self, forKey: .name)
        mediaType = try container.decode(String.self, forKey: .mediaType)
        uri = try container.decode(String.self, forKey: .uri)

        // Parse metadata for images
        metadata = try? container.decodeIfPresent(MediaItemMetadata.self, forKey: .metadata)

        // Image can be at root level as string or MediaItemImage object
        if let img = try? container.decode(String.self, forKey: ._imageUrl) {
            _imageUrl = img
        } else if let imgObj = try? container.decode(MediaItemImage.self, forKey: ._imageUrl) {
            _imageUrl = imgObj.path
        } else {
            _imageUrl = nil
        }

        // Optional fields - try different keys for artist
        // Artists can be an array of ArtistReference or a string
        if let artistsArray = try? container.decode([ArtistReference].self, forKey: .artists) {
            artist = artistsArray.map { $0.name }.joined(separator: ", ")
        } else {
            artist = nil
        }

        // Album can be an AlbumReference or a string
        if let albumRef = try? container.decode(AlbumReference.self, forKey: .album) {
            album = albumRef.name
        } else if let albumStr = try? container.decode(String.self, forKey: .album) {
            album = albumStr
        } else {
            album = nil
        }

        duration = try? container.decodeIfPresent(TimeInterval.self, forKey: .duration)
    }

    // Regular initializer for testing/preview
    init(itemId: String, provider: String, name: String, mediaType: String, uri: String, imageUrl: String?, artist: String?, album: String?, duration: TimeInterval?) {
        self.itemId = itemId
        self.provider = provider
        self.name = name
        self.mediaType = mediaType
        self.uri = uri
        self.metadata = nil
        self._imageUrl = imageUrl
        self.artist = artist
        self.album = album
        self.duration = duration
    }
}
