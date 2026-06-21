# Contributing

WYD Chicago is two clients on one backend. The golden rule: **[`PROJECT_CANON.md`](../PROJECT_CANON.md)
is the single source of truth.** Don't invent alternate color values, collection/field names, or
API shapes — if something's ambiguous, the canon wins, and if the canon is wrong, fix the canon first.

---

## Conventions

- **Indentation:** 2 spaces for web / JS / JSON; **4 spaces for Swift**.
- **Encoding:** UTF-8, LF line endings.
- **Dates:** Firestore timestamps in the live backend; **ISO-8601 strings** in mock JSON.
- **Money:** integer **cents** (`priceCents`, `0` = free).
- **Commits:** clear and imperative ("Add friends list to profile"). This repo does **not** use the
  Rep status-tag (🟢/🟡/🔴) convention.
- **Demo/seed content:** fictional and clearly labeled — no real addresses, no real minors' data.
- **Secrets:** never commit service-account keys or admin SDK creds (they're in `.gitignore`). Web
  Firebase keys in `firebase-config.js` are public by design and may be committed.
- **Hard rule:** never integrate **HealthKit** on iOS (out of scope; caused launch hangs elsewhere).

---

## File ownership map

Build files independently without collisions — each file has one owner/purpose.

### Web (`web/`)
| File | Purpose |
| --- | --- |
| `index.html` | app shell + landing/hero + feed + event detail (single-page, hash router) |
| `admin.html` | admin / master dashboard |
| `css/app.css` | the entire design system + components |
| `js/icons.js` | inline SVG icon set + the Chicago star logo |
| `js/recommend.js` | `recommendScore` (pure) |
| `js/data.js` | mock/localStorage backend implementing the contract + seed import |
| `js/firebase-config.js` | placeholder web keys + how to fill them (safe to commit) |
| `js/firebase.js` | real Firestore/Auth backend implementing the contract |
| `js/backend.js` | the switcher — exports `Auth`/`API`/`USING_FIREBASE`/`recommendScore` |
| `js/ui.js` | render helpers (cards, chips, avatars, sheets, toast) |
| `js/app.js` | router + page controllers |
| `js/admin.js` | admin dashboard logic |
| `seed.json` | ~12 fictional Chicago demo events + tags |
| `.nojekyll` / `README.md` | Pages serving config / "this folder is the website" note |

### Backend & docs
| Area | Files |
| --- | --- |
| Firebase | `firebase/firestore.rules`, `storage.rules`, `firestore.indexes.json`, `firebase.json`, `seed/*`, `functions/` |
| iOS | `ios/WYDChicago/` — `App/`, `Models/`, `Services/`, `DesignSystem/`, `Features/<Screen>/` |
| Docs | `docs/*.md`, root `README.md`, `.github/workflows/deploy-pages.yml` |

**Rule:** only touch files you own. App code imports **only** from `js/backend.js`, never directly
from `data.js`/`firebase.js`.

---

## Staying buildless

The website must keep working on GitHub Pages with **no build step and no Firebase configured**.

- **No bundler, no `npm install` to view the site.** Plain ES modules + custom CSS only.
- Firebase loads from its **CDN**, not from `node_modules`.
- Use native `import`/`export` and relative paths. Don't add a framework, a transpiler, or a package
  that requires a build.
- Keep `web/.nojekyll` in place so Pages serves module paths verbatim.
- The site must render real content in **mock mode** (seed → localStorage) on first load.

If you think you need a build step, you almost certainly don't — reach for a small vanilla helper
instead.

---

## How to add a new event type or interest tag

Tags live in the `tags` collection (`{ label, kind, emoji, color, sort }`), with two kinds:
`eventType` (one per event) and `interest` (matching/recommendation).

1. **Seed it.** Add the tag object to `web/seed.json` (demo/mock) and to `firebase/seed/` (live).
   Give it a stable `tagId`, a `label`, the right `kind`, an `emoji`, a chip `color` (a hex pulled
   from the design tokens reads best), and a `sort` index.
2. **Use the canonical id.** Reference it by `tagId` in `events.eventType` (for an event type) or in
   `events.tags[]` / `events.recommendedFor[]` / `users.interests[]` (for an interest). Never
   hard-code label strings — match by id.
3. **No code changes needed.** Filter chips, profile interests, and the ✨ For-you ranking read the
   `tags` collection dynamically, so adding a tag is a data change, not a code change.
4. **iOS parity.** If iOS bundles a local tag seed for previews, add the same tag there so both
   clients show it.

---

## Pull request checklist

- [ ] Matches `PROJECT_CANON.md` (colors, names, contract shapes) exactly.
- [ ] Only files you own were changed.
- [ ] Web still works in **mock mode** with no Firebase config.
- [ ] Indentation/encoding conventions followed (2-space web/JSON, 4-space Swift).
- [ ] No secrets committed; no real addresses or real minors' data in seed content.
- [ ] Safety gates intact (address-after-RSVP, verified-email RSVP/vote, draft-by-default).
- [ ] No HealthKit.
