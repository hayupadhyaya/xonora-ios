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
    let image: MediaItemImage?
    var favorite: Bool?

    var id: String { itemId }

    var artistNames: String {
        artists?.map { $0.name }.joined(separator: ", ") ?? "Unknown Artist"
    }

    var imageUrl: String? {
        // Check metadata images first - they have separate provider and path fields
        if let images = metadata?.images, !images.isEmpty {
            // Prioritize HTTP/HTTPS URLs (from external sources like theaudiodb)
            for image in images where image.type == "thumb" {
                let path = image.path
                if path.hasPrefix("http://") || path.hasPrefix("https://") {
                    return path
                }
                if path.hasPrefix("data:image") {
                    return path
                }
            }
            
            // If no HTTP URLs, use the first thumb image and construct a provider URI
            if let thumbImage = images.first(where: { $0.type == "thumb" }) {
                let path = thumbImage.path
                let provider = thumbImage.provider
                
                // If path is already a full URL, use it
                if path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("data:image") {
                    return path
                }
                
                // Otherwise construct a provider URI: "provider://path"
                if !provider.isEmpty {
                    return "\(provider)://\(path)"
                }
                
                // If provider is empty but path exists, try returning just the path
                return path
            }
            
            // Fallback: use any image
            if let anyImage = images.first {
                let path = anyImage.path
                if path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("data:image") {
                    return path
                }
                if !anyImage.provider.isEmpty {
                    return "\(anyImage.provider)://\(path)"
                }
            }
        }
        
        // Check top-level image field (fallback for some providers)
        if let image = image {
            let path = image.path
            if path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("data:image") {
                return path
            }
            if !image.provider.isEmpty {
                return "\(image.provider)://\(path)"
            }
            return path
        }

        // Fall back to the track's URI
        return uri
    }

    var formattedDuration: String {
        guard let duration = duration else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var sourceProvider: String? {
        // Extract provider from URI scheme (e.g., "spotify://track/123" -> "spotify")
        if let schemeEnd = uri.firstIndex(of: ":") {
            return String(uri[..<schemeEnd])
        }
        // Fallback to providerMappings if available
        if let mapping = providerMappings?.first {
            return mapping.providerDomain
        }
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
        case image
        case favorite
    }
}

struct MediaItemMetadata: Codable, Hashable {
    let images: [MediaItemImage]?
    let lyrics: String?
    let lrcLyrics: String?

    enum CodingKeys: String, CodingKey {
        case images
        case lyrics
        case lrcLyrics = "lrc_lyrics"
    }

    init(images: [MediaItemImage]?, lyrics: String? = nil, lrcLyrics: String? = nil) {
        self.images = images
        self.lyrics = lyrics
        self.lrcLyrics = lrcLyrics
    }
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
        // Check metadata images first - they have separate provider and path fields
        if let images = metadata?.images, !images.isEmpty {
            // Prioritize HTTP/HTTPS URLs
            for image in images where image.type == "thumb" {
                let path = image.path
                if path.hasPrefix("http://") || path.hasPrefix("https://") {
                    return path
                }
                if path.hasPrefix("data:image") {
                    return path
                }
            }
            
            // Use the first thumb image and construct a provider URI
            if let thumbImage = images.first(where: { $0.type == "thumb" }) {
                let path = thumbImage.path
                let provider = thumbImage.provider
                
                if path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("data:image") {
                    return path
                }
                
                if !provider.isEmpty {
                    return "\(provider)://\(path)"
                }
                
                return path
            }
            
            // Fallback: use any image
            if let anyImage = images.first {
                let path = anyImage.path
                if path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("data:image") {
                    return path
                }
                if !anyImage.provider.isEmpty {
                    return "\(anyImage.provider)://\(path)"
                }
            }
        }
        
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider
        case name
        case metadata
    }
}
