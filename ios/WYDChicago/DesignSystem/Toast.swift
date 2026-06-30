import SwiftUI

// MARK: - Toast — lightweight animated banner
//
// Usage: keep a `@State var toast: ToastData?` and attach `.wydToast($toast)`.
// Set it to show; it slides in from the top and auto-dismisses.

struct ToastData: Equatable, Identifiable {
    var id = UUID()
    var text: String
    var icon: String
    var tint: Color

    static func success(_ text: String) -> ToastData {
        .init(text: text, icon: "checkmark.circle.fill", tint: .wydSuccess)
    }
    static func info(_ text: String) -> ToastData {
        .init(text: text, icon: "sparkles", tint: .wydBrand)
    }
    static func warning(_ text: String) -> ToastData {
        .init(text: text, icon: "exclamationmark.triangle.fill", tint: .wydGold)
    }
}

private struct ToastBanner: View {
    let data: ToastData

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: data.icon)
                .foregroundColor(data.tint)
            Text(data.text)
                .font(WYDFont.bodySemibold(15))
                .foregroundColor(.wydText)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule().fill(Color.wydSurface2)
        )
        .overlay(Capsule().stroke(Color.wydBorder, lineWidth: 1))
        .wydCardShadow()
        .padding(.top, 8)
        .padding(.horizontal, 24)
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: ToastData?
    var duration: Double = 2.2

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast {
                ToastBanner(data: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                        withAnimation(WYDMotion.smooth) { self.toast = nil }
                    }
                    .onTapGesture {
                        withAnimation(WYDMotion.snappy) { self.toast = nil }
                    }
            }
        }
        .animation(WYDMotion.smooth, value: toast)
    }
}

extension View {
    /// Attach a top-anchored auto-dismissing toast bound to an optional `ToastData`.
    func wydToast(_ toast: Binding<ToastData?>, duration: Double = 2.2) -> some View {
        modifier(ToastModifier(toast: toast, duration: duration))
    }
}

#Preview("Toast") {
    struct Demo: View {
        @State private var toast: ToastData?
        var body: some View {
            ZStack {
                WYDBackground()
                VStack(spacing: 12) {
                    PrimaryButton(title: "Show success") { toast = .success("You're going 🎉") }
                    SecondaryButton(title: "Show info") { toast = .info("Saved to your list") }
                }
                .padding(.horizontal, 40)
            }
            .wydToast($toast)
            .preferredColorScheme(.dark)
        }
    }
    return Demo()
}
