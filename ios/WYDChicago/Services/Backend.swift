import Foundation

// MARK: - Backend contract (mirrors web canon §5 Auth + API surface)
//
// MockBackend (in-memory) and FirebaseBackend (real Firestore/Auth) both conform
// to `Backend`. App code talks to the protocol only, never a concrete type — the
// same swap the web does between data.js and firebase.js via backend.js.

// MARK: Sort options for the feed (canon §3).

enum FeedSort: String, CaseIterable, Identifiable {
    case hype          // 🔥 voteScore
    case soonest       // 🕒 startAt ascending
    case friends       // 👥 friends going
    case forYou        // ✨ recommendation score

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hype: return "🔥 Hype"
        case .soonest: return "🕒 Soonest"
        case .friends: return "👥 Friends"
        case .forYou: return "✨ For you"
        }
    }
}

// MARK: Feed query (mirrors web listEvents options).

struct FeedQuery {
    var type: String?            // eventType tagId
    var neighborhood: String?
    var when: String?            // "tonight" | "weekend" | "week" | nil
    var sort: FeedSort = .hype
    var search: String?
    var friendsOnly: Bool = false
    var forYou: Bool = false

    init(
        type: String? = nil,
        neighborhood: String? = nil,
        when: String? = nil,
        sort: FeedSort = .hype,
        search: String? = nil,
        friendsOnly: Bool = false,
        forYou: Bool = false
    ) {
        self.type = type
        self.neighborhood = neighborhood
        self.when = when
        self.sort = sort
        self.search = search
        self.friendsOnly = friendsOnly
        self.forYou = forYou
    }
}

// MARK: Sign-up payload (mirrors web Auth.signUp).

struct SignUpInput {
    var email: String
    var password: String
    var username: String
    var displayName: String
    var birthYear: Int
    var interests: [String]
}

// MARK: Event create/edit payload (mirrors web createEvent/updateEvent).
//
// A loose patch keyed by canonical field names. Concrete backends apply only the
// provided fields. Using a struct keeps it type-safe for the create path.

struct EventDraft {
    var title: String
    var description: String
    var eventType: String
    var tags: [String]
    var coverImageUrl: String?
    var startAt: Date
    var endAt: Date?
    var venueName: String?
    var neighborhood: String?
    var approxArea: String
    var exactAddress: String?
    var priceCents: Int
    var capacity: Int?
    var ageMin: Int
    var ageMax: Int
    var recommendedFor: [String]
    var isFeatured: Bool
    var status: EventStatus

    init(
        title: String = "",
        description: String = "",
        eventType: String = "",
        tags: [String] = [],
        coverImageUrl: String? = nil,
        startAt: Date = Date().addingTimeInterval(60 * 60 * 24),
        endAt: Date? = nil,
        venueName: String? = nil,
        neighborhood: String? = nil,
        approxArea: String = "",
        exactAddress: String? = nil,
        priceCents: Int = 0,
        capacity: Int? = nil,
        ageMin: Int = 14,
        ageMax: Int = 18,
        recommendedFor: [String] = [],
        isFeatured: Bool = false,
        status: EventStatus = .draft
    ) {
        self.title = title
        self.description = description
        self.eventType = eventType
        self.tags = tags
        self.coverImageUrl = coverImageUrl
        self.startAt = startAt
        self.endAt = endAt
        self.venueName = venueName
        self.neighborhood = neighborhood
        self.approxArea = approxArea
        self.exactAddress = exactAddress
        self.priceCents = priceCents
        self.capacity = capacity
        self.ageMin = ageMin
        self.ageMax = ageMax
        self.recommendedFor = recommendedFor
        self.isFeatured = isFeatured
        self.status = status
    }
}

// MARK: Report payload.

struct ReportInput {
    var targetType: ReportTargetType
    var targetId: String
    var reason: String
    var details: String
}

// MARK: Errors surfaced to view models.

enum BackendError: LocalizedError {
    case notSignedIn
    case notAuthorized
    case notFound
    case emailNotVerified
    case usernameTaken
    case invalidInput(String)
    case unimplemented(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You need to sign in first."
        case .notAuthorized: return "You don't have access to do that."
        case .notFound: return "We couldn't find that."
        case .emailNotVerified: return "Verify your email to RSVP or vote."
        case .usernameTaken: return "That username is taken — try another."
        case .invalidInput(let m): return m
        case .unimplemented(let m): return "Not wired up yet: \(m)"
        }
    }
}

// MARK: - The contract

/// The full backend surface. Mirrors the web `Auth` + `API` objects from canon §5.
/// `@MainActor` so view models can drive SwiftUI state directly off the results.
@MainActor
protocol Backend: AnyObject {

    var usingFirebase: Bool { get }

    // MARK: Auth (web `Auth`)

    /// Currently signed-in user, or nil. Published so the UI reacts to changes.
    var currentUser: UserProfile? { get }

    /// Subscribe to auth-state changes. Returns a cancel closure.
    func onAuthChange(_ callback: @escaping (UserProfile?) -> Void) -> () -> Void

    func signUp(_ input: SignUpInput) async throws -> UserProfile
    func signIn(email: String, password: String) async throws -> UserProfile
    func signOut() async throws
    func sendVerification() async throws
    func resetPassword(email: String) async throws

    func isAdmin() -> Bool
    func isHost() -> Bool

    func updateProfile(_ patch: ProfilePatch) async throws -> UserProfile

    // MARK: API (web `API`)

    func listTags() async throws -> [Tag]
    func listEvents(_ query: FeedQuery) async throws -> [Event]
    func getEvent(id: String) async throws -> Event

    func rsvp(eventId: String, status: RSVPStatus) async throws
    func getMyRsvp(eventId: String) async throws -> RSVPStatus

    func vote(eventId: String, dir: VoteDir) async throws
    func getMyVote(eventId: String) async throws -> VoteDir

    func toggleSave(eventId: String) async throws -> Bool

    func listAttendees(eventId: String) async throws -> [UserProfile]
    func addComment(eventId: String, text: String) async throws -> Comment
    func listComments(eventId: String) async throws -> [Comment]

    func report(_ input: ReportInput) async throws

    // Friends
    func searchUsers(query: String) async throws -> [UserProfile]
    func addFriend(username: String) async throws
    func listFriends() async throws -> [UserProfile]
    func listFriendRequests() async throws -> [UserProfile]
    func respondFriend(uid: String, accept: Bool) async throws

    // Admin / host
    func createEvent(_ draft: EventDraft) async throws -> Event
    func updateEvent(id: String, draft: EventDraft) async throws -> Event
    func setEventStatus(id: String, status: EventStatus) async throws
    func listReports() async throws -> [Report]

    // Recommendation (shared pure fn)
    func recommendScore(user: UserProfile, event: Event, friendsGoingCount: Int) -> Double
}

extension Backend {
    func recommendScore(user: UserProfile, event: Event, friendsGoingCount: Int) -> Double {
        Recommend.score(user: user, event: event, friendsGoingCount: friendsGoingCount)
    }
}

// MARK: - Profile patch (mirrors web updateProfile(patch))

/// Optional fields are applied only when non-nil, matching the web partial update.
struct ProfilePatch {
    var displayName: String?
    var bio: String?
    var gradeYear: String??     // double-optional: outer nil = leave, inner nil = clear
    var neighborhood: String??
    var interests: [String]?
    var snapchatUsername: String??
    var instagramUsername: String??
    var avatarUrl: String??

    init(
        displayName: String? = nil,
        bio: String? = nil,
        gradeYear: String?? = nil,
        neighborhood: String?? = nil,
        interests: [String]? = nil,
        snapchatUsername: String?? = nil,
        instagramUsername: String?? = nil,
        avatarUrl: String?? = nil
    ) {
        self.displayName = displayName
        self.bio = bio
        self.gradeYear = gradeYear
        self.neighborhood = neighborhood
        self.interests = interests
        self.snapchatUsername = snapchatUsername
        self.instagramUsername = instagramUsername
        self.avatarUrl = avatarUrl
    }
}
