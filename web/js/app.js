// app.js — the SPA controller. Owns the hash router, page rendering, and ALL behavior.
// It imports the backend contract (Auth/API/USING_FIREBASE) from backend.js and render
// helpers from ui.js. App code talks to the backend ONLY through backend.js, never to
// data.js/firebase.js directly (canon §5).
//
// Architecture:
//   - A tiny hash router maps #/route -> a page render function.
//   - Each page fetches what it needs from API, then asks ui.js to build HTML.
//   - Interactivity uses ONE delegated click handler on #app plus a couple of form/input
//     handlers, routing on data-action / data-id. Mutations (rsvp/vote/save) are
//     optimistic: we patch the DOM immediately, then call the backend and roll back on
//     error.

import { Auth, API, USING_FIREBASE, ready } from './backend.js';
import {
  renderFeed,
  renderFilterBar,
  renderEventDetail,
  renderProfile,
  renderFriends,
  renderAuth,
  renderSafety,
  renderAppBar,
  renderTabBar,
  renderSkeletonFeed,
  emptyState,
  showToast,
  openSheet,
  esc,
} from './ui.js';
import { icon } from './icons.js';

// ----------------------------------------------------------------- app state

const app = document.getElementById('app');

// Lightweight in-memory state. Kept simple on purpose.
const state = {
  user: null,
  tags: [], // all tag objects
  tagMap: {}, // id -> tag
  neighborhoods: [], // derived from events
  feed: {
    search: '',
    type: null,
    when: null,
    neighborhood: null,
    sort: 'hype',
  },
  // signup interest selection
  pickedInterests: new Set(),
  authMode: 'login',
};

// ----------------------------------------------------------------- boot

init();

async function init() {
  // Resolve which backend is live (mock vs Firebase) BEFORE any data/auth reads, so that
  // configuring real Firebase keys actually takes effect on first paint. Instant in demo mode.
  await ready();

  // Load tags up front (used by filters + auth interest picker). Fail soft.
  try {
    state.tags = await API.listTags();
    state.tagMap = Object.fromEntries(state.tags.map((t) => [t.id, t]));
  } catch (e) {
    state.tags = [];
  }

  // Re-render chrome (and current page) whenever auth changes.
  Auth.onChange((user) => {
    state.user = user;
    renderChrome();
    route(); // a login/logout can change what a page shows
  });

  window.addEventListener('hashchange', route);

  // First paint.
  state.user = Auth.currentUser();
  renderChrome();
  route();
}

// ----------------------------------------------------------------- chrome

let chromeMounted = false;
function renderChrome() {
  // App bar lives above #app; tab bar lives in <body>. We (re)mount them on demand.
  let bar = document.getElementById('wyd-appbar-host');
  if (!bar) {
    bar = document.createElement('div');
    bar.id = 'wyd-appbar-host';
    app.parentNode.insertBefore(bar, app);
  }
  bar.innerHTML = renderAppBar(state.user);

  let tabs = document.getElementById('wyd-tabbar-host');
  if (!tabs) {
    tabs = document.createElement('div');
    tabs.id = 'wyd-tabbar-host';
    document.body.appendChild(tabs);
  }
  tabs.innerHTML = renderTabBar(currentTabKey());

  if (!chromeMounted) {
    // Delegated clicks for chrome (app bar + tab bar) route via the same handler.
    bar.addEventListener('click', onDelegatedClick);
    tabs.addEventListener('click', onDelegatedClick);
    chromeMounted = true;
  } else {
    // innerHTML was replaced, so re-bind (listeners on the host element survive though,
    // since we keep the same host nodes — no rebind needed). Intentionally a no-op.
  }
}

function currentTabKey() {
  const h = location.hash || '#/';
  if (h.startsWith('#/friends')) return 'friends';
  if (h.startsWith('#/profile')) return 'profile';
  if (h.startsWith('#/search')) return 'search';
  if (h === '#/' || h.startsWith('#/event') || h === '') return 'feed';
  return 'feed';
}

// ----------------------------------------------------------------- router

function route() {
  const hash = location.hash || '#/';
  const parts = hash.replace(/^#\//, '').split('/'); // ["event","abc"] etc.
  const head = parts[0] || '';

  window.scrollTo({ top: 0, behavior: 'auto' });

  if (head === '' ) return pageFeed();
  if (head === 'event') return pageEventDetail(parts[1]);
  if (head === 'profile') return pageProfile();
  if (head === 'friends') return pageFriends();
  if (head === 'auth') return pageAuth();
  if (head === 'safety') return pageSafety();
  if (head === 'search') return pageFeed({ focusSearch: true });

  // Unknown route -> feed.
  return pageFeed();
}

function go(path) {
  if (location.hash === path) route();
  else location.hash = path;
}

// Re-render the current page (after a mutation that changes lists).
function refresh() {
  route();
}

// ----------------------------------------------------------------- pages

function demoBanner() {
  if (USING_FIREBASE) return '';
  return `
    <div class="demo-banner">
      ${icon('sparkles', { size: 16 })}
      <span><b>Demo mode.</b> Sample Chicago events, saved in your browser. A built-in
      admin login lives on the <a href="admin.html">admin page</a>.</span>
    </div>`;
}

async function pageFeed(opts = {}) {
  // Skeleton first for snappiness.
  app.innerHTML = `<div class="page">
    ${demoBanner()}
    <div id="feed-filters"></div>
    <div id="feed-list">${renderSkeletonFeed(4)}</div>
  </div>`;

  // Build filter bar once we know neighborhoods (derived after first event load).
  const filters = document.getElementById('feed-filters');
  filters.innerHTML = renderFilterBar(state.tags, {
    ...state.feed,
    neighborhoods: state.neighborhoods,
  });

  if (opts.focusSearch) {
    const input = filters.querySelector('input[type="search"]');
    if (input) setTimeout(() => input.focus(), 30);
  }

  await loadFeedList();
}

async function loadFeedList() {
  const listEl = document.getElementById('feed-list');
  if (!listEl) return;
  try {
    const events = await API.listEvents({
      type: state.feed.type || undefined,
      neighborhood: state.feed.neighborhood || undefined,
      when: state.feed.when || undefined,
      sort: state.feed.sort,
      search: state.feed.search || undefined,
      friendsOnly: state.feed.sort === 'friends' || undefined,
      forYou: state.feed.sort === 'foryou' || undefined,
    });

    // Hydrate type-tag + derive neighborhoods for chips.
    const hoods = new Set(state.neighborhoods);
    events.forEach((e) => {
      e._typeTag = state.tagMap[e.eventType];
      if (e.neighborhood) hoods.add(e.neighborhood);
    });
    if (hoods.size !== state.neighborhoods.length) {
      state.neighborhoods = [...hoods].sort();
      const filters = document.getElementById('feed-filters');
      if (filters)
        filters.innerHTML = renderFilterBar(state.tags, {
          ...state.feed,
          neighborhoods: state.neighborhoods,
        });
    }

    // Build per-card context (my vote / saved state) so cards reflect viewer state.
    const ctxMap = await buildEventCtxMap(events);
    listEl.innerHTML = renderFeed(events, ctxMap);
  } catch (e) {
    listEl.innerHTML = emptyState({
      title: 'Couldn’t load events',
      body: 'Something went wrong. Pull to refresh or try again.',
    });
  }
}

// Build { id: {myVote, saved, friendsGoing} } for a list of events.
async function buildEventCtxMap(events) {
  const ctxMap = {};
  const saved = new Set((state.user && state.user.savedEvents) || []);
  // Votes need the backend; do them in parallel but tolerate failures.
  await Promise.all(
    events.map(async (e) => {
      let myVote = 0;
      if (state.user) {
        try {
          myVote = await API.getMyVote(e.id);
        } catch {
          myVote = 0;
        }
      }
      ctxMap[e.id] = { myVote, saved: saved.has(e.id) };
    })
  );
  return ctxMap;
}

async function pageEventDetail(id) {
  app.innerHTML = `<div class="page"><div id="feed-list">${renderSkeletonFeed(1)}</div></div>`;
  try {
    const event = await API.getEvent(id);
    if (!event) {
      app.innerHTML = `<div class="page">${emptyState({
        title: 'Event not found',
        body: 'It might’ve been cancelled or removed.',
        cta: { label: 'Back to feed', action: 'go-feed' },
      })}</div>`;
      return;
    }
    event._typeTag = state.tagMap[event.eventType];

    // Gather viewer context.
    const [myRsvp, myVote, comments, attendees] = await Promise.all([
      state.user ? safe(API.getMyRsvp(id), null) : null,
      state.user ? safe(API.getMyVote(id), 0) : 0,
      safe(API.listComments(id), []),
      safe(API.listAttendees(id), []),
    ]);

    // Friends going = intersection of attendees with my friends (best-effort).
    let friendsGoing = [];
    if (state.user) {
      const friends = await safe(API.listFriends(), []);
      const friendIds = new Set(friends.map((f) => f.uid || f.id));
      friendsGoing = attendees.filter((a) => friendIds.has(a.uid || a.id));
    }

    const saved = new Set((state.user && state.user.savedEvents) || []).has(id);

    app.innerHTML = `<div class="page">${renderEventDetail(event, {
      tags: state.tagMap,
      myRsvp,
      myVote,
      saved,
      friendsGoing,
      comments,
      signedIn: !!state.user,
    })}</div>`;
  } catch (e) {
    app.innerHTML = `<div class="page">${emptyState({
      title: 'Couldn’t load that event',
      body: 'Try again in a sec.',
      cta: { label: 'Back to feed', action: 'go-feed' },
    })}</div>`;
  }
}

async function pageProfile() {
  if (!state.user) {
    app.innerHTML = `<div class="page">${renderProfile(null)}</div>`;
    return;
  }
  app.innerHTML = `<div class="page"><div id="feed-list">${renderSkeletonFeed(2)}</div></div>`;
  const user = state.user;
  const [friends, allEvents] = await Promise.all([
    safe(API.listFriends(), []),
    safe(API.listEvents({ sort: 'soonest' }), []),
  ]);

  // Determine which events the user is going to / has saved.
  const savedSet = new Set(user.savedEvents || []);
  const saved = allEvents.filter((e) => savedSet.has(e.id));
  saved.forEach((e) => (e._typeTag = state.tagMap[e.eventType]));

  const going = [];
  await Promise.all(
    allEvents.map(async (e) => {
      const r = await safe(API.getMyRsvp(e.id), null);
      if (r === 'going') {
        e._typeTag = state.tagMap[e.eventType];
        going.push(e);
      }
    })
  );

  app.innerHTML = `<div class="page">${renderProfile(user, {
    friendsCount: friends.length,
    going,
    saved,
    isAdmin: Auth.isAdmin(),
  })}</div>`;
}

async function pageFriends() {
  app.innerHTML = `<div class="page"><div id="feed-list">${renderSkeletonFeed(1)}</div></div>`;
  if (!state.user) {
    app.innerHTML = `<div class="page">${renderFriends({ signedIn: false })}</div>`;
    return;
  }
  const [friends, requests] = await Promise.all([
    safe(API.listFriends(), []),
    safe(API.listFriendRequests(), []),
  ]);
  app.innerHTML = `<div class="page">${renderFriends({
    signedIn: true,
    me: state.user,
    friends,
    requests,
  })}</div>`;
}

function pageAuth() {
  state.pickedInterests = new Set();
  app.innerHTML = `<div class="page">${renderAuth(state.authMode, state.tags)}</div>`;
}

function pageSafety() {
  app.innerHTML = `<div class="page">${renderSafety()}</div>`;
}

// ----------------------------------------------------------------- helpers

/** Resolve a promise to a fallback on rejection (keeps pages resilient). */
async function safe(promise, fallback) {
  try {
    return await promise;
  } catch {
    return fallback;
  }
}

/** Require a verified, signed-in user for an action; otherwise nudge + return false. */
function requireVerified(actionLabel = 'do that') {
  if (!state.user) {
    showToast('Log in first 👀', 'error');
    go('#/auth');
    return false;
  }
  if (!state.user.emailVerified) {
    showToast(`Verify your email to ${actionLabel}.`, 'error');
    return false;
  }
  return true;
}

// ----------------------------------------------------------------- delegated clicks

app.addEventListener('click', onDelegatedClick);

function onDelegatedClick(e) {
  const target = e.target.closest('[data-action]');
  if (!target) return;
  const action = target.dataset.action;
  const id = target.dataset.id;

  // Some controls (vote pill) sit inside a clickable card — stop the card from opening.
  if (target.closest('[data-stop]')) e.stopPropagation();

  switch (action) {
    // ---- navigation
    case 'go-feed':
      return go('#/');
    case 'go-search':
      return go('#/search');
    case 'go-friends':
      return go('#/friends');
    case 'go-profile':
      return go('#/profile');
    case 'go-auth':
      return go('#/auth');
    case 'go-admin':
      return (location.href = 'admin.html');
    case 'go-safety':
      return go('#/safety');
    case 'back':
      return history.length > 1 ? history.back() : go('#/');

    // ---- open event (whole card)
    case 'open':
      return go(`#/event/${id}`);

    // ---- rsvp
    case 'rsvp-going':
      return onRsvp(id, 'going', target);
    case 'rsvp-interested':
      return onRsvp(id, 'interested', target);

    // ---- vote
    case 'vote-up':
      e.stopPropagation();
      return onVote(id, 1, target);
    case 'vote-down':
      e.stopPropagation();
      return onVote(id, -1, target);

    // ---- save / bookmark
    case 'save':
      e.stopPropagation();
      return onSave(id, target);

    // ---- share
    case 'share-snap':
      return onShare(id, 'snapchat');
    case 'share-insta':
      return onShare(id, 'instagram');
    case 'share-copy':
      return onShare(id, 'copy');

    // ---- report
    case 'report':
      return openReportSheet('event', id);

    // ---- auth controls
    case 'auth-mode':
      state.authMode = id;
      return pageAuth();
    case 'toggle-interest':
      return toggleInterest(id, target);
    case 'forgot-pass':
      return onForgotPassword();
    case 'resend-verify':
      return onResendVerify();

    // ---- profile
    case 'signout':
      return onSignOut();
    case 'edit-profile':
      return openEditProfile();

    // ---- friends
    case 'friend-accept':
      return onRespondFriend(id, true);
    case 'friend-decline':
      return onRespondFriend(id, false);

    // ---- sort + filters (chips)
    case 'sort':
      state.feed.sort = id;
      return pageFeed();
    case 'filter-type':
      state.feed.type = state.feed.type === id ? null : id;
      return reFilter();
    case 'filter-when':
      state.feed.when = state.feed.when === id ? null : id;
      return reFilter();
    case 'filter-hood':
      state.feed.neighborhood = state.feed.neighborhood === id ? null : id;
      return reFilter();
    case 'filter-clear':
      state.feed.type = state.feed.when = state.feed.neighborhood = null;
      return reFilter();

    case 'noop':
      return; // read-only chips
    default:
      return;
  }
}

// Re-render only the filter bar (active states) + reload the list, no full nav.
function reFilter() {
  const filters = document.getElementById('feed-filters');
  if (filters)
    filters.innerHTML = renderFilterBar(state.tags, {
      ...state.feed,
      neighborhoods: state.neighborhoods,
    });
  loadFeedList();
}

// ----------------------------------------------------------------- input/forms

// Search (debounced) — listen on #app for the search input.
let searchTimer = null;
app.addEventListener('input', (e) => {
  const t = e.target;
  if (t.dataset && t.dataset.action === 'search') {
    clearTimeout(searchTimer);
    const val = t.value;
    searchTimer = setTimeout(() => {
      state.feed.search = val.trim();
      loadFeedList();
    }, 220);
  }
});

// Form submits (auth, comment, add-friend) — one delegated submit handler.
app.addEventListener('submit', (e) => {
  const form = e.target.closest('form[data-action]');
  if (!form) return;
  e.preventDefault();
  const action = form.dataset.action;
  if (action === 'do-login') return onLogin(form);
  if (action === 'do-signup') return onSignup(form);
  if (action === 'comment-form') return onComment(form.dataset.id, form);
  if (action === 'add-friend') return onAddFriend(form);
});

// ----------------------------------------------------------------- actions: rsvp/vote/save

async function onRsvp(id, status, btn) {
  if (!requireVerified('RSVP')) return;
  // Toggle off if already that status.
  const currentlyGoing = btn.classList.contains('is-going');
  const currentlyInterested = btn.classList.contains('is-interested');
  const newStatus =
    (status === 'going' && currentlyGoing) ||
    (status === 'interested' && currentlyInterested)
      ? null
      : status;

  try {
    await API.rsvp(id, newStatus);
    if (newStatus === 'going') showToast("You're in. See you there 🎉", 'success');
    else if (newStatus === 'interested') showToast('Marked interested ✨', 'success');
    else showToast('RSVP removed');
    // Re-render detail so the address gate + counts update.
    pageEventDetail(id);
  } catch (err) {
    showToast(friendlyError(err, 'Couldn’t RSVP'), 'error');
  }
}

async function onVote(id, dir, btn) {
  if (!requireVerified('vote')) return;
  const pill = btn.closest('.vote-pill');
  const up = pill.querySelector('.up');
  const down = pill.querySelector('.down');
  const scoreEl = pill.querySelector('.score');

  const wasUp = up.classList.contains('is-on');
  const wasDown = down.classList.contains('is-on');
  const prevScore = parseInt(scoreEl.textContent, 10) || 0;

  // Determine the new vote (toggle off if pressing the active one).
  let newDir = dir;
  if ((dir === 1 && wasUp) || (dir === -1 && wasDown)) newDir = 0;

  // Optimistic DOM update.
  const prevDelta = (wasUp ? 1 : 0) + (wasDown ? -1 : 0);
  const nextDelta = newDir; // 1 | -1 | 0
  up.classList.toggle('is-on', newDir === 1);
  down.classList.toggle('is-on', newDir === -1);
  // Update every score element for this event (card + detail can both be on screen).
  const optimistic = prevScore - prevDelta + nextDelta;
  setScore(id, optimistic);

  try {
    await API.vote(id, newDir);
  } catch (err) {
    // Roll back.
    up.classList.toggle('is-on', wasUp);
    down.classList.toggle('is-on', wasDown);
    setScore(id, prevScore);
    showToast(friendlyError(err, 'Couldn’t vote'), 'error');
  }
}

function setScore(id, value) {
  document
    .querySelectorAll(`.score[data-score="${cssEscape(id)}"]`)
    .forEach((el) => (el.textContent = value));
}

async function onSave(id, btn) {
  if (!state.user) {
    showToast('Log in to save events', 'error');
    return go('#/auth');
  }
  const wasOn = btn.classList.contains('is-on');
  btn.classList.toggle('is-on', !wasOn); // optimistic
  try {
    const saved = await API.toggleSave(id);
    btn.classList.toggle('is-on', saved);
    // Keep local user.savedEvents roughly in sync for ctx maps.
    if (state.user) {
      const set = new Set(state.user.savedEvents || []);
      saved ? set.add(id) : set.delete(id);
      state.user.savedEvents = [...set];
    }
    showToast(saved ? 'Saved 🔖' : 'Removed from saved');
  } catch (err) {
    btn.classList.toggle('is-on', wasOn); // roll back
    showToast(friendlyError(err, 'Couldn’t save'), 'error');
  }
}

// ----------------------------------------------------------------- actions: share

async function onShare(id, where) {
  const url = `${location.origin}${location.pathname}#/event/${id}`;
  const text = 'WYD tonight? Check this out 👀';
  if (where === 'copy') {
    try {
      await navigator.clipboard.writeText(url);
      showToast('Link copied 🔗', 'success');
    } catch {
      showToast('Copy this link: ' + url);
    }
    return;
  }
  // Snapchat / Instagram don't take arbitrary web links cleanly; fall back to the Web
  // Share sheet when available, else copy + nudge.
  if (navigator.share) {
    try {
      await navigator.share({ title: 'WYD Chicago', text, url });
      return;
    } catch {
      /* user cancelled — ignore */
    }
  }
  try {
    await navigator.clipboard.writeText(url);
  } catch {
    /* ignore */
  }
  const label = where === 'snapchat' ? 'Snapchat' : 'Instagram';
  showToast(`Link copied — paste it in ${label} 💜`, 'success');
}

// ----------------------------------------------------------------- actions: report

function openReportSheet(targetType, targetId) {
  if (!state.user) {
    showToast('Log in to report', 'error');
    return go('#/auth');
  }
  const reasons = [
    'Harassment or bullying',
    'Fake or scam event',
    'Illegal or dangerous',
    'Spam',
    'Something else',
  ];
  const body = `
    <form data-report-form>
      <div class="field">
        <label>Why are you reporting this?</label>
        <select class="select" name="reason">
          ${reasons.map((r) => `<option>${esc(r)}</option>`).join('')}
        </select>
      </div>
      <div class="field">
        <label>Details (optional)</label>
        <textarea class="textarea" name="details" placeholder="What's going on?"></textarea>
      </div>
      <button class="btn btn-primary btn-block" type="submit">Send report</button>
      <p class="muted tiny center mt-1">Reports go to WYD admins. Thanks for keeping it safe.</p>
    </form>`;
  const close = openSheet({ title: 'Report', body });
  const form = document.querySelector('[data-report-form]');
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const reason = form.reason.value;
    const details = form.details.value.trim();
    try {
      await API.report({ targetType, targetId, reason, details });
      close();
      showToast('Reported. We’ll take a look 🙏', 'success');
    } catch (err) {
      showToast(friendlyError(err, 'Couldn’t send report'), 'error');
    }
  });
}

// ----------------------------------------------------------------- actions: auth

function setAuthError(msg) {
  const box = app.querySelector('[data-auth-error]');
  if (!box) return;
  if (!msg) return box.classList.add('hide');
  box.innerHTML = `${icon('x', { size: 16 })} ${esc(msg)}`;
  box.classList.remove('hide');
}
function setAuthSuccess(msg) {
  const box = app.querySelector('[data-auth-success]');
  if (!box) return;
  if (!msg) return box.classList.add('hide');
  box.innerHTML = `${icon('check', { size: 16 })} ${esc(msg)}`;
  box.classList.remove('hide');
}
function setFieldError(form, field, msg) {
  const el = form.querySelector(`[data-err="${field}"]`);
  if (!el) return;
  if (!msg) {
    el.classList.add('hide');
    el.textContent = '';
  } else {
    el.textContent = msg;
    el.classList.remove('hide');
  }
}

async function onLogin(form) {
  setAuthError('');
  setAuthSuccess('');
  const email = form.email.value.trim();
  const password = form.password.value;
  if (!validEmail(email)) return setFieldError(form, 'email', 'Enter a valid email');
  setFieldError(form, 'email', '');
  if (!password) return setFieldError(form, 'password', 'Enter your password');
  setFieldError(form, 'password', '');

  const btn = form.querySelector('button[type="submit"]');
  btn.disabled = true;
  btn.textContent = 'Logging in…';
  try {
    const user = await Auth.signIn({ email, password });
    if (user && !user.emailVerified) {
      setAuthSuccess("Logged in! Verify your email to RSVP and vote.");
    }
    showToast('Welcome back 👋', 'success');
    go('#/');
  } catch (err) {
    setAuthError(friendlyError(err, 'Couldn’t log in. Check your email + password.'));
    btn.disabled = false;
    btn.textContent = 'Log in';
  }
}

async function onSignup(form) {
  setAuthError('');
  setAuthSuccess('');
  const displayName = form.displayName.value.trim();
  const username = form.username.value.trim().toLowerCase();
  const email = form.email.value.trim();
  const password = form.password.value;
  const birthYear = parseInt(form.birthYear.value, 10);

  let ok = true;
  if (!displayName) {
    showToast('Add your name', 'error');
    ok = false;
  }
  if (!/^[a-z0-9_]{3,20}$/.test(username)) {
    setFieldError(form, 'username', '3–20 chars: letters, numbers, _');
    ok = false;
  } else setFieldError(form, 'username', '');
  if (!validEmail(email)) {
    setFieldError(form, 'email', 'Enter a valid email');
    ok = false;
  } else setFieldError(form, 'email', '');
  if (!password || password.length < 6) {
    setFieldError(form, 'password', 'At least 6 characters');
    ok = false;
  } else setFieldError(form, 'password', '');

  // Age gate (canon §8): 14–18.
  const nowYear = new Date().getFullYear();
  const age = nowYear - birthYear;
  if (!birthYear || isNaN(birthYear) || age < 13 || age > 19) {
    setAuthError('WYD Chicago is for high-schoolers (about 14–18). Double-check your birth year.');
    ok = false;
  }
  if (!ok) return;

  const btn = form.querySelector('button[type="submit"]');
  btn.disabled = true;
  btn.textContent = 'Creating…';
  try {
    await Auth.signUp({
      email,
      password,
      username,
      displayName,
      birthYear,
      interests: [...state.pickedInterests],
    });
    // Most flows send a verification email on signup.
    try {
      await Auth.sendVerification();
    } catch {
      /* mock may no-op */
    }
    setAuthSuccess(
      "You're in! We sent a verification link to your email — tap it, then you can RSVP and vote."
    );
    showToast('Account made 🎉', 'success');
    go('#/');
  } catch (err) {
    setAuthError(friendlyError(err, 'Couldn’t create your account.'));
    btn.disabled = false;
    btn.textContent = 'Create account';
  }
}

function toggleInterest(id, btn) {
  if (state.pickedInterests.has(id)) state.pickedInterests.delete(id);
  else state.pickedInterests.add(id);
  btn.classList.toggle('is-active', state.pickedInterests.has(id));
}

async function onForgotPassword() {
  const body = `
    <form data-reset-form>
      <p class="muted small">Enter your email and we'll send a reset link.</p>
      <div class="field">
        <label>Email</label>
        <input class="input" name="email" type="email" placeholder="you@email.com" required/>
      </div>
      <button class="btn btn-primary btn-block" type="submit">Send reset link</button>
    </form>`;
  const close = openSheet({ title: 'Reset password', body });
  const form = document.querySelector('[data-reset-form]');
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const email = form.email.value.trim();
    if (!validEmail(email)) return showToast('Enter a valid email', 'error');
    try {
      await Auth.resetPassword(email);
      close();
      showToast('Reset link sent — check your email 📬', 'success');
    } catch (err) {
      showToast(friendlyError(err, 'Couldn’t send reset link'), 'error');
    }
  });
}

async function onResendVerify() {
  try {
    await Auth.sendVerification();
    showToast('Verification email sent 📬', 'success');
  } catch (err) {
    showToast(friendlyError(err, 'Couldn’t send email'), 'error');
  }
}

async function onSignOut() {
  try {
    await Auth.signOut();
    showToast('Signed out 👋');
    go('#/');
  } catch (err) {
    showToast(friendlyError(err, 'Couldn’t sign out'), 'error');
  }
}

// ----------------------------------------------------------------- actions: profile edit

function openEditProfile() {
  const u = state.user || {};
  const body = `
    <form data-edit-form>
      <div class="field">
        <label>Name</label>
        <input class="input" name="displayName" value="${esc(u.displayName || '')}"/>
      </div>
      <div class="field">
        <label>Bio</label>
        <textarea class="textarea" name="bio" maxlength="160" placeholder="Say something about you">${esc(
          u.bio || ''
        )}</textarea>
      </div>
      <div class="field">
        <label>Neighborhood</label>
        <input class="input" name="neighborhood" value="${esc(
          u.neighborhood || ''
        )}" placeholder="Lincoln Park"/>
      </div>
      <div class="row">
        <div class="field" style="flex:1">
          <label>Snapchat</label>
          <input class="input" name="snapchatUsername" value="${esc(
            u.snapchatUsername || ''
          )}" placeholder="@snap"/>
        </div>
        <div class="field" style="flex:1">
          <label>Instagram</label>
          <input class="input" name="instagramUsername" value="${esc(
            u.instagramUsername || ''
          )}" placeholder="@insta"/>
        </div>
      </div>
      <button class="btn btn-primary btn-block" type="submit">Save</button>
    </form>`;
  const close = openSheet({ title: 'Edit profile', body });
  const form = document.querySelector('[data-edit-form]');
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const patch = {
      displayName: form.displayName.value.trim(),
      bio: form.bio.value.trim(),
      neighborhood: form.neighborhood.value.trim() || null,
      snapchatUsername: form.snapchatUsername.value.trim() || null,
      instagramUsername: form.instagramUsername.value.trim() || null,
    };
    try {
      const updated = await Auth.updateProfile(patch);
      state.user = updated || { ...state.user, ...patch };
      close();
      showToast('Profile saved ✨', 'success');
      pageProfile();
    } catch (err) {
      showToast(friendlyError(err, 'Couldn’t save'), 'error');
    }
  });
}

// ----------------------------------------------------------------- actions: comments

async function onComment(id, form) {
  if (!requireVerified('comment')) return;
  const input = form.querySelector('input[name="text"]');
  const text = input.value.trim();
  if (!text) return;
  input.value = '';
  try {
    await API.addComment(id, text);
    pageEventDetail(id); // re-render with the new comment
  } catch (err) {
    input.value = text; // restore on failure
    showToast(friendlyError(err, 'Couldn’t post comment'), 'error');
  }
}

// ----------------------------------------------------------------- actions: friends

async function onAddFriend(form) {
  if (!state.user) {
    showToast('Log in to add friends', 'error');
    return go('#/auth');
  }
  const input = form.querySelector('input[name="username"]');
  const username = input.value.trim().toLowerCase().replace(/^@/, '');
  if (!username) return;
  try {
    await API.addFriend(username);
    input.value = '';
    showToast(`Request sent to @${username} 🤝`, 'success');
    pageFriends();
  } catch (err) {
    showToast(friendlyError(err, `Couldn’t add @${username}`), 'error');
  }
}

async function onRespondFriend(uid, accept) {
  try {
    await API.respondFriend(uid, accept);
    showToast(accept ? 'Friend added 🎉' : 'Request declined');
    pageFriends();
  } catch (err) {
    showToast(friendlyError(err, 'Couldn’t respond'), 'error');
  }
}

// ----------------------------------------------------------------- small utils

function validEmail(s) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s);
}

function friendlyError(err, fallback) {
  const msg = (err && (err.message || err.code)) || '';
  // Map a few common Firebase auth codes to teen-friendly copy.
  if (/email-already-in-use/.test(msg)) return 'That email already has an account.';
  if (/invalid-credential|wrong-password|user-not-found/.test(msg))
    return "Email or password doesn't match.";
  if (/weak-password/.test(msg)) return 'Pick a stronger password (6+ chars).';
  if (/username.*taken|taken/.test(msg)) return 'That username is taken — try another.';
  if (/too-many-requests/.test(msg)) return 'Too many tries. Wait a minute and retry.';
  if (/network/.test(msg)) return 'Network hiccup. Check your connection.';
  return msg && msg.length < 90 ? msg : fallback;
}

// Minimal CSS.escape fallback for older browsers (used in attribute selectors).
function cssEscape(value) {
  if (window.CSS && CSS.escape) return CSS.escape(value);
  return String(value).replace(/[^a-zA-Z0-9_-]/g, (c) => '\\' + c);
}
