import Foundation

struct Artist: Identifiable, Codable, Hashable {
    let itemId: String
    let provider: String
    let name: String
    let sortName: String?
    let uri: String
    let metadata: MediaItemMetadata?
    var favorite: Bool?

    var id: String { itemId }
    
    var imageUrl: String? {
        metadata?.images?.first(where: { $0.type == "thumb" })?.path ?? 
        metadata?.images?.first?.path
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider
        case name
        case sortName = "sort_name"
        case uri
        case metadata
    }
}
