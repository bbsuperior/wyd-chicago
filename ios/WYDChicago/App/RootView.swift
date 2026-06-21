import SwiftUI

// MARK: - Root tabs (canon §3: Feed · Search · ➕ (host/admin) · Friends · Profile)

enum RootTab: Hashable {
    case feed, search, create, friends, profile
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.isSignedIn {
                mainTabs
            } else {
                AuthView()
            }
        }
        .background(WYDBackground())
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
