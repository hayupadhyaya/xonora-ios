import SwiftUI

struct HistoryCardItem: View {
    let item: PlaybackHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: item.imageUrl, size: .small)) {
                placeholderView
            }
            .aspectRatio(1, contentMode: .fill)
            .frame(width: 150, height: 150)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

            // Custom Progress Bar (Below Image, Above Text)
            if let progress = item.progress, let duration = item.duration, duration > 0 {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(height: 4)
                        
                        Capsule()
                            .fill(Color.pink)
                            .frame(width: min(CGFloat(progress / duration) * geometry.size.width, geometry.size.width), height: 4)
                    }
                }
                .frame(height: 4)
                .padding(.top, 4)
                .padding(.bottom, 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.itemName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                if let artistName = item.artistName {
                    Text(artistName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

            }
        }
        .frame(width: 150)
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: iconForContentType)
                    .font(.largeTitle)
                    .foregroundColor(.gray)
            }
    }

    private var iconForContentType: String {
        switch item.contentType {
        case .album, .track, .playlist:
            return "music.note"
        case .audiobook:
            return "book.fill"
        case .podcast:
            return "mic.fill"
        case .radio:
            return "antenna.radiowaves.left.and.right"
        }
    }
}
