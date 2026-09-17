import SwiftUI

struct CompactProgressBar: View {
    let progress: CGFloat
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isLoading: Bool
    var color: Color = .white

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.2))
                        .frame(height: 4)

                    if isLoading {
                        LoadingProgressIndicator(color: color)
                            .frame(height: 4)
                            .clipped()
                    } else {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: geometry.size.width * progress, height: 4)
                    }
                }
            }
            .frame(height: 4)

            HStack {
                if isLoading {
                    Text("Loading...")
                        .font(.caption2)
                        .foregroundColor(color.opacity(0.9))
                } else {
                    Text(formatTime(currentTime))
                        .font(.caption2)
                        .foregroundColor(color.opacity(0.7))
                        .monospacedDigit()
                }

                Spacer()

                if !isLoading {
                    Text(formatTime(duration))
                        .font(.caption2)
                        .foregroundColor(color.opacity(0.7))
                        .monospacedDigit()
                }
            }
        }
    }
}
