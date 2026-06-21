import SwiftUI

// MARK: - ProfileViewModel (canon §3.5)

@MainActor
final class ProfileViewModel: ObservableObject {

    @Published var goingEvents: [Event] = []
    @Published var savedEvents: [Event] = []
    @Published var friendCount = 0
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Edit fields
    @Published var editingProfile = false
    @Published var editBio = ""
    @Published var editNeighborhood = ""
    @Published var editSnap = ""
    @Published var editInsta = ""

    private var backend: Backend
    init(backend: Backend) { self.backend = backend }
    func rebind(_ backend: Backend) { self.backend = backend }

    var user: UserProfile? { backend.currentUser }

    /// True when the email-verification gate still needs clearing (canon §8).
    var needsVerification: Bool {
        guard let u = backend.currentUser else { return false }
        return !u.emailVerified
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let me = backend.currentUser else { return }
        do {
            friendCount = (try? await backend.listFriends().count) ?? 0

            // "Going to" events: scan published events for my RSVP.
            let all = try await backend.listEvents(FeedQuery(sort: .soonest))
            var going: [Event] = []
            for ev in all where (try? await backend.getMyRsvp(eventId: ev.id)) == .going {
                going.append(ev)
            }
            goingEvents = going

            // Saved events.
            var saved: [Event] = []
            for id in me.savedEvents {
                if let ev = try? await backend.getEvent(id: id) { saved.append(ev) }
            }
            savedEvents = saved
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginEdit() {
        guard let u = backend.currentUser else { return }
        editBio = u.bio
        editNeighborhood = u.neighborhood ?? ""
        editSnap = u.snapchatUsername ?? ""
        editInsta = u.instagramUsername ?? ""
        editingProfile = true
    }

    func saveEdit() async {
        do {
            _ = try await backend.updateProfile(ProfilePatch(
                bio: editBio,
                neighborhood: editNeighborhood.isEmpty ? .some(nil) : .some(editNeighborhood),
                snapchatUsername: editSnap.isEmpty ? .some(nil) : .some(editSnap),
                instagramUsername: editInsta.isEmpty ? .some(nil) : .some(editInsta)
            ))
            editingProfile = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resendVerification() async {
        do { try await backend.sendVerification() }
        catch { errorMessage = error.localizedDescription }
    }

    func signOut() {
        Task { try? await backend.signOut() }
    }
}
