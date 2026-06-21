import SwiftUI

// MARK: - AuthView — onboarding / sign-in (canon §3.1)

struct AuthView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm: AuthViewModel
    @State private var didLoad = false

    init() {
        _vm = StateObject(wrappedValue: AuthViewModel(backend: MockBackend()))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer().frame(height: 24)
                VStack(spacing: 6) {
                    WYDLogo(size: 44)
                    Text(vm.mode == .signIn ? "WYD tonight?" : "Make your account")
                        .font(WYDFont.displaySemibold(18))
                        .foregroundColor(.wydMuted)
                }
                .padding(.bottom, 4)

                modeToggle

                VStack(spacing: 12) {
                    if vm.mode == .signUp {
                        field("Your name", text: $vm.displayName, icon: "person")
                        field("Username (lowercase)", text: $vm.username, icon: "at",
                              autocaps: false)
                    }
                    field("Email", text: $vm.email, icon: "envelope",
                          keyboard: .emailAddress, autocaps: false)
                    secureField("Password", text: $vm.password, icon: "lock")

                    if vm.mode == .signUp {
                        birthYearPicker
                        interestPicker
                        ageGate
                    }
                }

                if let err = vm.errorMessage {
                    Text(err)
                        .font(WYDFont.bodyMedium(14))
                        .foregroundColor(.wydDanger)
                        .multilineTextAlignment(.center)
                }

                PrimaryButton(
                    title: vm.mode == .signIn ? "Tap in" : "Create account",
                    systemImage: "bolt.fill",
                    isLoading: vm.isLoading,
                    isEnabled: vm.canSubmit
                ) {
                    Task { await vm.submit() }
                }

                if vm.mode == .signIn {
                    Button("Forgot password?") { Task { await vm.resetPassword() } }
                        .font(WYDFont.bodyMedium(14))
                        .foregroundColor(.wydMuted)
                }

                Text("By tapping in you confirm you're 13+ and agree to keep it chill.\nDemo content is fictional.")
                    .font(WYDFont.bodyMedium(12))
                    .foregroundColor(.wydMuted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 32)
        }
        .background(WYDBackground())
        .task {
            guard !didLoad else { return }
            didLoad = true
            vm.rebind(appState.backend)
            await vm.loadInterests()
        }
    }

    // MARK: Pieces

    private var modeToggle: some View {
        HStack(spacing: 0) {
            toggleButton("Sign in", .signIn)
            toggleButton("Sign up", .signUp)
        }
        .padding(4)
        .background(Capsule().fill(Color.wydSurface2))
    }

    private func toggleButton(_ title: String, _ m: AuthViewModel.Mode) -> some View {
        Button { withAnimation { vm.mode = m } } label: {
            Text(title)
                .font(WYDFont.bodySemibold(15))
                .foregroundColor(vm.mode == m ? .white : .wydMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(vm.mode == m ? AnyShapeStyle(LinearGradient.cityNight) : AnyShapeStyle(Color.clear))
                )
        }
        .buttonStyle(.plain)
    }

    private var birthYearPicker: some View {
        HStack {
            Label("Birth year", systemImage: "calendar").foregroundColor(.wydMuted)
            Spacer()
            Picker("Birth year", selection: $vm.birthYear) {
                ForEach(vm.birthYearOptions, id: \.self) { y in
                    Text(String(y)).tag(y)
                }
            }
            .tint(.wydBrand)
        }
        .font(WYDFont.body(15))
        .padding(.horizontal, 14).padding(.vertical, 6)
        .wydCardBackground(.wydSurface2)
    }

    private var interestPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick your interests")
                .font(WYDFont.bodyMedium(13)).foregroundColor(.wydMuted)
            FlowChips(tags: vm.interestTags, selected: vm.selectedInterests) { id in
                vm.toggleInterest(id)
            }
        }
    }

    private var ageGate: some View {
        Button { vm.ageConfirmed.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: vm.ageConfirmed ? "checkmark.square.fill" : "square")
                    .foregroundColor(vm.ageConfirmed ? .wydBrand : .wydMuted)
                Text("I'm a high-schooler (13–18) in the Chicago area.")
                    .font(WYDFont.bodyMedium(13))
                    .foregroundColor(.wydText)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Field helpers

    private func field(_ placeholder: String, text: Binding<String>, icon: String,
                       keyboard: UIKeyboardType = .default, autocaps: Bool = true) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(.wydMuted).frame(width: 20)
            TextField(placeholder, text: text)
                .font(WYDFont.body(16)).foregroundColor(.wydText)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocaps ? .sentences : .never)
                .autocorrectionDisabled(!autocaps)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .wydCardBackground(.wydSurface2)
    }

    private func secureField(_ placeholder: String, text: Binding<String>, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(.wydMuted).frame(width: 20)
            SecureField(placeholder, text: text)
                .font(WYDFont.body(16)).foregroundColor(.wydText)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .wydCardBackground(.wydSurface2)
    }
}

// MARK: - FlowChips — wrapping selectable interest chips

struct FlowChips: View {
    let tags: [Tag]
    let selected: Set<String>
    let onTap: (String) -> Void

    var body: some View {
        // Simple wrapping layout using a LazyVGrid of adaptive columns.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .leading)],
                  alignment: .leading, spacing: 8) {
            ForEach(tags) { tag in
                ChipView(label: tag.label, emoji: tag.emoji,
                         isSelected: selected.contains(tag.id),
                         accent: Color(hex: tag.color)) {
                    onTap(tag.id)
                }
            }
        }
    }
}

#Preview("Auth") {
    AuthView()
        .environmentObject(AppState(backend: MockBackend.loggedOut()))
        .preferredColorScheme(.dark)
}
