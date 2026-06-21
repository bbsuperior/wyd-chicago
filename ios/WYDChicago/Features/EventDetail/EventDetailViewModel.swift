import SwiftUI

// MARK: - EventDetailViewModel

@MainActor
final class EventDetailViewModel: ObservableObject {

    @Published var event: Event?
    @Published var myRsvp: RSVPStatus = .none
    @Published var myVote: VoteDir = .none
    @Published var isSaved = false
    @Published var attendees: [UserProfile] = []
    @Published var comments: [Comment] = []
    @Published var commentDraft = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showReportSheet = false

    private let eventId: String
    private var backend: Backend

    init(eventId: String, backend: Backend) {
        self.eventId = eventId
        self.backend = backend
    }

    func rebind(_ backend: Backend) { self.backend = backend }

    /// Address is only known to the client once the gated `getEvent` returns it
    /// (server hides it until you're "going"). canon §8.
    var canSeeExactAddress: Bool {
        event?.exactAddress != nil
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            event = try await backend.getEvent(id: eventId)
            myRsvp = try await backend.getMyRsvp(eventId: eventId)
            myVote = try await backend.getMyVote(eventId: eventId)
            attendees = try await backend.listAttendees(eventId: eventId)
            comments = try await backend.listComments(eventId: eventId)
            isSaved = backend.currentUser?.savedEvents.contains(eventId) ?? false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setRsvp(_ status: RSVPStatus) async {
        let target: RSVPStatus = (myRsvp == status) ? .none : status
        // optimistic
        let previous = myRsvp
        myRsvp = target
        do {
            try await backend.rsvp(eventId: eventId, status: target)
            // Reload so the exact address unlocks/locks and counts refresh.
            await load()
        } catch {
            myRsvp = previous
            errorMessage = error.localizedDescription
        }
    }

    func vote(_ dir: VoteDir) async {
        let previous = myVote
        myVote = dir
        do {
            try await backend.vote(eventId: eventId, dir: dir)
            event = try await backend.getEvent(id: eventId)
        } catch {
            myVote = previous
            errorMessage = error.localizedDescription
        }
    }

    func toggleSave() async {
        do {
            isSaved = try await backend.toggleSave(eventId: eventId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func postComment() async {
        let text = commentDraft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let c = try await backend.addComment(eventId: eventId, text: text)
            comments.append(c)
            commentDraft = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitReport(reason: String, details: String) async {
        do {
            try await backend.report(ReportInput(
                targetType: .event, targetId: eventId, reason: reason, details: details
            ))
            showReportSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
