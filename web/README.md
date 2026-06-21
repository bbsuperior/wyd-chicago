# web/ — the WYD Chicago website ✦

**This folder IS the website.** It's buildless — plain ES modules + CSS, no `npm install`, no
bundler. It works fully in **demo mode** with no backend (seed events load into localStorage), so
just open it and go.

**Run it:**

- Open `index.html` in your browser, **or**
- `python3 -m http.server 8000` from this folder, then visit <http://localhost:8000>.

**Demo admin login:** `admin@wydchicago.app` / `chicago` (try `admin.html`).

**Deploy:** this directory is exactly what **GitHub Pages** serves — the
[`deploy-pages.yml`](../.github/workflows/deploy-pages.yml) workflow uploads `web/` on every push to
`main`. The empty `.nojekyll` file keeps Pages from mangling the ES-module paths.

To go live with a real backend, paste your web keys into `js/firebase-config.js` and the site flips
from mock mode to Firebase automatically. See [../docs/FIREBASE_SETUP.md](../docs/FIREBASE_SETUP.md).
