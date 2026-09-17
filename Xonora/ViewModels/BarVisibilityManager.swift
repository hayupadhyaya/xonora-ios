import SwiftUI

struct ScrollData: Equatable {
    let offset: CGFloat
    let maxOffset: CGFloat
}

extension View {
    func trackScrollForBars(_ barManager: BarVisibilityManager) -> some View {
        self.onScrollGeometryChange(for: ScrollData.self) { geo in
            let offset = geo.contentOffset.y + geo.contentInsets.top
            let maxOffset = max(0, geo.contentSize.height - geo.containerSize.height)
            return ScrollData(offset: offset, maxOffset: maxOffset)
        } action: { _, newValue in
            barManager.scrolled(offset: newValue.offset, maxOffset: newValue.maxOffset)
        }
    }
}

@Observable
final class BarVisibilityManager {
    var barsCompact = false

    private var lastOffset: CGFloat = 0
    private var accumulatedDelta: CGFloat = 0
    private var lastDirection: ScrollDirection = .none
    private var pendingStateChange: Bool? = nil
    private let compactThreshold: CGFloat = 80
    private let expandThreshold: CGFloat = 60
    private let bottomBuffer: CGFloat = 200

    private enum ScrollDirection {
        case up, down, none
    }

    func scrolled(offset: CGFloat, maxOffset: CGFloat) {
        // At top of scroll, always show bars
        guard offset > 0 else {
            if barsCompact {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    barsCompact = false
                }
            }
            lastOffset = offset
            accumulatedDelta = 0
            lastDirection = .none
            pendingStateChange = nil
            return
        }

        let delta = offset - lastOffset
        lastOffset = offset

        // Determine direction
        let direction: ScrollDirection = delta > 0 ? .down : (delta < 0 ? .up : .none)
        guard direction != .none else { return }

        // Reset accumulation when scrolling up (we don't expand on scroll up)
        if direction == .up {
            accumulatedDelta = 0
            lastDirection = .none
            pendingStateChange = nil
            return
        }

        // Only handle downward scrolling for compacting
        if direction == .down {
            lastDirection = direction
            accumulatedDelta += delta

            // Check if near bottom (prevent expanding due to rubber band bounce)
            let nearBottom = maxOffset > 0 && offset >= maxOffset - bottomBuffer

            // Compact on scroll down, but not near bottom
            if accumulatedDelta > compactThreshold && !barsCompact && !nearBottom && pendingStateChange != true {
                pendingStateChange = true
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    barsCompact = true
                }
            }
        }
    }

    func resetBars() {
        guard barsCompact else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            barsCompact = false
        }
        accumulatedDelta = 0
        lastDirection = .none
        pendingStateChange = nil
    }
}
