import SwiftUI

struct MediaGridItem: View {
    let name: String
    let subtitle: String?
    let imageURL: URL?
    let placeholderIcon: String
    var providerIcon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedAsyncImage(url: imageURL) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Image(systemName: placeholderIcon)
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                    }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(minWidth: 50, maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
