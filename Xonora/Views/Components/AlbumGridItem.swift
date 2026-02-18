import SwiftUI

struct AlbumGridItem: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: album.imageUrl, size: .small)) {
                albumPlaceholder
            }
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    ProviderIcon(provider: album.sourceProvider, size: 12)
                    Text(album.artistNames)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var albumPlaceholder: some View {
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

struct AlbumGridItem_Previews: PreviewProvider {
    static var previews: some View {
        AlbumGridItem(album: Album(
            itemId: "1",
            provider: "apple_music",
            name: "Sample Album",
            version: nil,
            year: 2024,
            artists: [ArtistReference(itemId: "1", provider: "apple_music", name: "Sample Artist")],
            uri: "apple_music://album/1",
            metadata: nil
        ))
        .frame(width: 180)
        .padding()
    }
}
