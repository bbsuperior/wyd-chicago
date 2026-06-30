import SwiftUI

// MARK: - Root tabs (canon §3: Feed · Search · ➕ (host/admin) · Friends · Profile)

enum RootTab: Hashable {
    case feed, search, create, friends, profile
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showAssistant = false

    var body: some View {
        Group {
            if appState.isSignedIn {
                mainTabs
                    .overlay(alignment: .bottomTrailing) {
                        AssistantFab { showAssistant = true }
                            .padding(.trailing, 16)
                            .padding(.bottom, 70)   // clear the tab bar
                    }
                    .sheet(isPresented: $showAssistant) {
                        AssistantView().environmentObject(appState)
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)),
                        removal: .opacity
                    ))
            } else {
                AuthView()
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .scale(scale: 1.04))
                    ))
            }
        }
        .background(WYDBackground())
        .animation(WYDMotion.smooth, value: appState.isSignedIn)
    }

    private var mainTabs: some View {
        TabView(selection: $appState.selectedTab) {
            NavigationStack {
                FeedView()
            }
            .tabItem { Label("Feed", systemImage: "bolt.fill") }
            .tag(RootTab.feed)

            NavigationStack {
                FeedView(startInSearch: true)
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(RootTab.search)

            // ➕ Create — host/admin only (canon §3).
            if appState.isHost {
                NavigationStack {
                    AdminView(startOnCreate: true)
                }
                .tabItem { Label("Create", systemImage: "plus.circle.fill") }
                .tag(RootTab.create)
            }

            NavigationStack {
                FriendsView()
            }
            .tabItem { Label("Friends", systemImage: "person.2.fill") }
            .tag(RootTab.friends)

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
            .tag(RootTab.profile)
        }
        .tint(.wydBrand)
    }
}

// MARK: - Floating "Ask WYD AI" button

struct AssistantFab: View {
    let action: () -> Void
    @State private var appeared = false

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(LinearGradient.cityNight))
        }
        .buttonStyle(.pressable)
        .pulseGlow(.wydBrand2)
        .scaleEffect(appeared ? 1 : 0.2)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(WYDMotion.bouncy.delay(0.4)) { appeared = true } }
        .accessibilityLabel("Ask WYD AI")
    }
}

#Preview("Signed in — teen") {
    RootView()
        .environmentObject(AppState(backend: MockBackend()))
        .preferredColorScheme(.dark)
}

#Preview("Signed in — admin") {
    RootView()
        .environmentObject(AppState(backend: MockBackend.signedInAsAdmin()))
        .preferredColorScheme(.dark)
}

#Preview("Logged out") {
    RootView()
        .environmentObject(AppState(backend: MockBackend.loggedOut()))
        .preferredColorScheme(.dark)
}
