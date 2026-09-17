import SwiftUI

struct TrackCardItem: View {
    let track: Track

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: track.imageUrl ?? track.album?.imageUrl, size: .small)) {
                placeholderView
            }
            .aspectRatio(1, contentMode: .fill)
            .frame(width: 150, height: 150)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Text(track.artistNames)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
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
                Image(systemName: "music.note")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
            }
    }
}
