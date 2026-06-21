# Roadmap

Phased plan from scaffold to a real, shippable minors' events app. Each phase builds on the last;
safety work is threaded throughout, not bolted on at the end.

---

## Phase 0 — Foundation (this scaffold) ✅

The brand, contracts, and skeleton that everything else hangs off.

- [x] `PROJECT_CANON.md` — single source of truth (brand, data model, contracts, safety).
- [x] Design system tokens (dark-first) and the city-night gradient / star logo.
- [x] Web scaffold: buildless ES modules, the `backend.js` switcher, mock backend, seed data.
- [x] iOS scaffold: SwiftUI MVVM layout, models, `MockService` for previews.
- [x] Firebase config skeleton: rules, indexes, storage rules, seed, Functions stubs.
- [x] Docs (architecture, data model, features, roadmap, safety, setup, design, contributing).
- [x] GitHub Pages deploy workflow + demo mode (site runs with no backend).

---

## Phase 1 — Firebase live + email verification

- [ ] Create the **new** `wyd-chicago` Firebase project (not `my-gym-app-cc57a`).
- [ ] Enable Email/Password auth and **mandatory email verification**.
- [ ] Create Firestore + Storage; deploy `firestore.rules`, `storage.rules`, and indexes (Spark).
- [ ] Paste web keys into `web/js/firebase-config.js` so the site flips to live mode.
- [ ] Run the seed script to load tags + demo events.
- [ ] Set the first admin (Beckett) via console custom claim or the `setAdminRole` callable.

---

## Phase 2 — Web MVP (feed / RSVP / vote / auth)

- [ ] Auth + onboarding (sign up, username, interests, verification gate, login, reset).
- [ ] Feed with filter chips, sort (🔥 / 🕒 / 👥 / ✨), and search.
- [ ] Event detail with approximate-location gate and exact-address reveal after RSVP "going".
- [ ] RSVP (going/interested) and upvote/downvote with optimistic updates.
- [ ] Profile (interests, Snap/IG handles, going/saved events).

---

## Phase 3 — Admin + moderation

- [ ] Admin dashboard: create/edit/publish/cancel events, RSVP lists, feature events.
- [ ] Tag management.
- [ ] Reports moderation queue (open → reviewed → actioned).
- [ ] Block; instant cancel/unpublish.

---

## Phase 4 — Friends + recommendations

- [ ] Add-by-username, incoming/outgoing requests, friends list.
- [ ] 👥 Friends-going sort and friend avatars on event detail.
- [ ] ✨ For-you ranking wired to `recommendScore` (interests + friends + recency + neighborhood).
- [ ] Optional nightly recommendation refresh Cloud Function.

---

## Phase 5 — iOS app to TestFlight

- [ ] Create the Xcode project, add Firebase via SPM, drop in `GoogleService-Info.plist`.
- [ ] Build Feed · Search · ➕ · Friends · Profile against `MockService`, then live services.
- [ ] Match the web behavior via the shared service surface.
- [ ] Ship a build to **TestFlight** for trusted testers. *(Never integrate HealthKit.)*

---

## Phase 6 — Snapchat sharing + maps + push

- [ ] Share-event-to-Snapchat from event detail.
- [ ] Adopt **Snap Kit** Login + Creative Kit (see the Snapchat reality note in [FEATURES.md](FEATURES.md)).
- [ ] Map view for events (approximate area only until RSVP).
- [ ] Push notifications (friend requests, event reminders, "your friends are going").

---

> Phases can overlap, but **Phase 1 (Firebase live + verification)** and the safety gates from
> Phase 2 onward are prerequisites before any real teens use the app. See [SAFETY.md](SAFETY.md).
