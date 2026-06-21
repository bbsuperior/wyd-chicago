import SwiftUI

// MARK: - AdminViewModel — master dashboard / host create (canon §3.7, §4 roles)

@MainActor
final class AdminViewModel: ObservableObject {

    enum Tab: String, CaseIterable, Identifiable {
        case create = "Create"
        case manage = "Manage"
        case reports = "Reports"
        var id: String { rawValue }
    }

    @Published var tab: Tab = .create

    // Manage / reports
    @Published var allEvents: [Event] = []
    @Published var reports: [Report] = []

    // Tags for the create form
    @Published var eventTypeTags: [Tag] = []
    @Published var interestTags: [Tag] = []

    // Create form (EventDraft)
    @Published var draft = EventDraft()
    @Published var priceDollars: String = "0"
    @Published var capacityText: String = ""
    @Published var isSaving = false
    @Published var toast: String?
    @Published var errorMessage: String?

    private var backend: Backend
    init(backend: Backend) { self.backend = backend }
    func rebind(_ backend: Backend) { self.backend = backend }

    /// Admins see the full dashboard; hosts get just the create form.
    var isAdmin: Bool { backend.currentUser?.isAdmin ?? false }

    var canSubmitDraft: Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.eventType.isEmpty
            && !draft.approxArea.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func load() async {
        do {
            let tags = try await backend.listTags()
            eventTypeTags = tags.filter { $0.kind == .eventType }
            interestTags = tags.filter { $0.kind == .interest }
            if isAdmin {
                reports = try await backend.listReports()
                // Manage view wants all statuses; mock listEvents returns published only,
                // so we surface what we can plus the admin can re-publish drafts here.
                allEvents = try await backend.listEvents(FeedQuery(sort: .soonest))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleDraftTag(_ id: String) {
        if let idx = draft.tags.firstIndex(of: id) { draft.tags.remove(at: idx) }
        else { draft.tags.append(id) }
    }

    func submitDraft() async {
        guard canSubmitDraft else { return }
        isSaving = true
        defer { isSaving = false }

        // Map the entered price / capacity strings into the draft.
        draft.priceCents = Int((Double(priceDollars) ?? 0) * 100)
        draft.capacity = Int(capacityText)
        // Admins can publish straight away; hosts default to draft for review (canon §8).
        draft.status = isAdmin ? .published : .draft

        do {
            let ev = try await backend.createEvent(draft)
            toast = isAdmin ? "Published “\(ev.title)” 🎉" : "Submitted “\(ev.title)” for review ✅"
            draft = EventDraft()
            priceDollars = "0"; capacityText = ""
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setStatus(_ event: Event, _ status: EventStatus) async {
        do {
            try await backend.setEventStatus(id: event.id, status: status)
            toast = "\(event.title) → \(status.rawValue)"
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
