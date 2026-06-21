import SwiftUI

// MARK: - Color tokens (canon §2 — DARK-FIRST). Use these EXACT hex values.

extension Color {
    /// Hex initializer supporting "#RRGGBB" and "#RRGGBBAA".
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b, a: Double
        switch s.count {
        case 6:
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
            a = 1
        case 8:
            r = Double((value & 0xFF000000) >> 24) / 255
            g = Double((value & 0x00FF0000) >> 16) / 255
            b = Double((value & 0x0000FF00) >> 8) / 255
            a = Double(value & 0x000000FF) / 255
        default:
            r = 0; g = 0; b = 0; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    // App background, near-black indigo
    static let wydBg        = Color(hex: "#0B0B12")
    // Cards
    static let wydSurface   = Color(hex: "#15151F")
    // Raised / inputs / chips
    static let wydSurface2  = Color(hex: "#1E1E2C")
    // Hairlines
    static let wydBorder    = Color(hex: "#2A2A3A")
    // Primary text
    static let wydText      = Color(hex: "#F5F5FA")
    // Secondary text
    static let wydMuted     = Color(hex: "#9A9AB0")
    // Primary — electric Chicago-sky blue
    static let wydBrand     = Color(hex: "#5B8CFF")
    // Secondary — electric purple (gradients)
    static let wydBrand2    = Color(hex: "#C44CFF")
    // Hot pink/red — CTAs, votes, the Chicago-star nod
    static let wydAccent    = Color(hex: "#FF4D6D")
    // Highlights, upvotes, "featured"
    static let wydGold      = Color(hex: "#FFC83D")
    // Going / confirmed
    static let wydSuccess   = Color(hex: "#2EE6A6")
    // Cancel / report
    static let wydDanger    = Color(hex: "#FF5A5A")
}

// MARK: - Signature gradient ("city night")

extension LinearGradient {
    /// linear-gradient(135deg, #5B8CFF 0%, #C44CFF 55%, #FF4D6D 100%)
    /// 135deg in CSS == top-left → bottom-right.
    static let cityNight = LinearGradient(
        stops: [
            .init(color: .wydBrand,  location: 0.0),
            .init(color: .wydBrand2, location: 0.55),
            .init(color: .wydAccent, location: 1.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Shape & radii (canon §2)

enum WYDRadius {
    /// cards/sheets
    static let card: CGFloat = 20
    /// buttons/inputs
    static let button: CGFloat = 14
    /// chips/pills
    static let pill: CGFloat = 999
}

extension View {
    /// Neon glow reserved for the primary CTA: 0 8px 30px rgba(91,140,255,.35)
    func wydPrimaryGlow() -> some View {
        shadow(color: Color.wydBrand.opacity(0.35), radius: 15, x: 0, y: 8)
    }

    /// Soft card shadow.
    func wydCardShadow() -> some View {
        shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
    }

    /// Standard hairline-bordered surface card.
    func wydCardBackground(_ fill: Color = .wydSurface) -> some View {
        background(
            RoundedRectangle(cornerRadius: WYDRadius.card, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: WYDRadius.card, style: .continuous)
                .stroke(Color.wydBorder, lineWidth: 1)
        )
    }
}

// MARK: - Chicago six-pointed star (flag star) — reusable Shape

/// A six-pointed star matching the Chicago flag motif, used as the logo accent.
struct ChicagoStar: Shape {
    /// Ratio of the inner radius to the outer radius.
    var innerRatio: CGFloat = 0.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        let points = 6
        // Start pointing up.
        var angle = -CGFloat.pi / 2
        let step = CGFloat.pi / CGFloat(points)
        for i in 0..<(points * 2) {
            let radius = (i % 2 == 0) ? outer : inner
            let pt = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            angle += step
        }
        path.closeSubpath()
        return path
    }
}
