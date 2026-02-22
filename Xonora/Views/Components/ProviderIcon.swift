import SwiftUI

/// A view that displays a provider icon/logo based on the provider string
struct ProviderIcon: View {
    let provider: String
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: systemIconName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(providerColor)
            .frame(width: size, height: size)
    }

    /// System icon for each provider
    private var systemIconName: String {
        let normalizedProvider = provider.lowercased()

        switch normalizedProvider {
        case let p where p.contains("spotify"):
            return "circle.fill" // Placeholder - spotify green
        case let p where p.contains("apple"):
            return "applelogo"
        case let p where p.contains("tidal"):
            return "waveform"
        case let p where p.contains("qobuz"):
            return "hifispeaker"
        case let p where p.contains("deezer"):
            return "headphones"
        case let p where p.contains("youtube"):
            return "play.rectangle.fill"
        case let p where p.contains("soundcloud"):
            return "cloud.fill"
        case let p where p.contains("library"):
            return "folder.fill"
        case let p where p.contains("filesystem") || p.contains("file"):
            return "doc.fill"
        case let p where p.contains("plex"):
            return "play.tv"
        case let p where p.contains("subsonic") || p.contains("navidrome"):
            return "server.rack"
        case let p where p.contains("jellyfin"):
            return "play.square.stack"
        default:
            return "music.note"
        }
    }

    /// Provider brand color
    private var providerColor: Color {
        let normalizedProvider = provider.lowercased()

        switch normalizedProvider {
        case let p where p.contains("spotify"):
            return Color(red: 0.12, green: 0.84, blue: 0.38) // Spotify green
        case let p where p.contains("apple"):
            return Color(red: 0.98, green: 0.34, blue: 0.45) // Apple Music pink/red
        case let p where p.contains("tidal"):
            return Color.primary // Tidal black/white
        case let p where p.contains("qobuz"):
            return Color(red: 0.0, green: 0.55, blue: 0.82) // Qobuz blue
        case let p where p.contains("deezer"):
            return Color(red: 0.64, green: 0.0, blue: 1.0) // Deezer purple
        case let p where p.contains("youtube"):
            return Color.red
        case let p where p.contains("soundcloud"):
            return Color.orange
        case let p where p.contains("library"):
            return Color.accentColor
        default:
            return Color.secondary
        }
    }
}

/// Extension to get provider display name
extension String {
    var providerDisplayName: String {
        let normalized = self.lowercased()

        switch normalized {
        case let p where p.contains("spotify"):
            return "Spotify"
        case let p where p.contains("apple"):
            return "Apple Music"
        case let p where p.contains("tidal"):
            return "TIDAL"
        case let p where p.contains("qobuz"):
            return "Qobuz"
        case let p where p.contains("deezer"):
            return "Deezer"
        case let p where p.contains("youtube"):
            return "YouTube Music"
        case let p where p.contains("soundcloud"):
            return "SoundCloud"
        case let p where p.contains("library"):
            return "Library"
        case let p where p.contains("filesystem") || p.contains("file"):
            return "Local Files"
        case let p where p.contains("plex"):
            return "Plex"
        case let p where p.contains("subsonic"):
            return "Subsonic"
        case let p where p.contains("navidrome"):
            return "Navidrome"
        case let p where p.contains("jellyfin"):
            return "Jellyfin"
        default:
            // Clean up the provider string (remove instance IDs like spotify--KwvyDBMn)
            if let dashRange = self.range(of: "--") {
                return String(self[..<dashRange.lowerBound]).capitalized
            }
            return self.capitalized
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(["spotify", "apple_music", "tidal", "qobuz", "library", "filesystem"], id: \.self) { provider in
            HStack {
                ProviderIcon(provider: provider, size: 20)
                Text(provider.providerDisplayName)
            }
        }
    }
    .padding()
}
