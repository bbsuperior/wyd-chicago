import Foundation

// MARK: - reports/{reportId} (canon §4)

enum ReportTargetType: String, Codable, CaseIterable {
    case event
    case user
    case comment
}

enum ReportStatus: String, Codable, CaseIterable {
    case open
    case reviewed
    case actioned
}

struct Report: Codable, Identifiable, Hashable {
    /// Firestore document id.
    var id: String
    var targetType: ReportTargetType    // "event" | "user" | "comment"
    var targetId: String
    var reporterId: String
    var reason: String
    var details: String
    var status: ReportStatus            // "open" | "reviewed" | "actioned"
    var createdAt: Date

    init(
        id: String,
        targetType: ReportTargetType,
        targetId: String,
        reporterId: String,
        reason: String,
        details: String = "",
        status: ReportStatus = .open,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.targetType = targetType
        self.targetId = targetId
        self.reporterId = reporterId
        self.reason = reason
        self.details = details
        self.status = status
        self.createdAt = createdAt
    }
}
