// firebase-config.js — the web Firebase config for WYD Chicago.
//
// ⚠️ These web API keys are PUBLIC by design and are SAFE TO COMMIT. They identify the
// project to Firebase; they are NOT secrets. Real protection comes from Firebase Security
// Rules (firebase/firestore.rules) + App Check, not from hiding this object. (See .gitignore:
// only service-account / admin-SDK keys are ignored.)
//
// HOW TO FILL THESE IN (one-time, ~2 min):
//   1. Go to https://console.firebase.google.com and create a NEW project — suggested id
//      "wyd-chicago" (do NOT reuse any other project).
//   2. In the project, click the </> "Web app" button to register a web app.
//   3. Firebase shows a `firebaseConfig` object — copy each value below, replacing the
//      "PASTE_..." placeholders.
//   4. In Build → Authentication, enable the Email/Password sign-in provider.
//   5. In Build → Firestore Database, create a database (production mode) and deploy the
//      rules/indexes from the firebase/ folder.
//   6. Reload the site. backend.js auto-detects real keys and switches from the mock to
//      live Firebase. Until then, the site runs fully in mock mode (great for demos).

export const firebaseConfig = {
  apiKey: "PASTE_API_KEY",
  authDomain: "PASTE_PROJECT_ID.firebaseapp.com",
  projectId: "PASTE_PROJECT_ID",
  storageBucket: "PASTE_PROJECT_ID.appspot.com",
  messagingSenderId: "PASTE_SENDER_ID",
  appId: "PASTE_APP_ID",
  // measurementId is optional (Analytics) — paste it if you enabled Analytics:
  measurementId: "PASTE_MEASUREMENT_ID",
};

// Returns true only once the placeholders above have been replaced with real values.
// backend.js uses this to decide between the real Firebase backend and the mock.
export function isConfigured() {
  const required = [
    firebaseConfig.apiKey,
    firebaseConfig.authDomain,
    firebaseConfig.projectId,
    firebaseConfig.appId,
  ];
  return required.every(
    (v) => typeof v === "string" && v.length > 0 && !v.startsWith("PASTE_")
  );
}
