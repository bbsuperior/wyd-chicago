// admin.js — WYD Chicago admin dashboard ("master login"), canon §3.7 / §5.
//
// Gated by the `admin` role. Flow:
//   1. If not signed in OR not Auth.isAdmin() -> show a login form (email/password).
//      signIn() then re-check isAdmin(); reject non-admins with a clear message.
//      Demo admin: admin@wydchicago.app / chicago.
//   2. Once authed as admin, render the dashboard:
//        (a) EVENT EDITOR — create/edit events (all canon fields).
//        (b) EVENT LIST   — every event + status + counts + Publish/Cancel/Edit.
//        (c) REPORTS queue — listReports(); mark reviewed where supported.
//        (d) Sign out.
//
// Reuses the design system (css/app.css) + ui.js helpers (esc, showToast, formatWhen,
// priceLabel, openSheet) + icons.js. Imports ONLY from backend.js for data (the contract).
//
// Optimistic UI: mutating actions update the local model and re-render immediately, then
// reconcile against the backend; on error we toast and reload from source of truth.

import { Auth, API, ready } from './backend.js';
import { icon, logoSVG } from './icons.js';
import { esc, showToast, formatWhen, priceLabel } from './ui.js';

// ── module state ───────────────────────────────────────────────────────────────────────────────

const els = {
  bar: document.getElementById('admin-bar'),
  root: document.getElementById('admin'),
};

const state = {
  user: null,        // current auth user (or null)
  ready: false,      // first auth snapshot received
  tags: [],          // all tags (eventType + interest)
  events: [],        // ALL events (admin sees every status)
  reports: [],       // moderation queue
  editing: null,     // eventId being edited, or null = "create new"
  form: blankForm(), // working copy of the editor form
  loading: false,    // dashboard data loading
};

// Default values for a fresh event (canon defaults: ages 14–18, free, draft).
function blankForm() {
  return {
    title: '',
    description: '',
    eventType: '',
    tags: [],
    hostName: '',
    startAt: '',
    endAt: '',
    venueName: '',
    approxArea: '',
    neighborhood: '',
    exactAddress: '',
    priceCents: 0,
    capacity: '',
    ageMin: 14,
    ageMax: 18,
    recommendedFor: [],
    coverImageUrl: '',
    isFeatured: false,
  };
}

// ── boot ─────────────────────────────────────────────────────────────────────────────────────

renderBar();

// Single delegated click handler for the whole admin surface.
els.root.addEventListener('click', onClick);
els.root.addEventListener('submit', onSubmit);
els.root.addEventListener('change', onChange);
els.bar.addEventListener('click', onClick);

// Wait until the backend (mock vs Firebase) is resolved before subscribing to auth, so live
// Firebase auth state is honored once keys are configured. Instant in demo mode.
ready().then(() => {
  Auth.onChange((user) => {
    state.user = user;
    state.ready = true;
    // Whenever auth changes (incl. first snapshot), decide gate vs dashboard.
    if (user && Auth.isAdmin()) {
      loadDashboard();
    } else {
      renderBar();
      renderGate();
    }
  });
});

// ── chrome ──────────────────────────────────────────────────────────────────────────────────

function renderBar() {
  const signedInAsAdmin = state.user && Auth.isAdmin();
  const right = signedInAsAdmin
    ? `<span class="muted small">${esc(state.user.displayName || state.user.username || 'Admin')}</span>
       <button class="btn btn-ghost btn-sm" data-action="signout">${icon('logout', { size: 16 })} Sign out</button>`
    : `<a class="btn btn-ghost btn-sm" href="index.html">${icon('chevron-left', { size: 16 })} Back to app</a>`;

  els.bar.innerHTML = `
    <a class="brand" href="index.html" aria-label="WYD Chicago" style="display:flex;align-items:center">
      ${logoSVG({ size: 26 })}
    </a>
    <span class="admin-badge">Admin</span>
    <span class="spacer"></span>
    ${right}`;
}

// ── login gate ─────────────────────────────────────────────────────────────────────────────

function renderGate() {
  // If signed in but NOT an admin, say so plainly (don't just show a blank login).
  const wrongRole =
    state.user && !Auth.isAdmin()
      ? `<div class="notice error">${icon('x', { size: 16 })}
           You're signed in as <b>@${esc(state.user.username || 'you')}</b>, but that account isn't
           an admin. Sign out and use a master login.</div>`
      : '';

  const signoutBtn = state.user
    ? `<button class="btn btn-ghost btn-block btn-sm mt-1" data-action="signout">Sign out</button>`
    : '';

  els.root.innerHTML = `
    <div class="admin-login">
      <div class="center" style="margin-bottom:18px">
        <div style="display:flex;justify-content:center;margin-bottom:10px">${logoSVG({ size: 40 })}</div>
        <h1>Master login</h1>
        <p class="muted">Admins only. This is where events get made.</p>
      </div>

      <div class="admin-card">
        ${wrongRole}
        <div class="notice error hide" data-login-error></div>

        <form data-action="do-login">
          <div class="field">
            <label for="ad-email">Email</label>
            <input class="input" id="ad-email" name="email" type="email"
                   placeholder="admin@wydchicago.app" autocomplete="email" required/>
          </div>
          <div class="field">
            <label for="ad-pass">Password</label>
            <input class="input" id="ad-pass" name="password" type="password"
                   placeholder="••••••••" autocomplete="current-password" required/>
          </div>
          <button class="btn btn-primary btn-block mt-1" type="submit">Log in</button>
        </form>
        ${signoutBtn}

        <p class="muted small center mt-2">
          Demo admin: <b>admin@wydchicago.app</b> / <b>chicago</b>
        </p>
      </div>
    </div>`;
}

// ── dashboard ──────────────────────────────────────────────────────────────────────────────

async function loadDashboard() {
  renderBar();
  state.loading = true;
  renderDashboard();
  try {
    const [tags, events] = await Promise.all([API.listTags(), API.listEvents()]);
    state.tags = tags;
    // listEvents() already returns ALL statuses for admins (see data.js). Sort soonest-first
    // but keep cancelled/past visible so they can be managed.
    state.events = [...events].sort(
      (a, b) => new Date(a.startAt) - new Date(b.startAt)
    );
  } catch (err) {
    showToast(err.message || 'Could not load events.', 'error');
    state.events = [];
  }
  // Reports are admin-only and may throw if something's off — load independently.
  try {
    state.reports = await API.listReports();
  } catch (err) {
    state.reports = [];
  }
  state.loading = false;
  renderDashboard();
}

function renderDashboard() {
  if (!state.user || !Auth.isAdmin()) {
    renderGate();
    return;
  }
  els.root.innerHTML = `
    ${editorSection()}
    ${eventsSection()}
    ${reportsSection()}`;
}

// ── (a) EVENT EDITOR ─────────────────────────────────────────────────────────────────────────

function editorSection() {
  const f = state.form;
  const editing = !!state.editing;
  const eventTypes = state.tags.filter((t) => t.kind === 'eventType');
  const interests = state.tags.filter((t) => t.kind === 'interest');

  const typeOptions = eventTypes
    .map(
      (t) =>
        `<option value="${esc(t.id)}"${f.eventType === t.id ? ' selected' : ''}>${esc(
          (t.emoji ? t.emoji + ' ' : '') + t.label
        )}</option>`
    )
    .join('');

  // Multi-select tag pickers reuse .chip (active = selected).
  const tagPicker = (selected, action) =>
    interests
      .map(
        (t) =>
          `<button type="button" class="chip${selected.includes(t.id) ? ' is-active' : ''}"
                   data-action="${action}" data-id="${esc(t.id)}">
             <span class="emoji">${esc(t.emoji || '')}</span>${esc(t.label)}
           </button>`
      )
      .join('');

  return `
    <div class="admin-card">
      <h2>${editing ? 'Edit event' : 'New event'}</h2>
      <div class="sub">${
        editing
          ? 'Update the details, then save. Publish from the list below.'
          : "Fill it in and drop it. New events start as a draft until you publish 'em."
      }</div>

      <form data-action="save-event">
        <div class="field">
          <label for="ev-title">Title</label>
          <input class="input" id="ev-title" name="title" value="${esc(f.title)}"
                 placeholder="Rooftop kickback in Wicker Park" maxlength="120" required/>
        </div>

        <div class="field">
          <label for="ev-desc">Description</label>
          <textarea class="textarea" id="ev-desc" name="description"
                    placeholder="What's the vibe? Who's it for? Anything to bring?" maxlength="2000">${esc(
                      f.description
                    )}</textarea>
        </div>

        <div class="grid-2">
          <div class="field">
            <label for="ev-type">Event type</label>
            <select class="select" id="ev-type" name="eventType" required>
              <option value="" disabled${f.eventType ? '' : ' selected'}>Pick a type…</option>
              ${typeOptions}
            </select>
          </div>
          <div class="field">
            <label for="ev-host">Host name</label>
            <input class="input" id="ev-host" name="hostName" value="${esc(f.hostName)}"
                   placeholder="WYD Team" maxlength="80"/>
          </div>
        </div>

        <div class="field">
          <label>Tags <span class="hint">(what it's about — used for matching)</span></label>
          <div class="pick-row">${tagPicker(f.tags, 'toggle-tag')}</div>
        </div>

        <div class="grid-2">
          <div class="field">
            <label for="ev-start">Starts</label>
            <input class="input" id="ev-start" name="startAt" type="datetime-local"
                   value="${esc(f.startAt)}" required/>
          </div>
          <div class="field">
            <label for="ev-end">Ends <span class="hint">(optional)</span></label>
            <input class="input" id="ev-end" name="endAt" type="datetime-local"
                   value="${esc(f.endAt)}"/>
          </div>
        </div>

        <div class="grid-2">
          <div class="field">
            <label for="ev-venue">Venue name <span class="hint">(optional)</span></label>
            <input class="input" id="ev-venue" name="venueName" value="${esc(f.venueName)}"
                   placeholder="The Garage"/>
          </div>
          <div class="field">
            <label for="ev-hood">Neighborhood</label>
            <input class="input" id="ev-hood" name="neighborhood" value="${esc(f.neighborhood)}"
                   placeholder="Wicker Park"/>
          </div>
        </div>

        <div class="grid-2">
          <div class="field">
            <label for="ev-area">Approx area <span class="hint">(shown before RSVP)</span></label>
            <input class="input" id="ev-area" name="approxArea" value="${esc(f.approxArea)}"
                   placeholder="Near Wicker Park"/>
          </div>
          <div class="field">
            <label for="ev-addr">Exact address <span class="hint">(hidden until "Going")</span></label>
            <input class="input" id="ev-addr" name="exactAddress" value="${esc(f.exactAddress)}"
                   placeholder="1234 N Damen Ave"/>
          </div>
        </div>

        <div class="grid-2">
          <div class="field">
            <label for="ev-price">Price <span class="hint">(dollars, 0 = free)</span></label>
            <input class="input" id="ev-price" name="priceDollars" type="number" inputmode="decimal"
                   min="0" step="1" value="${esc(centsToDollars(f.priceCents))}" placeholder="0"/>
          </div>
          <div class="field">
            <label for="ev-cap">Capacity <span class="hint">(optional)</span></label>
            <input class="input" id="ev-cap" name="capacity" type="number" inputmode="numeric"
                   min="1" step="1" value="${esc(f.capacity)}" placeholder="No limit"/>
          </div>
        </div>

        <div class="grid-2">
          <div class="field">
            <label for="ev-agemin">Age min</label>
            <input class="input" id="ev-agemin" name="ageMin" type="number" inputmode="numeric"
                   min="13" max="18" step="1" value="${esc(f.ageMin)}"/>
          </div>
          <div class="field">
            <label for="ev-agemax">Age max</label>
            <input class="input" id="ev-agemax" name="ageMax" type="number" inputmode="numeric"
                   min="13" max="25" step="1" value="${esc(f.ageMax)}"/>
          </div>
        </div>

        <div class="field">
          <label>Recommended for <span class="hint">(who it's perfect for)</span></label>
          <div class="pick-row">${tagPicker(f.recommendedFor, 'toggle-recfor')}</div>
        </div>

        <div class="field">
          <label for="ev-cover">Cover image URL <span class="hint">(optional)</span></label>
          <input class="input" id="ev-cover" name="coverImageUrl" value="${esc(f.coverImageUrl)}"
                 placeholder="https://…/photo.jpg" type="url"/>
        </div>

        <div class="field">
          <label class="row gap-sm" style="align-items:center;cursor:pointer">
            <input type="checkbox" name="isFeatured" ${f.isFeatured ? 'checked' : ''}/>
            <span>${icon('star', { size: 15 })} Feature this event</span>
          </label>
        </div>

        <div class="row mt-1" style="gap:8px">
          <button class="btn btn-primary" type="submit">
            ${icon('check', { size: 17 })} ${editing ? 'Save changes' : 'Create event'}
          </button>
          ${
            editing
              ? `<button class="btn btn-ghost" type="button" data-action="cancel-edit">Cancel</button>`
              : ''
          }
        </div>
      </form>
    </div>`;
}

// ── (b) EVENT LIST ─────────────────────────────────────────────────────────────────────────

function eventsSection() {
  let body;
  if (state.loading) {
    body = `<p class="muted small">Loading events…</p>`;
  } else if (!state.events.length) {
    body = `<p class="muted small">No events yet. Make the first one up top 👆</p>`;
  } else {
    body = state.events.map(eventRow).join('');
  }
  return `
    <div class="admin-card">
      <h2>All events <span class="count-chip">· ${state.events.length}</span></h2>
      <div class="sub">Publish, cancel, or edit anything. Teens only see <b>published</b> events.</div>
      ${body}
    </div>`;
}

function eventRow(e) {
  const tag = state.tags.find((t) => t.id === e.eventType);
  const typeLabel = tag ? (tag.emoji ? tag.emoji + ' ' : '') + tag.label : e.eventType || 'Event';
  const featured = e.isFeatured ? ` ${icon('star', { size: 11 })} Featured` : '';

  // Status-aware actions: publish a draft/cancelled one, cancel a live one, always Edit.
  const actions = [];
  if (e.status !== 'published') {
    actions.push(
      `<button class="btn btn-primary btn-sm" data-action="publish" data-id="${esc(e.id)}">
         ${icon('check', { size: 15 })} Publish</button>`
    );
  }
  if (e.status !== 'cancelled') {
    actions.push(
      `<button class="btn btn-danger btn-sm" data-action="cancel" data-id="${esc(e.id)}">
         ${icon('x', { size: 15 })} Cancel</button>`
    );
  }
  if (e.status === 'cancelled') {
    // Allow moving a cancelled event back to draft.
    actions.push(
      `<button class="btn btn-sm" data-action="to-draft" data-id="${esc(e.id)}">
         ${icon('clock', { size: 15 })} Draft</button>`
    );
  }
  actions.push(
    `<button class="btn btn-sm" data-action="edit" data-id="${esc(e.id)}">
       ${icon('settings', { size: 15 })} Edit</button>`
  );

  const thumb = e.coverImageUrl
    ? `<img class="ev-thumb" src="${esc(e.coverImageUrl)}" alt="" loading="lazy"/>`
    : `<div class="ev-thumb"></div>`;

  return `
    <div class="ev-row">
      ${thumb}
      <div class="ev-main">
        <div class="t">${esc(e.title)}</div>
        <div class="s">
          <span class="status-pill ${esc(e.status)}">${esc(e.status)}</span>
          · ${esc(typeLabel)}${featured}
          · ${esc(formatWhen(e.startAt))}
          · ${esc(priceLabel(e.priceCents))}
        </div>
        <div class="s">
          ${icon('users', { size: 12 })} <b>${e.committedCount || 0}</b> going ·
          ${e.interestedCount || 0} interested ·
          ${icon('fire', { size: 12 })} ${e.voteScore || 0}
        </div>
      </div>
      <div class="ev-actions">${actions.join('')}</div>
    </div>`;
}

// ── (c) REPORTS QUEUE ──────────────────────────────────────────────────────────────────────

function reportsSection() {
  const open = state.reports.filter((r) => r.status === 'open');
  let body;
  if (!state.reports.length) {
    body = `<p class="muted small">Nothing reported. All quiet 🌙</p>`;
  } else {
    body = state.reports.map(reportRow).join('');
  }
  return `
    <div class="admin-card">
      <h2>Reports <span class="count-chip">· ${open.length} open</span></h2>
      <div class="sub">Stuff teens flagged. Review it, then take action in the event list.</div>
      ${body}
    </div>`;
}

function reportRow(r) {
  // markReviewed is optional in the contract; only offer it if the backend supports it.
  const canReview = typeof API.markReportReviewed === 'function';
  const reviewBtn =
    r.status === 'open' && canReview
      ? `<button class="btn btn-sm" data-action="review-report" data-id="${esc(r.reportId)}">
           ${icon('check', { size: 14 })} Mark reviewed</button>`
      : '';

  const statusCls =
    r.status === 'open' ? 'cancelled' : r.status === 'reviewed' ? 'draft' : 'published';

  return `
    <div class="report-row">
      <div class="meta">
        <span class="status-pill ${statusCls}">${esc(r.status)}</span>
        <span>${esc(r.targetType)} · ${esc(r.targetId)}</span>
        <span>${esc(formatWhen(r.createdAt))}</span>
      </div>
      <div><b>${esc(r.reason || 'No reason given')}</b></div>
      ${r.details ? `<div class="muted small">${esc(r.details)}</div>` : ''}
      ${reviewBtn ? `<div class="mt-1">${reviewBtn}</div>` : ''}
    </div>`;
}

// ── events: clicks ─────────────────────────────────────────────────────────────────────────

function onClick(ev) {
  const btn = ev.target.closest('[data-action]');
  if (!btn) return;
  const action = btn.dataset.action;
  const id = btn.dataset.id;

  switch (action) {
    case 'signout':
      ev.preventDefault();
      doSignOut();
      break;
    case 'toggle-tag':
      ev.preventDefault();
      toggleInArray(state.form.tags, id);
      btn.classList.toggle('is-active');
      break;
    case 'toggle-recfor':
      ev.preventDefault();
      toggleInArray(state.form.recommendedFor, id);
      btn.classList.toggle('is-active');
      break;
    case 'cancel-edit':
      ev.preventDefault();
      resetEditor();
      break;
    case 'edit':
      ev.preventDefault();
      startEdit(id);
      break;
    case 'publish':
      ev.preventDefault();
      changeStatus(id, 'published');
      break;
    case 'cancel':
      ev.preventDefault();
      changeStatus(id, 'cancelled');
      break;
    case 'to-draft':
      ev.preventDefault();
      changeStatus(id, 'draft');
      break;
    case 'review-report':
      ev.preventDefault();
      reviewReport(id);
      break;
    default:
      break;
  }
}

function onChange(ev) {
  // Keep the working form in sync with the cover URL preview etc. We read fresh on submit,
  // so no per-field sync is strictly required — but mirror checkbox/text so re-renders persist.
  const t = ev.target;
  if (!t.name) return;
  switch (t.name) {
    case 'isFeatured':
      state.form.isFeatured = t.checked;
      break;
    default:
      break;
  }
}

function onSubmit(ev) {
  const form = ev.target.closest('form[data-action]');
  if (!form) return;
  ev.preventDefault();
  const action = form.dataset.action;
  if (action === 'do-login') doLogin(form);
  else if (action === 'save-event') saveEvent(form);
}

// ── auth actions ───────────────────────────────────────────────────────────────────────────

async function doLogin(form) {
  const errBox = els.root.querySelector('[data-login-error]');
  const showErr = (msg) => {
    if (errBox) {
      errBox.textContent = msg;
      errBox.classList.remove('hide');
    } else {
      showToast(msg, 'error');
    }
  };
  if (errBox) errBox.classList.add('hide');

  const data = new FormData(form);
  const email = String(data.get('email') || '').trim();
  const password = String(data.get('password') || '');
  const submitBtn = form.querySelector('button[type="submit"]');
  if (submitBtn) submitBtn.disabled = true;

  try {
    await Auth.signIn({ email, password });
    // signIn succeeds for any valid account — gate on the admin role.
    if (!Auth.isAdmin()) {
      showErr("That account isn't an admin. Use a master login.");
      return; // onChange already re-rendered the gate with the wrong-role notice
    }
    showToast('Welcome back 👋', 'success');
    // onChange fires from signIn and triggers loadDashboard(); nothing else to do.
  } catch (err) {
    showErr(err.message || 'Wrong email or password.');
  } finally {
    if (submitBtn) submitBtn.disabled = false;
  }
}

async function doSignOut() {
  try {
    await Auth.signOut();
    showToast('Signed out.');
    // onChange handles re-rendering the gate.
  } catch (err) {
    showToast(err.message || 'Could not sign out.', 'error');
  }
}

// ── editor actions ─────────────────────────────────────────────────────────────────────────

function startEdit(id) {
  const e = state.events.find((x) => x.id === id);
  if (!e) {
    showToast('Event not found.', 'error');
    return;
  }
  state.editing = id;
  state.form = {
    title: e.title || '',
    description: e.description || '',
    eventType: e.eventType || '',
    tags: Array.isArray(e.tags) ? [...e.tags] : [],
    hostName: e.hostName || '',
    startAt: toLocalInput(e.startAt),
    endAt: toLocalInput(e.endAt),
    venueName: e.venueName || '',
    approxArea: e.approxArea || '',
    neighborhood: e.neighborhood || '',
    exactAddress: e.exactAddress || '',
    priceCents: Number.isFinite(e.priceCents) ? e.priceCents : 0,
    capacity: e.capacity == null ? '' : e.capacity,
    ageMin: Number.isFinite(e.ageMin) ? e.ageMin : 14,
    ageMax: Number.isFinite(e.ageMax) ? e.ageMax : 18,
    recommendedFor: Array.isArray(e.recommendedFor) ? [...e.recommendedFor] : [],
    coverImageUrl: e.coverImageUrl || '',
    isFeatured: !!e.isFeatured,
  };
  renderDashboard();
  els.root.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function resetEditor() {
  state.editing = null;
  state.form = blankForm();
  renderDashboard();
}

// Build a canon-shaped payload from the live form fields.
function readForm(form) {
  const data = new FormData(form);
  const str = (k) => String(data.get(k) || '').trim();
  const num = (k) => {
    const v = String(data.get(k) || '').trim();
    if (v === '') return null;
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
  };

  const priceDollars = num('priceDollars');
  const capacity = num('capacity');
  const ageMin = num('ageMin');
  const ageMax = num('ageMax');

  return {
    title: str('title'),
    description: str('description'),
    eventType: str('eventType'),
    tags: [...state.form.tags],
    hostName: str('hostName'),
    startAt: fromLocalInput(str('startAt')),
    endAt: str('endAt') ? fromLocalInput(str('endAt')) : null,
    venueName: str('venueName') || null,
    neighborhood: str('neighborhood') || null,
    approxArea: str('approxArea') || str('neighborhood') || 'Chicago',
    exactAddress: str('exactAddress') || null,
    priceCents: priceDollars == null ? 0 : Math.max(0, Math.round(priceDollars * 100)),
    capacity: capacity == null ? null : Math.max(1, Math.round(capacity)),
    ageMin: ageMin == null ? 14 : ageMin,
    ageMax: ageMax == null ? 18 : ageMax,
    recommendedFor: [...state.form.recommendedFor],
    coverImageUrl: str('coverImageUrl') || null,
    isFeatured: !!data.get('isFeatured'),
  };
}

async function saveEvent(form) {
  const payload = readForm(form);

  // Light client validation with friendly copy.
  if (!payload.title) return showToast('Give it a title first.', 'error');
  if (!payload.eventType) return showToast('Pick an event type.', 'error');
  if (!payload.startAt) return showToast('When does it start?', 'error');
  if (payload.ageMin > payload.ageMax) {
    return showToast('Age min can’t be above age max.', 'error');
  }

  const submitBtn = form.querySelector('button[type="submit"]');
  if (submitBtn) submitBtn.disabled = true;
  const editingId = state.editing;

  try {
    if (editingId) {
      const updated = await API.updateEvent(editingId, payload);
      // Reconcile the list entry (keep counts/status from the returned doc).
      const i = state.events.findIndex((x) => x.id === editingId);
      if (i >= 0) state.events[i] = { ...state.events[i], ...updated };
      showToast('Saved ✅', 'success');
    } else {
      const created = await API.createEvent(payload);
      state.events.push(created);
      state.events.sort((a, b) => new Date(a.startAt) - new Date(b.startAt));
      showToast('Event created — publish it when you’re ready.', 'success');
    }
    resetEditor();
  } catch (err) {
    showToast(err.message || 'Could not save.', 'error');
    if (submitBtn) submitBtn.disabled = false;
  }
}

// ── status actions (Publish / Cancel / Draft) — optimistic ──────────────────────────────────

async function changeStatus(id, status) {
  const e = state.events.find((x) => x.id === id);
  if (!e) return;
  const prev = e.status;
  // Optimistic flip + re-render.
  e.status = status;
  renderDashboard();

  const verb = status === 'published' ? 'Published' : status === 'cancelled' ? 'Cancelled' : 'Moved to draft';
  try {
    await API.setEventStatus(id, status);
    showToast(`${verb} 🎉`, 'success');
  } catch (err) {
    // Roll back.
    e.status = prev;
    renderDashboard();
    showToast(err.message || 'Could not update status.', 'error');
  }
}

// ── reports ────────────────────────────────────────────────────────────────────────────────

async function reviewReport(id) {
  if (typeof API.markReportReviewed !== 'function') return;
  const r = state.reports.find((x) => x.reportId === id);
  if (!r) return;
  const prev = r.status;
  r.status = 'reviewed';
  renderDashboard();
  try {
    await API.markReportReviewed(id);
    showToast('Marked reviewed.', 'success');
  } catch (err) {
    r.status = prev;
    renderDashboard();
    showToast(err.message || 'Could not update report.', 'error');
  }
}

// ── helpers ────────────────────────────────────────────────────────────────────────────────

function toggleInArray(arr, value) {
  const i = arr.indexOf(value);
  if (i >= 0) arr.splice(i, 1);
  else arr.push(value);
}

function centsToDollars(cents) {
  if (!Number.isFinite(cents) || cents <= 0) return 0;
  const d = cents / 100;
  return Number.isInteger(d) ? d : d.toFixed(2);
}

// Convert an ISO/timestamp into a value a <input type="datetime-local"> accepts
// (local time, "YYYY-MM-DDTHH:mm"), or '' when empty/invalid.
function toLocalInput(iso) {
  if (!iso) return '';
  const d = iso instanceof Date ? iso : new Date(iso);
  if (isNaN(d)) return '';
  const pad = (n) => String(n).padStart(2, '0');
  return (
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` +
    `T${pad(d.getHours())}:${pad(d.getMinutes())}`
  );
}

// Convert a datetime-local string (local) back to an ISO-8601 string for storage.
function fromLocalInput(local) {
  if (!local) return '';
  const d = new Date(local); // parsed as local time
  if (isNaN(d)) return '';
  return d.toISOString();
}
