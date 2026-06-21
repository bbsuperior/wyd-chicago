import Foundation

// MARK: - Recommendation score (canon §4 — kept pure, mirrors web/js/recommend.js)
//
// score = 3*overlap(user.interests, event.tags)
//       + 2*friendsGoingCount
//       + recencyBoost
//       + neighborhoodBoost
//       - agePenalty
//
// Powers the "✨ For you" sort. Pure function, no side effects.

enum Recommend {

    /// Compute a recommendation score for an event given the viewing user.
    /// - Parameters:
    ///   - user: the viewing user's profile.
    ///   - event: the candidate event.
    ///   - friendsGoingCount: how many of the user's friends are going/interested.
    static func score(user: UserProfile, event: Event, friendsGoingCount: Int) -> Double {
        // Interest overlap: how many of the user's interests match the event's tags.
        let userInterests = Set(user.interests)
        let eventTags = Set(event.tags + event.recommendedFor)
        let overlap = userInterests.intersection(eventTags).count

        // Recency boost: sooner events score higher (decays over ~14 days).
        let hoursUntil = event.startAt.timeIntervalSinceNow / 3600
        let recencyBoost: Double
        if hoursUntil < 0 {
            recencyBoost = 0                       // already started/past
        } else {
            recencyBoost = max(0, 5 - (hoursUntil / 72))   // ~5 down to 0 over ~15 days
        }

        // Neighborhood boost: same neighborhood feels closer to home.
        let neighborhoodBoost: Double = {
            guard let un = user.neighborhood, let en = event.neighborhood else { return 0 }
            return un.caseInsensitiveCompare(en) == .orderedSame ? 2 : 0
        }()

        // Age penalty: penalize events outside the user's age band.
        let age = user.age
        let agePenalty: Double = (age < event.ageMin || age > event.ageMax) ? 6 : 0

        return 3 * Double(overlap)
            + 2 * Double(friendsGoingCount)
            + recencyBoost
            + neighborhoodBoost
            - agePenalty
    }
}
