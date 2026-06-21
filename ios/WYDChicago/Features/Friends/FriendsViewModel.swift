import SwiftUI

// MARK: - FriendsViewModel (canon §3.6)

@MainActor
final class FriendsViewModel: ObservableObject {

    @Published var friends: [UserProfile] = []
    @Published var requests: [UserProfile] = []
    @Published var searchResults: [UserProfile] = []
    @Published var searchQuery = ""
    @Published var isLoading = false
    @Published var toast: String?
    @Published var errorMessage: String?

    private var backend: Backend
    init(backend: Backend) { self.backend = backend }
    func rebind(_ backend: Backend) { self.backend = backend }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            friends = try await backend.listFriends()
            requests = try await backend.listFriendRequests()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runSearch() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        do { searchResults = try await backend.searchUsers(query: searchQuery) }
        catch { errorMessage = error.localizedDescription }
    }

    func addFriend(_ user: UserProfile) async {
        do {
            try await backend.addFriend(username: user.username)
            toast = "Request sent to @\(user.username) 🤝"
            searchResults.removeAll { $0.id == user.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func respond(_ user: UserProfile, accept: Bool) async {
        do {
            try await backend.respondFriend(uid: user.id, accept: accept)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
