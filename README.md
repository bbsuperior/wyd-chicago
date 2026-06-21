# WYD Chicago ✦

[![status](https://img.shields.io/badge/status-foundation%20%2F%20scaffold-5B8CFF)](docs/ROADMAP.md)
[![web](https://img.shields.io/badge/web-buildless%20ES%20modules-C44CFF)](web/)
[![ios](https://img.shields.io/badge/iOS-SwiftUI%2016%2B-FF4D6D)](ios/)
[![backend](https://img.shields.io/badge/backend-Firebase-FFC83D)](firebase/)
[![demo mode](https://img.shields.io/badge/demo%20mode-no%20backend%20needed-2EE6A6)](#run-the-website-locally)

**WYD** = "What You Doing?" — the question Chicago teens text each other a hundred times a week.
WYD Chicago answers it: a clean, dead-simple app that shows what's actually going on around the
city tonight — parties, kickbacks, concerts, games, fundraisers, open mics — and lets you see
who's going, **tap in**, vote on what's good, and find people with the same vibe.

Built for Chicago-area teenagers (~14–18). Zero learning curve, big tap targets, one clear
action per screen. Two clients — a **website** and a native **iOS app** — share **one Firebase
backend** and mirror the same screens.

---

## The city-night brand at a glance

Dark-first, because it reads "going out tonight" and makes event photos pop.

| Token | Hex | Used for |
| --- | --- | --- |
| `--bg` | `#0B0B12` | app background (near-black indigo) |
| `--surface` | `#15151F` | cards |
| `--brand` | `#5B8CFF` | primary — electric Chicago-sky blue |
| `--brand-2` | `#C44CFF` | secondary — electric purple |
| `--accent` | `#FF4D6D` | CTAs, votes, the Chicago-star nod |
| `--gold` | `#FFC83D` | highlights, upvotes, featured |
| `--success` | `#2EE6A6` | going / confirmed |

**Signature gradient ("city night"):** `linear-gradient(135deg, #5B8CFF 0%, #C44CFF 55%, #FF4D6D 100%)`
on the logo, primary buttons, and the hero.

**Logo:** the wordmark **WYD** in Space Grotesk 700 with the city-night gradient, followed by a
small **six-pointed star** — the Chicago flag star ✦ — as the accent. "Chicago" sits beneath in
muted caps.

**Type:** Space Grotesk (display) + Inter (body), both from Google Fonts.

Full system in [docs/DESIGN.md](docs/DESIGN.md).

---

## Features

- **Feed (Home)** — scrollable event cards, filter chips (type / neighborhood / when), and sort
  by 🔥 Hype · 🕒 Soonest · 👥 Friends going · ✨ For you. Search.
- **Event detail** — cover, host, when, *approximate* location (exact address only after you RSVP
  "going"), attendee counts, friends going, RSVP, upvote/downvote, comments, share to Snapchat/IG.
- **Auth + onboarding** — email/password with mandatory email verification, username, age/grade,
  interest tags.
- **Profile** — your username, interests, Snap + Instagram handles, friends, events you're going to.
- **Friends** — add by username (Snapchat-style), requests, friends list.
- **Admin / "master login"** — create/edit/publish/cancel events, RSVP lists, manage tags, feature
  events, review reports.
- **Safety** — age gate, approximate-location-until-RSVP, reporting & moderation, guidelines.

Full screen-by-screen writeup in [docs/FEATURES.md](docs/FEATURES.md).

---

## Repo layout

```
wyd-chicago/
├── web/        the website (buildless ES modules + CSS) — this folder IS what GitHub Pages serves
├── ios/        native SwiftUI app (iOS 16+, MVVM)
├── firebase/   Firestore rules, indexes, Storage rules, seed data, Cloud Functions
├── docs/       architecture, data model, features, roadmap, safety, setup, design, contributing
└── PROJECT_CANON.md   the single source of truth (brand, data model, contracts, safety)
```

---

## Run the website locally

The web client is **buildless** — plain ES modules + CSS, no npm install, no bundler. It works
fully in **demo mode** with no backend (seed events load from `web/seed.json` into localStorage),
so you can show it to people immediately.

**Easiest:** open `web/index.html` in your browser.

**Recommended (proper module/path serving):**

```bash
cd web
python3 -m http.server 8000
# then open http://localhost:8000
```

### Demo admin login

In demo mode the site ships with a built-in master login so you can try the admin dashboard:

```
email:    admin@wydchicago.app
password: chicago
```

Open `admin.html` (or the admin link in the app) after logging in.

> Demo content is fictional and clearly labeled — no real addresses or real minors' data.

To go live with a real backend, follow [docs/FIREBASE_SETUP.md](docs/FIREBASE_SETUP.md): create a
**new** Firebase project named `wyd-chicago`, paste the web keys into
`web/js/firebase-config.js`, and the site automatically switches from mock mode to Firebase.

---

## How it deploys (GitHub Pages)

Every push to `main` triggers [`.github/workflows/deploy-pages.yml`](.github/workflows/deploy-pages.yml),
which publishes the `web/` directory to GitHub Pages. A `web/.nojekyll` file keeps Pages from
mangling the ES-module paths. Because the site runs in demo mode with no backend, the deployed
Pages site is fully interactive out of the box.

To enable it: in your repo settings, set **Pages → Build and deployment → Source → GitHub Actions**.

---

## Project status: foundation / scaffold

This is **Phase 0** — the brand, data model, code contracts, web scaffold, iOS scaffold, Firebase
config, and docs are in place and the site runs in demo mode. Firebase isn't live yet and the
clients are not feature-complete. See the phased plan in [docs/ROADMAP.md](docs/ROADMAP.md).

---

## Docs

- [Architecture](docs/ARCHITECTURE.md) — two clients, one backend, the `backend.js` switcher.
- [Data model](docs/DATA_MODEL.md) — collections, fields, counters, recommendation scoring.
- [Features](docs/FEATURES.md) — every screen with user stories.
- [Roadmap](docs/ROADMAP.md) — phased plan with checklists.
- [Safety](docs/SAFETY.md) — trust & safety policy for a minors' app.
- [Firebase setup](docs/FIREBASE_SETUP.md) — step-by-step to go live.
- [Design](docs/DESIGN.md) — the full brand & design system.
- [Contributing](docs/CONTRIBUTING.md) — conventions, ownership map, how to extend.

---

Made for Chicago. ✦
