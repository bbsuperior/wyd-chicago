# Data Model

The Firestore collections, fields, and subcollections below are **canonical** — web mock data,
iOS `Codable` models, security rules, and Cloud Functions all use these exact names. This is a
readable writeup of [Project Canon §4](../PROJECT_CANON.md); the canon wins on any conflict.

Conventions: timestamps are Firestore timestamps (ISO-8601 strings in mock JSON); money is integer
cents; usernames are lowercase `[a-z0-9_]`, 3–20 chars.

---

## ER-style overview

```
users/{uid}
  └── friends/{friendUid}        (status, since, direction)

events/{eventId}
  ├── attendees/{uid}            (status: going|interested, rsvpAt)
  ├── votes/{uid}                (dir: +1|-1, votedAt)
  └── comments/{commentId}       (authorId, authorName, text, createdAt)

tags/{tagId}                     (label, kind: eventType|interest, emoji, color, sort)

reports/{reportId}               (targetType, targetId, reporterId, reason, details, status)

Relationships (by id reference, not nested):
  users.interests[]   ─▶ tags (kind=interest)
  events.eventType    ─▶ tags (kind=eventType)   [single]
  events.tags[]       ─▶ tags (kind=interest)
  events.recommendedFor[] ─▶ tags (kind=interest)
  events.hostId / createdBy ─▶ users
  reports.targetId    ─▶ events | users | comments
```

---

## `users/{uid}`

| Field | Type | Notes |
| --- | --- | --- |
| `displayName` | string | |
| `username` | string | unique, lowercase `[a-z0-9_]`, 3–20 |
| `avatarUrl` | string \| null | |
| `bio` | string | |
| `birthYear` | number | derives an **age range** — exact DOB is never displayed |
| `gradeYear` | string \| null | "Freshman".."Senior", optional |
| `neighborhood` | string \| null | e.g. "Lincoln Park" |
| `interests` | string[] | tagIds with `kind=interest` |
| `snapchatUsername` | string \| null | |
| `instagramUsername` | string \| null | |
| `role` | `"user" \| "host" \| "admin"` | default `"user"`; `admin` = "master login" |
| `savedEvents` | string[] | eventIds |
| `emailVerified` | boolean | mirrors the auth token |
| `createdAt` / `updatedAt` | timestamp | |

**Subcollection — `users/{uid}/friends/{friendUid}`**

```
{ status: "pending" | "accepted", since: timestamp, direction: "in" | "out" }
```

`direction` distinguishes incoming vs outgoing requests for the Friends screen.

---

## `events/{eventId}`

| Field | Type | Notes |
| --- | --- | --- |
| `title` | string | |
| `description` | string | |
| `eventType` | string | **single** tagId with `kind=eventType` (e.g. `house-party`) |
| `tags` | string[] | tagIds (`kind=interest`) used for matching/recommendation |
| `hostId` | string \| null | uid if a host posted it |
| `hostName` | string | display name ("@beckett" or "WYD Team") |
| `coverImageUrl` | string \| null | |
| `images` | string[] | |
| `startAt` | timestamp | |
| `endAt` | timestamp \| null | |
| `venueName` | string \| null | |
| `neighborhood` | string \| null | |
| `approxArea` | string | shown **before** RSVP, e.g. "Wicker Park" |
| `exactAddress` | string \| null | **revealed only after RSVP "going" / to admin** |
| `priceCents` | number | `0` = free |
| `capacity` | number \| null | |
| `ageMin` | number | default `14` |
| `ageMax` | number | default `18` |
| `recommendedFor` | string[] | tagIds — "who it's recommended for" |
| `committedCount` | number | attendees with status `going` (denormalized) |
| `interestedCount` | number | attendees with status `interested` (denormalized) |
| `upvotes` | number | denormalized |
| `downvotes` | number | denormalized |
| `voteScore` | number | `upvotes − downvotes`, used for 🔥 Hype sort |
| `status` | `"draft" \| "published" \| "cancelled"` | events default to `draft` until an admin publishes |
| `isFeatured` | boolean | |
| `createdBy` | string | admin/host uid |
| `createdAt` / `updatedAt` | timestamp | |

**Subcollections**

| Path | Shape |
| --- | --- |
| `events/{id}/attendees/{uid}` | `{ status: "going" \| "interested", rsvpAt: timestamp }` |
| `events/{id}/votes/{uid}` | `{ dir: 1 \| -1, votedAt: timestamp }` |
| `events/{id}/comments/{commentId}` | `{ authorId, authorName, text, createdAt }` |

> **Safety:** `exactAddress` is gated. Only `approxArea`/`neighborhood` shows publicly; the exact
> address is returned only to a user who has RSVP'd "going" or to an admin. See [SAFETY.md](SAFETY.md).

---

## `tags/{tagId}`

```
label: string      // "House Party"
kind:  "eventType" | "interest"
emoji: string      // "🏠"
color: string      // hex used for the chip accent
sort:  number
```

Two kinds in one collection: `eventType` tags classify an event (one per event); `interest` tags
power matching, profiles, and the ✨ For you ranking.

---

## `reports/{reportId}`

```
targetType: "event" | "user" | "comment"
targetId:   string
reporterId: string
reason:     string
details:    string
status:     "open" | "reviewed" | "actioned"
createdAt:  timestamp
```

Create-only for authenticated users; admins read and work the moderation queue.

---

## Counters (denormalized, distributed)

`committedCount`, `interestedCount`, `upvotes`, `downvotes`, and `voteScore` are **denormalized**
onto the event document so the feed can read and sort them in a single query (no fan-out reads of
subcollections).

- **Authoritative path:** Cloud Function triggers on the `attendees` and `votes` subcollections
  recompute the counters on every write. This is the **distributed-counter approach**: each RSVP or
  vote is its own subcollection document (one per user), so concurrent writers never contend on a
  single hot field — the function aggregates them server-side. For very high traffic this generalizes
  to sharded counters, but per-user docs already spread the load.
- **Snappy path:** the client applies an **optimistic update** locally the moment the user taps,
  then reconciles when the function's authoritative value lands. `voteScore` is always kept as
  `upvotes − downvotes`.

In mock mode there are no triggers, so `data.js` updates the counters inline.

---

## Recommendation scoring (✨ For you)

A **pure, client-computable** function (also a Cloud Function later), shared in spirit across web
(`web/js/recommend.js`) and iOS:

```
score = 3 * overlap(user.interests, event.tags)
      + 2 * friendsGoingCount
      + recencyBoost
      + neighborhoodBoost
      − agePenalty
```

- `overlap(...)` — count of shared interest tagIds between the user and the event.
- `friendsGoingCount` — friends with an `attendees` record on the event (weighted heaviest after
  interests).
- `recencyBoost` — soon-but-not-past events rank higher.
- `neighborhoodBoost` — event in (or near) the user's neighborhood.
- `agePenalty` — pushes down events outside the user's `ageMin`/`ageMax` band.

Keeping it pure means mock and live mode rank identically, and web and iOS stay equivalent.

---

## Auth & roles (summary)

- Firebase Auth, **email/password with mandatory email verification**. RSVP and voting require
  `request.auth.token.email_verified == true`.
- **Admin ("master login")** = custom claim `admin: true` and/or `users/{uid}.role == "admin"`. Set
  via an admin-only callable Function, or the Firebase console for the first owner (Beckett).
- **Host** = `role: "host"` — can create events without full admin powers.

Enforcement details live in `firebase/firestore.rules`; setup in [FIREBASE_SETUP.md](FIREBASE_SETUP.md).
