import Foundation

struct LyricLine: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    let text: String
}
