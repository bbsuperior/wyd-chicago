import Foundation

// MARK: - Enums mirroring canon §4

/// users/{uid}.role — "admin" is the "master login".
enum UserRole: String, Codable, CaseIterable {
    case user
    case host
    case admin
}

/// events/{eventId}.status — events default to draft until an admin publishes.
enum EventStatus: String, Codable, CaseIterable {
    case draft
    case published
    case cancelled
}

/// attendees/{uid}.status. `none` is a client-side convenience for "no RSVP".
enum RSVPStatus: String, Codable, CaseIterable {
    case going
    case interested
    case none

    var label: String {
        switch self {
        case .going: return "Going"
        case .interested: return "Interested"
        case .none: return "Tap in"
        }
    }
}

/// tags/{tagId}.kind
enum TagKind: String, Codable, CaseIterable {
    case eventType
    case interest
}

/// votes/{uid}.dir — stored as 1 / -1. `none` (0) means no vote.
enum VoteDir: Int, Codable, CaseIterable {
    case up = 1
    case down = -1
    case none = 0
}
