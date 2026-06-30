import SwiftUI
import Foundation

// MARK: - Confetti — a celebratory burst, fired by bumping `trigger`
//
// Drop it in an overlay and increment `trigger` to fire (e.g. on RSVP "Going").
// Pure SwiftUI, self-contained, auto-clears. Honors Reduce Motion.

struct ConfettiView: View {
    var trigger: Int
    var colors: [Color] = [.wydBrand, .wydBrand2, .wydAccent, .wydGold, .wydSuccess]
    var count: Int = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pieces: [Piece] = []
    @State private var fired = false

    struct Piece: Identifiable {
        let id = UUID()
        let color: Color
        let dx: CGFloat
        let dy: CGFloat
        let size: CGFloat
        let spin: Double
        let isCircle: Bool
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { p in
                    Group {
                        if p.isCircle {
                            Circle().fill(p.color)
                        } else {
                            RoundedRectangle(cornerRadius: 1.5).fill(p.color)
                        }
                    }
                    .frame(width: p.size, height: p.isCircle ? p.size : p.size * 0.6)
                    .rotationEffect(.degrees(fired ? p.spin : 0))
                    .offset(x: fired ? p.dx : 0, y: fired ? p.dy : 0)
                    .opacity(fired ? 0 : 1)
                    .scaleEffect(fired ? 0.6 : 1)
                }
            }
            .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _ in burst() }
    }

    private func burst() {
        guard !reduceMotion else { return }
        pieces = (0..<count).map { _ in
            let angle = Double.random(in: 0..<(2 * .pi))
            let dist = CGFloat.random(in: 90...230)
            return Piece(
                color: colors.randomElement() ?? .wydBrand,
                dx: cos(angle) * dist,
                dy: sin(angle) * dist + CGFloat.random(in: 40...160), // gravity bias
                size: CGFloat.random(in: 7...13),
                spin: Double.random(in: -260...260),
                isCircle: Bool.random()
            )
        }
        fired = false
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 1.15)) { fired = true }
        }
    }
}

#Preview("Confetti") {
    struct Demo: View {
        @State private var t = 0
        var body: some View {
            ZStack {
                WYDBackground()
                ConfettiView(trigger: t)
                PrimaryButton(title: "Celebrate 🎉") { t += 1 }
                    .padding(.horizontal, 60)
            }
            .preferredColorScheme(.dark)
        }
    }
    return Demo()
}
