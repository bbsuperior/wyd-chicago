// data.js — MOCK backend for WYD Chicago (canon §5).
//
// Implements the FULL Auth + API interface, backed by localStorage, so the whole site works
// on GitHub Pages with NO Firebase configured. firebase.js implements the SAME interface against
// real Firestore; backend.js picks one at runtime. App code imports ONLY from backend.js.
//
// ── BUILT-IN DEMO ADMIN ("master login") ────────────────────────────────────────────────────
//   email:    admin@wydchicago.app
//   password: chicago
//   role:     admin
// Sign in with these to reach the admin dashboard. (Documented per canon — demo only.)
// You can also sign up your own account; new accounts are role "user".
// ─────────────────────────────────────────────────────────────────────────────────────────────
//
// State model in localStorage (single key, JSON blob): users (profile docs), creds (email→{uid,
// password}), events, and per-user RSVPs/votes/saves/friends/comments/reports. Seeded from
// seed.js on first load. Counts (committed/interested/up/down) stay consistent on every mutation.

import { recommendScore } from './recommend.js';
import { SEED_TAGS, SEED_EVENTS, SEED_USERS } from './seed.js';

export { recommendScore };
export const USING_FIREBASE = false;

const STORE_KEY = 'wyd.mock.v1';
const SESSION_KEY = 'wyd.mock.session.v1';

// Demo admin credentials (also documented in the header above).
const DEMO_ADMIN_EMAIL = 'admin@wydchicago.app';
const DEMO_ADMIN_PASSWORD = 'chicago';

// ── store load / save ────────────────────────────────────────────────────────────────────────

function nowISO() { return new Date().toISOString(); }
function uid(prefix) { return `${prefix}_${Math.random().toString(36).slice(2, 10)}`; }

function freshStore() {
  // Seed users -> profile docs keyed by uid; seed creds for demo accounts.
  const users = {};
  const creds = {}; // email(lowercased) -> { uid, password }
  for (const u of SEED_USERS) {
    users[u.uid] = {
      ...u,
      bio: u.bio || '',
      savedEvents: Array.isArray(u.savedEvents) ? [...u.savedEvents] : [],
      createdAt: nowISO(),
      updatedAt: nowISO(),
    };
  }
  // Demo admin login maps to the seeded 'admin' user.
  creds[DEMO_ADMIN_EMAIL] = { uid: 'admin', password: DEMO_ADMIN_PASSWORD };
  // Give the other seed users predictable demo logins (username@demo.wyd / "chicago").
  for (const u of SEED_USERS) {
    if (u.uid === 'admin') continue;
    creds[`${u.username}@demo.wyd`] = { uid: u.uid, password: 'chicago' };
  }

  // Events keyed by id. attendees/votes/comments live in parallel maps keyed by eventId.
  const events = {};
  const attendees = {}; // eventId -> { uid -> { status, rsvpAt } }
  const votes = {};     // eventId -> { uid -> { dir, votedAt } }
  const comments = {};  // eventId -> [ { commentId, authorId, authorName, text, createdAt } ]
  for (const e of SEED_EVENTS) {
    events[e.id] = { ...e, createdAt: nowISO(), updatedAt: nowISO() };
    attendees[e.id] = {};
    votes[e.id] = {};
    comments[e.id] = [];
  }

  // friends[uid] -> { friendUid -> { status, since, direction } }
  const friends = {};
  // Pre-wire a couple of accepted demo friendships so the friends feed isn't empty.
  function befriend(a, b) {
    friends[a] = friends[a] || {};
    friends[b] = friends[b] || {};
    friends[a][b] = { status: 'accepted', since: nowISO(), direction: 'out' };
    friends[b][a] = { status: 'accepted', since: nowISO(), direction: 'in' };
  }
  befriend('u_maya', 'u_priya');
  befriend('u_deon', 'u_jordan');

  const reports = []; // { reportId, targetType, targetId, reporterId, reason, details, status, createdAt }

  return { users, creds, events, attendees, votes, comments, friends, reports, tags: SEED_TAGS };
}

function loadStore() {
  try {
    const raw = localStorage.getItem(STORE_KEY);
    if (raw) return JSON.parse(raw);
  } catch (_) { /* corrupt — reseed */ }
  const s = freshStore();
  saveStore(s);
  return s;
}

function saveStore(s) {
  try { localStorage.setItem(STORE_KEY, JSON.stringify(s)); } catch (_) { /* quota — ignore */ }
}

let store = loadStore();
function persist() { saveStore(store); }

// ── session ──────────────────────────────────────────────────────────────────────────────────

let currentUid = (() => {
  try { return localStorage.getItem(SESSION_KEY) || null; } catch (_) { return null; }
})();

const authListeners = new Set();

function setSession(u) {
  currentUid = u ? u.uid : null;
  try {
    if (currentUid) localStorage.setItem(SESSION_KEY, currentUid);
    else localStorage.removeItem(SESSION_KEY);
  } catch (_) { /* ignore */ }
  const snapshot = currentUser();
  for (const cb of authListeners) {
    try { cb(snapshot); } catch (_) { /* listener error shouldn't break others */ }
  }
}

function currentUser() {
  if (!currentUid) return null;
  const u = store.users[currentUid];
  return u ? clone(u) : null;
}

function clone(o) { return JSON.parse(JSON.stringify(o)); }

// ── helpers ──────────────────────────────────────────────────────────────────────────────────

function requireUser() {
  if (!currentUid || !store.users[currentUid]) {
    throw new Error('You need to be signed in to do that.');
  }
  return store.users[currentUid];
}

function ageFromBirthYear(by) {
  const y = Number(by);
  if (!Number.isFinite(y) || y <= 0) return null;
  return new Date().getFullYear() - y;
}

function friendsGoingCount(eventId, viewerUid) {
  if (!viewerUid) return 0;
  const myFriends = store.friends[viewerUid] || {};
  const att = store.attendees[eventId] || {};
  let n = 0;
  for (const [fUid, rel] of Object.entries(myFriends)) {
    if (rel.status !== 'accepted') continue;
    if (att[fUid] && att[fUid].status === 'going') n += 1;
  }
  return n;
}

// Returns an Event enriched with viewer-specific, non-canonical convenience fields the UI uses.
function decorateEvent(e, viewerUid) {
  const out = clone(e);
  // Hide exact address unless the viewer RSVP'd "going" or is an admin (canon §8).
  const att = (store.attendees[e.id] || {})[viewerUid];
  const viewer = viewerUid ? store.users[viewerUid] : null;
  const isAdmin = viewer && viewer.role === 'admin';
  const goingHere = att && att.status === 'going';
  if (!goingHere && !isAdmin) out.exactAddress = null;
  // viewer extras (not part of the canon doc, prefixed to signal that):
  out._myRsvp = att ? att.status : null;
  const myVote = (store.votes[e.id] || {})[viewerUid];
  out._myVote = myVote ? myVote.dir : 0;
  out._saved = !!(viewer && (viewer.savedEvents || []).includes(e.id));
  out._friendsGoing = friendsGoingCount(e.id, viewerUid);
  return out;
}

function userPublic(u) {
  if (!u) return null;
  return {
    uid: u.uid,
    displayName: u.displayName,
    username: u.username,
    avatarUrl: u.avatarUrl ?? null,
    bio: u.bio ?? '',
    neighborhood: u.neighborhood ?? null,
    interests: Array.isArray(u.interests) ? [...u.interests] : [],
    gradeYear: u.gradeYear ?? null,
    snapchatUsername: u.snapchatUsername ?? null,
    instagramUsername: u.instagramUsername ?? null,
    role: u.role || 'user',
  };
}

function delay(ms = 60) { return new Promise((r) => setTimeout(r, ms)); }

// ── AUTH ─────────────────────────────────────────────────────────────────────────────────────

export const Auth = {
  currentUser() { return currentUser(); },

  onChange(cb) {
    authListeners.add(cb);
    // fire immediately with current state (async to match real backends)
    Promise.resolve().then(() => cb(currentUser()));
    return () => authListeners.delete(cb);
  },

  async signUp({ email, password, username, displayName, birthYear, interests }) {
    await delay();
    const emailKey = String(email || '').trim().toLowerCase();
    if (!emailKey || !password) throw new Error('Email and password are required.');
    if (store.creds[emailKey]) throw new Error('That email is already in use.');

    const handle = String(username || '').trim().toLowerCase();
    if (!/^[a-z0-9_]{3,20}$/.test(handle)) {
      throw new Error('Username must be 3–20 chars: letters, numbers, underscores.');
    }
    if (Object.values(store.users).some((u) => u.username === handle)) {
      throw new Error('That username is taken.');
    }

    const newUid = uid('u');
    const profile = {
      uid: newUid,
      displayName: (displayName || handle).trim(),
      username: handle,
      avatarUrl: null,
      bio: '',
      birthYear: Number(birthYear) || null,
      gradeYear: null,
      neighborhood: null,
      interests: Array.isArray(interests) ? [...interests] : [],
      snapchatUsername: null,
      instagramUsername: null,
      role: 'user',
      savedEvents: [],
      emailVerified: false, // becomes true after sendVerification() (fake verify)
      createdAt: nowISO(),
      updatedAt: nowISO(),
    };
    store.users[newUid] = profile;
    store.creds[emailKey] = { uid: newUid, password: String(password) };
    store.attendees[newUid]; // no-op; keep shapes consistent
    persist();
    setSession(profile);
    return clone(profile);
  },

  async signIn({ email, password }) {
    await delay();
    const emailKey = String(email || '').trim().toLowerCase();
    const cred = store.creds[emailKey];
    if (!cred || cred.password !== String(password)) {
      throw new Error('Wrong email or password.');
    }
    const u = store.users[cred.uid];
    if (!u) throw new Error('Account not found.');
    setSession(u);
    return clone(u);
  },

  async signOut() {
    await delay();
    setSession(null);
  },

  async sendVerification() {
    await delay();
    // Mock: there's no real email. Flip emailVerified true so the RSVP/vote gate opens.
    const u = requireUser();
    u.emailVerified = true;
    u.updatedAt = nowISO();
    persist();
    setSession(u); // re-emit so the UI updates
  },

  async resetPassword(email) {
    await delay();
    // Mock: nothing to send. Always resolves so the UI can show a friendly toast.
    return;
  },

  isAdmin() {
    const u = currentUser();
    return !!u && u.role === 'admin';
  },

  isHost() {
    const u = currentUser();
    return !!u && (u.role === 'host' || u.role === 'admin');
  },

  async updateProfile(patch) {
    await delay();
    const u = requireUser();
    const allowed = [
      'displayName', 'avatarUrl', 'bio', 'birthYear', 'gradeYear', 'neighborhood',
      'interests', 'snapchatUsername', 'instagramUsername',
    ];
    for (const k of allowed) {
      if (k in patch) u[k] = patch[k];
    }
    // username change: validate + uniqueness
    if ('username' in patch && patch.username != null) {
      const handle = String(patch.username).trim().toLowerCase();
      if (!/^[a-z0-9_]{3,20}$/.test(handle)) {
        throw new Error('Username must be 3–20 chars: letters, numbers, underscores.');
      }
      if (Object.values(store.users).some((x) => x.uid !== u.uid && x.username === handle)) {
        throw new Error('That username is taken.');
      }
      u.username = handle;
    }
    u.updatedAt = nowISO();
    persist();
    setSession(u);
    return clone(u);
  },
};

// ── API ──────────────────────────────────────────────────────────────────────────────────────

const WHEN_RANGES = {
  // "when" filter -> predicate on startAt millis relative to now
  today: (start, now) => sameDay(start, now),
  weekend: (start, now) => isThisWeekend(start, now),
  week: (start, now) => start >= now && start <= now + 7 * 864e5,
};

function sameDay(ms, nowMs) {
  const a = new Date(ms), b = new Date(nowMs);
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}
function isThisWeekend(ms, nowMs) {
  const d = new Date(ms);
  const day = d.getDay(); // 0 Sun .. 6 Sat
  const isWknd = day === 5 || day === 6 || day === 0;
  return isWknd && ms >= nowMs && ms <= nowMs + 7 * 864e5;
}

export const API = {
  async listTags() {
    await delay();
    return clone(store.tags).sort((a, b) => (a.sort || 0) - (b.sort || 0));
  },

  async listEvents({ type, neighborhood, when, sort, search, friendsOnly, forYou } = {}) {
    await delay();
    const viewerUid = currentUid;
    const viewer = viewerUid ? store.users[viewerUid] : null;
    const isAdmin = viewer && viewer.role === 'admin';
    const now = Date.now();

    let list = Object.values(store.events);

    // Non-admins only see published events.
    if (!isAdmin) list = list.filter((e) => e.status === 'published');

    // Hide events that have already started/ended for the feed.
    list = list.filter((e) => new Date(e.startAt).getTime() >= now - 6 * 36e5); // 6h grace

    if (type) list = list.filter((e) => e.eventType === type);
    if (neighborhood) list = list.filter((e) => e.neighborhood === neighborhood);
    if (when && WHEN_RANGES[when]) {
      list = list.filter((e) => WHEN_RANGES[when](new Date(e.startAt).getTime(), now));
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

    // friends-only: keep events where at least one accepted friend is going.
    const wantFriends = friendsOnly || sort === 'friendsOnly';
    if (wantFriends && viewerUid) {
      list = list.filter((e) => friendsGoingCount(e.id, viewerUid) > 0);
    } else if (wantFriends && !viewerUid) {
      list = []; // not signed in -> no friends
    }

    // sorting
    const wantForYou = forYou || sort === 'forYou';
    if (wantForYou) {
      list = list
        .map((e) => ({ e, s: recommendScore(viewer, e, friendsGoingCount(e.id, viewerUid)) }))
        .sort((a, b) => b.s - a.s || new Date(a.e.startAt) - new Date(b.e.startAt))
        .map((x) => x.e);
    } else if (sort === 'hype') {
      list.sort((a, b) => (b.voteScore || 0) - (a.voteScore || 0) || new Date(a.startAt) - new Date(b.startAt));
    } else if (sort === 'friendsOnly') {
      list.sort((a, b) => friendsGoingCount(b.id, viewerUid) - friendsGoingCount(a.id, viewerUid) || new Date(a.startAt) - new Date(b.startAt));
    } else {
      // default + "soonest"
      list.sort((a, b) => new Date(a.startAt) - new Date(b.startAt));
    }

    return list.map((e) => decorateEvent(e, viewerUid));
  },

  async getEvent(id) {
    await delay();
    const e = store.events[id];
    if (!e) throw new Error('Event not found.');
    return decorateEvent(e, currentUid);
  },

  async rsvp(id, status) {
    await delay();
    const u = requireUser();
    if (!u.emailVerified) throw new Error('Verify your email before RSVPing.');
    const e = store.events[id];
    if (!e) throw new Error('Event not found.');
    const att = store.attendees[id] || (store.attendees[id] = {});
    const prev = att[u.uid] ? att[u.uid].status : null;

    // adjust counts off the previous state
    if (prev === 'going') e.committedCount = Math.max(0, e.committedCount - 1);
    if (prev === 'interested') e.interestedCount = Math.max(0, e.interestedCount - 1);

    if (status === null) {
      delete att[u.uid];
    } else if (status === 'going' || status === 'interested') {
      att[u.uid] = { status, rsvpAt: nowISO() };
      if (status === 'going') e.committedCount += 1;
      else e.interestedCount += 1;
    } else {
      throw new Error('Invalid RSVP status.');
    }
    e.updatedAt = nowISO();
    persist();
  },

  async getMyRsvp(id) {
    await delay();
    if (!currentUid) return null;
    const att = (store.attendees[id] || {})[currentUid];
    return att ? att.status : null;
  },

  async vote(id, dir) {
    await delay();
    const u = requireUser();
    if (!u.emailVerified) throw new Error('Verify your email before voting.');
    const e = store.events[id];
    if (!e) throw new Error('Event not found.');
    const v = store.votes[id] || (store.votes[id] = {});
    const prev = v[u.uid] ? v[u.uid].dir : 0;

    // remove previous contribution
    if (prev === 1) e.upvotes = Math.max(0, e.upvotes - 1);
    if (prev === -1) e.downvotes = Math.max(0, e.downvotes - 1);

    if (dir === 0) {
      delete v[u.uid];
    } else if (dir === 1 || dir === -1) {
      v[u.uid] = { dir, votedAt: nowISO() };
      if (dir === 1) e.upvotes += 1;
      else e.downvotes += 1;
    } else {
      throw new Error('Invalid vote direction.');
    }
    e.voteScore = e.upvotes - e.downvotes;
    e.updatedAt = nowISO();
    persist();
  },

  async getMyVote(id) {
    await delay();
    if (!currentUid) return 0;
    const v = (store.votes[id] || {})[currentUid];
    return v ? v.dir : 0;
  },

  async toggleSave(id) {
    await delay();
    const u = requireUser();
    if (!store.events[id]) throw new Error('Event not found.');
    u.savedEvents = u.savedEvents || [];
    const i = u.savedEvents.indexOf(id);
    let saved;
    if (i >= 0) { u.savedEvents.splice(i, 1); saved = false; }
    else { u.savedEvents.push(id); saved = true; }
    u.updatedAt = nowISO();
    persist();
    setSession(u);
    return saved;
  },

  async listAttendees(id) {
    await delay();
    const att = store.attendees[id] || {};
    return Object.keys(att)
      .map((auid) => store.users[auid])
      .filter(Boolean)
      .map(userPublic);
  },

  async addComment(id, text) {
    await delay();
    const u = requireUser();
    if (!store.events[id]) throw new Error('Event not found.');
    const body = String(text || '').trim();
    if (!body) throw new Error('Say something first.');
    const c = {
      commentId: uid('c'),
      authorId: u.uid,
      authorName: u.displayName,
      text: body.slice(0, 500),
      createdAt: nowISO(),
    };
    (store.comments[id] || (store.comments[id] = [])).push(c);
    persist();
    return clone(c);
  },

  async listComments(id) {
    await delay();
    return clone(store.comments[id] || []).sort(
      (a, b) => new Date(a.createdAt) - new Date(b.createdAt)
    );
  },

  async report({ targetType, targetId, reason, details }) {
    await delay();
    const u = requireUser();
    if (!['event', 'user', 'comment'].includes(targetType)) {
      throw new Error('Invalid report target.');
    }
    store.reports.push({
      reportId: uid('r'),
      targetType,
      targetId: String(targetId),
      reporterId: u.uid,
      reason: String(reason || '').slice(0, 200),
      details: String(details || '').slice(0, 1000),
      status: 'open',
      createdAt: nowISO(),
    });
    persist();
  },

  // ── friends ──────────────────────────────────────────────────────────────────────────────

  async searchUsers(query) {
    await delay();
    const q = String(query || '').trim().toLowerCase();
    if (!q) return [];
    return Object.values(store.users)
      .filter((u) => u.uid !== currentUid)
      .filter((u) =>
        u.username.includes(q) || (u.displayName || '').toLowerCase().includes(q)
      )
      .slice(0, 20)
      .map(userPublic);
  },

  async addFriend(username) {
    await delay();
    const me = requireUser();
    const handle = String(username || '').trim().toLowerCase();
    const target = Object.values(store.users).find((u) => u.username === handle);
    if (!target) throw new Error('No one with that username.');
    if (target.uid === me.uid) throw new Error("You can't add yourself.");

    store.friends[me.uid] = store.friends[me.uid] || {};
    store.friends[target.uid] = store.friends[target.uid] || {};

    const existing = store.friends[me.uid][target.uid];
    if (existing && existing.status === 'accepted') throw new Error("You're already friends.");

    // If they already sent ME a request, accept it instead of duplicating.
    const incoming = store.friends[me.uid][target.uid];
    if (incoming && incoming.status === 'pending' && incoming.direction === 'in') {
      incoming.status = 'accepted';
      store.friends[target.uid][me.uid] = { status: 'accepted', since: nowISO(), direction: 'out' };
      store.friends[me.uid][target.uid].since = nowISO();
      persist();
      return;
    }

    // Otherwise create an outgoing pending request.
    store.friends[me.uid][target.uid] = { status: 'pending', since: nowISO(), direction: 'out' };
    store.friends[target.uid][me.uid] = { status: 'pending', since: nowISO(), direction: 'in' };
    persist();
  },

  async listFriends() {
    await delay();
    if (!currentUid) return [];
    const rel = store.friends[currentUid] || {};
    return Object.entries(rel)
      .filter(([, r]) => r.status === 'accepted')
      .map(([fUid]) => store.users[fUid])
      .filter(Boolean)
      .map(userPublic);
  },

  async listFriendRequests() {
    await delay();
    if (!currentUid) return [];
    const rel = store.friends[currentUid] || {};
    // incoming pending requests (someone wants to add ME)
    return Object.entries(rel)
      .filter(([, r]) => r.status === 'pending' && r.direction === 'in')
      .map(([fUid]) => store.users[fUid])
      .filter(Boolean)
      .map(userPublic);
  },

  async respondFriend(targetUid, accept) {
    await delay();
    const me = requireUser();
    const rel = store.friends[me.uid] || {};
    const req = rel[targetUid];
    if (!req || req.status !== 'pending' || req.direction !== 'in') {
      throw new Error('No pending request from that user.');
    }
    if (accept) {
      req.status = 'accepted';
      req.since = nowISO();
      store.friends[targetUid] = store.friends[targetUid] || {};
      store.friends[targetUid][me.uid] = { status: 'accepted', since: nowISO(), direction: 'out' };
    } else {
      delete rel[targetUid];
      if (store.friends[targetUid]) delete store.friends[targetUid][me.uid];
    }
    persist();
  },

  // ── admin / host ───────────────────────────────────────────────────────────────────────────

  async createEvent(data) {
    await delay();
    const u = requireUser();
    if (u.role !== 'admin' && u.role !== 'host') {
      throw new Error('Only hosts and admins can create events.');
    }
    const id = uid('ev');
    const upvotes = 0, downvotes = 0;
    const e = {
      title: String(data.title || 'Untitled event').trim(),
      description: String(data.description || '').trim(),
      eventType: data.eventType || 'kickback',
      tags: Array.isArray(data.tags) ? [...data.tags] : [],
      hostId: u.uid,
      hostName: data.hostName || u.displayName,
      coverImageUrl: data.coverImageUrl ?? null,
      images: Array.isArray(data.images) ? [...data.images] : [],
      startAt: data.startAt || nowISO(),
      endAt: data.endAt ?? null,
      venueName: data.venueName ?? null,
      neighborhood: data.neighborhood ?? null,
      approxArea: data.approxArea || data.neighborhood || 'Chicago',
      exactAddress: data.exactAddress ?? null,
      priceCents: Number.isFinite(data.priceCents) ? data.priceCents : 0,
      capacity: data.capacity ?? null,
      ageMin: Number.isFinite(data.ageMin) ? data.ageMin : 14,
      ageMax: Number.isFinite(data.ageMax) ? data.ageMax : 18,
      recommendedFor: Array.isArray(data.recommendedFor) ? [...data.recommendedFor] : [],
      committedCount: 0,
      interestedCount: 0,
      upvotes,
      downvotes,
      voteScore: upvotes - downvotes,
      // Hosts default to draft (canon §8: admins publish). Admins may publish directly.
      status: data.status || (u.role === 'admin' ? 'draft' : 'draft'),
      isFeatured: !!data.isFeatured,
      createdBy: u.uid,
      id,
      createdAt: nowISO(),
      updatedAt: nowISO(),
    };
    store.events[id] = e;
    store.attendees[id] = {};
    store.votes[id] = {};
    store.comments[id] = [];
    persist();
    return decorateEvent(e, u.uid);
  },

  async updateEvent(id, patch) {
    await delay();
    const u = requireUser();
    const e = store.events[id];
    if (!e) throw new Error('Event not found.');
    if (u.role !== 'admin' && !(u.role === 'host' && e.createdBy === u.uid)) {
      throw new Error('You can only edit your own events.');
    }
    const editable = [
      'title', 'description', 'eventType', 'tags', 'hostName', 'coverImageUrl', 'images',
      'startAt', 'endAt', 'venueName', 'neighborhood', 'approxArea', 'exactAddress',
      'priceCents', 'capacity', 'ageMin', 'ageMax', 'recommendedFor', 'isFeatured',
    ];
    for (const k of editable) if (k in patch) e[k] = patch[k];
    // status only via setEventStatus, but allow admin to set here too if present
    if ('status' in patch && u.role === 'admin') e.status = patch.status;
    e.updatedAt = nowISO();
    persist();
    return decorateEvent(e, u.uid);
  },

  async setEventStatus(id, status) {
    await delay();
    const u = requireUser();
    const e = store.events[id];
    if (!e) throw new Error('Event not found.');
    if (u.role !== 'admin' && !(u.role === 'host' && e.createdBy === u.uid)) {
      throw new Error('Not allowed.');
    }
    if (!['draft', 'published', 'cancelled'].includes(status)) {
      throw new Error('Invalid status.');
    }
    // Only admins may publish; hosts can draft/cancel their own.
    if (status === 'published' && u.role !== 'admin') {
      throw new Error('Only an admin can publish.');
    }
    e.status = status;
    e.updatedAt = nowISO();
    persist();
  },

  async listReports() {
    await delay();
    const u = requireUser();
    if (u.role !== 'admin') throw new Error('Admins only.');
    return clone(store.reports).sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  },
};
