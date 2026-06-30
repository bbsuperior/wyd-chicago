import SwiftUI

// MARK: - ProfileView (canon §3.5)

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm: ProfileViewModel
    @State private var didLoad = false

    init() {
        _vm = StateObject(wrappedValue: ProfileViewModel(backend: MockBackend()))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let user = vm.user {
                    headerCard(user).appear(delay: 0.0, yOffset: 20)
                    if vm.needsVerification { verifyBanner.appear(delay: 0.06) }
                    if appState.isAdmin { adminLink.appear(delay: 0.10) }
                    socialRow(user).appear(delay: 0.14)
                    eventsSection(title: "Going to 🎟️", events: vm.goingEvents,
                                  empty: "You haven't tapped into anything yet.")
                        .appear(delay: 0.20)
                    eventsSection(title: "Saved 🔖", events: vm.savedEvents,
                                  empty: "Nothing saved. Bookmark events you're feeling.")
                        .appear(delay: 0.26)
                    settings.appear(delay: 0.32)
                } else {
                    ProgressView().tint(.wydBrand).padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(WYDBackground())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: String.self) { id in EventDetailView(eventId: id) }
        .refreshable { await vm.load() }
        .task {
            guard !didLoad else { return }
            didLoad = true
            vm.rebind(appState.backend)
            await vm.load()
        }
        .sheet(isPresented: $vm.editingProfile) { editSheet }
    }

    // MARK: Header

    private func headerCard(_ user: UserProfile) -> some View {
        VStack(spacing: 10) {
            AvatarView(user: user, size: 84)
            Text(user.displayName).font(WYDFont.displayBold(24)).foregroundColor(.wydText)
            Text("@\(user.username)").font(WYDFont.bodyMedium(15)).foregroundColor(.wydBrand)
            if !user.bio.isEmpty {
                Text(user.bio).font(WYDFont.body(15)).foregroundColor(.wydMuted)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 20) {
                statNum(vm.friendCount, "friends")
                statNum(vm.goingEvents.count, "going")
                stat(user.gradeYear ?? "—", "grade")
            }
            .padding(.top, 4)
            SecondaryButton(title: "Edit profile", systemImage: "pencil") {
                Haptics.tap(); vm.beginEdit()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .wydCardBackground()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(WYDFont.displaySemibold(18)).foregroundColor(.wydText)
            Text(label).font(WYDFont.bodyMedium(12)).foregroundColor(.wydMuted)
        }
    }

    private func statNum(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            CountUp(target: value)
                .font(WYDFont.displaySemibold(18))
                .foregroundColor(.wydText)
            Text(label).font(WYDFont.bodyMedium(12)).foregroundColor(.wydMuted)
        }
    }

    private var verifyBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Verify your email", systemImage: "envelope.badge")
                .font(WYDFont.bodySemibold(15)).foregroundColor(.wydGold)
            Text("You'll need a verified email to RSVP and vote. Check your inbox.")
                .font(WYDFont.body(13)).foregroundColor(.wydMuted)
            Button("Resend / verify now") {
                Haptics.success(); Task { await vm.resendVerification() }
            }
                .font(WYDFont.bodySemibold(14)).foregroundColor(.wydBrand)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .wydCardBackground(.wydSurface2)
        .pulseGlow(.wydGold)
    }

    private var adminLink: some View {
        NavigationLink {
            AdminView()
        } label: {
            HStack {
                Label("Master login — Admin dashboard", systemImage: "crown.fill")
                    .font(WYDFont.bodySemibold(15)).foregroundColor(.wydGold)
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.wydMuted)
            }
            .padding(14)
            .wydCardBackground(.wydSurface2)
        }
        .buttonStyle(.plain)
    }

    private func socialRow(_ user: UserProfile) -> some View {
        HStack(spacing: 10) {
            if let snap = user.snapchatUsername {
                socialChip("👻 @\(snap)", color: .wydGold)
            }
            if let insta = user.instagramUsername {
                socialChip("📸 @\(insta)", color: .wydAccent)
            }
            Spacer()
        }
    }

    private func socialChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(WYDFont.bodyMedium(13)).foregroundColor(.wydText)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(Color.wydSurface2))
            .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
    }

    private func eventsSection(title: String, events: [Event], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(WYDFont.displaySemibold(18)).foregroundColor(.wydText)
            if events.isEmpty {
                Text(empty).font(WYDFont.body(14)).foregroundColor(.wydMuted)
            } else {
                ForEach(events) { ev in
                    NavigationLink(value: ev.id) {
                        miniRow(ev)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    private func miniRow(_ ev: Event) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12).fill(LinearGradient.cityNight.opacity(0.85))
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(ev.title).font(WYDFont.bodySemibold(15)).foregroundColor(.wydText).lineLimit(1)
                Text("\(ev.whenChip) · \(ev.approxArea)")
                    .font(WYDFont.bodyMedium(12)).foregroundColor(.wydMuted)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.wydMuted)
        }
        .padding(10)
        .wydCardBackground(.wydSurface)
    }

    private var settings: some View {
        VStack(spacing: 10) {
            NavigationLink { GuidelinesView() } label: {
                settingRow("Community guidelines", icon: "shield.lefthalf.filled")
            }.buttonStyle(.plain)
            Button(role: .destructive) { vm.signOut() } label: {
                HStack {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(WYDFont.bodySemibold(15)).foregroundColor(.wydDanger)
                    Spacer()
                }
                .padding(14)
                .wydCardBackground(.wydSurface2)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private func settingRow(_ title: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon).font(WYDFont.bodyMedium(15)).foregroundColor(.wydText)
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.wydMuted)
        }
        .padding(14)
        .wydCardBackground(.wydSurface2)
    }

    // MARK: Edit sheet

    private var editSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    editField("Bio", text: $vm.editBio)
                    editField("Neighborhood", text: $vm.editNeighborhood)
                    editField("Snapchat", text: $vm.editSnap, autocaps: false)
                    editField("Instagram", text: $vm.editInsta, autocaps: false)
                    PrimaryButton(title: "Save", systemImage: "checkmark") {
                        Task { await vm.saveEdit() }
                    }
                }
                .padding(16)
            }
            .background(WYDBackground())
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { vm.editingProfile = false }.foregroundColor(.wydMuted)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func editField(_ label: String, text: Binding<String>, autocaps: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(WYDFont.bodyMedium(13)).foregroundColor(.wydMuted)
            TextField(label, text: text)
                .font(WYDFont.body(16)).foregroundColor(.wydText)
                .textInputAutocapitalization(autocaps ? .sentences : .never)
                .autocorrectionDisabled(!autocaps)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .wydCardBackground(.wydSurface2)
        }
    }
}

// MARK: - Community guidelines (canon §8 safety)

struct GuidelinesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Keep it chill 🤝")
                    .font(WYDFont.displayBold(24)).foregroundColor(.wydText)
                ForEach(guidelines, id: \.0) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.0).font(WYDFont.bodySemibold(16)).foregroundColor(.wydText)
                        Text(item.1).font(WYDFont.body(14)).foregroundColor(.wydMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .wydCardBackground(.wydSurface2)
                }
                Text("See something off? Hit report. Admins can pull events instantly.")
                    .font(WYDFont.bodyMedium(13)).foregroundColor(.wydMuted)
            }
            .padding(16)
        }
        .background(WYDBackground())
        .navigationTitle("Guidelines")
        .navigationBarTitleDisplayMode(.inline)
    }

    private let guidelines: [(String, String)] = [
        ("No harassment", "Be cool to people. Bullying, threats, or hate gets you removed."),
        ("No illegal stuff", "Don't promote drugs, weapons, or anything illegal. Period."),
        ("Hosts are accountable", "If you post an event, you're responsible for it being safe."),
        ("Respect privacy", "Exact addresses only show after RSVP. Don't share people's info."),
        ("Stay your age", "This is for high-schoolers (13–18) in the Chicago area.")
    ]
}

#Preview("Profile — teen") {
    NavigationStack { ProfileView() }
        .environmentObject(AppState(backend: MockBackend()))
        .preferredColorScheme(.dark)
}

#Preview("Profile — admin") {
    NavigationStack { ProfileView() }
        .environmentObject(AppState(backend: MockBackend.signedInAsAdmin()))
        .preferredColorScheme(.dark)
}
