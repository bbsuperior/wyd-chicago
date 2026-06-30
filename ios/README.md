# WYD Chicago — iOS app

SwiftUI, iOS 16+, MVVM. Shares the **same Firebase backend and Firestore schema as
the website** (see `../PROJECT_CANON.md`). The app runs out of the box against an
in-memory **MockBackend** — no Firebase, no API keys, no network — so you can build,
preview, and demo it immediately. Wiring real Firebase is a small, well-marked swap.

> **Note:** there's no `.xcodeproj` checked in. You generate it from `project.yml`
> with [XcodeGen](https://github.com/yonat-co/XcodeGen) (one command). This keeps the
> repo clean and merge-friendly.

---

## 1. Create the Xcode project

```bash
# Install XcodeGen (Homebrew):
brew install xcodegen

# From the ios/ folder, generate WYDChicago.xcodeproj:
cd ios
xcodegen generate

# Open it:
open WYDChicago.xcodeproj
```

Pick an iPhone simulator (e.g. iPhone 15) and hit **Run**. You'll land signed in as a
demo teen with ~8 fictional Chicago events, friends, votes, RSVPs, and comments — all
from `MockBackend`. SwiftUI **previews** in every `*View.swift` work the same way.

If you don't have XcodeGen, you can instead create a new "iOS App" project in Xcode
(SwiftUI lifecycle, bundle id `app.wydchicago.ios`, iOS 16) and drag the `WYDChicago/`
folder in. XcodeGen is just the tidy path.

---

## 2. Project layout (MVVM, canon §6)

```
ios/
├─ project.yml                # XcodeGen spec (bundle id, iOS 16, Firebase SPM refs ready)
└─ WYDChicago/
   ├─ App/                    # @main App (splash → root), RootView (TabView), AppState
   ├─ Models/                 # Codable structs mirroring canon §4 + enums
   ├─ Services/               # Backend protocol, MockBackend, FirebaseBackend stub, Recommend
   ├─ DesignSystem/           # Theme, Typography, Components, Motion (animation language)
   ├─ Features/<Screen>/      # View + ViewModel per screen (incl. Launch/SplashView)
   └─ Resources/              # Assets.xcassets (AppIcon), Fonts/
```

Tabs (canon §3): **Feed · Search · ➕ Create (host/admin only) · Friends · Profile**.
Admin dashboard and Event detail are pushed as navigation destinations.

### Motion & animation

All animation runs through one shared language in `DesignSystem/Motion.swift`:

- **Spring tokens** — `WYDMotion.snappy / .smooth / .bouncy / .fade` so everything
  moves with the same personality.
- **`AuroraBackground`** — slow-drifting blurred "city night" orbs behind the launch
  and auth screens.
- **`SplashView`** (`Features/Launch/`) — animated launch: the Chicago star spins in,
  the wordmark snaps, then it cross-fades to the app.
- **Reusable modifiers** — `.appear(delay:)` (staggered fade-in, used by the feed,
  profile, and event detail), `.pressable` button style (tap scale), `.shake(_:)`
  (error feedback on login), `.shimmer()`, `.pulseGlow()`. Login uses a
  `matchedGeometryEffect` sliding toggle and the vote pill bounces with
  `contentTransition(.numericText())`.
- **`CountUpText` / `CountUp`** — numbers that tick up on appear (profile stats).
- **`ConfettiView`** (`DesignSystem/Confetti.swift`) — a celebratory burst fired by a
  trigger; pops when you RSVP "Going". Honors Reduce Motion.
- **`ToastData` + `.wydToast(_:)`** (`DesignSystem/Toast.swift`) — top-anchored,
  auto-dismissing snackbar (RSVP / save confirmations).
- **`Haptics`** (`DesignSystem/Haptics.swift`) — one wrapper for tap/select/success
  feedback, wired through votes, RSVPs, chips, friend requests, and login.
- **`SkeletonEventCard`** — shimmering placeholder shown while the feed loads.

The whole app talks to one **`Backend`** protocol (`Services/Backend.swift`) that mirrors
the web `Auth` + `API` surface from canon §5. `MockBackend` and `FirebaseBackend` both
conform to it — exactly how the web swaps `data.js` ↔ `firebase.js` via `backend.js`.

### WYD AI — the in-app assistant

The sparkles button (bottom-right, over the tabs) opens a chat with **WYD AI**, an
assistant that helps teens find something to do. It follows the same swap pattern as the
backend, behind one `AssistantService` protocol (`Services/Assistant.swift`):

- **`ClaudeAssistant`** (`Services/ClaudeAssistant.swift`) — calls the Claude **Messages
  API** natively over `URLSession` (there's no official Anthropic Swift SDK), with the
  **web search** server tool enabled so it can answer with current info.
- **`MockAssistant`** (`Services/MockAssistant.swift`) — a zero-config offline fallback so
  the chat works (human-like, multi-message, no dashes) with no key.
- **Long-term memory** (`MemoryStore`) persists to disk on-device. The model saves facts
  via `remember: …` lines, which the app stores and re-injects into the system prompt every
  session, so the assistant stays personal across launches. View/clear it from the chat's
  ••• menu.
- **Texting feel** — replies render as several short bubbles, revealed one at a time with a
  typing indicator (`AssistantView` / `AssistantViewModel`). The system prompt keeps it
  casual and dash-free.

**Enable live AI:** supply `ANTHROPIC_API_KEY` via an env var, an xcconfig/CI build setting
(wired through `project.yml`), or a git-ignored `Secrets.plist`. With no key the app stays
in demo mode automatically. Override the model with the `ANTHROPIC_MODEL` Info.plist value
if needed.

---

## 3. Go live: add Firebase via Swift Package Manager

1. **Create the Firebase project.** Use a **new** project — do NOT reuse any other
   project. Suggested id: `wyd-chicago`. Add an iOS app with bundle id
   `app.wydchicago.ios`.

2. **Add the Firebase SPM package.** Two options:
   - **Via `project.yml` (recommended):** uncomment the `packages:` block and the
     `dependencies:` entries (FirebaseAuth, FirebaseFirestore, FirebaseStorage) at the
     bottom of `project.yml`, then re-run `xcodegen generate`.
   - **Via Xcode:** File → Add Packages… → `https://github.com/firebase/firebase-ios-sdk`
     → add **FirebaseAuth**, **FirebaseFirestore**, **FirebaseStorage** to the
     `WYDChicago` target.

3. **Drop in `GoogleService-Info.plist`.** Download it from the Firebase console and
   place it at `ios/WYDChicago/GoogleService-Info.plist`. It is **git-ignored** by design
   (see `../.gitignore`) — keep it local.

4. **Flip the app to Firebase.** In `App/WYDChicagoApp.swift`, swap the two marked lines:
   ```swift
   // Add at top:  import FirebaseCore
   FirebaseApp.configure()
   _appState = StateObject(wrappedValue: AppState(backend: FirebaseBackend()))
   ```
   and remove the MockBackend line. `FirebaseBackend.swift` already contains the real
   FirebaseAuth/Firestore calls; they're guarded behind `#if canImport(FirebaseFirestore)`
   so the file compiled fine before you added the package, and "just works" after.

5. **Deploy the rules / indexes / seed** from the `firebase/` folder (see that folder's
   setup guide). Counters (`committedCount`, `voteScore`, …) are maintained by Cloud
   Functions — **deploying Functions needs the Blaze plan**; everything else runs on the
   free Spark tier.

That's the entire swap. No view or view-model code changes — they only know the protocol.

---

## 4. Fonts (optional, nice-to-have)

The design uses **Space Grotesk** (display) and **Inter** (body). Bundle the TTFs under
`WYDChicago/Resources/Fonts/` (see the README in that folder). If they're absent,
`Typography.swift` falls back to **SF Pro Rounded** automatically, so nothing breaks.

---

## 5. Safety notes (canon §8)

- **Exact address is hidden until you RSVP "Going."** The mock enforces this in
  `getEvent`; in production it's enforced by Firestore security rules.
- RSVP and voting require a **verified email** (`emailVerified`). The mock starts new
  sign-ups unverified so you can exercise the gate; tap "verify now" in Profile.
- Report / block flows write to the `reports` collection; admins moderate from the
  **Master login** dashboard.
- All demo/seed content is fictional and clearly labeled. No real addresses.

---

## 6. Hard rules

- **Never integrate HealthKit.** Out of scope and previously caused launch hangs. Do not
  add it.
- Use the **exact** color hex, collection names, and field names from `PROJECT_CANON.md`.
  Don't invent alternates — the web and iOS clients must stay byte-compatible.
