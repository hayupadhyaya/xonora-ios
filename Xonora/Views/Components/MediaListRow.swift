import SwiftUI

// MARK: - Grid Columns Helper

@MainActor
func gridColumns(
    for category: String,
    horizontalSizeClass: UserInterfaceSizeClass?,
    verticalSizeClass: UserInterfaceSizeClass?
) -> [GridItem] {
    let isIPad = UIDevice.current.userInterfaceIdiom == .pad
    let isLandscape = verticalSizeClass == .compact
    let userPref = UserPreferences.shared.gridColumnCount(for: category, landscape: isLandscape)
    let count: Int
    if userPref > 0 {
        count = userPref
    } else {
        if isIPad {
            count = isLandscape ? 8 : 4
        } else {
            count = isLandscape ? 4 : 2
        }
    }
    return Array(repeating: GridItem(.flexible(), spacing: 16), count: count)
}

func columnRange(
    horizontalSizeClass: UserInterfaceSizeClass?,
    verticalSizeClass: UserInterfaceSizeClass?
) -> ClosedRange<Int> {
    let isIPad = UIDevice.current.userInterfaceIdiom == .pad
    let isLandscape = verticalSizeClass == .compact
    if isIPad {
        return isLandscape ? 8...16 : 4...8
    } else {
        return isLandscape ? 4...8 : 2...4
    }
}

/// Shared list row for grid-capable media types (Albums, Playlists, Audiobooks, Podcasts, Radio)
struct MediaListRow: View {
    let title: String
    let subtitle: String?
    let imageUrl: String?
    let imageShape: ImageShape

    enum ImageShape {
        case rounded, circle
    }

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: imageUrl, size: .thumbnail)) {
                RoundedRectangle(cornerRadius: imageShape == .rounded ? 6 : 22)
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundColor(.gray)
                    }
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 44, height: 44)
            .clipShape(
                imageShape == .rounded
                    ? AnyShape(RoundedRectangle(cornerRadius: 6))
                    : AnyShape(Circle())
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// List row for Radio (no chevron, tap plays directly)
struct RadioListRow: View {
    let title: String
    let imageUrl: String?

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: imageUrl, size: .thumbnail)) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.gray)
                    }
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(title)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
