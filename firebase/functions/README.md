# WYD Chicago — Cloud Functions

Counters, profile bootstrap, and role management for the WYD Chicago backend.

## What's in here

| Function | Trigger | Does |
| --- | --- | --- |
| `onAttendeeCreated/Deleted/Updated` | `events/{id}/attendees/{uid}` | Keeps `committedCount` / `interestedCount` accurate via atomic increments. |
| `onVoteCreated/Deleted/Updated` | `events/{id}/votes/{uid}` | Keeps `upvotes` / `downvotes` / `voteScore` accurate. |
| `onUserCreate` | `beforeUserCreated` (blocking) | Writes the default `users/{uid}` profile with `role: "user"`. |
| `setUserRole` | callable | Admin-only: promote a user to `host` or `admin` (sets custom claim + `role`). |
| `markWelcomeOnVerify` | callable | Client calls once after email verification (no native verify trigger exists). |
| `refreshRecommendations` | scheduled (nightly) | Optional stub for future server-side recommendation precompute. |

## Install

```bash
cd firebase/functions
npm install
```

## Emulate locally

From the `firebase/` directory:

```bash
firebase emulators:start
```

This boots auth, firestore, functions, storage, and the emulator UI (see
`firebase.json`). The functions react to emulated Firestore writes, so you can
RSVP/vote against the emulator and watch the counters update.

> Tip: seed the emulator first —
> `FIRESTORE_EMULATOR_HOST="127.0.0.1:8080" node firebase/seed/seed.mjs`

## Deploy

```bash
firebase deploy --only functions
```

Rules and indexes deploy separately and do **not** need Blaze:

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage
```

## ⚠️ Blaze plan required for Functions

**Cloud Functions cannot be deployed on the free Spark tier.** You must enable
the **Blaze (pay-as-you-go)** plan on the Firebase project before
`firebase deploy --only functions` will succeed. The blocking `onUserCreate`
function additionally relies on **Identity Platform**, which Blaze enables.

Everything else in this repo — **Firestore rules, indexes, Storage rules, and
Auth** — runs on the free **Spark** tier. So you can ship the app with mock or
rules-only mode and turn Functions on later once billing is enabled.

(Free-tier Blaze still includes a generous monthly Functions quota; for a demo
the expected cost is effectively $0.)
