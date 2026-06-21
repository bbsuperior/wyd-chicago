// recommend.js — pure recommendation scoring shared by every backend (mock + firebase).
// No imports. Mirrors canon §4 so the "✨ For you" sort behaves identically across web & iOS.
//
//   score = 3*overlap(user.interests, event.tags)
//         + 2*friendsGoingCount
//         + recencyBoost            // sooner events get a small nudge
//         + neighborhoodBoost       // event in the user's neighborhood
//         - agePenalty              // event age range doesn't fit the user
//
// Keep this pure: same inputs -> same number, no Date.now() side effects beyond `now`.

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * @param {object|null} user   a User (uses interests[], neighborhood, birthYear)
 * @param {object}      event  an Event (uses tags[], startAt, neighborhood, ageMin, ageMax)
 * @param {number}      friendsGoingCount  how many of the user's friends are "going"
 * @returns {number} a comparable score; higher = better match
 */
export function recommendScore(user, event, friendsGoingCount = 0) {
  if (!event) return 0;
  const u = user || {};

  // --- 3 * interest-tag overlap ---
  const interests = Array.isArray(u.interests) ? u.interests : [];
  const eventTags = Array.isArray(event.tags) ? event.tags : [];
  const tagSet = new Set(eventTags);
  let overlap = 0;
  for (const t of interests) {
    if (tagSet.has(t)) overlap += 1;
  }
  let score = 3 * overlap;

  // --- 2 * friends going ---
  score += 2 * (Number(friendsGoingCount) || 0);

  // --- recency boost: events happening sooner get a gentle bump (0..3) ---
  // We boost imminence, not age — this is an "upcoming events" feed.
  const startMs = toMillis(event.startAt);
  if (startMs != null) {
    const daysOut = (startMs - Date.now()) / DAY_MS;
    if (daysOut >= 0) {
      // tonight (~0 days) ≈ 3, two weeks out ≈ 0
      score += Math.max(0, 3 - daysOut / 5);
    }
    // already-passed events get nothing extra (they shouldn't be in the feed anyway)
  }

  // --- neighborhood match ---
  if (u.neighborhood && event.neighborhood && u.neighborhood === event.neighborhood) {
    score += 2;
  }

  // --- age penalty: subtract when the user falls outside the event's age range ---
  const age = ageFromBirthYear(u.birthYear);
  if (age != null) {
    const ageMin = Number.isFinite(event.ageMin) ? event.ageMin : 14;
    const ageMax = Number.isFinite(event.ageMax) ? event.ageMax : 18;
    if (age < ageMin) score -= (ageMin - age);
    else if (age > ageMax) score -= (age - ageMax);
  }

  return score;
}

// Accepts ISO string, Date, millis number, or a Firestore-like { seconds } / toDate().
function toMillis(value) {
  if (value == null) return null;
  if (typeof value === 'number') return value;
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'string') {
    const ms = Date.parse(value);
    return Number.isNaN(ms) ? null : ms;
  }
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value.toDate === 'function') return value.toDate().getTime();
  if (typeof value.seconds === 'number') return value.seconds * 1000;
  return null;
}

function ageFromBirthYear(birthYear) {
  const by = Number(birthYear);
  if (!Number.isFinite(by) || by <= 0) return null;
  const now = new Date();
  return now.getFullYear() - by;
}
