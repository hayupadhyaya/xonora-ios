import Foundation
import SwiftUI

/// In-memory image cache with automatic cleanup
actor ImageCache {
    static let shared = ImageCache()

    private var cache = NSCache<NSString, UIImage>()
    private var downloadingURLs = Set<String>()
    private let urlSession: URLSession

    private init() {
        cache.countLimit = 100 // Max 100 images
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB max

        // Reuse single URLSession to avoid reporter disconnection errors
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: config)
    }

    func image(for url: URL) -> UIImage? {
        let key = url.absoluteString as NSString
        return cache.object(forKey: key)
    }

    func setImage(_ image: UIImage, for url: URL) {
        let key = url.absoluteString as NSString
        let cost = image.pngData()?.count ?? 0
        cache.setObject(image, forKey: key, cost: cost)
    }

    func isDownloading(_ url: URL) -> Bool {
        downloadingURLs.contains(url.absoluteString)
    }

    func startDownloading(_ url: URL) {
        downloadingURLs.insert(url.absoluteString)
    }

    func finishDownloading(_ url: URL) {
        downloadingURLs.remove(url.absoluteString)
    }

    func clearCache() {
        cache.removeAllObjects()
    }

    var session: URLSession {
        urlSession
    }
}

/// A view that displays an image from a URL with caching support
struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = false

    init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
            } else {
                placeholder()
                    .onAppear {
                        loadImage()
                    }
            }
        }
        .onChange(of: url) { newURL in
            if newURL != url {
                image = nil
                loadImage()
            }
        }
    }

    private func loadImage() {
        guard let url = url else { return }
        guard !isLoading else { return }

        // Check cache first
        Task {
            if let cached = await ImageCache.shared.image(for: url) {
                await MainActor.run {
                    self.image = cached
                }
                return
            }

            // Check if already downloading
            guard await !ImageCache.shared.isDownloading(url) else { return }

            await MainActor.run { isLoading = true }
            await ImageCache.shared.startDownloading(url)

            do {
                // Use shared URLSession to avoid creating multiple sessions
                let session = await ImageCache.shared.session
                let (data, _) = try await session.data(from: url)
                if let downloadedImage = UIImage(data: data) {
                    await ImageCache.shared.setImage(downloadedImage, for: url)
                    await MainActor.run {
                        self.image = downloadedImage
                    }
                }
            } catch {
                // Silent failure - placeholder remains visible
            }

            await ImageCache.shared.finishDownloading(url)
            await MainActor.run { isLoading = false }
        }
    }
}

/// Convenience extension for common placeholder styles
extension CachedAsyncImage where Placeholder == Color {
    init(url: URL?) {
        self.init(url: url) {
            Color.gray.opacity(0.3)
        }
    }
}
