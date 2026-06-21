# Architecture

WYD Chicago is **two clients on one backend**: a buildless website (served on GitHub Pages) and a
native iOS app (SwiftUI). Both mirror the same screens and talk to the same Firebase project.

```
        ┌─────────────────┐         ┌─────────────────┐
        │   Web client    │         │   iOS client    │
        │  (web/, ES mods)│         │ (SwiftUI, MVVM) │
        └────────┬────────┘         └────────┬────────┘
                 │  same Auth/API surface     │
                 ▼                            ▼
        ┌──────────────────────────────────────────────┐
        │              Firebase backend                 │
        │  Auth · Firestore · Storage · Cloud Functions │
        └──────────────────────────────────────────────┘
```

The guiding rule: **web and iOS expose the same `Auth` + `API` surface** so behavior matches
across clients. The web defines it as ES-module exports; iOS mirrors it as Swift protocols.

---

## The `backend.js` switcher pattern (web)

The website never imports a concrete backend directly. There is one indirection point:

```
app.js / admin.js / ui.js   ──imports──▶   backend.js
                                              │
                            picks ONE at runtime:
                       ┌──────────────────────┴───────────────────────┐
                       ▼                                               ▼
                  data.js  (mock, localStorage)              firebase.js (Firestore/Auth)
                       └──────────────┬────────────────────────────────┘
                          both implement the SAME contract
                                      │
                            recommend.js (pure recommendScore, shared)
```

`backend.js` decides which implementation to use:

- If `web/js/firebase-config.js` contains **real keys** → use `firebase.js` (live mode).
- Otherwise → use `data.js` (mock mode). This is the default and is what GitHub Pages serves.

`backend.js` re-exports `Auth`, `API`, the boolean `USING_FIREBASE`, and `recommendScore`. Every
page controller imports **only** from `backend.js`. Swapping mock ↔ Firebase changes nothing in
app code — it's a config flip.

### Why buildless

The web client is plain ES modules + custom CSS, no bundler and no `npm install` to view it.
Firebase loads from its CDN. This keeps GitHub Pages deployment trivial (just copy `web/`) and
lets the site run fully in demo mode for instant sharing. See
[CONTRIBUTING.md](CONTRIBUTING.md#staying-buildless) for the rules that keep it that way.

---

## The shared contract

Both web backends implement the same interface (full signatures live in the
[Project Canon §5](../PROJECT_CANON.md) and are summarized in [DATA_MODEL.md](DATA_MODEL.md)):

- **`Auth`** — `currentUser`, `onChange`, `signUp`, `signIn`, `signOut`, `sendVerification`,
  `resetPassword`, `isAdmin`, `isHost`, `updateProfile`.
- **`API`** — events (`listEvents`, `getEvent`, `rsvp`, `vote`, `toggleSave`, `listAttendees`,
  comments, `report`), friends (`searchUsers`, `addFriend`, `listFriends`, `listFriendRequests`,
  `respondFriend`), and admin/host (`createEvent`, `updateEvent`, `setEventStatus`, `listReports`),
  plus `listTags`.

`recommendScore(user, event, friendsGoingCount)` is a **pure** function in `web/js/recommend.js`,
imported by both backends so the ✨ For you ranking is identical in mock and live mode.

---

## Data flow

### Read (e.g. the Feed)
1. `app.js` asks `backend.js` → `API.listEvents({ sort, type, ... })`.
2. In mock mode, `data.js` reads/filters from localStorage (seeded from `seed.json`). In live mode,
   `firebase.js` runs a Firestore query (backed by composite indexes).
3. For `sort: "forYou"`, both compute `recommendScore` per event and sort descending.
4. `ui.js` renders event cards; `app.js` wires the interactions.

### Write (e.g. RSVP / vote)
1. User taps **Going** → `API.rsvp(id, "going")`.
2. The client does an **optimistic update** (bump `committedCount` locally for a snappy UI).
3. Mock mode persists to localStorage. Live mode writes to `events/{id}/attendees/{uid}`; a Cloud
   Function trigger then maintains the denormalized `committedCount` authoritatively.
4. **Safety gate:** `exactAddress` is only returned to a user who has RSVP'd "going" (or to an
   admin). In live mode this is enforced by Firestore security rules; the mock mirrors the behavior.

Counters (`committedCount`, `interestedCount`, `upvotes`, `downvotes`, `voteScore`) are denormalized
and maintained server-side — see the distributed-counter notes in [DATA_MODEL.md](DATA_MODEL.md).

---

## Mock mode vs Firebase mode

| | Mock mode (`data.js`) | Firebase mode (`firebase.js`) |
| --- | --- | --- |
| Trigger | no real keys in `firebase-config.js` | real keys present |
| Storage | browser `localStorage`, seeded from `seed.json` | Firestore + Storage |
| Auth | fake session incl. the demo admin login | Firebase Auth + email verification |
| Counters | updated inline in the mock | Cloud Function triggers |
| Address gate | enforced in mock logic | enforced in security rules |
| Use | demos, local dev, GitHub Pages default | production |

Both satisfy the same contract, so the rest of the app can't tell which is active (other than the
exported `USING_FIREBASE` flag, used only to show a small "demo mode" hint).

---

## How web and iOS mirror each other

- **Same data model** — iOS `Codable` structs in `ios/WYDChicago/Models/` use the exact collection
  and field names from [DATA_MODEL.md](DATA_MODEL.md).
- **Same service surface** — iOS defines a `FirestoreService` protocol mirroring the web `Auth`/`API`
  methods, with a real implementation and a `MockService` for SwiftUI previews (the iOS equivalent
  of `data.js`).
- **Same screens** — Feed · Search · ➕ (host/admin) · Friends · Profile in a `TabView`, with Admin
  and Event-detail as navigation destinations.
- **Same recommendation logic** — `recommendScore` is kept pure and equivalent on both platforms.

The result: a feature shipped on one client has a clear, matching shape on the other.
