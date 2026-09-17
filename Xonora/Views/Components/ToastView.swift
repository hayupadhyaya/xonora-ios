import SwiftUI

struct ToastView: View {
    let message: String
    let type: ToastType

    enum ToastType {
        case success
        case error
        case info

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            case .info: return .blue
            }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .font(.title3)
                .foregroundColor(type.color)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(2)

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal)
    }
}

@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var toast: ToastItem?

    struct ToastItem: Identifiable {
        let id = UUID()
        let message: String
        let type: ToastView.ToastType
    }

    private init() {}

    func show(_ message: String, type: ToastView.ToastType = .info) {
        toast = ToastItem(message: message, type: type)

        // Auto-dismiss after 3 seconds
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.toast?.id == toast?.id {
                self.toast = nil
            }
        }
    }

    func dismiss() {
        toast = nil
    }
}

struct ToastModifier: ViewModifier {
    @StateObject private var toastManager = ToastManager.shared

    func body(content: Content) -> some View {
        ZStack {
            content

            if let toast = toastManager.toast {
                VStack {
                    ToastView(message: toast.message, type: toast.type)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture {
                            toastManager.dismiss()
                        }

                    Spacer()
                }
                .zIndex(999)
                .animation(.spring(response: 0.3), value: toastManager.toast != nil)
            }
        }
    }
}

extension View {
    func toastView() -> some View {
        modifier(ToastModifier())
    }
}
