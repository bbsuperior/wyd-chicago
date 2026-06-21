import Foundation

// MARK: - users/{uid} (canon §4)

struct UserProfile: Codable, Identifiable, Hashable {
    /// Firestore document id (== auth uid). Not stored as a field.
    var id: String

    var displayName: String
    var username: String                 // unique handle, lowercase [a-z0-9_], 3–20
    var avatarUrl: String?
    var bio: String
    var birthYear: Int                   // we never display exact DOB
    var gradeYear: String?               // "Freshman".."Senior"
    var neighborhood: String?            // e.g. "Lincoln Park"
    var interests: [String]              // tagIds (kind=interest)
    var snapchatUsername: String?
    var instagramUsername: String?
    var role: UserRole
    var savedEvents: [String]            // eventIds
    var emailVerified: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        displayName: String,
        username: String,
        avatarUrl: String? = nil,
        bio: String = "",
        birthYear: Int,
        gradeYear: String? = nil,
        neighborhood: String? = nil,
        interests: [String] = [],
        snapchatUsername: String? = nil,
        instagramUsername: String? = nil,
        role: UserRole = .user,
        savedEvents: [String] = [],
        emailVerified: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.username = username
        self.avatarUrl = avatarUrl
        self.bio = bio
        self.birthYear = birthYear
        self.gradeYear = gradeYear
        self.neighborhood = neighborhood
        self.interests = interests
        self.snapchatUsername = snapchatUsername
        self.instagramUsername = instagramUsername
        self.role = role
        self.savedEvents = savedEvents
        self.emailVerified = emailVerified
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: Derived

    var isAdmin: Bool { role == .admin }
    var isHost: Bool { role == .host || role == .admin }

    /// Age derived from birthYear (we never show DOB). Uses current year.
    var age: Int {
        let year = Calendar.current.component(.year, from: Date())
        return max(0, year - birthYear)
    }

    /// Initials for avatar fallback.
    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.joined().uppercased()
    }
}
