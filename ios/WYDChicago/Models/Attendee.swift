import Foundation

// MARK: - events/{eventId}/attendees/{uid} (canon §4)

struct Attendee: Codable, Identifiable, Hashable {
    /// Document id == attendee uid. Not stored as a field.
    var id: String
    var status: RSVPStatus      // "going" | "interested"
    var rsvpAt: Date

    init(id: String, status: RSVPStatus, rsvpAt: Date = Date()) {
        self.id = id
        self.status = status
        self.rsvpAt = rsvpAt
    }
}
