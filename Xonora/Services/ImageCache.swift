import Foundation
import SwiftUI
import CryptoKit

/// Image cache with in-memory and disk persistence
actor ImageCache {
    static let shared = ImageCache()

    private var cache = NSCache<NSString, UIImage>()
    private var downloadingURLs = Set<String>()
    private let urlSession: URLSession
    private let diskCacheDirectory: URL
    private let fileManager = FileManager.default

    /// Max disk cache size: 200MB
    private let maxDiskCacheSize: Int = 200 * 1024 * 1024

    private init() {
        cache.countLimit = 100 // Max 100 images in memory
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB max in memory

        // Reuse single URLSession -- use .default for connection pooling, disable URL cache
        // since we manage our own disk cache
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:]
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: config)

        // Set up disk cache directory
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        diskCacheDirectory = caches.appendingPathComponent("ImageCache", isDirectory: true)
        try? fm.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
    }

    func image(for url: URL) -> UIImage? {
        let key = stableCacheKey(for: url) as NSString

        // Check memory cache first
        if let memoryImage = cache.object(forKey: key) {
            return memoryImage
        }

        // Check disk cache
        let filePath = diskFilePath(for: url)
        guard fileManager.fileExists(atPath: filePath.path),
              let data = try? Data(contentsOf: filePath),
              let diskImage = UIImage(data: data) else {
            return nil
        }

        // Promote to memory cache (use pixel dimensions, not points)
        let cost = Int(diskImage.size.width * diskImage.scale * diskImage.size.height * diskImage.scale * 4)
        cache.setObject(diskImage, forKey: key, cost: cost)
        return diskImage
    }

    func setImage(_ image: UIImage, for url: URL) {
        let key = stableCacheKey(for: url) as NSString
        // Estimate memory usage: width * height * 4 bytes (for RGBA), using pixel dimensions not points
        let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        cache.setObject(image, forKey: key, cost: cost)

        // Write to disk asynchronously
        let filePath = diskFilePath(for: url)
        Task.detached(priority: .utility) {
            if let data = image.jpegData(compressionQuality: 0.85) {
                try? data.write(to: filePath, options: .atomic)
            }
        }
    }

    func isDownloading(_ url: URL) -> Bool {
        downloadingURLs.contains(stableCacheKey(for: url))
    }

    func startDownloading(_ url: URL) {
        downloadingURLs.insert(stableCacheKey(for: url))
    }

    func finishDownloading(_ url: URL) {
        downloadingURLs.remove(stableCacheKey(for: url))
    }

    func clearCache() {
        cache.removeAllObjects()
        // Clear disk cache
        try? fileManager.removeItem(at: diskCacheDirectory)
        try? fileManager.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
    }

    var session: URLSession {
        urlSession
    }

    // MARK: - Disk Cache Helpers

    func getDiskUsage() -> Int {
        guard let files = try? fileManager.contentsOfDirectory(at: diskCacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return files.reduce(0) { total, url in
            let resources = try? url.resourceValues(forKeys: [.fileSizeKey])
            return total + (resources?.fileSize ?? 0)
        }
    }

    /// Stable cache key that strips ephemeral auth tokens from imageproxy URLs.
    /// Ensures the same image content maps to the same cache entry regardless of token rotation.
    private func stableCacheKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              var queryItems = components.queryItems,
              queryItems.contains(where: { $0.name == "token" }) else {
            return url.absoluteString
        }
        queryItems.removeAll { $0.name == "token" }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.string ?? url.absoluteString
    }

    private func diskFilePath(for url: URL) -> URL {
        let key = stableCacheKey(for: url)
        let hash = SHA256.hash(data: Data(key.utf8))
        let filename = hash.compactMap { String(format: "%02x", $0) }.joined()
        return diskCacheDirectory.appendingPathComponent(filename + ".jpg")
    }
}

/// A view that displays an image from a URL with caching support
struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let placeholder: () -> Placeholder

    @Environment(\.scenePhase) private var scenePhase
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
            }
        }
        .onAppear {
            if image == nil {
                loadImage()
            }
        }
        .onChange(of: url) { oldURL, newURL in
            if newURL != oldURL {
                image = nil
                loadImage()
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active && image == nil && url != nil {
                isLoading = false
                loadImage()
            }
        }
    }

    private func loadImage() {
        guard let url = url else { return }
        guard !isLoading else { return }

        Task {
            // Check cache first (memory + disk)
            if let cached = await ImageCache.shared.image(for: url) {
                await MainActor.run {
                    self.image = cached
                }
                return
            }

            // If another view is already downloading this URL, wait for it
            if await ImageCache.shared.isDownloading(url) {
                // Poll cache until the other download finishes
                for _ in 0..<20 { // Up to ~2 seconds
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    if await !ImageCache.shared.isDownloading(url) {
                        break
                    }
                }
                // Check cache again after waiting
                if let cached = await ImageCache.shared.image(for: url) {
                    await MainActor.run {
                        self.image = cached
                    }
                }
                return
            }

            await MainActor.run { isLoading = true }
            await ImageCache.shared.startDownloading(url)

            do {
                let session = await ImageCache.shared.session
                let (data, response) = try await session.data(from: url)

                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode != 200 {
                    if httpResponse.statusCode != 404 {
                        // Log non-404 errors; 404s are expected for expired imageproxy tokens
                        print("[ImageCache] Error loading image from \(url.absoluteString): HTTP \(httpResponse.statusCode)")
                    }
                    await ImageCache.shared.finishDownloading(url)
                    await MainActor.run { isLoading = false }
                    return
                }

                // Decode image on background thread to avoid blocking main thread
                let downloadedImage = await Task.detached(priority: .userInitiated) {
                    guard let image = UIImage(data: data) else { return nil as UIImage? }

                    // Pre-render the image to force decompression
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = image.scale
                    format.opaque = false

                    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
                    let decodedImage = renderer.image { context in
                        image.draw(at: .zero)
                    }
                    return decodedImage
                }.value

                if let downloadedImage = downloadedImage {
                    await ImageCache.shared.setImage(downloadedImage, for: url)
                    await MainActor.run {
                        self.image = downloadedImage
                    }
                } else {
                    print("[ImageCache] Failed to decode image data from \(url.absoluteString), data size: \(data.count) bytes")
                }
            } catch let error as URLError where error.code == .timedOut {
                print("[ImageCache] Timeout loading image from \(url.absoluteString)")
            } catch let error as URLError where error.code == .cancelled {
                // Task was cancelled (e.g., view disappeared) - this is normal
            } catch {
                print("[ImageCache] Exception loading image from \(url.absoluteString): \(error.localizedDescription)")
            }

            await ImageCache.shared.finishDownloading(url)
            await MainActor.run { isLoading = false }
        }
    }

    private func safeLog(_ message: String) {
        // Truncate extremely long messages to avoid system logging issues (decode: bad range)
        // especially important for base64 data: URLs
        let logMessage = message.count > 1000 ? String(message.prefix(1000)) + "... (truncated)" : message
        print(logMessage)
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
