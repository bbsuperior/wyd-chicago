import Foundation
import Combine

// MARK: - MockBackend — in-memory, zero external deps.
//
// Renders real-looking content in SwiftUI previews and the simulator with NO
// Firebase. Seeds ~8 demo events, demo users, and a demo admin ("master login").
// All content is clearly fictional (canon §9). Signed in as a demo teen by default
// so the feed, RSVP, voting, friends, and saves all work immediately.

@MainActor
final class MockBackend: ObservableObject, Backend {

    let usingFirebase = false

    // MARK: Stores

    @Published private(set) var users: [String: UserProfile] = [:]
    @Published private(set) var events: [String: Event] = [:]
    private var tags: [Tag] = []
    private var comments: [String: [Comment]] = [:]          // eventId -> comments
    private var attendees: [String: [String: RSVPStatus]] = [:]  // eventId -> uid -> status
    private var votes: [String: [String: VoteDir]] = [:]     // eventId -> uid -> dir
    private var friends: [String: [String: (status: String, direction: String)]] = [:] // uid -> friendUid -> edge
    private var reports: [Report] = []

    @Published private(set) var currentUserId: String?
    private var authListeners: [UUID: (UserProfile?) -> Void] = [:]

    var currentUser: UserProfile? {
        guard let id = currentUserId else { return nil }
        return users[id]
    }

    // MARK: Init / seed

    init(signedInAsDemoTeen: Bool = true) {
        seed()
        if signedInAsDemoTeen {
            currentUserId = "u_demo"
        }
    }

    /// Convenience for previews that want to start signed-in as the admin.
    static func signedInAsAdmin() -> MockBackend {
        let b = MockBackend(signedInAsDemoTeen: false)
        b.currentUserId = "u_admin"
        return b
    }

    /// Convenience for previews that want to start signed-in as the demo host.
    static func signedInAsHost() -> MockBackend {
        let b = MockBackend(signedInAsDemoTeen: false)
        b.currentUserId = "u_host"
        return b
    }

    /// Convenience for previews that want the logged-out / auth flow.
    static func loggedOut() -> MockBackend {
        MockBackend(signedInAsDemoTeen: false)
    }

    // MARK: Auth

    func onAuthChange(_ callback: @escaping (UserProfile?) -> Void) -> () -> Void {
        let key = UUID()
        authListeners[key] = callback
        callback(currentUser)
        return { [weak self] in self?.authListeners[key] = nil }
    }

    private func emitAuth() {
        let u = currentUser
        authListeners.values.forEach { $0(u) }
    }

    func signUp(_ input: SignUpInput) async throws -> UserProfile {
        let uname = input.username.lowercased()
        guard !users.values.contains(where: { $0.username == uname }) else {
            throw BackendError.usernameTaken
        }
        let uid = "u_\(UUID().uuidString.prefix(8))"
        let profile = UserProfile(
            id: uid,
            displayName: input.displayName,
            username: uname,
            birthYear: input.birthYear,
            interests: input.interests,
            role: .user,
            emailVerified: false       // mock starts unverified to exercise the gate
        )
        users[uid] = profile
        currentUserId = uid
        emitAuth()
        return profile
    }

    func signIn(email: String, password: String) async throws -> UserProfile {
        // Mock: match by a fake email of username@wyd.test, else default to demo teen.
        let handle = email.split(separator: "@").first.map(String.init)?.lowercased()
        if let handle, let match = users.values.first(where: { $0.username == handle }) {
            currentUserId = match.id
        } else {
            currentUserId = "u_demo"
        }
        emitAuth()
        guard let u = currentUser else { throw BackendError.notFound }
        return u
    }

    func signOut() async throws {
        currentUserId = nil
        emitAuth()
    }

    func sendVerification() async throws {
        // Mock: flip the current user to verified so the gate can be exercised.
        guard let id = currentUserId, var u = users[id] else { throw BackendError.notSignedIn }
        u.emailVerified = true
        u.updatedAt = Date()
        users[id] = u
        emitAuth()
    }

    func resetPassword(email: String) async throws { /* no-op in mock */ }

    func isAdmin() -> Bool { currentUser?.isAdmin ?? false }
    func isHost() -> Bool { currentUser?.isHost ?? false }

    func updateProfile(_ patch: ProfilePatch) async throws -> UserProfile {
        guard let id = currentUserId, var u = users[id] else { throw BackendError.notSignedIn }
        if let v = patch.displayName { u.displayName = v }
        if let v = patch.bio { u.bio = v }
        if let v = patch.gradeYear { u.gradeYear = v }
        if let v = patch.neighborhood { u.neighborhood = v }
        if let v = patch.interests { u.interests = v }
        if let v = patch.snapchatUsername { u.snapchatUsername = v }
        if let v = patch.instagramUsername { u.instagramUsername = v }
        if let v = patch.avatarUrl { u.avatarUrl = v }
        u.updatedAt = Date()
        users[id] = u
        emitAuth()
        return u
    }

    // MARK: API — read

    func listTags() async throws -> [Tag] {
        tags.sorted { $0.sort < $1.sort }
    }

    func listEvents(_ query: FeedQuery) async throws -> [Event] {
        var result = events.values.filter { $0.status == .published }

        if let type = query.type, !type.isEmpty {
            result = result.filter { $0.eventType == type }
        }
        if let n = query.neighborhood, !n.isEmpty {
            result = result.filter { $0.neighborhood?.caseInsensitiveCompare(n) == .orderedSame }
        }
        if let when = query.when {
            let cal = Calendar.current
            result = result.filter { ev in
                switch when {
                case "tonight": return cal.isDateInToday(ev.startAt)
                case "weekend":
                    let wd = cal.component(.weekday, from: ev.startAt)
                    return wd == 6 || wd == 7 || wd == 1   // Fri/Sat/Sun
                case "week":
                    return ev.startAt.timeIntervalSinceNow < 60 * 60 * 24 * 7 && ev.startAt > Date()
                default: return true
                }
            }
        }
        if let q = query.search?.lowercased(), !q.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(q)
                    || $0.description.lowercased().contains(q)
                    || $0.approxArea.lowercased().contains(q)
                    || ($0.neighborhood?.lowercased().contains(q) ?? false)
            }
        }
        if query.friendsOnly {
            let friendIds = friendUids(of: currentUserId)
            result = result.filter { ev in
                friendIds.contains { fid in (attendees[ev.id]?[fid] ?? .none) != .none }
            }
        }

        // Sort
        switch query.sort {
        case .hype:
            result.sort { $0.voteScore > $1.voteScore }
        case .soonest:
            result.sort { $0.startAt < $1.startAt }
        case .friends:
            result.sort { friendsGoing(eventId: $0.id) > friendsGoing(eventId: $1.id) }
        case .forYou:
            if let me = currentUser {
                result.sort {
                    recommendScore(user: me, event: $0, friendsGoingCount: friendsGoing(eventId: $0.id))
                        > recommendScore(user: me, event: $1, friendsGoingCount: friendsGoing(eventId: $1.id))
                }
            } else {
                result.sort { $0.voteScore > $1.voteScore }
            }
        }
        return result
    }

    func getEvent(id: String) async throws -> Event {
        guard let ev = events[id] else { throw BackendError.notFound }
        // Gate exact address: hidden unless the viewer is "going" or an admin.
        var out = ev
        let viewer = currentUserId
        let isGoing = viewer.flatMap { attendees[id]?[$0] } == .going
        if !isGoing && !isAdmin() {
            out.exactAddress = nil
        }
        return out
    }

    // MARK: API — RSVP / vote / save

    func rsvp(eventId: String, status: RSVPStatus) async throws {
        guard let uid = currentUserId else { throw BackendError.notSignedIn }
        try requireVerified()
        var map = attendees[eventId] ?? [:]
        let previous = map[uid] ?? .none
        if status == .none { map[uid] = nil } else { map[uid] = status }
        attendees[eventId] = map
        applyAttendeeDelta(eventId: eventId, from: previous, to: status)
    }

    func getMyRsvp(eventId: String) async throws -> RSVPStatus {
        guard let uid = currentUserId else { return .none }
        return attendees[eventId]?[uid] ?? .none
    }

    func vote(eventId: String, dir: VoteDir) async throws {
        guard let uid = currentUserId else { throw BackendError.notSignedIn }
        try requireVerified()
        var map = votes[eventId] ?? [:]
        let previous = map[uid] ?? .none
        if dir == .none { map[uid] = nil } else { map[uid] = dir }
        votes[eventId] = map
        applyVoteDelta(eventId: eventId, from: previous, to: dir)
    }

    func getMyVote(eventId: String) async throws -> VoteDir {
        guard let uid = currentUserId else { return .none }
        return votes[eventId]?[uid] ?? .none
    }

    func toggleSave(eventId: String) async throws -> Bool {
        guard let uid = currentUserId, var u = users[uid] else { throw BackendError.notSignedIn }
        if let idx = u.savedEvents.firstIndex(of: eventId) {
            u.savedEvents.remove(at: idx)
            users[uid] = u
            emitAuth()
            return false
        } else {
            u.savedEvents.append(eventId)
            users[uid] = u
            emitAuth()
            return true
        }
    }

    func listAttendees(eventId: String) async throws -> [UserProfile] {
        let map = attendees[eventId] ?? [:]
        return map.keys.compactMap { users[$0] }
    }

    func addComment(eventId: String, text: String) async throws -> Comment {
        guard let me = currentUser else { throw BackendError.notSignedIn }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BackendError.invalidInput("Say something first 👀") }
        let c = Comment(
            id: "c_\(UUID().uuidString.prefix(8))",
            authorId: me.id,
            authorName: "@\(me.username)",
            text: trimmed
        )
        comments[eventId, default: []].append(c)
        return c
    }

    func listComments(eventId: String) async throws -> [Comment] {
        (comments[eventId] ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    func report(_ input: ReportInput) async throws {
        guard let me = currentUser else { throw BackendError.notSignedIn }
        let r = Report(
            id: "r_\(UUID().uuidString.prefix(8))",
            targetType: input.targetType,
            targetId: input.targetId,
            reporterId: me.id,
            reason: input.reason,
            details: input.details
        )
        reports.append(r)
    }

    // MARK: API — friends

    func searchUsers(query: String) async throws -> [UserProfile] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return users.values
            .filter { $0.id != currentUserId }
            .filter { $0.username.contains(q) || $0.displayName.lowercased().contains(q) }
            .sorted { $0.username < $1.username }
    }

    func addFriend(username: String) async throws {
        guard let me = currentUserId else { throw BackendError.notSignedIn }
        let uname = username.lowercased()
        guard let target = users.values.first(where: { $0.username == uname }) else {
            throw BackendError.notFound
        }
        guard target.id != me else { throw BackendError.invalidInput("That's you 😅") }
        friends[me, default: [:]][target.id] = (status: "pending", direction: "out")
        friends[target.id, default: [:]][me] = (status: "pending", direction: "in")
    }

    func listFriends() async throws -> [UserProfile] {
        guard let me = currentUserId else { return [] }
        let edges = friends[me] ?? [:]
        return edges.filter { $0.value.status == "accepted" }
            .keys.compactMap { users[$0] }
            .sorted { $0.username < $1.username }
    }

    func listFriendRequests() async throws -> [UserProfile] {
        guard let me = currentUserId else { return [] }
        let edges = friends[me] ?? [:]
        return edges.filter { $0.value.status == "pending" && $0.value.direction == "in" }
            .keys.compactMap { users[$0] }
            .sorted { $0.username < $1.username }
    }

    func respondFriend(uid: String, accept: Bool) async throws {
        guard let me = currentUserId else { throw BackendError.notSignedIn }
        if accept {
            friends[me, default: [:]][uid] = (status: "accepted", direction: "in")
            friends[uid, default: [:]][me] = (status: "accepted", direction: "out")
        } else {
            friends[me]?[uid] = nil
            friends[uid]?[me] = nil
        }
    }

    // MARK: API — admin / host

    func createEvent(_ draft: EventDraft) async throws -> Event {
        guard let me = currentUser else { throw BackendError.notSignedIn }
        guard me.isHost else { throw BackendError.notAuthorized }
        let id = "e_\(UUID().uuidString.prefix(8))"
        let ev = Event(
            id: id,
            title: draft.title,
            description: draft.description,
            eventType: draft.eventType,
            tags: draft.tags,
            hostId: me.id,
            hostName: "@\(me.username)",
            coverImageUrl: draft.coverImageUrl,
            startAt: draft.startAt,
            endAt: draft.endAt,
            venueName: draft.venueName,
            neighborhood: draft.neighborhood,
            approxArea: draft.approxArea,
            exactAddress: draft.exactAddress,
            priceCents: draft.priceCents,
            capacity: draft.capacity,
            ageMin: draft.ageMin,
            ageMax: draft.ageMax,
            recommendedFor: draft.recommendedFor,
            status: draft.status,
            isFeatured: draft.isFeatured,
            createdBy: me.id
        )
        events[id] = ev
        return ev
    }

    func updateEvent(id: String, draft: EventDraft) async throws -> Event {
        guard isHost() else { throw BackendError.notAuthorized }
        guard var ev = events[id] else { throw BackendError.notFound }
        ev.title = draft.title
        ev.description = draft.description
        ev.eventType = draft.eventType
        ev.tags = draft.tags
        ev.coverImageUrl = draft.coverImageUrl
        ev.startAt = draft.startAt
        ev.endAt = draft.endAt
        ev.venueName = draft.venueName
        ev.neighborhood = draft.neighborhood
        ev.approxArea = draft.approxArea
        ev.exactAddress = draft.exactAddress
        ev.priceCents = draft.priceCents
        ev.capacity = draft.capacity
        ev.ageMin = draft.ageMin
        ev.ageMax = draft.ageMax
        ev.recommendedFor = draft.recommendedFor
        ev.isFeatured = draft.isFeatured
        ev.status = draft.status
        ev.updatedAt = Date()
        events[id] = ev
        return ev
    }

    func setEventStatus(id: String, status: EventStatus) async throws {
        guard isAdmin() || isHost() else { throw BackendError.notAuthorized }
        guard var ev = events[id] else { throw BackendError.notFound }
        ev.status = status
        ev.updatedAt = Date()
        events[id] = ev
    }

    func listReports() async throws -> [Report] {
        guard isAdmin() else { throw BackendError.notAuthorized }
        return reports.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Helpers

    private func requireVerified() throws {
        guard let u = currentUser else { throw BackendError.notSignedIn }
        guard u.emailVerified else { throw BackendError.emailNotVerified }
    }

    private func friendUids(of uid: String?) -> Set<String> {
        guard let uid else { return [] }
        let edges = friends[uid] ?? [:]
        return Set(edges.filter { $0.value.status == "accepted" }.keys)
    }

    private func friendsGoing(eventId: String) -> Int {
        let fids = friendUids(of: currentUserId)
        let map = attendees[eventId] ?? [:]
        return fids.filter { (map[$0] ?? .none) != .none }.count
    }

    private func applyAttendeeDelta(eventId: String, from: RSVPStatus, to: RSVPStatus) {
        guard var ev = events[eventId] else { return }
        if from == .going { ev.committedCount = max(0, ev.committedCount - 1) }
        if from == .interested { ev.interestedCount = max(0, ev.interestedCount - 1) }
        if to == .going { ev.committedCount += 1 }
        if to == .interested { ev.interestedCount += 1 }
        events[eventId] = ev
    }

    private func applyVoteDelta(eventId: String, from: VoteDir, to: VoteDir) {
        guard var ev = events[eventId] else { return }
        if from == .up { ev.upvotes = max(0, ev.upvotes - 1) }
        if from == .down { ev.downvotes = max(0, ev.downvotes - 1) }
        if to == .up { ev.upvotes += 1 }
        if to == .down { ev.downvotes += 1 }
        ev.voteScore = ev.upvotes - ev.downvotes
        events[eventId] = ev
    }

    // MARK: - Seed (fictional demo content, canon §9)

    private func seed() {
        // ---- Tags ----
        let eventTypes: [Tag] = [
            Tag(id: "house-party", label: "House Party", kind: .eventType, emoji: "🏠", color: "#FF4D6D", sort: 0),
            Tag(id: "kickback", label: "Kickback", kind: .eventType, emoji: "🛋️", color: "#5B8CFF", sort: 1),
            Tag(id: "concert", label: "Concert", kind: .eventType, emoji: "🎤", color: "#C44CFF", sort: 2),
            Tag(id: "game", label: "Game", kind: .eventType, emoji: "🏀", color: "#FFC83D", sort: 3),
            Tag(id: "fundraiser", label: "Fundraiser", kind: .eventType, emoji: "💸", color: "#2EE6A6", sort: 4),
            Tag(id: "open-mic", label: "Open Mic", kind: .eventType, emoji: "🎙️", color: "#5B8CFF", sort: 5)
        ]
        let interests: [Tag] = [
            Tag(id: "music", label: "Music", kind: .interest, emoji: "🎧", color: "#C44CFF", sort: 0),
            Tag(id: "hoops", label: "Hoops", kind: .interest, emoji: "🏀", color: "#FFC83D", sort: 1),
            Tag(id: "art", label: "Art", kind: .interest, emoji: "🎨", color: "#FF4D6D", sort: 2),
            Tag(id: "gaming", label: "Gaming", kind: .interest, emoji: "🎮", color: "#5B8CFF", sort: 3),
            Tag(id: "food", label: "Food", kind: .interest, emoji: "🍕", color: "#FFC83D", sort: 4),
            Tag(id: "dance", label: "Dance", kind: .interest, emoji: "💃", color: "#FF4D6D", sort: 5),
            Tag(id: "skate", label: "Skate", kind: .interest, emoji: "🛹", color: "#2EE6A6", sort: 6),
            Tag(id: "photography", label: "Photo", kind: .interest, emoji: "📸", color: "#5B8CFF", sort: 7)
        ]
        tags = eventTypes + interests

        // ---- Users ----
        let admin = UserProfile(
            id: "u_admin", displayName: "WYD Team", username: "beckett",
            bio: "running the city 🌃", birthYear: 2004, neighborhood: "The Loop",
            interests: ["music", "hoops"], snapchatUsername: "wydchicago",
            instagramUsername: "wydchicago", role: .admin, emailVerified: true
        )
        let host = UserProfile(
            id: "u_host", displayName: "Maya R.", username: "mayaonthemic",
            bio: "open mic host @ Pilsen", birthYear: 2007, gradeYear: "Junior",
            neighborhood: "Pilsen", interests: ["music", "art", "photography"],
            snapchatUsername: "mayarrr", instagramUsername: "maya.on.the.mic",
            role: .host, emailVerified: true
        )
        let demo = UserProfile(
            id: "u_demo", displayName: "You", username: "you",
            bio: "just tryna see whats good", birthYear: 2008, gradeYear: "Sophomore",
            neighborhood: "Lincoln Park", interests: ["music", "hoops", "gaming", "food"],
            snapchatUsername: "you_demo", instagramUsername: "you.demo",
            role: .user, savedEvents: [], emailVerified: true
        )
        let friendsList: [UserProfile] = [
            UserProfile(id: "u_jay", displayName: "Jayden", username: "jaydot", birthYear: 2008,
                        gradeYear: "Sophomore", neighborhood: "Hyde Park",
                        interests: ["hoops", "gaming"], role: .user, emailVerified: true),
            UserProfile(id: "u_sof", displayName: "Sofia", username: "sofvibes", birthYear: 2007,
                        gradeYear: "Junior", neighborhood: "Wicker Park",
                        interests: ["music", "dance", "art"], role: .user, emailVerified: true),
            UserProfile(id: "u_des", displayName: "Desmond", username: "desmoneyy", birthYear: 2006,
                        gradeYear: "Senior", neighborhood: "Bronzeville",
                        interests: ["music", "skate"], role: .user, emailVerified: true),
            UserProfile(id: "u_amel", displayName: "Amelia", username: "ameliaa", birthYear: 2009,
                        gradeYear: "Freshman", neighborhood: "Lincoln Park",
                        interests: ["food", "photography"], role: .user, emailVerified: true)
        ]
        for u in [admin, host, demo] + friendsList { users[u.id] = u }

        // demo is friends with jay, sof, des (accepted); amelia sent a request (incoming)
        for fid in ["u_jay", "u_sof", "u_des"] {
            friends["u_demo", default: [:]][fid] = (status: "accepted", direction: "out")
            friends[fid, default: [:]]["u_demo"] = (status: "accepted", direction: "in")
        }
        friends["u_demo", default: [:]]["u_amel"] = (status: "pending", direction: "in")
        friends["u_amel", default: [:]]["u_demo"] = (status: "pending", direction: "out")

        // ---- Events (8 demo, fictional) ----
        let now = Date()
        func at(_ days: Int, hour: Int, minute: Int = 0) -> Date {
            let cal = Calendar.current
            let base = cal.date(byAdding: .day, value: days, to: now)!
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
        }

        let seedEvents: [Event] = [
            Event(id: "e1", title: "Rooftop Kickback 🌆",
                  description: "Lowkey rooftop hang, good music, bring a friend. First 30 only.",
                  eventType: "kickback", tags: ["music", "food"], hostId: "u_admin", hostName: "WYD Team",
                  startAt: at(0, hour: 20), endAt: at(0, hour: 23),
                  venueName: "A rooftop", neighborhood: "West Loop", approxArea: "West Loop",
                  exactAddress: "1234 W Fulton Market, Chicago (demo)", priceCents: 0, capacity: 30,
                  recommendedFor: ["music", "food"], committedCount: 18, interestedCount: 42,
                  upvotes: 64, downvotes: 3, voteScore: 61, status: .published, isFeatured: true,
                  createdBy: "u_admin"),

            Event(id: "e2", title: "Pilsen Open Mic 🎙️",
                  description: "Poets, rappers, singers — sign up at the door. All ages, free.",
                  eventType: "open-mic", tags: ["music", "art"], hostId: "u_host", hostName: "@mayaonthemic",
                  startAt: at(1, hour: 19), endAt: at(1, hour: 22),
                  venueName: "Pilsen art space", neighborhood: "Pilsen", approxArea: "Pilsen",
                  exactAddress: "1900 S Halsted (demo)", priceCents: 0,
                  recommendedFor: ["music", "art"], committedCount: 27, interestedCount: 55,
                  upvotes: 48, downvotes: 1, voteScore: 47, status: .published, isFeatured: false,
                  createdBy: "u_host"),

            Event(id: "e3", title: "Friday Night Hoops Run 🏀",
                  description: "5v5 runs, winner stays on. Bring a white & dark shirt.",
                  eventType: "game", tags: ["hoops"], hostId: nil, hostName: "WYD Team",
                  startAt: at(2, hour: 18), endAt: at(2, hour: 21),
                  venueName: "Gym", neighborhood: "Hyde Park", approxArea: "Hyde Park",
                  exactAddress: "Local rec center (demo)", priceCents: 500,
                  recommendedFor: ["hoops"], committedCount: 22, interestedCount: 30,
                  upvotes: 39, downvotes: 4, voteScore: 35, status: .published, isFeatured: false,
                  createdBy: "u_admin"),

            Event(id: "e4", title: "Wicker Park House Party 🏠",
                  description: "Bday bash. Loud, packed, fun. RSVP for the addy.",
                  eventType: "house-party", tags: ["music", "dance"], hostId: nil, hostName: "WYD Team",
                  startAt: at(2, hour: 21), endAt: at(3, hour: 1),
                  venueName: nil, neighborhood: "Wicker Park", approxArea: "Wicker Park",
                  exactAddress: "Near Damen & North (demo)", priceCents: 0, capacity: 80,
                  recommendedFor: ["music", "dance"], committedCount: 51, interestedCount: 90,
                  upvotes: 88, downvotes: 12, voteScore: 76, status: .published, isFeatured: true,
                  createdBy: "u_admin"),

            Event(id: "e5", title: "Skate Jam @ the park 🛹",
                  description: "Chill skate session, beginners welcome. Filmers come thru.",
                  eventType: "kickback", tags: ["skate", "photography"], hostId: nil, hostName: "WYD Team",
                  startAt: at(3, hour: 16), endAt: at(3, hour: 19),
                  venueName: "Skatepark", neighborhood: "Logan Square", approxArea: "Logan Square",
                  exactAddress: "The skatepark (demo)", priceCents: 0,
                  recommendedFor: ["skate", "photography"], committedCount: 14, interestedCount: 22,
                  upvotes: 31, downvotes: 2, voteScore: 29, status: .published, isFeatured: false,
                  createdBy: "u_admin"),

            Event(id: "e6", title: "Local Artists Showcase 🎨",
                  description: "Teen artists drop their work + live music. Snacks included.",
                  eventType: "concert", tags: ["art", "music"], hostId: "u_host", hostName: "@mayaonthemic",
                  startAt: at(4, hour: 18), endAt: at(4, hour: 21),
                  venueName: "Community center", neighborhood: "Bronzeville", approxArea: "Bronzeville",
                  exactAddress: "Bronzeville arts hub (demo)", priceCents: 0,
                  recommendedFor: ["art", "music"], committedCount: 9, interestedCount: 17,
                  upvotes: 20, downvotes: 0, voteScore: 20, status: .published, isFeatured: false,
                  createdBy: "u_host"),

            Event(id: "e7", title: "Charity Bake Sale + Hangout 💸",
                  description: "Raising money for the food bank. Cookies, music, good vibes.",
                  eventType: "fundraiser", tags: ["food"], hostId: nil, hostName: "WYD Team",
                  startAt: at(5, hour: 13), endAt: at(5, hour: 16),
                  venueName: "School courtyard", neighborhood: "Lincoln Park", approxArea: "Lincoln Park",
                  exactAddress: "School courtyard (demo)", priceCents: 0,
                  recommendedFor: ["food"], committedCount: 12, interestedCount: 25,
                  upvotes: 26, downvotes: 1, voteScore: 25, status: .published, isFeatured: false,
                  createdBy: "u_admin"),

            Event(id: "e8", title: "Late Night Gaming LAN 🎮",
                  description: "BYO controller. Smash, 2K, and Mario Kart brackets. Pizza on us.",
                  eventType: "kickback", tags: ["gaming", "food"], hostId: nil, hostName: "WYD Team",
                  startAt: at(6, hour: 19), endAt: at(7, hour: 0),
                  venueName: "Rec room", neighborhood: "Lakeview", approxArea: "Lakeview",
                  exactAddress: "The rec room (demo)", priceCents: 300, capacity: 24,
                  recommendedFor: ["gaming", "food"], committedCount: 16, interestedCount: 20,
                  upvotes: 34, downvotes: 5, voteScore: 29, status: .published, isFeatured: false,
                  createdBy: "u_admin")
        ]
        for ev in seedEvents { events[ev.id] = ev }

        // Seed RSVPs so friends-going + counts look alive.
        attendees["e1"] = ["u_jay": .going, "u_sof": .interested, "u_des": .going]
        attendees["e4"] = ["u_sof": .going, "u_des": .going, "u_jay": .interested]
        attendees["e3"] = ["u_jay": .going]
        attendees["e8"] = ["u_jay": .interested]

        // Seed a couple of comments + a report for the admin queue.
        comments["e1"] = [
            Comment(id: "c1", authorId: "u_jay", authorName: "@jaydot", text: "im so down 🔥"),
            Comment(id: "c2", authorId: "u_sof", authorName: "@sofvibes", text: "who else going??")
        ]
        comments["e4"] = [
            Comment(id: "c3", authorId: "u_des", authorName: "@desmoneyy", text: "this gonna be packed")
        ]
        reports = [
            Report(id: "r1", targetType: .comment, targetId: "c2", reporterId: "u_des",
                   reason: "Spam", details: "(demo report)")
        ]
    }
}
