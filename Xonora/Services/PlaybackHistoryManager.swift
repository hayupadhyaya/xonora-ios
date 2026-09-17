import Foundation

actor PlaybackHistoryManager {
    static let shared = PlaybackHistoryManager()

    private let maxHistoryItems = 100
    private let maxHistoryAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    private let userDefaultsKey = "playbackHistory"

    private var historyItems: [PlaybackHistoryItem] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: "playbackHistory"),
           let decoded = try? JSONDecoder().decode([PlaybackHistoryItem].self, from: data) {
            self.historyItems = decoded
        } else {
            self.historyItems = []
        }
        
        Task {
            await clearOldHistory()
        }
    }

    // MARK: - Public Methods

    func addToHistory(item: PlaybackHistoryItem) {
        // Remove existing entry for the same item if it exists
        historyItems.removeAll { $0.itemId == item.itemId }

        // Add new entry at the beginning
        historyItems.insert(item, at: 0)

        // Limit to max items
        if historyItems.count > maxHistoryItems {
            historyItems = Array(historyItems.prefix(maxHistoryItems))
        }

        saveHistory()
    }

    func getRecentlyPlayed(limit: Int = 20) -> [PlaybackHistoryItem] {
        // Return all recent items
        return Array(historyItems.prefix(limit))
    }

    func getRecentlyPlayedByType(contentTypes: [PlaybackHistoryItem.ContentType], limit: Int = 20) -> [PlaybackHistoryItem] {
        // Return recent items filtered by specific content types
        let filteredItems = historyItems.filter { contentTypes.contains($0.contentType) }
        return Array(filteredItems.prefix(limit))
    }

    func getContinueListening() -> [PlaybackHistoryItem] {
        // Return audiobooks and podcasts that have progress
        return historyItems.filter {
            ($0.contentType == .audiobook || $0.contentType == .podcast) &&
            $0.progress != nil &&
            $0.duration != nil &&
            ($0.progress ?? 0) < ($0.duration ?? 0) // Not completed
        }
    }

    func updateProgress(itemId: String, progress: TimeInterval, duration: TimeInterval) {
        if let index = historyItems.firstIndex(where: { $0.itemId == itemId }) {
            let existingItem = historyItems[index]

            let updatedItem = PlaybackHistoryItem(
                id: existingItem.id,
                timestamp: Date(),
                contentType: existingItem.contentType,
                itemId: existingItem.itemId,
                itemName: existingItem.itemName,
                itemUri: existingItem.itemUri,
                artistName: existingItem.artistName,
                imageUrl: existingItem.imageUrl,
                progress: progress,
                duration: duration
            )

            historyItems[index] = updatedItem
            saveHistory()
        }
    }

    func removeFromHistory(itemId: String) {
        historyItems.removeAll { $0.itemId == itemId }
        saveHistory()
    }

    func clearOldHistory() {
        let cutoffDate = Date().addingTimeInterval(-maxHistoryAge)
        historyItems.removeAll { $0.timestamp < cutoffDate }
        saveHistory()
    }

    func clearAllHistory() {
        historyItems.removeAll()
        saveHistory()
    }

    // MARK: - Private Methods

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([PlaybackHistoryItem].self, from: data) else {
            historyItems = []
            return
        }

        historyItems = decoded
    }

    private func saveHistory() {
        guard let encoded = try? JSONEncoder().encode(historyItems) else {
            print("Failed to encode playback history")
            return
        }

        UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
    }
}
