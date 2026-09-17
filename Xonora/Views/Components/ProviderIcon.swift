import SwiftUI

struct ProviderIcon: View {
    let provider: String?
    let size: CGFloat

    init(provider: String?, size: CGFloat = 16) {
        self.provider = provider
        self.size = size
    }

    var body: some View {
        if let provider = provider, !provider.isEmpty {
            Image(systemName: providerIcon)
                .font(.system(size: size))
                .foregroundColor(providerColor)
        }
    }

    private var providerIcon: String {
        guard let provider = provider?.lowercased() else {
            return "music.note"
        }

        if provider.contains("spotify") {
            return "s.circle.fill"
        } else if provider.contains("apple") || provider.contains("applemusic") {
            return "applelogo"
        } else if provider.contains("tidal") {
            return "waveform.circle.fill"
        } else if provider.contains("qobuz") {
            return "q.circle.fill"
        } else if provider.contains("deezer") {
            return "d.circle.fill"
        } else if provider.contains("youtube") || provider.contains("ytmusic") {
            return "play.rectangle.fill"
        } else if provider.contains("soundcloud") {
            return "cloud.fill"
        } else if provider.contains("bandcamp") {
            return "b.circle.fill"
        } else if provider.contains("filesystem") || provider.contains("file") {
            return "folder.fill"
        } else if provider.contains("url") || provider.contains("stream") {
            return "antenna.radiowaves.left.and.right"
        } else if provider.contains("radio") {
            return "dot.radiowaves.left.and.right"
        } else if provider.contains("podcast") {
            return "mic.fill"
        } else {
            return "music.note.list"
        }
    }

    private var providerColor: Color {
        guard let provider = provider?.lowercased() else {
            return .secondary
        }

        if provider.contains("spotify") {
            return Color(red: 0.11, green: 0.73, blue: 0.33) // Spotify Green
        } else if provider.contains("apple") || provider.contains("applemusic") {
            return Color(red: 0.98, green: 0.26, blue: 0.45) // Apple Music Pink
        } else if provider.contains("tidal") {
            return Color(red: 0.0, green: 0.0, blue: 0.0) // Tidal Black
        } else if provider.contains("qobuz") {
            return Color(red: 0.23, green: 0.47, blue: 0.82) // Qobuz Blue
        } else if provider.contains("deezer") {
            return Color(red: 1.0, green: 0.65, blue: 0.0) // Deezer Orange
        } else if provider.contains("youtube") || provider.contains("ytmusic") {
            return Color(red: 1.0, green: 0.0, blue: 0.0) // YouTube Red
        } else if provider.contains("soundcloud") {
            return Color(red: 1.0, green: 0.4, blue: 0.0) // SoundCloud Orange
        } else if provider.contains("bandcamp") {
            return Color(red: 0.38, green: 0.73, blue: 0.82) // Bandcamp Cyan
        } else if provider.contains("filesystem") || provider.contains("file") {
            return .blue
        } else if provider.contains("url") || provider.contains("stream") {
            return .purple
        } else if provider.contains("radio") {
            return .orange
        } else if provider.contains("podcast") {
            return .purple
        } else {
            return .secondary
        }
    }
}

// Extension to get display name for provider
extension String {
    var providerDisplayName: String {
        let provider = self.lowercased()

        if provider.contains("spotify") {
            return "Spotify"
        } else if provider.contains("applemusic") {
            return "Apple Music"
        } else if provider.contains("apple") {
            return "Apple"
        } else if provider.contains("tidal") {
            return "Tidal"
        } else if provider.contains("qobuz") {
            return "Qobuz"
        } else if provider.contains("deezer") {
            return "Deezer"
        } else if provider.contains("ytmusic") {
            return "YouTube Music"
        } else if provider.contains("youtube") {
            return "YouTube"
        } else if provider.contains("soundcloud") {
            return "SoundCloud"
        } else if provider.contains("bandcamp") {
            return "Bandcamp"
        } else if provider.contains("filesystem") {
            return "Local Files"
        } else if provider.contains("file") {
            return "Files"
        } else if provider.contains("url") || provider.contains("stream") {
            return "Stream"
        } else if provider.contains("radio") {
            return "Radio"
        } else if provider.contains("podcast") {
            return "Podcast"
        } else {
            return self.capitalized
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            ProviderIcon(provider: "spotify", size: 16)
            Text("Spotify")
        }
        HStack {
            ProviderIcon(provider: "applemusic", size: 16)
            Text("Apple Music")
        }
        HStack {
            ProviderIcon(provider: "tidal", size: 16)
            Text("Tidal")
        }
        HStack {
            ProviderIcon(provider: "qobuz", size: 16)
            Text("Qobuz")
        }
        HStack {
            ProviderIcon(provider: "youtube", size: 16)
            Text("YouTube Music")
        }
    }
    .padding()
}
