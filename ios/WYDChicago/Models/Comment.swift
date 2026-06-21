import Foundation

// MARK: - events/{eventId}/comments/{commentId} (canon §4)

struct Comment: Codable, Identifiable, Hashable {
    /// Firestore document id.
    var id: String
    var authorId: String
    var authorName: String
    var text: String
    var createdAt: Date

    init(
        id: String,
        authorId: String,
        authorName: String,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.authorId = authorId
        self.authorName = authorName
        self.text = text
        self.createdAt = createdAt
    }
}
