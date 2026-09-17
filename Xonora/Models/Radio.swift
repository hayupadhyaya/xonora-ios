import Foundation

struct Radio: Identifiable, Codable, Hashable {
    let itemId: String
    let provider: String
    let name: String
    let metadata: MediaItemMetadata?
    let uri: String
    let image: MediaItemImage?
    
    var id: String { itemId }
    
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
        
        // Check top-level image field
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

        // For everything else (including local files), use the item's URI
        // Music Assistant's imageproxy can extract artwork from URIs
        return uri
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider
        case name
        case metadata
        case uri
        case image
    }
}
