import SwiftUI

/// A text view that scrolls horizontally when content exceeds available width
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    /// Explicit point size used for height calculation.
    /// When nil, falls back to semantic-font lookup.
    private let explicitSize: CGFloat?

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animating = false

    private let scrollSpeed: Double = 30
    private let pauseDuration: Double = 2.0

    /// Semantic font initialiser (unchanged API).
    init(_ text: String, font: Font = .body, color: Color = .primary) {
        self.text = text
        self.font = font
        self.color = color
        self.explicitSize = nil
    }

    /// Explicit-size initialiser for scaled layouts.
    init(_ text: String, font: Font, size: CGFloat, color: Color = .primary) {
        self.text = text
        self.font = font
        self.color = color
        self.explicitSize = size
    }

    var body: some View {
        GeometryReader { geometry in
            let needsScroll = textWidth > geometry.size.width

            ZStack(alignment: .leading) {
                if needsScroll {
                    scrollingText
                        .onAppear {
                            containerWidth = geometry.size.width
                            startAnimation()
                        }
                        .onChange(of: text) { _ in
                            resetAnimation()
                        }
                } else {
                    staticText
                }
            }
            .frame(width: geometry.size.width, alignment: .leading)
            .clipped()
        }
        .frame(height: textHeight)
        .accessibilityLabel(text)
    }

    private var staticText: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .lineLimit(1)
            .background(
                GeometryReader { proxy in
                    Color.clear.onAppear {
                        textWidth = proxy.size.width
                    }
                }
            )
    }

    private var scrollingText: some View {
        HStack(spacing: 50) {
            Text(text)
                .font(font)
                .foregroundColor(color)
                .lineLimit(1)
                .fixedSize()

            Text(text)
                .font(font)
                .foregroundColor(color)
                .lineLimit(1)
                .fixedSize()
        }
        .background(
            GeometryReader { proxy in
                Color.clear.onAppear {
                    textWidth = (proxy.size.width - 50) / 2
                }
            }
        )
        .offset(x: offset)
    }

    private var textHeight: CGFloat {
        if let size = explicitSize {
            // UIFont gives the true line height for a given point size.
            return UIFont.systemFont(ofSize: size).lineHeight
        }
        // Fallback: map semantic Font → UIFont text style.
        let uiFont: UIFont
        switch font {
        case .title2:      uiFont = UIFont.preferredFont(forTextStyle: .title2)
        case .title3:      uiFont = UIFont.preferredFont(forTextStyle: .title3)
        case .headline:    uiFont = UIFont.preferredFont(forTextStyle: .headline)
        case .subheadline: uiFont = UIFont.preferredFont(forTextStyle: .subheadline)
        default:           uiFont = UIFont.preferredFont(forTextStyle: .body)
        }
        return uiFont.lineHeight
    }

    private func startAnimation() {
        guard textWidth > containerWidth else { return }
        animating = true

        let scrollDistance = textWidth + 50
        let duration = scrollDistance / scrollSpeed

        DispatchQueue.main.asyncAfter(deadline: .now() + pauseDuration) {
            guard animating else { return }
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                offset = -scrollDistance
            }
        }
    }

    private func resetAnimation() {
        animating = false
        offset = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startAnimation()
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        MarqueeText("Short text", font: .title2, color: .white)
            .frame(width: 200)
            .background(Color.gray)

        MarqueeText("This is a very long text that should scroll because it exceeds the container width", font: .title2, color: .white)
            .frame(width: 200)
            .background(Color.gray)
    }
    .padding()
}
