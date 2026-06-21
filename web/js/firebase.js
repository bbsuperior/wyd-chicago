// firebase.js — REAL backend for WYD Chicago using the Firebase v10 MODULAR SDK (canon §5).
//
// Implements the SAME Auth + API interface as data.js, against Firebase Auth + Firestore.
// Loaded from the gstatic CDN (buildless — no npm). backend.js imports this only when
// firebase-config.js holds real keys; otherwise the mock (data.js) is used.
//
// Counters (committedCount/interestedCount/upvotes/downvotes/voteScore) are denormalized and
// kept correct by Cloud Functions triggers on the attendees/votes subcollections (canon §4).
// Here we ALSO apply an optimistic client-side increment for a snappy UI; if a Function also
// runs, you may double-count briefly — converge by re-reading getEvent(). For a deploy without
// Functions, the optimistic writes keep counts roughly correct on their own.
//
// Importing this module must NOT crash even before keys are filled — all SDK init is wrapped.

import { firebaseConfig } from './firebase-config.js';
import { recommendScore } from './recommend.js';
import { SEED_TAGS } from './seed.js';

export { recommendScore };
export const USING_FIREBASE = true;

const SDK = 'https://www.gstatic.com/firebasejs/10.12.2';

// Lazily import the SDK pieces. Wrapped so a missing/blocked CDN doesn't throw at module load.
const appMod = await import(`${SDK}/firebase-app.js`);
const authMod = await import(`${SDK}/firebase-auth.js`);
const fsMod = await import(`${SDK}/firebase-firestore.js`);

const {
  getAuth, onAuthStateChanged, signInWithEmailAndPassword, createUserWithEmailAndPassword,
  signOut: fbSignOut, sendEmailVerification, sendPasswordResetEmail, updateProfile: fbUpdateProfile,
} = authMod;

const {
  getFirestore, collection, doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, addDoc,
  query, where, orderBy, limit, serverTimestamp, increment, Timestamp,
} = fsMod;

const app = appMod.initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);

// ── shared state: keep a cached profile + admin/host flags from custom claims ─────────────────

let _profile = null;     // users/{uid} doc data + uid
let _claims = {};         // decoded custom claims (admin/host)
const listeners = new Set();

function emit() {
  const snap = _profile ? { ..._profile } : null;
  for (const cb of listeners) {
    try { cb(snap); } catch (_) { /* ignore */ }
  }
}

onAuthStateChanged(auth, async (fbUser) => {
  if (!fbUser) { _profile = null; _claims = {}; emit(); return; }
  try {
    const tokenRes = await fbUser.getIdTokenResult();
    _claims = tokenRes.claims || {};
  } catch (_) { _claims = {}; }
  _profile = await loadProfile(fbUser);
  emit();
});

async function loadProfile(fbUser) {
  const ref = doc(db, 'users', fbUser.uid);
  let snap = await getDoc(ref);
  if (!snap.exists()) {
    // First sign-in before onUserCreate Function ran: create a minimal profile.
    const base = defaultProfile(fbUser);
    await setDoc(ref, { ...base, createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
    snap = await getDoc(ref);
  }
  const data = snap.data() || {};
  return {
    uid: fbUser.uid,
    ...data,
    emailVerified: fbUser.emailVerified,
    // role: prefer custom claim, fall back to the users doc
    role: _claims.admin ? 'admin' : (_claims.host ? 'host' : (data.role || 'user')),
  };
}

function defaultProfile(fbUser) {
  const handle = (fbUser.email || 'user').split('@')[0].toLowerCase().replace(/[^a-z0-9_]/g, '').slice(0, 20) || 'user';
  return {
    displayName: fbUser.displayName || handle,
    username: handle,
    avatarUrl: null,
    bio: '',
    birthYear: null,
    gradeYear: null,
    neighborhood: null,
    interests: [],
    snapchatUsername: null,
    instagramUsername: null,
    role: 'user',
    savedEvents: [],
    emailVerified: !!fbUser.emailVerified,
  };
}

// ── converters / helpers ──────────────────────────────────────────────────────────────────────

function tsToISO(v) {
  if (!v) return null;
  if (typeof v === 'string') return v;
  if (v instanceof Date) return v.toISOString();
  if (typeof v.toDate === 'function') return v.toDate().toISOString();
  if (typeof v.seconds === 'number') return new Date(v.seconds * 1000).toISOString();
  return null;
}

function toTimestamp(iso) {
  if (!iso) return null;
  const d = iso instanceof Date ? iso : new Date(iso);
  return Number.isNaN(d.getTime()) ? null : Timestamp.fromDate(d);
}

function eventFromDoc(snap) {
  const d = snap.data() || {};
  return {
    ...d,
    id: snap.id,
    startAt: tsToISO(d.startAt),
    endAt: tsToISO(d.endAt),
    createdAt: tsToISO(d.createdAt),
    updatedAt: tsToISO(d.updatedAt),
  };
}

function userPublic(uid, d) {
  return {
    uid,
    displayName: d.displayName,
    username: d.username,
    avatarUrl: d.avatarUrl ?? null,
    bio: d.bio ?? '',
    neighborhood: d.neighborhood ?? null,
    interests: Array.isArray(d.interests) ? d.interests : [],
    gradeYear: d.gradeYear ?? null,
    snapchatUsername: d.snapchatUsername ?? null,
    instagramUsername: d.instagramUsername ?? null,
    role: d.role || 'user',
  };
}

function requireUid() {
  if (!auth.currentUser) throw new Error('You need to be signed in to do that.');
  return auth.currentUser.uid;
}

function requireVerified() {
  if (!auth.currentUser || !auth.currentUser.emailVerified) {
    throw new Error('Verify your email first.');
  }
  return auth.currentUser.uid;
}

async function friendsGoingCount(eventId, viewerUid) {
  if (!viewerUid) return 0;
  // accepted friends
  const friendsSnap = await getDocs(
    query(collection(db, 'users', viewerUid, 'friends'), where('status', '==', 'accepted'))
  );
  const friendUids = friendsSnap.docs.map((d) => d.id);
  if (!friendUids.length) return 0;
  // attendees going on this event
  const attSnap = await getDocs(
    query(collection(db, 'events', eventId, 'attendees'), where('status', '==', 'going'))
  );
  const going = new Set(attSnap.docs.map((d) => d.id));
  let n = 0;
  for (const fu of friendUids) if (going.has(fu)) n += 1;
  return n;
}

async function decorate(ev, viewerUid) {
  const out = { ...ev };
  const isAdmin = _profile && _profile.role === 'admin';
  let myRsvp = null;
  if (viewerUid) {
    const a = await getDoc(doc(db, 'events', ev.id, 'attendees', viewerUid));
    myRsvp = a.exists() ? a.data().status : null;
    const v = await getDoc(doc(db, 'events', ev.id, 'votes', viewerUid));
    out._myVote = v.exists() ? v.data().dir : 0;
  } else {
    out._myVote = 0;
  }
  out._myRsvp = myRsvp;
  // exact address gated to going-attendees or admin (canon §8)
  if (myRsvp !== 'going' && !isAdmin) out.exactAddress = null;
  out._saved = !!(_profile && (_profile.savedEvents || []).includes(ev.id));
  out._friendsGoing = await friendsGoingCount(ev.id, viewerUid);
  return out;
}

// ── AUTH ─────────────────────────────────────────────────────────────────────────────────────

export const Auth = {
  currentUser() { return _profile ? { ..._profile } : null; },

  onChange(cb) {
    listeners.add(cb);
    Promise.resolve().then(() => cb(_profile ? { ..._profile } : null));
    return () => listeners.delete(cb);
  },

  async signUp({ email, password, username, displayName, birthYear, interests }) {
    const handle = String(username || '').trim().toLowerCase();
    if (!/^[a-z0-9_]{3,20}$/.test(handle)) {
      throw new Error('Username must be 3–20 chars: letters, numbers, underscores.');
    }
    // uniqueness check (best-effort; enforce hard in security rules / a Function too)
    const taken = await getDocs(query(collection(db, 'users'), where('username', '==', handle), limit(1)));
    if (!taken.empty) throw new Error('That username is taken.');

    const cred = await createUserWithEmailAndPassword(auth, String(email).trim(), String(password));
    const fbUser = cred.user;
    if (displayName) { try { await fbUpdateProfile(fbUser, { displayName }); } catch (_) {} }

    const profile = {
      displayName: (displayName || handle).trim(),
      username: handle,
      avatarUrl: null,
      bio: '',
      birthYear: Number(birthYear) || null,
      gradeYear: null,
      neighborhood: null,
      interests: Array.isArray(interests) ? interests : [],
      snapchatUsername: null,
      instagramUsername: null,
      role: 'user',
      savedEvents: [],
      emailVerified: false,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    };
    await setDoc(doc(db, 'users', fbUser.uid), profile, { merge: true });
    try { await sendEmailVerification(fbUser); } catch (_) { /* user can retry */ }

    _profile = { uid: fbUser.uid, ...profile, emailVerified: false, role: 'user' };
    emit();
    return { ..._profile };
  },

  async signIn({ email, password }) {
    const cred = await signInWithEmailAndPassword(auth, String(email).trim(), String(password));
    _profile = await loadProfile(cred.user);
    emit();
    return { ..._profile };
  },

  async signOut() {
    await fbSignOut(auth);
    _profile = null;
    _claims = {};
    emit();
  },

  async sendVerification() {
    if (!auth.currentUser) throw new Error('Sign in first.');
    await sendEmailVerification(auth.currentUser);
  },

  async resetPassword(email) {
    await sendPasswordResetEmail(auth, String(email).trim());
  },

  isAdmin() { return !!(_profile && _profile.role === 'admin'); },
  isHost() { return !!(_profile && (_profile.role === 'host' || _profile.role === 'admin')); },

  async updateProfile(patch) {
    const uid = requireUid();
    const ref = doc(db, 'users', uid);
    const allowed = [
      'displayName', 'avatarUrl', 'bio', 'birthYear', 'gradeYear', 'neighborhood',
      'interests', 'snapchatUsername', 'instagramUsername',
    ];
    const update = { updatedAt: serverTimestamp() };
    for (const k of allowed) if (k in patch) update[k] = patch[k];
    if ('username' in patch && patch.username != null) {
      const handle = String(patch.username).trim().toLowerCase();
      if (!/^[a-z0-9_]{3,20}$/.test(handle)) {
        throw new Error('Username must be 3–20 chars: letters, numbers, underscores.');
      }
      const taken = await getDocs(query(collection(db, 'users'), where('username', '==', handle), limit(1)));
      if (!taken.empty && taken.docs[0].id !== uid) throw new Error('That username is taken.');
      update.username = handle;
    }
    await updateDoc(ref, update);
    _profile = { ..._profile, ...update, updatedAt: new Date().toISOString() };
    emit();
    return { ..._profile };
  },
};

// ── API ──────────────────────────────────────────────────────────────────────────────────────

function whenWindow(when) {
  const now = new Date();
  if (when === 'today') {
    const end = new Date(now); end.setHours(23, 59, 59, 999);
    return { from: now, to: end };
  }
  if (when === 'week') {
    const end = new Date(now.getTime() + 7 * 864e5);
    return { from: now, to: end };
  }
  if (when === 'weekend') {
    // next Fri 00:00 .. Sun 23:59 (or this weekend if we're in it)
    const d = new Date(now);
    const day = d.getDay();
    const toFri = (5 - day + 7) % 7;
    const fri = new Date(d); fri.setDate(d.getDate() + (day === 6 || day === 0 ? 0 : toFri)); fri.setHours(0, 0, 0, 0);
    const sun = new Date(fri); sun.setDate(fri.getDate() + (fri.getDay() === 5 ? 2 : (fri.getDay() === 6 ? 1 : 0))); sun.setHours(23, 59, 59, 999);
    return { from: now > fri ? now : fri, to: sun };
  }
  return null;
}

export const API = {
  async listTags() {
    const snap = await getDocs(collection(db, 'tags'));
    if (snap.empty) {
      // Fresh project with no tags doc yet — fall back to the seed list so chips render.
      return [...SEED_TAGS].sort((a, b) => (a.sort || 0) - (b.sort || 0));
    }
    return snap.docs
      .map((d) => ({ id: d.id, ...d.data() }))
      .sort((a, b) => (a.sort || 0) - (b.sort || 0));
  },

  async listEvents({ type, neighborhood, when, sort, search, friendsOnly, forYou } = {}) {
    const viewerUid = auth.currentUser ? auth.currentUser.uid : null;
    const isAdmin = _profile && _profile.role === 'admin';

    const constraints = [];
    // Non-admins: only published. Admins: all statuses.
    if (!isAdmin) constraints.push(where('status', '==', 'published'));
    if (type) constraints.push(where('eventType', '==', type));
    if (neighborhood) constraints.push(where('neighborhood', '==', neighborhood));

    // Only upcoming events (server-side lower bound).
    constraints.push(where('startAt', '>=', Timestamp.fromDate(new Date(Date.now() - 6 * 36e5))));

    // Primary order must lead with the range field (startAt) for Firestore.
    constraints.push(orderBy('startAt', 'asc'));

    const snap = await getDocs(query(collection(db, 'events'), ...constraints));
    let list = snap.docs.map(eventFromDoc);

    // "when" upper bound (client-side; lower bound already applied server-side).
    const w = whenWindow(when);
    if (w) {
      list = list.filter((e) => {
        const t = new Date(e.startAt).getTime();
        return t >= w.from.getTime() && t <= w.to.getTime();
      });
    }

    if (search) {
      const q = String(search).trim().toLowerCase();
      list = list.filter((e) =>
        e.title.toLowerCase().includes(q) ||
        (e.description || '').toLowerCase().includes(q) ||
        (e.neighborhood || '').toLowerCase().includes(q) ||
        (e.approxArea || '').toLowerCase().includes(q)
      );
    }

    // friends-only / friends sort needs per-event friend counts.
    const wantFriends = friendsOnly || sort === 'friendsOnly';
    const wantForYou = forYou || sort === 'forYou';
    const needCounts = wantFriends || wantForYou || sort === 'friendsOnly';

    let counts = null;
    if (needCounts && viewerUid) {
      counts = {};
      await Promise.all(list.map(async (e) => { counts[e.id] = await friendsGoingCount(e.id, viewerUid); }));
    }

    if (wantFriends) {
      if (!viewerUid) return [];
      list = list.filter((e) => (counts[e.id] || 0) > 0);
    }

    if (wantForYou) {
      list = list
        .map((e) => ({ e, s: recommendScore(_profile, e, (counts && counts[e.id]) || 0) }))
        .sort((a, b) => b.s - a.s || new Date(a.e.startAt) - new Date(b.e.startAt))
        .map((x) => x.e);
    } else if (sort === 'hype') {
      list.sort((a, b) => (b.voteScore || 0) - (a.voteScore || 0) || new Date(a.startAt) - new Date(b.startAt));
    } else if (sort === 'friendsOnly') {
      list.sort((a, b) => ((counts && counts[b.id]) || 0) - ((counts && counts[a.id]) || 0) || new Date(a.startAt) - new Date(b.startAt));
    } // else already startAt-asc (soonest / default)

    return Promise.all(list.map((e) => decorate(e, viewerUid)));
  },

  async getEvent(id) {
    const snap = await getDoc(doc(db, 'events', id));
    if (!snap.exists()) throw new Error('Event not found.');
    return decorate(eventFromDoc(snap), auth.currentUser ? auth.currentUser.uid : null);
  },

  async rsvp(id, status) {
    const uid = requireVerified();
    if (status !== null && status !== 'going' && status !== 'interested') {
      throw new Error('Invalid RSVP status.');
    }
    const attRef = doc(db, 'events', id, 'attendees', uid);
    const evRef = doc(db, 'events', id);
    const prevSnap = await getDoc(attRef);
    const prev = prevSnap.exists() ? prevSnap.data().status : null;

    // Write the attendee subcollection doc first.
    if (status === null) await deleteDoc(attRef);
    else await setDoc(attRef, { status, rsvpAt: serverTimestamp() });

    // Optimistic count deltas (a Cloud Function trigger reconciles authoritatively, canon §4).
    if (prev !== status) {
      let going = 0, interested = 0;
      if (prev === 'going') going -= 1;
      if (prev === 'interested') interested -= 1;
      if (status === 'going') going += 1;
      if (status === 'interested') interested += 1;
      const update = { updatedAt: serverTimestamp() };
      if (going) update.committedCount = increment(going);
      if (interested) update.interestedCount = increment(interested);
      try { await updateDoc(evRef, update); } catch (_) { /* Function will reconcile */ }
    }
  },

  async getMyRsvp(id) {
    if (!auth.currentUser) return null;
    const a = await getDoc(doc(db, 'events', id, 'attendees', auth.currentUser.uid));
    return a.exists() ? a.data().status : null;
  },

  async vote(id, dir) {
    const uid = requireVerified();
    const voteRef = doc(db, 'events', id, 'votes', uid);
    const evRef = doc(db, 'events', id);
    const prevSnap = await getDoc(voteRef);
    const prev = prevSnap.exists() ? prevSnap.data().dir : 0;

    if (dir === 0) {
      await deleteDoc(voteRef);
    } else if (dir === 1 || dir === -1) {
      await setDoc(voteRef, { dir, votedAt: serverTimestamp() });
    } else {
      throw new Error('Invalid vote direction.');
    }

    if (prev !== dir) {
      const update = { updatedAt: serverTimestamp() };
      let up = 0, down = 0;
      if (prev === 1) up -= 1; if (prev === -1) down -= 1;
      if (dir === 1) up += 1; if (dir === -1) down += 1;
      if (up) update.upvotes = increment(up);
      if (down) update.downvotes = increment(down);
      update.voteScore = increment(up - down);
      try { await updateDoc(evRef, update); } catch (_) { /* Function reconciles */ }
    }
  },

  async getMyVote(id) {
    if (!auth.currentUser) return 0;
    const v = await getDoc(doc(db, 'events', id, 'votes', auth.currentUser.uid));
    return v.exists() ? v.data().dir : 0;
  },

  async toggleSave(id) {
    const uid = requireUid();
    const saved = !((_profile.savedEvents || []).includes(id));
    const next = saved
      ? [...(_profile.savedEvents || []), id]
      : (_profile.savedEvents || []).filter((x) => x !== id);
    await updateDoc(doc(db, 'users', uid), { savedEvents: next, updatedAt: serverTimestamp() });
    _profile = { ..._profile, savedEvents: next };
    emit();
    return saved;
  },

  async listAttendees(id) {
    const snap = await getDocs(collection(db, 'events', id, 'attendees'));
    const uids = snap.docs.map((d) => d.id);
    const users = await Promise.all(uids.map(async (u) => {
      const us = await getDoc(doc(db, 'users', u));
      return us.exists() ? userPublic(u, us.data()) : null;
    }));
    return users.filter(Boolean);
  },

  async addComment(id, text) {
    const uid = requireUid();
    const body = String(text || '').trim();
    if (!body) throw new Error('Say something first.');
    const ref = await addDoc(collection(db, 'events', id, 'comments'), {
      authorId: uid,
      authorName: _profile.displayName,
      text: body.slice(0, 500),
      createdAt: serverTimestamp(),
    });
    return {
      commentId: ref.id,
      authorId: uid,
      authorName: _profile.displayName,
      text: body.slice(0, 500),
      createdAt: new Date().toISOString(),
    };
  },

  async listComments(id) {
    const snap = await getDocs(query(collection(db, 'events', id, 'comments'), orderBy('createdAt', 'asc')));
    return snap.docs.map((d) => ({ commentId: d.id, ...d.data(), createdAt: tsToISO(d.data().createdAt) }));
  },

  async report({ targetType, targetId, reason, details }) {
    const uid = requireUid();
    if (!['event', 'user', 'comment'].includes(targetType)) throw new Error('Invalid report target.');
    await addDoc(collection(db, 'reports'), {
      targetType,
      targetId: String(targetId),
      reporterId: uid,
      reason: String(reason || '').slice(0, 200),
      details: String(details || '').slice(0, 1000),
      status: 'open',
      createdAt: serverTimestamp(),
    });
  },

  // ── friends ──────────────────────────────────────────────────────────────────────────────

  async searchUsers(queryStr) {
    const q = String(queryStr || '').trim().toLowerCase();
    if (!q) return [];
    // Prefix search on username via range query (Firestore has no contains).
    const snap = await getDocs(query(
      collection(db, 'users'),
      where('username', '>=', q),
      where('username', '<=', q + String.fromCharCode(0xf8ff)),
      limit(20)
    ));
    const me = auth.currentUser ? auth.currentUser.uid : null;
    return snap.docs.filter((d) => d.id !== me).map((d) => userPublic(d.id, d.data()));
  },

  async addFriend(username) {
    const me = requireUid();
    const handle = String(username || '').trim().toLowerCase();
    const snap = await getDocs(query(collection(db, 'users'), where('username', '==', handle), limit(1)));
    if (snap.empty) throw new Error('No one with that username.');
    const target = snap.docs[0];
    if (target.id === me) throw new Error("You can't add yourself.");

    // If they already requested ME, accept instead.
    const incoming = await getDoc(doc(db, 'users', me, 'friends', target.id));
    if (incoming.exists() && incoming.data().status === 'pending' && incoming.data().direction === 'in') {
      await setDoc(doc(db, 'users', me, 'friends', target.id), { status: 'accepted', since: serverTimestamp(), direction: 'in' });
      await setDoc(doc(db, 'users', target.id, 'friends', me), { status: 'accepted', since: serverTimestamp(), direction: 'out' });
      return;
    }
    await setDoc(doc(db, 'users', me, 'friends', target.id), { status: 'pending', since: serverTimestamp(), direction: 'out' });
    await setDoc(doc(db, 'users', target.id, 'friends', me), { status: 'pending', since: serverTimestamp(), direction: 'in' });
  },

  async listFriends() {
    if (!auth.currentUser) return [];
    const me = auth.currentUser.uid;
    const snap = await getDocs(query(collection(db, 'users', me, 'friends'), where('status', '==', 'accepted')));
    const users = await Promise.all(snap.docs.map(async (d) => {
      const us = await getDoc(doc(db, 'users', d.id));
      return us.exists() ? userPublic(d.id, us.data()) : null;
    }));
    return users.filter(Boolean);
  },

  async listFriendRequests() {
    if (!auth.currentUser) return [];
    const me = auth.currentUser.uid;
    const snap = await getDocs(query(
      collection(db, 'users', me, 'friends'),
      where('status', '==', 'pending'),
      where('direction', '==', 'in')
    ));
    const users = await Promise.all(snap.docs.map(async (d) => {
      const us = await getDoc(doc(db, 'users', d.id));
      return us.exists() ? userPublic(d.id, us.data()) : null;
    }));
    return users.filter(Boolean);
  },

  async respondFriend(targetUid, accept) {
    const me = requireUid();
    const ref = doc(db, 'users', me, 'friends', targetUid);
    const req = await getDoc(ref);
    if (!req.exists() || req.data().status !== 'pending' || req.data().direction !== 'in') {
      throw new Error('No pending request from that user.');
    }
    if (accept) {
      await setDoc(ref, { status: 'accepted', since: serverTimestamp(), direction: 'in' });
      await setDoc(doc(db, 'users', targetUid, 'friends', me), { status: 'accepted', since: serverTimestamp(), direction: 'out' });
    } else {
      await deleteDoc(ref);
      try { await deleteDoc(doc(db, 'users', targetUid, 'friends', me)); } catch (_) {}
    }
  },

  // ── admin / host ───────────────────────────────────────────────────────────────────────────

  async createEvent(data) {
    const uid = requireUid();
    if (!(_profile.role === 'admin' || _profile.role === 'host')) {
      throw new Error('Only hosts and admins can create events.');
    }
    const ev = {
      title: String(data.title || 'Untitled event').trim(),
      description: String(data.description || '').trim(),
      eventType: data.eventType || 'kickback',
      tags: Array.isArray(data.tags) ? data.tags : [],
      hostId: uid,
      hostName: data.hostName || _profile.displayName,
      coverImageUrl: data.coverImageUrl ?? null,
      images: Array.isArray(data.images) ? data.images : [],
      startAt: toTimestamp(data.startAt) || serverTimestamp(),
      endAt: toTimestamp(data.endAt),
      venueName: data.venueName ?? null,
      neighborhood: data.neighborhood ?? null,
      approxArea: data.approxArea || data.neighborhood || 'Chicago',
      exactAddress: data.exactAddress ?? null,
      priceCents: Number.isFinite(data.priceCents) ? data.priceCents : 0,
      capacity: data.capacity ?? null,
      ageMin: Number.isFinite(data.ageMin) ? data.ageMin : 14,
      ageMax: Number.isFinite(data.ageMax) ? data.ageMax : 18,
      recommendedFor: Array.isArray(data.recommendedFor) ? data.recommendedFor : [],
      committedCount: 0,
      interestedCount: 0,
      upvotes: 0,
      downvotes: 0,
      voteScore: 0,
      status: data.status || 'draft', // canon §8: default draft until admin publishes
      isFeatured: !!data.isFeatured,
      createdBy: uid,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    };
    const ref = await addDoc(collection(db, 'events'), ev);
    const snap = await getDoc(ref);
    return decorate(eventFromDoc(snap), uid);
  },

  async updateEvent(id, patch) {
    requireUid();
    const evRef = doc(db, 'events', id);
    const editable = [
      'title', 'description', 'eventType', 'tags', 'hostName', 'coverImageUrl', 'images',
      'venueName', 'neighborhood', 'approxArea', 'exactAddress',
      'priceCents', 'capacity', 'ageMin', 'ageMax', 'recommendedFor', 'isFeatured',
    ];
    const update = { updatedAt: serverTimestamp() };
    for (const k of editable) if (k in patch) update[k] = patch[k];
    if ('startAt' in patch) update.startAt = toTimestamp(patch.startAt);
    if ('endAt' in patch) update.endAt = toTimestamp(patch.endAt);
    if ('status' in patch && _profile.role === 'admin') update.status = patch.status;
    await updateDoc(evRef, update);
    const snap = await getDoc(evRef);
    return decorate(eventFromDoc(snap), auth.currentUser.uid);
  },

  async setEventStatus(id, status) {
    requireUid();
    if (!['draft', 'published', 'cancelled'].includes(status)) throw new Error('Invalid status.');
    if (status === 'published' && _profile.role !== 'admin') throw new Error('Only an admin can publish.');
    await updateDoc(doc(db, 'events', id), { status, updatedAt: serverTimestamp() });
  },

  async listReports() {
    if (!(_profile && _profile.role === 'admin')) throw new Error('Admins only.');
    const snap = await getDocs(query(collection(db, 'reports'), orderBy('createdAt', 'desc')));
    return snap.docs.map((d) => ({ reportId: d.id, ...d.data(), createdAt: tsToISO(d.data().createdAt) }));
  },
};
