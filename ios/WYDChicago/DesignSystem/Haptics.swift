import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Haptics — tiny wrapper so feedback reads the same everywhere
//
// No-ops cleanly on platforms without UIKit haptics (previews, macOS).

enum Haptics {

    static func tap() { impact(.light) }
    static func select() { impact(.soft) }
    static func bump() { impact(.medium) }

    static func success() { notify(.success) }
    static func warning() { notify(.warning) }
    static func error() { notify(.error) }

    #if canImport(UIKit)
    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.prepare()
        gen.impactOccurred()
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
    #else
    private static func impact(_ style: Int = 0) {}
    private static func notify(_ type: Int = 0) {}
    #endif
}

// MARK: - Fire a haptic whenever a value changes

extension View {
    /// Run a haptic each time `value` changes (skips the initial render).
    func haptic<V: Equatable>(on value: V, _ feedback: @escaping () -> Void) -> some View {
        onChange(of: value) { _ in feedback() }
    }
}
