import SwiftUI
import Combine

// MARK: - AppState — session + selected backend service (the "service")
//
// Holds the single Backend instance the whole app talks to, and mirrors the
// signed-in user for easy access in views. Swap `MockBackend()` for
// `FirebaseBackend()` here (or via `useFirebase`) once Firebase is wired —
// see ios/README.md.

@MainActor
final class AppState: ObservableObject {

    /// The active backend service. App code uses this — never a concrete type.
    let backend: Backend

    /// The signed-in user, mirrored from the backend's auth stream.
    @Published private(set) var currentUser: UserProfile?

    /// Which tab is selected (so deep actions, like "create", can switch tabs).
    @Published var selectedTab: RootTab = .feed

    private var authUnsubscribe: (() -> Void)?

    // MARK: Init

    /// - Parameter backend: inject a backend. Pass `MockBackend()` (the default
    ///   used by `WYDChicagoApp`) so the app + previews run with zero external deps.
    init(backend: Backend) {
        self.backend = backend
        self.authUnsubscribe = backend.onAuthChange { [weak self] user in
            self?.currentUser = user
        }
    }

    deinit { authUnsubscribe?() }

    // MARK: Derived session helpers

    var isSignedIn: Bool { currentUser != nil }
    var isAdmin: Bool { currentUser?.isAdmin ?? false }
    var isHost: Bool { currentUser?.isHost ?? false }
    /// Email-verified gate (RSVP / vote require this — canon §8).
    var isVerified: Bool { currentUser?.emailVerified ?? false }

    func signOut() {
        Task { try? await backend.signOut() }
    }
}
