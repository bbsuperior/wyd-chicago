import SwiftUI

// MARK: - FriendsView (canon §3.6) — add by username, requests, friends list

struct FriendsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm: FriendsViewModel
    @State private var didLoad = false

    init() {
        _vm = StateObject(wrappedValue: FriendsViewModel(backend: MockBackend()))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                searchBar

                if !vm.searchResults.isEmpty {
                    section("Add friends") {
                        ForEach(vm.searchResults) { user in
                            personRow(user, trailing: {
                                Button { Task { await vm.addFriend(user) } } label: {
                                    Text("Add")
                                        .font(WYDFont.bodySemibold(14))
                                        .padding(.horizontal, 16).padding(.vertical, 8)
                                        .background(Capsule().fill(LinearGradient.cityNight))
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                            })
                        }
                    }
                }

                if !vm.requests.isEmpty {
                    section("Requests 👋") {
                        ForEach(vm.requests) { user in
                            personRow(user, trailing: {
                                HStack(spacing: 8) {
                                    Button { Task { await vm.respond(user, accept: true) } } label: {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.white).padding(8)
                                            .background(Circle().fill(Color.wydSuccess))
                                    }.buttonStyle(.plain)
                                    Button { Task { await vm.respond(user, accept: false) } } label: {
                                        Image(systemName: "xmark")
                                            .foregroundColor(.white).padding(8)
                                            .background(Circle().fill(Color.wydSurface2))
                                    }.buttonStyle(.plain)
                                }
                            })
                        }
                    }
                }

                section("Your friends") {
                    if vm.friends.isEmpty {
                        EmptyStateView(
                            emoji: "🫂",
                            title: "No friends added yet",
                            subtitle: "Search a username up top to add people. See what your crew's doing this weekend."
                        )
                    } else {
                        ForEach(vm.friends) { user in
                            personRow(user, trailing: {
                                if let snap = user.snapchatUsername {
                                    Text("👻 @\(snap)")
                                        .font(WYDFont.bodyMedium(13)).foregroundColor(.wydMuted)
                                }
                            })
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(WYDBackground())
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await vm.load() }
        .task {
            guard !didLoad else { return }
            didLoad = true
            vm.rebind(appState.backend)
            await vm.load()
        }
        .overlay(alignment: .bottom) {
            if let toast = vm.toast {
                Text(toast)
                    .font(WYDFont.bodyMedium(14)).foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Color.wydSurface2))
                    .overlay(Capsule().stroke(Color.wydBorder, lineWidth: 1))
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        withAnimation { vm.toast = nil }
                    }
            }
        }
    }

    // MARK: Pieces

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.wydMuted)
            TextField("Add by username", text: $vm.searchQuery)
                .font(WYDFont.body(16)).foregroundColor(.wydText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await vm.runSearch() } }
                .onChange(of: vm.searchQuery) { _ in Task { await vm.runSearch() } }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .wydCardBackground(.wydSurface2)
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(WYDFont.displaySemibold(18)).foregroundColor(.wydText)
            content()
        }
    }

    private func personRow<Trailing: View>(_ user: UserProfile,
                                           @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            AvatarView(user: user, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName).font(WYDFont.bodySemibold(15)).foregroundColor(.wydText)
                Text("@\(user.username)").font(WYDFont.bodyMedium(13)).foregroundColor(.wydMuted)
            }
            Spacer()
            trailing()
        }
        .padding(12)
        .wydCardBackground(.wydSurface)
    }
}

#Preview("Friends") {
    NavigationStack { FriendsView() }
        .environmentObject(AppState(backend: MockBackend()))
        .preferredColorScheme(.dark)
}
