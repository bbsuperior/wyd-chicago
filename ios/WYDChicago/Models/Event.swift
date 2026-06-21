import Foundation

// MARK: - events/{eventId} (canon §4)

struct Event: Codable, Identifiable, Hashable {
    /// Firestore document id. Not stored as a field.
    var id: String

    var title: String
    var description: String
    var eventType: String                // single tagId with kind=eventType
    var tags: [String]                   // tagIds (kind=interest)
    var hostId: String?
    var hostName: String
    var coverImageUrl: String?
    var images: [String]
    var startAt: Date
    var endAt: Date?
    var venueName: String?
    var neighborhood: String?
    var approxArea: String               // shown before RSVP
    var exactAddress: String?            // revealed only after RSVP / to admin
    var priceCents: Int                  // 0 = free
    var capacity: Int?
    var ageMin: Int                      // default 14
    var ageMax: Int                      // default 18
    var recommendedFor: [String]         // tagIds
    var committedCount: Int              // attendees with status "going"
    var interestedCount: Int             // attendees with status "interested"
    var upvotes: Int
    var downvotes: Int
    var voteScore: Int                   // upvotes - downvotes (🔥 Hype sort)
    var status: EventStatus
    var isFeatured: Bool
    var createdBy: String                // admin/host uid
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        title: String,
        description: String,
        eventType: String,
        tags: [String] = [],
        hostId: String? = nil,
        hostName: String,
        coverImageUrl: String? = nil,
        images: [String] = [],
        startAt: Date,
        endAt: Date? = nil,
        venueName: String? = nil,
        neighborhood: String? = nil,
        approxArea: String,
        exactAddress: String? = nil,
        priceCents: Int = 0,
        capacity: Int? = nil,
        ageMin: Int = 14,
        ageMax: Int = 18,
        recommendedFor: [String] = [],
        committedCount: Int = 0,
        interestedCount: Int = 0,
        upvotes: Int = 0,
        downvotes: Int = 0,
        voteScore: Int = 0,
        status: EventStatus = .draft,
        isFeatured: Bool = false,
        createdBy: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.eventType = eventType
        self.tags = tags
        self.hostId = hostId
        self.hostName = hostName
        self.coverImageUrl = coverImageUrl
        self.images = images
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
        self.committedCount = committedCount
        self.interestedCount = interestedCount
        self.upvotes = upvotes
        self.downvotes = downvotes
        self.voteScore = voteScore
        self.status = status
        self.isFeatured = isFeatured
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: Derived display helpers

    var isFree: Bool { priceCents <= 0 }

    /// "$12" or "Free".
    var priceLabel: String {
        guard priceCents > 0 else { return "Free" }
        let dollars = Double(priceCents) / 100
        if dollars.truncatingRemainder(dividingBy: 1) == 0 {
            return "$\(Int(dollars))"
        }
        return String(format: "$%.2f", dollars)
    }

    /// Short start-time label, e.g. "Fri 8:00 PM".
    var startLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return f.string(from: startAt)
    }

    /// e.g. "Tonight" / "Tomorrow" / weekday.
    var whenChip: String {
        let cal = Calendar.current
        if cal.isDateInToday(startAt) { return "Tonight" }
        if cal.isDateInTomorrow(startAt) { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: startAt)
    }
}
