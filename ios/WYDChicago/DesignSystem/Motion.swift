import SwiftUI

// MARK: - Motion (the app's animation language)
//
// One place for every spring, curve, and reusable motion modifier so the whole
// app moves with the same personality: quick, bouncy, "city at night" energy.
// iOS 16+ compatible (no PhaseAnimator / iOS 17 APIs).

enum WYDMotion {
    /// Default snappy spring for taps, toggles, and selections.
    static let snappy   = Animation.spring(response: 0.34, dampingFraction: 0.74)
    /// Softer spring for entrances and layout settles.
    static let smooth   = Animation.spring(response: 0.5,  dampingFraction: 0.82)
    /// Playful overshoot for celebratory beats (vote, RSVP, success).
    static let bouncy   = Animation.spring(response: 0.42, dampingFraction: 0.55)
    /// Plain ease for fades.
    static let fade     = Animation.easeInOut(duration: 0.28)

    /// Staggered entrance delay (clamped) — used so list items cascade in.
    static func stagger(_ index: Int, step: Double = 0.06, max: Double = 0.5) -> Double {
        Swift.min(Double(index) * step, max)
    }
}

// MARK: - CountUpText: animates an integer ticking up to its value

/// A number that counts up to `value` when it first appears (or when `value`
/// changes inside an animation). Style it like any Text via modifiers.
struct CountUpText: View, Animatable {
    var value: Double
    var suffix: String = ""

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))\(suffix)")
            .monospacedDigit()
    }
}

/// Counts up from 0 → `target` on appear.
struct CountUp: View {
    let target: Int
    var suffix: String = ""
    var duration: Double = 0.9
    @State private var shown: Double = 0

    var body: some View {
        CountUpText(value: shown, suffix: suffix)
            .onAppear {
                shown = 0
                withAnimation(.easeOut(duration: duration)) { shown = Double(target) }
            }
            .onChange(of: target) { new in
                withAnimation(.easeOut(duration: duration)) { shown = Double(new) }
            }
    }
}

// MARK: - Reusable transitions

extension AnyTransition {
    /// Fields that appear/disappear when switching sign-in ↔ sign-up.
    static var signUpField: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        )
    }
}

// MARK: - Appear: slide-up + fade entrance, with optional stagger delay

private struct AppearModifier: ViewModifier {
    let delay: Double
    let yOffset: CGFloat
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : yOffset)
            .onAppear {
                withAnimation(WYDMotion.smooth.delay(delay)) { shown = true }
            }
    }
}

extension View {
    /// Fade + rise into place. Pass a delay (e.g. `WYDMotion.stagger(i)`) to cascade.
    func appear(delay: Double = 0, yOffset: CGFloat = 16) -> some View {
        modifier(AppearModifier(delay: delay, yOffset: yOffset))
    }
}

// MARK: - Pressable: scale + dim on touch-down (use as a ButtonStyle)

struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(WYDMotion.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

// MARK: - Shake: horizontal wobble driven by an animatable count (error feedback)

struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 8
    var shakes: CGFloat = 3
    var animatableData: CGFloat   // bump this to trigger

    func effectValue(size: CGSize) -> ProjectionTransform {
        let dx = travel * sin(animatableData * .pi * shakes)
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: 0))
    }
}

extension View {
    /// Shake whenever `trigger` changes. Drive `trigger` from an Int you bump on error.
    func shake(_ trigger: Int) -> some View {
        modifier(ShakeTrigger(trigger: trigger))
    }
}

private struct ShakeTrigger: ViewModifier {
    var trigger: Int
    @State private var amount: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .modifier(ShakeEffect(animatableData: amount))
            .onChange(of: trigger) { _ in
                amount = 0
                withAnimation(.linear(duration: 0.45)) { amount = 1 }
            }
    }
}

// MARK: - Shimmer: a sweeping highlight for skeleton / loading states

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, .white.opacity(0.35), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.6)
                .offset(x: phase * geo.size.width * 1.6)
                .blendMode(.plusLighter)
            }
            .mask(content)
            .allowsHitTesting(false)
        )
        .onAppear {
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}

// MARK: - Pulsing neon glow (for the primary CTA / live elements)

private struct PulseGlowModifier: ViewModifier {
    var color: Color
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(on ? 0.55 : 0.25),
                    radius: on ? 22 : 12, x: 0, y: 8)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

extension View {
    func pulseGlow(_ color: Color = .wydBrand) -> some View {
        modifier(PulseGlowModifier(color: color))
    }
}

// MARK: - AuroraBackground: slow-drifting "city night" orbs behind content

/// Animated ambient background — three blurred gradient orbs that breathe and
/// drift. Used on the launch + auth screens for a premium, alive feel.
struct AuroraBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Color.wydBg

            orb(.wydBrand, size: 360)
                .offset(x: animate ? -120 : -80, y: animate ? -220 : -300)
            orb(.wydBrand2, size: 320)
                .offset(x: animate ? 140 : 90, y: animate ? -60 : 20)
            orb(.wydAccent, size: 300)
                .offset(x: animate ? -90 : -140, y: animate ? 260 : 320)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }

    private func orb(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(0.35)
            .blur(radius: 90)
    }
}

#Preview("Aurora") {
    ZStack {
        AuroraBackground()
        VStack(spacing: 20) {
            WYDLogo(size: 44)
            PrimaryButton(title: "Tap in", systemImage: "bolt.fill") {}
                .padding(.horizontal, 40)
        }
    }
    .preferredColorScheme(.dark)
}
