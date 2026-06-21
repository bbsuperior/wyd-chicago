# Firebase Setup

Step-by-step to take WYD Chicago from demo mode to a live Firebase backend. Most of this runs on
the **free Spark tier** — only Cloud Functions need the **Blaze** plan.

> **Use a NEW project.** Create a fresh project named **`wyd-chicago`**. Do **not** reuse any
> existing project (e.g. `my-gym-app-cc57a`) — WYD Chicago is its own app with its own data,
> rules, and billing.

---

## 1. Create the Firebase project

1. Go to <https://console.firebase.google.com> and click **Add project**.
2. Name it **`wyd-chicago`**. Accept (or skip) Google Analytics — not required.
3. When it's created, open the project.

---

## 2. Enable Email/Password auth + email verification

1. **Build → Authentication → Get started.**
2. **Sign-in method → Email/Password → Enable** (you can leave "Email link" off).
3. Email verification is sent by the app via `sendVerification()`; no extra console toggle is
   required, but you can customize the verification template under **Authentication → Templates**.
4. *(Optional later: Sign in with Apple / Google.)*

> RSVP and voting are gated on `email_verified` in the security rules, so verification is mandatory
> in practice.

---

## 3. Create Firestore + Storage

1. **Build → Firestore Database → Create database** → start in **production mode** → pick a region
   (e.g. `us-central1`). Our `firestore.rules` will lock it down properly.
2. **Build → Storage → Get started** → same region. Our `storage.rules` enforces size/type limits
   on event covers and avatars.

---

## 4. Install firebase-tools and log in

```bash
npm install -g firebase-tools
firebase login
```

From the repo root, point the CLI at your new project (creates/updates `.firebaserc`):

```bash
firebase use --add
# select wyd-chicago, give it the alias "default"
```

The Firebase config lives in `firebase/` (see `firebase/firebase.json`). Run deploy commands from
the directory that contains `firebase.json`, or pass `--config firebase/firebase.json`.

---

## 5. Deploy rules + indexes (free Spark tier)

```bash
# from the firebase/ directory (or add --config firebase/firebase.json):
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
firebase deploy --only storage:rules

# or all three at once:
firebase deploy --only firestore:rules,firestore:indexes,storage:rules
```

The composite indexes (status+startAt, status+voteScore, eventType+startAt, …) back the feed
queries. All of this is free on Spark.

---

## 6. Cloud Functions require the Blaze plan

Counter triggers, `onUserCreate`, `setAdminRole`, `sendWelcomeOnVerify`, and the optional nightly
recommendation refresh live in `firebase/functions/` (Node 20).

> **Deploying Functions requires the Blaze (pay-as-you-go) plan.** The free **Spark tier cannot
> deploy Cloud Functions.** Beckett must enable billing on the **`wyd-chicago`** project before
> this step. Everything else above works on Spark.

Enable Blaze: **Firebase console → ⚙ → Usage and billing → Modify plan → Blaze.** Then:

```bash
cd firebase/functions
npm install
cd ..
firebase deploy --only functions
```

Until Blaze is enabled, the app still works — clients apply optimistic counter updates; only the
authoritative server-side recompute is deferred.

---

## 7. Add the web keys

1. In the console: **⚙ Project settings → General → Your apps → Web app (`</>`)**. Register a web
   app (no Hosting needed) and copy the config object.
2. Paste the values into **`web/js/firebase-config.js`** (these web keys are **public by design** and
   safe to commit). The moment real keys are present, `web/js/backend.js` switches the site from
   mock mode to live Firebase automatically.

---

## 8. Seed the project

Load tags + demo events into the new project:

```bash
# run the seed script from firebase/seed/ per its README
# (it writes firebase/seed/*.json into Firestore using the Admin SDK)
node firebase/seed/seed.js
```

This gives a fresh project realistic, clearly-fictional Chicago demo content.

---

## 9. Set the first admin ("master login")

Two ways — use whichever is handy for the first owner (Beckett):

**A) Firebase console (simplest for the first admin)**
- **Authentication → Users**, find your account, and add a **custom claim** `{"admin": true}` (via
  the Admin SDK / console tooling), and/or set `users/{yourUid}.role = "admin"` in Firestore.

**B) The `setAdminRole` callable (for subsequent admins)**
- Once you are an admin, call the **`setAdminRole`** callable Cloud Function (admin-only) to grant
  `admin`/`host` roles to other users without touching the console.

After setting the claim, sign out and back in so the new token carries `admin: true`.

---

## Quick reference

```bash
npm install -g firebase-tools
firebase login
firebase use --add                                   # select wyd-chicago

firebase deploy --only firestore:rules,firestore:indexes,storage:rules   # Spark OK

# Blaze required for the next two:
cd firebase/functions && npm install && cd ..
firebase deploy --only functions

node firebase/seed/seed.js                            # seed tags + demo events
# then paste web keys into web/js/firebase-config.js
```
