import SwiftUI

// MARK: - SplashView — animated launch screen
//
// Plays a short, self-contained intro: an aurora fades up, the Chicago star
// draws itself and spins into place, the wordmark snaps in, then the whole
// thing hands off to the app via `onFinish`. Pure SwiftUI, no assets needed.

struct SplashView: View {
    var onFinish: () -> Void = {}

    @State private var starIn = false
    @State private var wordmarkIn = false
    @State private var tagline = false
    @State private var ring = false
    @State private var leaving = false

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 18) {
                ZStack {
                    // Expanding glow ring behind the star.
                    Circle()
                        .stroke(LinearGradient.cityNight, lineWidth: 3)
                        .frame(width: 120, height: 120)
                        .scaleEffect(ring ? 1.8 : 0.4)
                        .opacity(ring ? 0 : 0.9)

                    ChicagoStar()
                        .fill(LinearGradient.cityNight)
                        .frame(width: 88, height: 88)
                        .rotationEffect(.degrees(starIn ? 0 : -120))
                        .scaleEffect(starIn ? 1 : 0.2)
                        .opacity(starIn ? 1 : 0)
                        .pulseGlow(.wydBrand2)
                }

                Text("WYD")
                    .font(WYDFont.displayBold(56))
                    .foregroundStyle(LinearGradient.cityNight)
                    .opacity(wordmarkIn ? 1 : 0)
                    .scaleEffect(wordmarkIn ? 1 : 0.7)

                Text("CHICAGO")
                    .font(WYDFont.bodySemibold(15))
                    .tracking(8)
                    .foregroundColor(.wydMuted)
                    .opacity(tagline ? 1 : 0)
                    .offset(y: tagline ? 0 : 8)
            }
            .scaleEffect(leaving ? 1.15 : 1)
            .opacity(leaving ? 0 : 1)
        }
        .task { await run() }
    }

    private func run() async {
        withAnimation(WYDMotion.bouncy) { starIn = true }
        withAnimation(.easeOut(duration: 1.1)) { ring = true }
        try? await Task.sleep(nanoseconds: 260_000_000)
        withAnimation(WYDMotion.snappy) { wordmarkIn = true }
        try? await Task.sleep(nanoseconds: 180_000_000)
        withAnimation(WYDMotion.smooth) { tagline = true }
        try? await Task.sleep(nanoseconds: 800_000_000)
        withAnimation(.easeIn(duration: 0.45)) { leaving = true }
        try? await Task.sleep(nanoseconds: 420_000_000)
        onFinish()
    }
}

#Preview("Splash") {
    SplashView()
        .preferredColorScheme(.dark)
}
