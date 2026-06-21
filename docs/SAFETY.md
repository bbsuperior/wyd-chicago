# Safety & Trust

WYD Chicago is built **for minors** (~14–18). Safety is non-negotiable and is a product
requirement, not an afterthought. This expands [Project Canon §8](../PROJECT_CANON.md) into a
working trust & safety policy. Every client and the backend must uphold these rules.

---

## 1. Age gate

- Age is collected at sign-up via `birthYear`; we derive an **age range** and **never display exact
  date of birth**.
- Every event carries `ageMin` (default `14`) and `ageMax` (default `18`).
- The recommendation score applies an **age penalty** for events outside a user's band, and the UI
  surfaces the age band on event detail so teens self-select appropriately.
- WYD is intended for high-school-age teens in the Chicago area; it is not a platform for adults to
  reach minors.

---

## 2. Location privacy — approximate until you RSVP

The single most important physical-safety rule:

- **Only `approxArea`/`neighborhood` is shown publicly** (e.g. "Wicker Park").
- **`exactAddress` is revealed only after a user RSVPs "going"** — or to an admin.
- This is enforced server-side in `firebase/firestore.rules`, not just hidden in the UI, so a
  scraped or inspected response can't leak an address to someone who hasn't committed. The mock
  backend mirrors the same gate so demos behave identically.

Maps (Phase 6) show the approximate area only until RSVP.

---

## 3. Reporting & moderation

- **Report** is available on **events, users, and comments**. Reports write to the `reports`
  collection: `{ targetType, targetId, reporterId, reason, details, status, createdAt }`.
- Reports are **create-only** for authenticated users; only admins can read and work them.
- New reports start `status: "open"` and move through `reviewed` → `actioned` in the admin
  moderation queue.
- **Block** lets a user stop seeing/being contacted by another user.

---

## 4. Admin controls

- **Admins ("master login")** can **create, edit, publish, cancel, and unpublish events instantly**,
  manage tags, feature events, and review reports.
- **Events default to `draft`** and are only visible once an **admin publishes** them — nothing
  reaches teens without review.
- A cancelled event (`status: "cancelled"`) is removed from the feed immediately.
- Admin is a custom claim (`admin: true`) and/or `users/{uid}.role == "admin"`, set via an
  admin-only callable Function or the Firebase console for the first owner. **Hosts** (`role: "host"`)
  can create events (as drafts) but have no moderation powers.

---

## 5. Data minimization

- **Collect the minimum.** We store `birthYear` (not full DOB) and derive an age range; the exact
  date is never shown.
- Snapchat/Instagram handles are **optional** and user-provided.
- Service-account keys and admin SDK credentials are git-ignored and never committed (web Firebase
  keys are public by design and may be committed — see [`.gitignore`](../.gitignore)).
- Demo/seed content is **fictional and clearly labeled** — no real addresses, no real minors' data.
- Friends-only visibility options are planned (see [ROADMAP.md](ROADMAP.md)).

---

## 6. Authentication gates

- **Email/password with mandatory email verification.**
- **RSVP and voting require a verified email** (`request.auth.token.email_verified == true`),
  enforced in security rules — this raises the cost of throwaway accounts.

---

## 7. Community guidelines

A guidelines screen is linked from event detail and profile. The short version, in plain teen
language:

- **Be cool to each other.** No harassment, bullying, threats, or hate.
- **No illegal-goods promotion.** No drugs, weapons, or anything you couldn't post at school.
- **Hosts are accountable** for what they post and who they invite.
- **Keep it real.** No fake events, no scams, no impersonation.
- **If something's off, report it.** Admins review reports and can pull events instantly.

Breaking the guidelines can get content removed, an event cancelled, or an account actioned.

---

## 8. Summary of enforcement points

| Protection | Where it lives |
| --- | --- |
| Age gate | sign-up + `ageMin`/`ageMax` + recommendation age penalty |
| Address hidden until RSVP | `firestore.rules` (mirrored in mock) |
| Verified-email gate on RSVP/vote | `firestore.rules` |
| Draft-by-default events | `firestore.rules` + admin publish |
| Reporting | `reports` collection + admin queue |
| Instant cancel/unpublish | admin dashboard + `setEventStatus` |
| No secret keys committed | `.gitignore` |

Safety rules **override** convenience and aesthetics. If a feature can't ship without weakening one
of these gates, it doesn't ship.
