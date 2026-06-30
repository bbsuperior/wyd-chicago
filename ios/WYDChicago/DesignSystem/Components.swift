import SwiftUI

// MARK: - Reusable components (canon §2 design system)

// MARK: Logo wordmark — "WYD" gradient + Chicago star

struct WYDLogo: View {
    var size: CGFloat = 34
    var showCity: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("WYD")
                    .font(WYDFont.displayBold(size))
                    .foregroundStyle(LinearGradient.cityNight)
                ChicagoStar()
                    .fill(LinearGradient.cityNight)
                    .frame(width: size * 0.42, height: size * 0.42)
                    .offset(y: size * 0.04)
            }
            if showCity {
                Text("CHICAGO")
                    .font(WYDFont.bodyMedium(size * 0.3))
                    .tracking(size * 0.12)
                    .foregroundColor(.wydMuted)
            }
        }
    }
}

// MARK: PrimaryButton — gradient CTA with neon glow

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(WYDFont.bodySemibold(17))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: WYDRadius.button, style: .continuous)
                    .fill(LinearGradient.cityNight)
            )
        }
        .buttonStyle(.pressable)
        .opacity(isEnabled && !isLoading ? 1 : 0.5)
        .disabled(!isEnabled || isLoading)
        .animation(WYDMotion.snappy, value: isLoading)
        .animation(WYDMotion.snappy, value: isEnabled)
        .wydPrimaryGlow()
    }
}

// MARK: SecondaryButton — outlined surface button

struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    var tint: Color = .wydText
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(WYDFont.bodySemibold(16))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundColor(tint)
            .background(
                RoundedRectangle(cornerRadius: WYDRadius.button, style: .continuous)
                    .fill(Color.wydSurface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: WYDRadius.button, style: .continuous)
                    .stroke(Color.wydBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
    }
}

// MARK: ChipView — filter / tag pill

struct ChipView: View {
    let label: String
    var emoji: String?
    var isSelected: Bool = false
    var accent: Color = .wydBrand
    var action: (() -> Void)?

    var body: some View {
        let content = HStack(spacing: 5) {
            if let emoji { Text(emoji) }
            Text(label).font(WYDFont.bodyMedium(14))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundColor(isSelected ? .white : .wydText)
        .background(
            Capsule().fill(isSelected ? accent : Color.wydSurface2)
        )
        .overlay(
            Capsule().stroke(isSelected ? accent : Color.wydBorder, lineWidth: 1)
        )
        .scaleEffect(isSelected ? 1.06 : 1)
        .animation(WYDMotion.bouncy, value: isSelected)

        if let action {
            Button(action: action) { content }.buttonStyle(.pressable)
        } else {
            content
        }
    }
}

// MARK: AvatarView — single avatar with initials fallback

struct AvatarView: View {
    let user: UserProfile
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient.cityNight)
            Text(user.initials)
                .font(WYDFont.bodySemibold(size * 0.4))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.wydBg, lineWidth: 2))
    }
}

// MARK: AvatarStackView — overlapping "friends going" avatars

struct AvatarStackView: View {
    let users: [UserProfile]
    var size: CGFloat = 28
    var maxShown: Int = 4

    var body: some View {
        let shown = Array(users.prefix(maxShown))
        let extra = users.count - shown.count
        HStack(spacing: -size * 0.35) {
            ForEach(shown) { user in
                AvatarView(user: user, size: size)
            }
            if extra > 0 {
                ZStack {
                    Circle().fill(Color.wydSurface2)
                    Text("+\(extra)")
                        .font(WYDFont.bodySemibold(size * 0.34))
                        .foregroundColor(.wydText)
                }
                .frame(width: size, height: size)
                .overlay(Circle().stroke(Color.wydBg, lineWidth: 2))
            }
        }
    }
}

// MARK: VotePill — up/down vote control with score

struct VotePill: View {
    let upvotes: Int
    let downvotes: Int
    let myVote: VoteDir
    let onVote: (VoteDir) -> Void

    private var score: Int { upvotes - downvotes }

    var body: some View {
        HStack(spacing: 10) {
            Button { onVote(myVote == .up ? .none : .up) } label: {
                Image(systemName: myVote == .up ? "flame.fill" : "flame")
                    .foregroundColor(myVote == .up ? .wydGold : .wydMuted)
                    .scaleEffect(myVote == .up ? 1.25 : 1)
            }
            Text("\(score)")
                .font(WYDFont.bodySemibold(15))
                .foregroundColor(score >= 0 ? .wydText : .wydMuted)
                .frame(minWidth: 22)
                .contentTransition(.numericText())
            Button { onVote(myVote == .down ? .none : .down) } label: {
                Image(systemName: myVote == .down ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .foregroundColor(myVote == .down ? .wydAccent : .wydMuted)
                    .scaleEffect(myVote == .down ? 1.25 : 1)
            }
        }
        .buttonStyle(.plain)
        .animation(WYDMotion.bouncy, value: myVote)
        .animation(WYDMotion.snappy, value: score)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.wydSurface2))
        .overlay(Capsule().stroke(Color.wydBorder, lineWidth: 1))
    }
}

// MARK: EventCardView — the core feed cell

struct EventCardView: View {
    let event: Event
    var friendsGoing: [UserProfile] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover
            ZStack(alignment: .topLeading) {
                cover
                HStack(spacing: 6) {
                    if event.isFeatured {
                        badge("✨ Featured", color: .wydGold, filled: true)
                    }
                    badge(event.whenChip, color: .wydBrand, filled: false)
                }
                .padding(12)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(event.title)
                    .font(WYDFont.displaySemibold(20))
                    .foregroundColor(.wydText)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(event.approxArea, systemImage: "mappin.and.ellipse")
                    Text("·")
                    Text(event.startLabel)
                    Text("·")
                    Text(event.priceLabel)
                        .foregroundColor(event.isFree ? .wydSuccess : .wydText)
                }
                .font(WYDFont.bodyMedium(13))
                .foregroundColor(.wydMuted)

                HStack {
                    if !friendsGoing.isEmpty {
                        AvatarStackView(users: friendsGoing, size: 26)
                        Text(friendsGoing.count == 1
                             ? "\(friendsGoing[0].displayName.split(separator: " ").first.map(String.init) ?? "A friend") is going"
                             : "\(friendsGoing.count) friends going")
                            .font(WYDFont.bodyMedium(13))
                            .foregroundColor(.wydText)
                    } else {
                        Label("\(event.committedCount) going", systemImage: "person.2.fill")
                            .font(WYDFont.bodyMedium(13))
                            .foregroundColor(.wydMuted)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").foregroundColor(.wydGold)
                        Text("\(event.voteScore)")
                            .font(WYDFont.bodySemibold(14))
                            .foregroundColor(.wydText)
                    }
                }
            }
            .padding(14)
        }
        .wydCardBackground()
        .wydCardShadow()
    }

    private var cover: some View {
        ZStack {
            // Gradient placeholder when no image (mock has no real URLs).
            LinearGradient.cityNight.opacity(0.85)
            Image(systemName: coverSymbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: WYDRadius.card,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: WYDRadius.card,
                style: .continuous
            )
        )
    }

    private var coverSymbol: String {
        switch event.eventType {
        case "house-party": return "party.popper.fill"
        case "kickback": return "sofa.fill"
        case "concert": return "music.mic"
        case "game": return "basketball.fill"
        case "fundraiser": return "heart.fill"
        case "open-mic": return "music.note"
        default: return "sparkles"
        }
    }

    private func badge(_ text: String, color: Color, filled: Bool) -> some View {
        Text(text)
            .font(WYDFont.bodySemibold(12))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundColor(filled ? .black : .white)
            .background(
                Capsule().fill(filled ? color : Color.black.opacity(0.45))
            )
    }
}

// MARK: Background — city-night-tinted app background

struct WYDBackground: View {
    var body: some View {
        ZStack {
            Color.wydBg
            LinearGradient(
                colors: [Color.wydBrand.opacity(0.12), .clear],
                startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

// MARK: Empty state

struct EmptyStateView: View {
    var emoji: String = "🌃"
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Text(emoji).font(.system(size: 44))
            Text(title)
                .font(WYDFont.displaySemibold(20))
                .foregroundColor(.wydText)
            Text(subtitle)
                .font(WYDFont.body(15))
                .foregroundColor(.wydMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }
}

// MARK: Previews

#Preview("Components") {
    ScrollView {
        VStack(spacing: 16) {
            WYDLogo()
            PrimaryButton(title: "Tap in", systemImage: "bolt.fill") {}
            SecondaryButton(title: "Interested", systemImage: "star") {}
            HStack {
                ChipView(label: "Tonight", emoji: "🌙", isSelected: true) {}
                ChipView(label: "Concerts", emoji: "🎤") {}
            }
            VotePill(upvotes: 64, downvotes: 3, myVote: .up) { _ in }
        }
        .padding()
    }
    .background(WYDBackground())
    .preferredColorScheme(.dark)
}
