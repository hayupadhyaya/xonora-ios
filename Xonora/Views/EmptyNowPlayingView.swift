import SwiftUI

struct EmptyNowPlayingView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Music note icon
            Image(systemName: "music.note")
                .font(.system(size: 80))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("No Music Playing")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Start playing music from your library to see playback controls here")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
}

#Preview {
    EmptyNowPlayingView()
}
