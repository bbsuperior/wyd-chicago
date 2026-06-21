# Features & Screens

The web and iOS clients **mirror each other** — same screens, same actions. This is a writeup of
[Project Canon §3](../PROJECT_CANON.md) with short user stories. Copy stays in the casual teen
voice ("WYD tonight?", "Tap in.", "Your friends are going.").

iOS arranges these as a `TabView`: **Feed · Search · ➕ (host/admin only) · Friends · Profile**,
with Admin and Event-detail pushed as navigation destinations.

---

## 1. Onboarding / Auth

> *"I'm new — let me in fast, then show me stuff I actually care about."*

- Sign up with email + password.
- Pick a username (unique, lowercase), enter age/grade.
- Pick interest tags so the feed isn't empty on day one.
- **Email verification gate** — you verify before you can RSVP or vote.
- Log in; forgot password.

Big tap targets, one step at a time, no jargon.

---

## 2. Feed (Home) — the core screen

> *"What's good tonight?"*

The screen teens spend the most time on. A scrollable list of event cards with:

- **Filter chips** across the top — event type, neighborhood, and when.
- **Sort control:**
  - 🔥 **Hype** — by `voteScore`.
  - 🕒 **Soonest** — by `startAt`.
  - 👥 **Friends going** — events your friends committed to.
  - ✨ **For you** — ranked by the recommendation score (interests + friends + recency +
    neighborhood).
- **Search.**

Each card shows the cover, title, host, when, approximate area, counts, and a quick RSVP.

---

## 3. Event detail

> *"Who's going, and where exactly?"*

- Cover image, title, host, when.
- **Approximate location only** — the exact address is revealed **after you RSVP "going"** (safety).
- Description, tags, and "recommended for" tags.
- Attendee counts: **committed** (going) vs **interested**.
- Avatars of **friends going**.
- **RSVP** — Going / Interested.
- **Upvote / downvote.**
- **Share to Snapchat / Instagram.**
- **Comments.**
- Report (links into Safety).

---

## 4. Create / Edit event — admin/host only

> *"I'm throwing something — put it on the map."*

Available to `host` and `admin` roles. Create or edit an event, set type/tags, time, approximate
area + exact address, price, capacity, age band, and "recommended for" tags. Events default to
**draft** until an admin publishes.

---

## 5. Profile

> *"This is me — and everything I'm going to."*

Your name, username, age, interests, **Snapchat + Instagram handles**, friends count, events you're
going to, saved events, settings, and sign out.

---

## 6. Friends

> *"Add my friends, see what they're doing."*

- **Add by username** (Snapchat-style).
- Incoming / outgoing requests.
- Friends list.
- "Share my Snap."

---

## 7. Admin dashboard ("master login")

> *"I run this — let me manage everything in one place."*

Gated by the `admin` role. Create / edit / publish / cancel events, see RSVP lists, manage tags,
feature events, and review the **reports** moderation queue. Admins can cancel or unpublish
instantly.

---

## 8. Safety

> *"Keep it safe."*

Report, block, community guidelines, and the age gate — linked from event detail and profile.
Full policy in [SAFETY.md](SAFETY.md).

---

## Snapchat reality note

We want WYD to feel native to how Chicago teens already share — and that means Snapchat. But the
**full Snap social-graph integration is limited**: there's no public API to read a user's Snapchat
friend list, so we **cannot auto-import friends** from Snap.

What we ship instead:

- **Add-by-username on profiles** — users put their `snapchatUsername` on their profile, and the
  Friends screen adds people by WYD username (Snapchat-style). It's manual, but it's how teens
  already swap handles.
- **Share-event-to-Snapchat** — event detail can hand off to Snapchat to share an event (sticker /
  link / attachment), which is fully supported.

**What we can adopt later:** Snap Kit — **Login Kit** (sign in with Snapchat, with the user's
consent) and **Creative Kit** (share branded event stickers straight into the camera). These are
the supported, policy-compliant integration points and are tracked in
[ROADMAP.md](ROADMAP.md) (Phase 6). We design the Friends and share flows now so adding Snap Kit
later is additive, not a rewrite.
