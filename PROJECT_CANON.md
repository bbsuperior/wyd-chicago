# WYD Chicago — Project Canon

> **This file is the single source of truth.** Every build agent, file, and platform
> (web + iOS) must follow the brand tokens, data model, and code contracts defined here.
> Do not invent alternate color values, collection names, or API shapes. When in doubt,
> this document wins.

---

## 1. What WYD Chicago is

**WYD** = "What You Doing?" — the question teenagers text each other a hundred times a week.
WYD Chicago answers it: a clean, dead-simple app that shows what's actually going on around
the city tonight — parties, kickbacks, concerts, games, fundraisers, open mics — and lets you
see who's going, commit to going, vote on what's good, and find people with the same interests.

- **Audience:** Chicago-area teenagers (high-school age, ~14–18). The UI must be obvious with
  zero learning curve. No menus to hunt through, no jargon, big tap targets, one clear action
  per screen.
- **Two clients, one backend:** a website (this repo, served on GitHub Pages) and a native iOS
  app (SwiftUI). Both talk to the same Firebase backend and mirror the same screens.
- **Owner / admin ("master login"):** Beckett and trusted admins can create, edit, publish, and
  cancel events, manage tags, and moderate reports. Regular teens browse, RSVP, vote, and add
  friends — they cannot create events unless granted a `host` role.

### Brand voice
Casual, confident, friendly, low-effort to read. Talk like a 16-year-old texting, not a brand.
Examples: "WYD tonight?", "See what's good 👀", "Your friends are going.", "Tap in."
Never condescending. Never corporate.

---

## 2. Design system (DARK-FIRST)

Default theme is **dark** — it reads "going out tonight," makes event photos pop, and feels
premium. A light theme is a later nice-to-have; build dark first. All colors are CSS custom
properties on the web and `Color` extensions on iOS. **Use these exact hex values.**

### Color tokens
```
--bg:           #0B0B12   /* app background, near-black indigo */
--surface:      #15151F   /* cards */
--surface-2:    #1E1E2C   /* raised / inputs / chips */
--border:       #2A2A3A   /* hairlines */
--text:         #F5F5FA   /* primary text */
--muted:        #9A9AB0   /* secondary text */
--brand:        #5B8CFF   /* primary — electric Chicago-sky blue */
--brand-2:      #C44CFF   /* secondary — electric purple (gradients) */
--accent:       #FF4D6D   /* hot pink/red — CTAs, votes, the Chicago-star nod */
--gold:         #FFC83D   /* highlights, upvotes, "featured" */
--success:      #2EE6A6   /* going / confirmed */
--danger:       #FF5A5A   /* cancel / report */
```

### Signature gradient ("city night")
`linear-gradient(135deg, #5B8CFF 0%, #C44CFF 55%, #FF4D6D 100%)`
Used on the logo, primary buttons, and the hero. Reserve it for hype moments; don't drown the UI.

### Typography
- **Display / headings:** `Space Grotesk` (Google Fonts), weights 500/600/700. Punchy, modern.
- **Body / UI:** `Inter` (Google Fonts), weights 400/500/600.
- Web loads both from Google Fonts CDN. iOS bundles them (or falls back to SF Pro Rounded).

### Shape & motion
- Radius: cards/sheets `20px`, buttons/inputs `14px`, chips/pills `999px`. Friendly, rounded.
- Soft shadows; neon glow only on the primary CTA (`box-shadow: 0 8px 30px rgba(91,140,255,.35)`).
- Subtle 150–200ms transitions. Respect `prefers-reduced-motion`.

### Logo / motif
Wordmark **"WYD"** in Space Grotesk 700 with the city-night gradient, followed by a small
**six-pointed star** (the Chicago flag star) as the dot/accent. "Chicago" sits beneath in muted
caps with tracking. A reusable inline SVG star lives in the web assets and iOS design system.

### Iconography
Simple line icons (Lucide-style). On web, inline SVGs in `js/icons.js`. On iOS, SF Symbols.

---

## 3. Information architecture (screens — web & iOS mirror each other)

1. **Onboarding / Auth** — sign up (email + password), pick username, age/grade, pick interest
   tags; email verification gate; login; forgot password.
2. **Feed (Home)** — the core screen. Scrollable list of event cards. Filter chips across the top
   (event type, neighborhood, when) and a sort control (🔥 Hype / 🕒 Soonest / 👥 Friends going /
   ✨ For you). Search. This is where most time is spent.
3. **Event detail** — cover image, title, host, when, *approximate* location (exact address
   revealed only after RSVP), description, tags, "recommended for" tags, attendee counts
   (committed vs interested), avatars of friends going, RSVP (Going / Interested), upvote/downvote,
   share to Snapchat / Instagram, comments.
4. **Create / Edit event** — admin/host only.
5. **Profile** — your name, username, age, interests, Snapchat + Instagram handles, friends count,
   events you're going to, saved events, settings, sign out.
6. **Friends** — add by username (Snapchat-style), incoming/outgoing requests, friends list,
   "share my Snap."
7. **Admin dashboard ("master login")** — create/edit/publish/cancel events, see RSVP lists,
   manage tags, feature events, review reports. Gated by `admin` role.
8. **Safety** — report, block, community guidelines, age gate. Linked from event detail & profile.

iOS uses a `TabView`: **Feed · Search · ➕ (host/admin only) · Friends · Profile**, with Admin and
Event-detail pushed as navigation destinations.

---

## 4. Data model (Firebase / Firestore)

Collection and field names below are **canonical**. Web mock data, iOS models, security rules,
and Cloud Functions must all match these names exactly.

### `users/{uid}`
```
displayName: string
username: string            // unique handle, lowercase, [a-z0-9_], 3–20
avatarUrl: string|null
bio: string
birthYear: number          // used to derive age range; we never display exact DOB
gradeYear: string|null      // "Freshman".."Senior" optional
neighborhood: string|null   // e.g. "Lincoln Park"
interests: string[]         // tagIds (kind=interest)
snapchatUsername: string|null
instagramUsername: string|null
role: "user" | "host" | "admin"   // default "user"; admin = "master login"
savedEvents: string[]       // eventIds
emailVerified: boolean      // mirrors auth token
createdAt: timestamp
updatedAt: timestamp
```
Subcollections:
- `users/{uid}/friends/{friendUid}` → `{ status: "pending"|"accepted", since: timestamp, direction: "in"|"out" }`

### `events/{eventId}`
```
title: string
description: string
eventType: string           // single tagId with kind=eventType (e.g. "house-party")
tags: string[]              // tagIds (kind=interest) for matching/recommendation
hostId: string|null         // uid if a host posted it
hostName: string            // display name of host ("@beckett" or "WYD Team")
coverImageUrl: string|null
images: string[]
startAt: timestamp
endAt: timestamp|null
venueName: string|null
neighborhood: string|null
approxArea: string          // shown before RSVP, e.g. "Wicker Park"
exactAddress: string|null   // revealed only after RSVP / to admin
priceCents: number          // 0 = free
capacity: number|null
ageMin: number              // default 14
ageMax: number              // default 18
recommendedFor: string[]    // tagIds — "who it's recommended for"
committedCount: number      // attendees with status "going"
interestedCount: number     // attendees with status "interested"
upvotes: number
downvotes: number
voteScore: number           // upvotes - downvotes (used for 🔥 Hype sort)
status: "draft" | "published" | "cancelled"
isFeatured: boolean
createdBy: string           // admin/host uid
createdAt: timestamp
updatedAt: timestamp
```
Subcollections:
- `events/{eventId}/attendees/{uid}` → `{ status: "going"|"interested", rsvpAt: timestamp }`
- `events/{eventId}/votes/{uid}`     → `{ dir: 1 | -1, votedAt: timestamp }`
- `events/{eventId}/comments/{commentId}` → `{ authorId, authorName, text, createdAt }`

### `tags/{tagId}`
```
label: string               // "House Party"
kind: "eventType" | "interest"
emoji: string               // "🏠"
color: string               // hex used for the chip accent
sort: number
```

### `reports/{reportId}`
```
targetType: "event" | "user" | "comment"
targetId: string
reporterId: string
reason: string
details: string
status: "open" | "reviewed" | "actioned"
createdAt: timestamp
```

### Counters & recommendation
- `committedCount`, `interestedCount`, `upvotes`, `downvotes`, `voteScore` are denormalized and
  maintained by Cloud Functions triggers on the `attendees` / `votes` subcollections (with a
  client-side optimistic update for snappy UI). Document the distributed-counter approach.
- **Recommendation score** (client-computable, also a Cloud Function later):
  `score = 3*overlap(user.interests, event.tags) + 2*friendsGoingCount + recencyBoost + neighborhoodBoost - agePenalty`.
  Powers the **✨ For you** sort. Keep the function pure and shared in spirit across web & iOS.

### Auth & roles
- Firebase Auth, **email/password with mandatory email verification**. Optional later: Sign in with
  Apple / Google. RSVP and voting require `request.auth.token.email_verified == true`.
- **Admin ("master login")** = custom claim `admin: true` (and/or `users/{uid}.role == "admin"`).
  Set via a Cloud Function callable restricted to existing admins, or the Firebase console for the
  first owner (Beckett). Hosts get `role: "host"` to create events without full admin powers.

---

## 5. Web code contract (so files built independently still fit together)

The website is **buildless** — plain ES modules + custom CSS, served straight from `web/` on
GitHub Pages. No bundler, no npm install required to view it. (Firebase loads from its CDN.)

### The backend interface (THE contract)
`web/js/data.js` (mock, localStorage-backed) **and** `web/js/firebase.js` (real Firestore/Auth)
both implement the SAME interface. `web/js/backend.js` picks one at runtime: it uses Firebase iff
`web/js/firebase-config.js` contains real keys, otherwise the mock. App code imports ONLY from
`backend.js`, never directly from `data.js`/`firebase.js`.

```js
// backend.js exports:
export const Auth = {
  currentUser(): User | null,
  onChange(cb: (user|null) => void): unsubscribe,
  signUp({ email, password, username, displayName, birthYear, interests }): Promise<User>,
  signIn({ email, password }): Promise<User>,
  signOut(): Promise<void>,
  sendVerification(): Promise<void>,
  resetPassword(email): Promise<void>,
  isAdmin(): boolean,
  isHost(): boolean,
  updateProfile(patch): Promise<User>,
};

export const API = {
  listTags(): Promise<Tag[]>,
  listEvents({ type, neighborhood, when, sort, search, friendsOnly, forYou } = {}): Promise<Event[]>,
  getEvent(id): Promise<Event>,
  rsvp(id, status /* "going"|"interested"|null */): Promise<void>,
  getMyRsvp(id): Promise<"going"|"interested"|null>,
  vote(id, dir /* 1 | -1 | 0 */): Promise<void>,
  getMyVote(id): Promise<1|-1|0>,
  toggleSave(id): Promise<boolean>,
  listAttendees(id): Promise<User[]>,
  addComment(id, text): Promise<Comment>,
  listComments(id): Promise<Comment[]>,
  report({ targetType, targetId, reason, details }): Promise<void>,
  // friends
  searchUsers(query): Promise<User[]>,
  addFriend(username): Promise<void>,
  listFriends(): Promise<User[]>,
  listFriendRequests(): Promise<User[]>,
  respondFriend(uid, accept): Promise<void>,
  // admin / host
  createEvent(data): Promise<Event>,
  updateEvent(id, patch): Promise<Event>,
  setEventStatus(id, status): Promise<void>,
  listReports(): Promise<Report[]>,
};

export const USING_FIREBASE; // boolean
export function recommendScore(user, event, friendsGoingCount): number;
```

`recommendScore` lives in a shared `web/js/recommend.js` imported by both implementations.

### File ownership (avoid collisions)
- `web/index.html` — app shell + landing/hero + feed + event-detail (single-page; hash router).
- `web/admin.html` — admin/master dashboard.
- `web/css/app.css` — the entire design system + components (tokens from §2).
- `web/js/icons.js` — inline SVG icon set + the Chicago star logo SVG.
- `web/js/recommend.js` — `recommendScore` (pure).
- `web/js/data.js` — mock/localStorage backend implementing the contract + seed import.
- `web/js/firebase-config.js` — placeholder keys + how to fill them (safe to commit; web keys are public).
- `web/js/firebase.js` — real Firestore/Auth backend implementing the contract.
- `web/js/backend.js` — the switcher (`USING_FIREBASE`, re-exports `Auth`/`API`).
- `web/js/ui.js` — render helpers (event card, chips, avatars, sheets, toast).
- `web/js/app.js` — router + page controllers wiring `ui.js` to `backend.js`.
- `web/js/admin.js` — admin dashboard logic.
- `web/seed.json` (or `web/js/seed.js`) — ~12 realistic Chicago demo events + tags so the site
  looks alive on first load with no backend. (Demo content; clearly fictional.)

The site must **work fully on GitHub Pages with no Firebase configured** (mock mode), so Beckett
can show it to people immediately.

---

## 6. iOS code contract

- SwiftUI, iOS 16+, MVVM. Firebase via Swift Package Manager (FirebaseAuth, FirebaseFirestore,
  FirebaseStorage). Folder layout under `ios/WYDChicago/`:
  `App/` (entry + tabs), `Models/` (Codable structs mirroring §4), `Services/` (AuthService,
  EventService, FirestoreService protocol + a MockService for previews), `DesignSystem/`
  (Color+Theme, Typography, reusable views), `Features/<Screen>/` (View + ViewModel).
- Mirror the web `Auth`/`API` surface as Swift protocols so behavior matches across clients.
- Ship with a `MockService` so SwiftUI previews and the simulator render real-looking content
  before Firebase is wired. Include a `README` explaining how to create the Xcode project and add
  the `GoogleService-Info.plist`.
- **Hard rule:** never integrate HealthKit (out of scope and previously caused launch hangs in
  another project).

---

## 7. Firebase backend deliverables

- `firebase/firestore.rules` — real, enforce §4 roles (admins/hosts write events; users own their
  profile/RSVP/vote; email-verified gate on RSVP/vote; reports create-only for auth users; admins
  read reports).
- `firebase/storage.rules` — event cover images & avatars; size/type limits.
- `firebase/firestore.indexes.json` — composite indexes for feed queries (status+startAt,
  status+voteScore, eventType+startAt, etc.).
- `firebase/firebase.json` — hosting (optional), firestore, storage, functions config.
- `firebase/seed/*.json` + a seed script — tags + demo events for a fresh project.
- `firebase/functions/` — Node 20 Cloud Functions stubs: maintain counters (attendee/vote
  triggers), `onUserCreate` (default profile + role), `setAdminRole` (callable, admin-only),
  `sendWelcomeOnVerify`, nightly recommendation refresh (optional). Document that **deploying
  Functions requires the Blaze plan** (Beckett must enable billing on the new project — Spark
  cannot deploy Functions). Everything else runs on the free Spark tier.
- A new Firebase project is required (do NOT reuse `my-gym-app-cc57a`). Suggested id:
  `wyd-chicago`. The setup guide walks through creating it.

---

## 8. Safety & trust (non-negotiable for a minors' app)

- Age gate at sign-up; events carry `ageMin`/`ageMax`.
- **Exact address is hidden until a user RSVPs "going"** — only `approxArea`/neighborhood shows
  publicly. (`exactAddress` is gated in security rules.)
- Report & block on events, users, comments → `reports` collection → admin moderation queue.
- Community guidelines screen; no harassment, no illegal-goods promotion, hosts accountable.
- Admins can cancel/unpublish instantly. Default events to `draft` until an admin publishes.
- Privacy: collect the minimum; never display birth date; friends-only visibility options later.

---

## 9. Conventions

- Indent 2 spaces (web/JS/JSON), 4 spaces (Swift). UTF-8, LF endings.
- Dates stored as Firestore timestamps; in mock JSON use ISO-8601 strings.
- Money in integer cents.
- Commit messages: clear and imperative. This repo does NOT use the Rep status-tag convention.
- Demo/seed content is fictional and clearly labeled; no real addresses or real minors' data.
