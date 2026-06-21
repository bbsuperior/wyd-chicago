# Design System

WYD Chicago is **dark-first** — it reads "going out tonight," makes event photos pop, and feels
premium. A light theme is a later nice-to-have. This is [Project Canon §2](../PROJECT_CANON.md)
written for designers and devs. **Use these exact values** — on web they're CSS custom properties
in `web/css/app.css`; on iOS they're `Color` extensions in `ios/WYDChicago/DesignSystem/`.

---

## Color tokens

| Token | Hex | Role |
| --- | --- | --- |
| `--bg` | `#0B0B12` | app background — near-black indigo |
| `--surface` | `#15151F` | cards |
| `--surface-2` | `#1E1E2C` | raised / inputs / chips |
| `--border` | `#2A2A3A` | hairlines |
| `--text` | `#F5F5FA` | primary text |
| `--muted` | `#9A9AB0` | secondary text |
| `--brand` | `#5B8CFF` | primary — electric Chicago-sky blue |
| `--brand-2` | `#C44CFF` | secondary — electric purple (gradients) |
| `--accent` | `#FF4D6D` | hot pink/red — CTAs, votes, the Chicago-star nod |
| `--gold` | `#FFC83D` | highlights, upvotes, "featured" |
| `--success` | `#2EE6A6` | going / confirmed |
| `--danger` | `#FF5A5A` | cancel / report |

---

## Signature gradient — "city night"

```css
linear-gradient(135deg, #5B8CFF 0%, #C44CFF 55%, #FF4D6D 100%)
```

Used on the **logo, primary buttons, and the hero**. Reserve it for hype moments — don't drown the
UI in it. A flat `--surface` card with one gradient CTA reads far better than a gradient everywhere.

---

## Typography

- **Display / headings:** `Space Grotesk` (Google Fonts), weights **500 / 600 / 700**. Punchy, modern.
- **Body / UI:** `Inter` (Google Fonts), weights **400 / 500 / 600**.
- **Web** loads both from the Google Fonts CDN.
- **iOS** bundles them (or falls back to **SF Pro Rounded**).

Pair them: Space Grotesk for titles and the wordmark, Inter for everything you read in a sentence.

---

## Shape & motion

- **Radius:** cards/sheets `20px`, buttons/inputs `14px`, chips/pills `999px`. Friendly, rounded.
- **Shadows:** soft. Reserve the **neon glow** for the primary CTA only:
  ```css
  box-shadow: 0 8px 30px rgba(91, 140, 255, .35);
  ```
- **Motion:** subtle **150–200ms** transitions. Always respect `prefers-reduced-motion`.

---

## Logo / motif

The wordmark **"WYD"** in Space Grotesk **700** with the city-night gradient, followed by a small
**six-pointed star** — the Chicago flag star ✦ — as the dot/accent. **"Chicago"** sits beneath in
muted caps with letter-tracking.

A reusable inline **SVG star** lives in the web assets (`web/js/icons.js`) and the iOS design system,
so the star is consistent everywhere it appears.

---

## Iconography

Simple **line icons** (Lucide-style).

- **Web:** inline SVGs in `web/js/icons.js`.
- **iOS:** **SF Symbols**.

Keep icons single-weight and unfussy — clarity over decoration.

---

## Components (reference)

These render from the tokens above; built in `web/css/app.css` + `web/js/ui.js` and mirrored on iOS.

- **Event card** — cover image, title (Space Grotesk), host + when (Inter/muted), approximate area,
  attendee counts, vote affordance, quick RSVP. Radius `20px`, surface background, soft shadow.
- **Chips / pills** — filter chips and tags, radius `999px`, `--surface-2` background with the tag's
  accent color. Big enough to tap.
- **Buttons** — primary uses the city-night gradient + neon glow; secondary is `--surface-2` with a
  `--border` hairline. Radius `14px`.
- **Avatars** — round, with a friends-going stack on event detail.
- **Sheets** — bottom sheets for RSVP/share/report, radius `20px`.
- **Toast** — brief confirmations ("You're going ✦").

---

## Voice

Casual, confident, friendly, low-effort to read. **Talk like a 16-year-old texting, not a brand.**

- ✅ "WYD tonight?" · "See what's good 👀" · "Your friends are going." · "Tap in."
- ❌ corporate, condescending, or wordy.

Microcopy should sound like a text from a friend, not a notification from an institution.

---

## Accessibility notes

- Maintain readable contrast on `--bg`/`--surface` (primary text `--text`, secondary `--muted`).
- Respect `prefers-reduced-motion` — drop the transitions, keep the layout.
- Big tap targets (it's a teen app used one-handed, on the move).
