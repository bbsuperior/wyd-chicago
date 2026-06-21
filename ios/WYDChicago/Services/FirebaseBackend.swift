import Foundation

// MARK: - FirebaseBackend — real Firestore/Auth backend (documented stub).
//
// This file compiles BEFORE the Firebase SPM packages are added: every method
// body is wrapped in `#if canImport(FirebaseFirestore)`. When Firebase is wired
// (see README), fill in the real calls — the documented intent is right here.
//
// It conforms to the same `Backend` protocol as `MockBackend`, so flipping
// AppState from `MockBackend()` to `FirebaseBackend()` is the only swap needed —
// exactly mirroring how the web flips data.js → firebase.js via backend.js.
//
// Canonical collection/field names come from PROJECT_CANON.md §4. Do not rename.

#if canImport(FirebaseFirestore)
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
#endif

@MainActor
final class FirebaseBackend: ObservableObject, Backend {

    let usingFirebase = true

    @Published private(set) var currentUserProfile: UserProfile?
    var currentUser: UserProfile? { currentUserProfile }

    #if canImport(FirebaseFirestore)
    private let db = Firestore.firestore()
    private var authHandle: AuthStateDidChangeListenerHandle?
    #endif

    init() {
        #if canImport(FirebaseFirestore)
        // Assumes FirebaseApp.configure() was called in the App entry point.
        // Bootstrap the current user profile if a session already exists.
        Task { await refreshCurrentUserProfile() }
        #endif
    }

    // MARK: - Auth

    func onAuthChange(_ callback: @escaping (UserProfile?) -> Void) -> () -> Void {
        #if canImport(FirebaseFirestore)
        // Listen to FirebaseAuth state, then load users/{uid} into a UserProfile.
        let handle = Auth.auth().addStateDidChangeListener { [weak self] _, fbUser in
            guard let self else { return }
            Task { @MainActor in
                if fbUser != nil {
                    await self.refreshCurrentUserProfile()
                } else {
                    self.currentUserProfile = nil
                }
                callback(self.currentUserProfile)
            }
        }
        return { Auth.auth().removeStateDidChangeListener(handle) }
        #else
        callback(nil)
        return {}
        #endif
    }

    func signUp(_ input: SignUpInput) async throws -> UserProfile {
        #if canImport(FirebaseFirestore)
        // 1. Auth.auth().createUser(withEmail:password:)
        // 2. Reserve username (transaction on a `usernames/{username}` doc) to enforce uniqueness.
        // 3. Write users/{uid} with the canonical §4 fields (role "user", emailVerified false).
        // 4. result.user.sendEmailVerification()
        // 5. Return the new UserProfile.
        let result = try await Auth.auth().createUser(withEmail: input.email, password: input.password)
        let uid = result.user.uid
        let profile = UserProfile(
            id: uid,
            displayName: input.displayName,
            username: input.username.lowercased(),
            birthYear: input.birthYear,
            interests: input.interests,
            role: .user,
            emailVerified: false
        )
        try await db.collection("users").document(uid).setData(encode(profile))
        try await result.user.sendEmailVerification()
        currentUserProfile = profile
        return profile
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func signIn(email: String, password: String) async throws -> UserProfile {
        #if canImport(FirebaseFirestore)
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        let profile = try await loadProfile(uid: result.user.uid)
        currentUserProfile = profile
        return profile
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func signOut() async throws {
        #if canImport(FirebaseFirestore)
        try Auth.auth().signOut()
        currentUserProfile = nil
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func sendVerification() async throws {
        #if canImport(FirebaseFirestore)
        try await Auth.auth().currentUser?.sendEmailVerification()
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func resetPassword(email: String) async throws {
        #if canImport(FirebaseFirestore)
        try await Auth.auth().sendPasswordReset(withEmail: email)
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func isAdmin() -> Bool { currentUserProfile?.isAdmin ?? false }
    func isHost() -> Bool { currentUserProfile?.isHost ?? false }

    func updateProfile(_ patch: ProfilePatch) async throws -> UserProfile {
        #if canImport(FirebaseFirestore)
        guard let uid = Auth.auth().currentUser?.uid else { throw BackendError.notSignedIn }
        var fields: [String: Any] = ["updatedAt": FieldValue.serverTimestamp()]
        if let v = patch.displayName { fields["displayName"] = v }
        if let v = patch.bio { fields["bio"] = v }
        if let v = patch.gradeYear { fields["gradeYear"] = v as Any }
        if let v = patch.neighborhood { fields["neighborhood"] = v as Any }
        if let v = patch.interests { fields["interests"] = v }
        if let v = patch.snapchatUsername { fields["snapchatUsername"] = v as Any }
        if let v = patch.instagramUsername { fields["instagramUsername"] = v as Any }
        if let v = patch.avatarUrl { fields["avatarUrl"] = v as Any }
        try await db.collection("users").document(uid).updateData(fields)
        let profile = try await loadProfile(uid: uid)
        currentUserProfile = profile
        return profile
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    // MARK: - API: read

    func listTags() async throws -> [Tag] {
        #if canImport(FirebaseFirestore)
        // db.collection("tags").order(by: "sort").getDocuments() → decode [Tag]
        let snap = try await db.collection("tags").order(by: "sort").getDocuments()
        return try snap.documents.map { try decode(Tag.self, id: $0.documentID, data: $0.data()) }
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func listEvents(_ query: FeedQuery) async throws -> [Event] {
        #if canImport(FirebaseFirestore)
        // Base: events where status == "published". Then apply server-side filters that
        // have composite indexes (see firebase/firestore.indexes.json):
        //   - eventType == query.type
        //   - neighborhood == query.neighborhood
        //   - order by startAt (soonest) or voteScore (hype)
        // "friends going" and "for you" sorts need client-side ranking after fetch.
        var q: Query = db.collection("events").whereField("status", isEqualTo: EventStatus.published.rawValue)
        if let type = query.type, !type.isEmpty { q = q.whereField("eventType", isEqualTo: type) }
        if let n = query.neighborhood, !n.isEmpty { q = q.whereField("neighborhood", isEqualTo: n) }
        switch query.sort {
        case .soonest: q = q.order(by: "startAt")
        default: q = q.order(by: "voteScore", descending: true)
        }
        let snap = try await q.getDocuments()
        var events = try snap.documents.map { try decode(Event.self, id: $0.documentID, data: $0.data()) }
        // Client-side search + friends/forYou ranking mirror the web behavior.
        if let s = query.search?.lowercased(), !s.isEmpty {
            events = events.filter { $0.title.lowercased().contains(s) || $0.description.lowercased().contains(s) }
        }
        return events
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func getEvent(id: String) async throws -> Event {
        #if canImport(FirebaseFirestore)
        // db.collection("events").document(id).getDocument(). Security rules hide
        // exactAddress unless the requester is "going" or an admin (canon §8).
        let doc = try await db.collection("events").document(id).getDocument()
        guard let data = doc.data() else { throw BackendError.notFound }
        return try decode(Event.self, id: doc.documentID, data: data)
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    // MARK: - API: RSVP / vote / save

    func rsvp(eventId: String, status: RSVPStatus) async throws {
        #if canImport(FirebaseFirestore)
        // Requires email_verified (enforced by rules). Write or delete
        // events/{eventId}/attendees/{uid}. Counter is fixed up by a Cloud Function
        // trigger; do an optimistic local update in the view model for snappiness.
        guard let uid = Auth.auth().currentUser?.uid else { throw BackendError.notSignedIn }
        let ref = db.collection("events").document(eventId).collection("attendees").document(uid)
        if status == .none {
            try await ref.delete()
        } else {
            try await ref.setData(["status": status.rawValue, "rsvpAt": FieldValue.serverTimestamp()])
        }
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func getMyRsvp(eventId: String) async throws -> RSVPStatus {
        #if canImport(FirebaseFirestore)
        guard let uid = Auth.auth().currentUser?.uid else { return .none }
        let doc = try await db.collection("events").document(eventId)
            .collection("attendees").document(uid).getDocument()
        if let raw = doc.data()?["status"] as? String { return RSVPStatus(rawValue: raw) ?? .none }
        return .none
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func vote(eventId: String, dir: VoteDir) async throws {
        #if canImport(FirebaseFirestore)
        // Write or delete events/{eventId}/votes/{uid}. A Cloud Function trigger
        // recomputes upvotes/downvotes/voteScore on the event doc.
        guard let uid = Auth.auth().currentUser?.uid else { throw BackendError.notSignedIn }
        let ref = db.collection("events").document(eventId).collection("votes").document(uid)
        if dir == .none {
            try await ref.delete()
        } else {
            try await ref.setData(["dir": dir.rawValue, "votedAt": FieldValue.serverTimestamp()])
        }
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func getMyVote(eventId: String) async throws -> VoteDir {
        #if canImport(FirebaseFirestore)
        guard let uid = Auth.auth().currentUser?.uid else { return .none }
        let doc = try await db.collection("events").document(eventId)
            .collection("votes").document(uid).getDocument()
        if let raw = doc.data()?["dir"] as? Int { return VoteDir(rawValue: raw) ?? .none }
        return .none
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func toggleSave(eventId: String) async throws -> Bool {
        #if canImport(FirebaseFirestore)
        // Toggle eventId in users/{uid}.savedEvents using arrayUnion/arrayRemove.
        guard let uid = Auth.auth().currentUser?.uid else { throw BackendError.notSignedIn }
        let ref = db.collection("users").document(uid)
        let saved = (try await ref.getDocument().data()?["savedEvents"] as? [String]) ?? []
        let nowSaved = !saved.contains(eventId)
        try await ref.updateData([
            "savedEvents": nowSaved ? FieldValue.arrayUnion([eventId]) : FieldValue.arrayRemove([eventId])
        ])
        return nowSaved
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func listAttendees(eventId: String) async throws -> [UserProfile] {
        #if canImport(FirebaseFirestore)
        // Read events/{eventId}/attendees, then batch-load the matching users/{uid} docs.
        let snap = try await db.collection("events").document(eventId).collection("attendees").getDocuments()
        var out: [UserProfile] = []
        for d in snap.documents {
            if let p = try? await loadProfile(uid: d.documentID) { out.append(p) }
        }
        return out
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func addComment(eventId: String, text: String) async throws -> Comment {
        #if canImport(FirebaseFirestore)
        guard let user = Auth.auth().currentUser, let profile = currentUserProfile else {
            throw BackendError.notSignedIn
        }
        let ref = db.collection("events").document(eventId).collection("comments").document()
        let comment = Comment(id: ref.documentID, authorId: user.uid,
                              authorName: "@\(profile.username)", text: text)
        try await ref.setData([
            "authorId": comment.authorId, "authorName": comment.authorName,
            "text": comment.text, "createdAt": FieldValue.serverTimestamp()
        ])
        return comment
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func listComments(eventId: String) async throws -> [Comment] {
        #if canImport(FirebaseFirestore)
        let snap = try await db.collection("events").document(eventId)
            .collection("comments").order(by: "createdAt").getDocuments()
        return try snap.documents.map { try decode(Comment.self, id: $0.documentID, data: $0.data()) }
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func report(_ input: ReportInput) async throws {
        #if canImport(FirebaseFirestore)
        // Create-only for authed users (rules); admins read the queue.
        guard let uid = Auth.auth().currentUser?.uid else { throw BackendError.notSignedIn }
        try await db.collection("reports").addDocument(data: [
            "targetType": input.targetType.rawValue, "targetId": input.targetId,
            "reporterId": uid, "reason": input.reason, "details": input.details,
            "status": ReportStatus.open.rawValue, "createdAt": FieldValue.serverTimestamp()
        ])
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    // MARK: - API: friends

    func searchUsers(query: String) async throws -> [UserProfile] {
        #if canImport(FirebaseFirestore)
        // Prefix query on username: where username >= q and username <= q + "\u{f8ff}".
        let q = query.lowercased()
        let snap = try await db.collection("users")
            .whereField("username", isGreaterThanOrEqualTo: q)
            .whereField("username", isLessThanOrEqualTo: q + "\u{f8ff}")
            .limit(to: 20).getDocuments()
        return try snap.documents.map { try decode(UserProfile.self, id: $0.documentID, data: $0.data()) }
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func addFriend(username: String) async throws {
        #if canImport(FirebaseFirestore)
        // Resolve username → uid, then write reciprocal edges under
        // users/{me}/friends/{them} (out, pending) and users/{them}/friends/{me} (in, pending).
        guard let me = Auth.auth().currentUser?.uid else { throw BackendError.notSignedIn }
        let snap = try await db.collection("users")
            .whereField("username", isEqualTo: username.lowercased()).limit(to: 1).getDocuments()
        guard let target = snap.documents.first else { throw BackendError.notFound }
        let them = target.documentID
        let now = FieldValue.serverTimestamp()
        try await db.collection("users").document(me).collection("friends").document(them)
            .setData(["status": "pending", "direction": "out", "since": now])
        try await db.collection("users").document(them).collection("friends").document(me)
            .setData(["status": "pending", "direction": "in", "since": now])
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func listFriends() async throws -> [UserProfile] {
        #if canImport(FirebaseFirestore)
        guard let me = Auth.auth().currentUser?.uid else { return [] }
        let snap = try await db.collection("users").document(me).collection("friends")
            .whereField("status", isEqualTo: "accepted").getDocuments()
        var out: [UserProfile] = []
        for d in snap.documents { if let p = try? await loadProfile(uid: d.documentID) { out.append(p) } }
        return out
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func listFriendRequests() async throws -> [UserProfile] {
        #if canImport(FirebaseFirestore)
        guard let me = Auth.auth().currentUser?.uid else { return [] }
        let snap = try await db.collection("users").document(me).collection("friends")
            .whereField("status", isEqualTo: "pending")
            .whereField("direction", isEqualTo: "in").getDocuments()
        var out: [UserProfile] = []
        for d in snap.documents { if let p = try? await loadProfile(uid: d.documentID) { out.append(p) } }
        return out
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func respondFriend(uid: String, accept: Bool) async throws {
        #if canImport(FirebaseFirestore)
        guard let me = Auth.auth().currentUser?.uid else { throw BackendError.notSignedIn }
        let mine = db.collection("users").document(me).collection("friends").document(uid)
        let theirs = db.collection("users").document(uid).collection("friends").document(me)
        if accept {
            try await mine.updateData(["status": "accepted"])
            try await theirs.updateData(["status": "accepted"])
        } else {
            try await mine.delete()
            try await theirs.delete()
        }
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    // MARK: - API: admin / host

    func createEvent(_ draft: EventDraft) async throws -> Event {
        #if canImport(FirebaseFirestore)
        // Rules allow this only for role host/admin. Default status is draft until
        // an admin publishes. Counters start at 0.
        guard let me = Auth.auth().currentUser?.uid, let profile = currentUserProfile else {
            throw BackendError.notSignedIn
        }
        let ref = db.collection("events").document()
        let ev = Event(
            id: ref.documentID, title: draft.title, description: draft.description,
            eventType: draft.eventType, tags: draft.tags, hostId: me, hostName: "@\(profile.username)",
            coverImageUrl: draft.coverImageUrl, startAt: draft.startAt, endAt: draft.endAt,
            venueName: draft.venueName, neighborhood: draft.neighborhood, approxArea: draft.approxArea,
            exactAddress: draft.exactAddress, priceCents: draft.priceCents, capacity: draft.capacity,
            ageMin: draft.ageMin, ageMax: draft.ageMax, recommendedFor: draft.recommendedFor,
            status: draft.status, isFeatured: draft.isFeatured, createdBy: me
        )
        try await ref.setData(encode(ev))
        return ev
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func updateEvent(id: String, draft: EventDraft) async throws -> Event {
        #if canImport(FirebaseFirestore)
        try await db.collection("events").document(id).updateData([
            "title": draft.title, "description": draft.description, "eventType": draft.eventType,
            "tags": draft.tags, "coverImageUrl": draft.coverImageUrl as Any, "startAt": draft.startAt,
            "endAt": draft.endAt as Any, "venueName": draft.venueName as Any,
            "neighborhood": draft.neighborhood as Any, "approxArea": draft.approxArea,
            "exactAddress": draft.exactAddress as Any, "priceCents": draft.priceCents,
            "capacity": draft.capacity as Any, "ageMin": draft.ageMin, "ageMax": draft.ageMax,
            "recommendedFor": draft.recommendedFor, "isFeatured": draft.isFeatured,
            "status": draft.status.rawValue, "updatedAt": FieldValue.serverTimestamp()
        ])
        return try await getEvent(id: id)
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func setEventStatus(id: String, status: EventStatus) async throws {
        #if canImport(FirebaseFirestore)
        try await db.collection("events").document(id).updateData([
            "status": status.rawValue, "updatedAt": FieldValue.serverTimestamp()
        ])
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    func listReports() async throws -> [Report] {
        #if canImport(FirebaseFirestore)
        // Admin-only by rules.
        let snap = try await db.collection("reports").order(by: "createdAt", descending: true).getDocuments()
        return try snap.documents.map { try decode(Report.self, id: $0.documentID, data: $0.data()) }
        #else
        fatalError("Add the Firebase SPM packages (see ios/README.md) to use FirebaseBackend.")
        #endif
    }

    // MARK: - Private helpers

    #if canImport(FirebaseFirestore)
    /// Reload users/{uid} for the signed-in auth user into `currentUserProfile`.
    private func refreshCurrentUserProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { currentUserProfile = nil; return }
        currentUserProfile = try? await loadProfile(uid: uid)
    }

    private func loadProfile(uid: String) async throws -> UserProfile {
        let doc = try await db.collection("users").document(uid).getDocument()
        guard let data = doc.data() else { throw BackendError.notFound }
        return try decode(UserProfile.self, id: doc.documentID, data: data)
    }

    /// Encode a Codable model to a Firestore field dictionary (drops the `id`,
    /// which is the document key, not a field).
    private func encode<T: Encodable>(_ value: T) -> [String: Any] {
        let encoder = Firestore.Encoder()
        var dict = (try? encoder.encode(value)) ?? [:]
        dict["id"] = nil
        return dict
    }

    /// Decode a Firestore document (plus its id) into a Codable model.
    private func decode<T: Decodable>(_ type: T.Type, id: String, data: [String: Any]) throws -> T {
        var merged = data
        merged["id"] = id
        return try Firestore.Decoder().decode(T.self, from: merged)
    }
    #endif
}
