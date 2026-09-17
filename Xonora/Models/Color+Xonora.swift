import SwiftUI

extension Color {
    // Asset colors with fallback for platforms where assets may not load
    private static let xonoraPurpleValue = Color(red: 0.6, green: 0.2, blue: 0.8)
    private static let xonoraBlueValue = Color(red: 0.2, green: 0.4, blue: 1.0)
    private static let xonoraCyanValue = Color(red: 0.0, green: 0.8, blue: 1.0)

    static var xonoraGradient: LinearGradient {
        LinearGradient(
            colors: [xonoraPurpleValue, xonoraBlueValue, xonoraCyanValue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var xonoraGradientHorizontal: LinearGradient {
        LinearGradient(
            colors: [xonoraPurpleValue, xonoraBlueValue, xonoraCyanValue],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
