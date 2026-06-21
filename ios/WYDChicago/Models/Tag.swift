import Foundation

// MARK: - tags/{tagId} (canon §4)

struct Tag: Codable, Identifiable, Hashable {
    /// Firestore document id (the tagId, e.g. "house-party").
    var id: String

    var label: String        // "House Party"
    var kind: TagKind        // eventType | interest
    var emoji: String        // "🏠"
    var color: String        // hex used for the chip accent
    var sort: Int

    init(
        id: String,
        label: String,
        kind: TagKind,
        emoji: String,
        color: String,
        sort: Int = 0
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.emoji = emoji
        self.color = color
        self.sort = sort
    }
}
