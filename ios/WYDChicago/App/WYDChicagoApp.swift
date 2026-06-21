import SwiftUI

// MARK: - App entry point
//
// Dark-first (canon §2). Uses MockBackend by default so it runs with zero
// external deps. To go live: add the Firebase SPM packages, drop in
// GoogleService-Info.plist, uncomment the FirebaseApp.configure() block below,
// and construct AppState(backend: FirebaseBackend()). See ios/README.md.

@main
struct WYDChicagoApp: App {

    @StateObject private var appState: AppState

    init() {
        // --- Firebase bootstrap (uncomment after adding Firebase via SPM) ---
        // FirebaseApp.configure()
        // _appState = StateObject(wrappedValue: AppState(backend: FirebaseBackend()))

        // Mock-backed by default (no Firebase needed):
        _appState = StateObject(wrappedValue: AppState(backend: MockBackend()))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .tint(.wydBrand)
                .preferredColorScheme(.dark)   // dark-first
        }
    }
}
