import SwiftUI

extension Color {
    // Colors are defined in Assets.xcassets (XonoraPurple, XonoraBlue, XonoraCyan)
    // They are automatically available as Color.xonoraPurple, Color.xonoraBlue, Color.xonoraCyan

    static var xonoraGradient: LinearGradient {
        LinearGradient(
            colors: [.xonoraPurple, .xonoraBlue, .xonoraCyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var xonoraGradientHorizontal: LinearGradient {
        LinearGradient(
            colors: [.xonoraPurple, .xonoraBlue, .xonoraCyan],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
