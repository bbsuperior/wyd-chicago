// backend.js — THE SWITCHER (canon §5).
//
// App code imports ONLY from here:  import { Auth, API, USING_FIREBASE } from './backend.js'
// It NEVER imports data.js or firebase.js directly.
//
// Choice of backend:
//   • If firebase-config.js holds real keys (isConfigured() === true) -> the real Firebase
//     backend (firebase.js).
//   • Otherwise -> the localStorage mock (data.js), so the site works fully on GitHub Pages
//     with no backend configured (great for demos).
//
// ── Top-level await note ─────────────────────────────────────────────────────────────────────
// This is an ES module, and `import { Auth, API } from './backend.js'` must give the caller a
// usable Auth/API IMMEDIATELY (so app.js never blocks on first paint). The mock is synchronous
// to import, so we eagerly load it and bind Auth/API to it right away. If Firebase is configured,
// we ALSO kick off a dynamic import of firebase.js and, once it resolves, swap the live bindings
// over to it. Callers can `await ready()` if they specifically need the final backend resolved
// (e.g. before reading USING_FIREBASE), but they don't have to — the UI works against the mock
// in the meantime and transparently upgrades.
//
// Because exported bindings are live, we keep stable `Auth`/`API` proxy objects whose methods
// forward to whichever implementation is currently active. This way references captured by
// app.js stay valid across the swap.

import { isConfigured } from './firebase-config.js';
import * as Mock from './data.js';

// Active implementation (starts as the mock so nothing blocks).
let impl = Mock;

// USING_FIREBASE reflects the ACTIVE backend. It flips to true once firebase.js is live.
export let USING_FIREBASE = false;

// recommendScore is identical across backends (pure, shared) — re-export the mock's copy.
export const recommendScore = Mock.recommendScore;

// Stable proxy objects: every key on the contract forwards to `impl` at call time, so swapping
// the implementation later requires no changes on the caller's side.
const AUTH_METHODS = [
  'currentUser', 'onChange', 'signUp', 'signIn', 'signOut', 'sendVerification',
  'resetPassword', 'isAdmin', 'isHost', 'updateProfile',
];
const API_METHODS = [
  'listTags', 'listEvents', 'getEvent', 'rsvp', 'getMyRsvp', 'vote', 'getMyVote',
  'toggleSave', 'listAttendees', 'addComment', 'listComments', 'report',
  'searchUsers', 'addFriend', 'listFriends', 'listFriendRequests', 'respondFriend',
  'createEvent', 'updateEvent', 'setEventStatus', 'listReports',
];

function makeProxy(methodNames, pick) {
  const obj = {};
  for (const name of methodNames) {
    obj[name] = (...args) => pick()[name](...args);
  }
  return obj;
}

export const Auth = makeProxy(AUTH_METHODS, () => impl.Auth);
export const API = makeProxy(API_METHODS, () => impl.API);

// Resolve the final backend. Resolves to a small info object once decided.
const readyPromise = (async () => {
  if (!isConfigured()) {
    USING_FIREBASE = false;
    return { usingFirebase: false };
  }
  try {
    const FB = await import('./firebase.js');
    impl = FB;                 // swap live bindings over to Firebase
    USING_FIREBASE = true;
    return { usingFirebase: true };
  } catch (err) {
    // If Firebase fails to load (CDN blocked, bad keys), stay on the mock so the app still works.
    console.warn('[backend] Firebase configured but failed to load; falling back to mock.', err);
    impl = Mock;
    USING_FIREBASE = false;
    return { usingFirebase: false, error: err };
  }
})();

// Await this if you need the final backend resolved (e.g. to read USING_FIREBASE reliably).
// The UI doesn't have to: Auth/API work against the mock until/unless Firebase takes over.
export function ready() {
  return readyPromise;
}
