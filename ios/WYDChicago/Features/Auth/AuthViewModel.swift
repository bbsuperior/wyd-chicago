import SwiftUI

// MARK: - AuthViewModel — sign up / sign in / verify gate (canon §3.1, §8)

@MainActor
final class AuthViewModel: ObservableObject {

    enum Mode { case signIn, signUp }

    @Published var mode: Mode = .signIn

    // Shared fields
    @Published var email = ""
    @Published var password = ""

    // Sign-up fields
    @Published var displayName = ""
    @Published var username = ""
    @Published var birthYear = 2008
    @Published var selectedInterests: Set<String> = []
    @Published var ageConfirmed = false

    @Published var interestTags: [Tag] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var backend: Backend
    init(backend: Backend) { self.backend = backend }
    func rebind(_ backend: Backend) { self.backend = backend }

    /// Birth-year options for a teen audience (ages ~14–18).
    var birthYearOptions: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 18)...(current - 13)).reversed()
    }

    func loadInterests() async {
        if interestTags.isEmpty {
            let all = (try? await backend.listTags()) ?? []
            interestTags = all.filter { $0.kind == .interest }
        }
    }

    var canSubmit: Bool {
        switch mode {
        case .signIn:
            return !email.isEmpty && password.count >= 6
        case .signUp:
            let unameOK = username.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil
            return !email.isEmpty && password.count >= 6
                && !displayName.isEmpty && unameOK && ageConfirmed
        }
    }

    func toggleInterest(_ id: String) {
        if selectedInterests.contains(id) { selectedInterests.remove(id) }
        else { selectedInterests.insert(id) }
    }

    func submit() async {
        guard canSubmit else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            switch mode {
            case .signIn:
                _ = try await backend.signIn(email: email, password: password)
            case .signUp:
                _ = try await backend.signUp(SignUpInput(
                    email: email,
                    password: password,
                    username: username.lowercased(),
                    displayName: displayName,
                    birthYear: birthYear,
                    interests: Array(selectedInterests)
                ))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetPassword() async {
        guard !email.isEmpty else {
            errorMessage = "Type your email first."
            return
        }
        do {
            try await backend.resetPassword(email: email)
            errorMessage = "Check your email for a reset link."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
