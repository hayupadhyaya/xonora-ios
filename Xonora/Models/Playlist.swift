import Foundation

struct Playlist: Identifiable, Codable, Hashable {
    let itemId: String
    let provider: String
    let name: String
    let uri: String
    let metadata: MediaItemMetadata?
    let isEditable: Bool?
    let owner: String?
    var favorite: Bool?

    var id: String { itemId }

    var imageUrl: String? {
        metadata?.images?.first(where: { $0.type == "thumb" })?.path ??
        metadata?.images?.first?.path
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
        case uri
        case metadata
        case isEditable = "is_editable"
        case owner
        case favorite
    }
}
