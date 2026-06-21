import SwiftUI

// MARK: - FeedViewModel — drives the core Feed/Search screen.

@MainActor
final class FeedViewModel: ObservableObject {

    @Published var events: [Event] = []
    @Published var tags: [Tag] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Filters / sort (canon §3).
    @Published var search: String = ""
    @Published var selectedType: String?        // eventType tagId
    @Published var selectedWhen: String?         // "tonight" | "weekend" | "week"
    @Published var sort: FeedSort = .hype
    @Published var friendsOnly = false

    /// friends-going avatars per event id, for the cards.
    @Published var friendsGoingByEvent: [String: [UserProfile]] = [:]

    private var backend: Backend

    init(backend: Backend) {
        self.backend = backend
    }

    /// Swap in the real backend after the view supplies it from the environment.
    func rebind(_ backend: Backend) {
        self.backend = backend
    }

    var eventTypeTags: [Tag] { tags.filter { $0.kind == .eventType } }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if tags.isEmpty { tags = try await backend.listTags() }
            let query = FeedQuery(
                type: selectedType,
                when: selectedWhen,
                sort: sort,
                search: search.isEmpty ? nil : search,
                friendsOnly: friendsOnly,
                forYou: sort == .forYou
            )
            events = try await backend.listEvents(query)
            await loadFriendsGoing()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// For each event, figure out which of my friends are going (for the avatar stack).
    private func loadFriendsGoing() async {
        guard let me = backend.currentUser else { friendsGoingByEvent = [:]; return }
        let friends = (try? await backend.listFriends()) ?? []
        guard !friends.isEmpty else { friendsGoingByEvent = [:]; return }
        let friendIds = Set(friends.map(\.id))
        var map: [String: [UserProfile]] = [:]
        for event in events {
            let attendees = (try? await backend.listAttendees(eventId: event.id)) ?? []
            let going = attendees.filter { friendIds.contains($0.id) && $0.id != me.id }
            if !going.isEmpty { map[event.id] = going }
        }
        friendsGoingByEvent = map
    }

    func selectType(_ tagId: String?) {
        selectedType = (selectedType == tagId) ? nil : tagId
        Task { await load() }
    }

    func selectWhen(_ when: String?) {
        selectedWhen = (selectedWhen == when) ? nil : when
        Task { await load() }
    }

    func setSort(_ s: FeedSort) {
        sort = s
        Task { await load() }
    }

    func runSearch() {
        Task { await load() }
    }
}
