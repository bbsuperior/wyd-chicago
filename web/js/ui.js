// ui.js — pure-ish render helpers. These turn data (events, users, tags) into DOM
// nodes or HTML strings. They DON'T fetch or mutate state — app.js owns that and wires
// behavior via event delegation. Interactive elements carry data-action + data-id so
// app.js can listen once on a container and route clicks.
//
// Most helpers return an HTML *string* (composable into templates). showToast and a few
// builders create real DOM nodes when that's more convenient.

import { icon, starSVG, logoSVG } from './icons.js';

// ----------------------------------------------------------------- utilities

/** Escape user-supplied text before dropping it into innerHTML. */
export function esc(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** Initials for avatar fallbacks ("Beckett Bortz" -> "BB"). */
function initials(name) {
  const parts = String(name || '?')
    .trim()
    .split(/\s+/)
    .filter(Boolean);
  if (!parts.length) return '?';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

/** Deterministic, on-brand gradient cover (offline-safe, no third-party images). */
function hashStr(s) {
  let h = 0;
  s = String(s || 'wyd');
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return h;
}
const COVER_GRADS = [
  ['#5B8CFF', '#C44CFF'],
  ['#C44CFF', '#FF4D6D'],
  ['#FF4D6D', '#FFC83D'],
  ['#5B8CFF', '#2EE6A6'],
  ['#7A5BFF', '#FF4D6D'],
  ['#FF4D6D', '#5B8CFF'],
];
function coverGradient(event) {
  const [a, b] = COVER_GRADS[hashStr(event && (event.id || event.title)) % COVER_GRADS.length];
  return `linear-gradient(135deg, ${a} 0%, ${b} 100%)`;
}
/**
 * Inner markup for a cover box. Always paints a branded gradient (set as the box
 * background by the caller). If the event has a real photo we layer it on top
 * (and quietly drop it if it fails to load); otherwise we show the type emoji so
 * an image-less event still looks intentional.
 */
function coverInner(event, typeTag) {
  if (event && event.coverImageUrl) {
    return `<img src="${esc(event.coverImageUrl)}" alt="${esc(event.title)}" loading="lazy" onerror="this.remove()"/>`;
  }
  const emoji = (typeTag && typeTag.emoji) || '🎉';
  return `<span class="cover-emoji" aria-hidden="true">${esc(emoji)}</span>`;
}

/** Friendly relative/absolute "when" string from an ISO date or timestamp. */
export function formatWhen(iso) {
  if (!iso) return 'TBD';
  const d = iso instanceof Date ? iso : new Date(iso);
  if (isNaN(d)) return 'TBD';
  const now = new Date();
  const ms = d - now;
  const dayMs = 86400000;
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const startOfDate = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const dayDiff = Math.round((startOfDate - startOfToday) / dayMs);
  const time = d
    .toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })
    .toLowerCase()
    .replace(' ', '');

  if (ms < 0 && dayDiff === 0) return 'Happening now';
  if (dayDiff === 0) return `Tonight · ${time}`;
  if (dayDiff === 1) return `Tomorrow · ${time}`;
  if (dayDiff > 1 && dayDiff < 7) {
    const wd = d.toLocaleDateString('en-US', { weekday: 'long' });
    return `${wd} · ${time}`;
  }
  const md = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  return `${md} · ${time}`;
}

/** Price label from integer cents. 0 -> "Free". */
export function priceLabel(cents) {
  if (cents == null || cents === 0) return 'Free';
  const dollars = cents / 100;
  return Number.isInteger(dollars) ? `$${dollars}` : `$${dollars.toFixed(2)}`;
}

// ----------------------------------------------------------------- atoms

/**
 * chip(tag) — a tag/filter chip. Accepts either a tag object {id,label,emoji} or a
 * plain object {id,label,emoji,active}. Returns an HTML string.
 */
export function chip(tag, opts = {}) {
  const id = tag.id != null ? tag.id : tag.value;
  const emoji = tag.emoji ? `<span class="emoji">${esc(tag.emoji)}</span>` : '';
  const active = opts.active || tag.active ? ' is-active' : '';
  const action = opts.action || 'filter';
  return (
    `<button class="chip${active}" data-action="${action}" data-id="${esc(id)}" ` +
    `data-group="${esc(opts.group || tag.kind || '')}">${emoji}${esc(tag.label)}</button>`
  );
}

/** A small read-only event-type chip used on cards / detail (tinted, no action). */
function typeChip(tag) {
  if (!tag) return '';
  const emoji = tag.emoji ? `${esc(tag.emoji)} ` : '';
  return `<span class="type-chip">${emoji}${esc(tag.label)}</span>`;
}

/**
 * avatarStack(users, max) — overlapping circle avatars + "+N". Returns HTML string.
 * users: array of {displayName, avatarUrl}.
 */
export function avatarStack(users, max = 4) {
  const list = Array.isArray(users) ? users : [];
  if (!list.length) return '';
  const shown = list.slice(0, max);
  const extra = list.length - shown.length;
  const avs = shown
    .map((u) =>
      u && u.avatarUrl
        ? `<span class="av"><img src="${esc(u.avatarUrl)}" alt="${esc(
            u.displayName || ''
          )}" loading="lazy"/></span>`
        : `<span class="av">${esc(initials(u && u.displayName))}</span>`
    )
    .join('');
  const more = extra > 0 ? `<span class="av more">+${extra}</span>` : '';
  return `<span class="avatar-stack">${avs}${more}</span>`;
}

// ----------------------------------------------------------------- event card

/**
 * renderEventCard(event, ctx) — the core feed unit. ctx may carry the viewer's current
 * state for this event: { myVote: 1|-1|0, saved: bool, friendsGoing: [users] }.
 * Returns an HTML string. The whole card is clickable (data-action="open").
 */
export function renderEventCard(event, ctx = {}) {
  const myVote = ctx.myVote || 0;
  const saved = !!ctx.saved;
  const friends = ctx.friendsGoing || [];
  const tag = event._typeTag; // optionally hydrated tag object for the event type
  const featured = event.isFeatured
    ? `<span class="featured-badge">${icon('star', {
        size: 12,
      })} Featured</span>`
    : '';

  const going = event.committedCount || 0;
  const interested = event.interestedCount || 0;
  const goingLine = friends.length
    ? `${avatarStack(friends, 3)} <span class="going-line"><b>${
        friends.length
      } friend${friends.length > 1 ? 's' : ''}</b> + ${going} going</span>`
    : `<span class="going-line"><b>${going}</b> going · ${interested} interested</span>`;

  const price =
    event.priceCents > 0
      ? `<span class="meta">${priceLabel(event.priceCents)}</span>`
      : `<span class="meta price-free">Free</span>`;

  return `
    <article class="event-card${event.isFeatured ? ' is-featured' : ''}"
             data-action="open" data-id="${esc(event.id)}">
      <div class="cover" style="background:${coverGradient(event)}">
        ${coverInner(event, tag)}
        <div class="scrim"></div>
        <div class="top-row">
          ${featured}
          <span class="spacer"></span>
          ${tag ? typeChip(tag) : ''}
        </div>
        <div class="title-wrap">
          <h3>${esc(event.title)}</h3>
          <div class="host">by ${esc(event.hostName || 'WYD')}</div>
        </div>
      </div>
      <div class="body">
        <div class="meta-row">
          <span class="meta">${icon('clock', { size: 14 })} ${esc(
    formatWhen(event.startAt)
  )}</span>
          <span class="neighborhood-badge">${icon('map-pin', {
            size: 12,
          })} ${esc(event.neighborhood || event.approxArea || 'Chicago')}</span>
          ${price}
        </div>
        <div class="card-footer">
          ${goingLine}
          <span class="vote-pill" data-stop="1">
            <button class="up${myVote === 1 ? ' is-on' : ''}"
                    data-action="vote-up" data-id="${esc(event.id)}"
                    aria-label="Upvote">${icon('fire', { size: 16 })}</button>
            <span class="score" data-score="${esc(event.id)}">${event.voteScore || 0}</span>
            <button class="down${myVote === -1 ? ' is-on' : ''}"
                    data-action="vote-down" data-id="${esc(event.id)}"
                    aria-label="Downvote">${icon('x', { size: 16 })}</button>
          </span>
          <button class="bookmark-btn${saved ? ' is-on' : ''}"
                  data-action="save" data-id="${esc(event.id)}"
                  aria-label="Save event">${icon('bookmark', { size: 17 })}</button>
        </div>
      </div>
    </article>`;
}

/**
 * renderFeed(events, ctxMap) — list of event cards. ctxMap is an optional
 * { [eventId]: ctx } so cards can show the viewer's vote/save state.
 */
export function renderFeed(events, ctxMap = {}) {
  if (!events || !events.length) {
    return emptyState({
      title: 'Nothing here yet',
      body: "No events match that. Try clearing a filter or check back tonight.",
    });
  }
  return events.map((e) => renderEventCard(e, ctxMap[e.id] || {})).join('');
}

// ----------------------------------------------------------------- filter bar

/**
 * renderFilterBar(tags, state) — search + horizontal filter chips + segmented sort.
 * tags: array of tag objects (both kinds). state: { search, type, neighborhood, when,
 * sort, neighborhoods: [] }. Returns HTML string.
 */
export function renderFilterBar(tags, state = {}) {
  const eventTypes = (tags || []).filter((t) => t.kind === 'eventType');
  const neighborhoods = state.neighborhoods || [];

  // "When" quick filters.
  const whenOpts = [
    { id: 'tonight', label: 'Tonight', emoji: '🌙' },
    { id: 'weekend', label: 'This weekend', emoji: '🎉' },
    { id: 'week', label: 'This week', emoji: '📅' },
  ];

  const typeChips = eventTypes
    .map((t) =>
      chip(t, { action: 'filter-type', active: state.type === t.id, group: 'type' })
    )
    .join('');
  const whenChips = whenOpts
    .map((w) =>
      chip(w, { action: 'filter-when', active: state.when === w.id, group: 'when' })
    )
    .join('');
  const hoodChips = neighborhoods
    .map((n) =>
      chip(
        { id: n, label: n, emoji: '📍' },
        {
          action: 'filter-hood',
          active: state.neighborhood === n,
          group: 'hood',
        }
      )
    )
    .join('');

  const clear =
    state.type || state.when || state.neighborhood
      ? `<button class="chip" data-action="filter-clear">${icon('x', {
          size: 14,
        })} Clear</button>`
      : '';

  const sorts = [
    { id: 'hype', label: '🔥 Hype' },
    { id: 'soonest', label: '🕒 Soonest' },
    { id: 'friends', label: '👥 Friends' },
    { id: 'foryou', label: '✨ For you' },
  ];
  const sortBtns = sorts
    .map(
      (s) =>
        `<button class="${
          (state.sort || 'hype') === s.id ? 'is-active' : ''
        }" data-action="sort" data-id="${s.id}">${s.label}</button>`
    )
    .join('');

  return `
    <div class="search">
      ${icon('search', { size: 18 })}
      <input type="search" placeholder="Search events, hosts, neighborhoods…"
             data-action="search" value="${esc(state.search || '')}"
             autocomplete="off" enterkeyhint="search"/>
    </div>
    <div class="chip-row">
      ${clear}${typeChips}${whenChips}${hoodChips}
    </div>
    <div class="segmented" role="tablist" aria-label="Sort events">
      ${sortBtns}
    </div>`;
}

// ----------------------------------------------------------------- event detail

/**
 * renderEventDetail(event, ctx) — full detail page.
 * ctx: { myRsvp, myVote, saved, friendsGoing, comments, tags (id->tag map),
 *        signedIn, addressVisible }.
 */
export function renderEventDetail(event, ctx = {}) {
  const tagMap = ctx.tags || {};
  const typeTag = event._typeTag || tagMap[event.eventType];
  const myRsvp = ctx.myRsvp || null;
  const myVote = ctx.myVote || 0;
  const saved = !!ctx.saved;
  const friends = ctx.friendsGoing || [];
  const comments = ctx.comments || [];
  const signedIn = !!ctx.signedIn;

  // Address gating (canon §8): exact address only after RSVP "going".
  const addressBlock =
    myRsvp === 'going' && event.exactAddress
      ? `<div class="address-revealed">${icon('map-pin', {
          size: 16,
        })} ${esc(event.exactAddress)}</div>`
      : `<div class="address-locked">${icon('map-pin', {
          size: 16,
        })} Exact address shows once you tap <b>Going</b>. For now: ${esc(
          event.approxArea || event.neighborhood || 'Chicago'
        )}.</div>`;

  const interestTags = (event.tags || [])
    .map((id) => tagMap[id])
    .filter(Boolean)
    .map((t) => chip(t, { action: 'noop' }))
    .join('');
  const recFor = (event.recommendedFor || [])
    .map((id) => tagMap[id])
    .filter(Boolean)
    .map((t) => chip(t, { action: 'noop' }))
    .join('');

  const cancelled =
    event.status === 'cancelled'
      ? `<div class="notice error">${icon('x', {
          size: 16,
        })} This event was cancelled by the host.</div>`
      : '';

  // RSVP bar
  const goingCls = myRsvp === 'going' ? ' is-going' : '';
  const intCls = myRsvp === 'interested' ? ' is-interested' : '';
  const rsvpBar =
    event.status === 'cancelled'
      ? ''
      : `<div class="rsvp-bar">
          <button class="btn${goingCls}" data-action="rsvp-going" data-id="${esc(
          event.id
        )}">${icon('check', { size: 18 })} ${
          myRsvp === 'going' ? "You're going" : "I'm going"
        }</button>
          <button class="btn${intCls}" data-action="rsvp-interested" data-id="${esc(
          event.id
        )}">${icon('heart', { size: 18 })} ${
          myRsvp === 'interested' ? 'Interested' : 'Interested?'
        }</button>
        </div>`;

  const commentsHtml = comments.length
    ? `<div class="comment-list">${comments
        .map((c) => renderComment(c))
        .join('')}</div>`
    : `<p class="muted small">No comments yet. Say something 👀</p>`;

  return `
    <div class="detail-hero" style="background:${coverGradient(event)}">
      ${coverInner(event, typeTag)}
      <div class="scrim"></div>
      <button class="back" data-action="back" aria-label="Back">${icon(
        'chevron-left',
        { size: 22 }
      )}</button>
      <div class="hero-foot">
        <div class="row gap-sm" style="margin-bottom:8px">
          ${event.isFeatured ? `<span class="featured-badge">${icon('star', { size: 12 })} Featured</span>` : ''}
          ${typeTag ? typeChip(typeTag) : ''}
        </div>
        <h1>${esc(event.title)}</h1>
        <div class="muted" style="margin-top:4px">by ${esc(
          event.hostName || 'WYD'
        )}</div>
      </div>
    </div>

    <div class="detail-body">
      ${cancelled}

      <div class="info-grid">
        <div class="info-tile">
          <div class="label">${icon('clock', { size: 13 })} When</div>
          <div class="value">${esc(formatWhen(event.startAt))}</div>
        </div>
        <div class="info-tile">
          <div class="label">${icon('map-pin', { size: 13 })} Area</div>
          <div class="value">${esc(
            event.neighborhood || event.approxArea || 'Chicago'
          )}</div>
        </div>
        <div class="info-tile">
          <div class="label">${icon('users', { size: 13 })} Going</div>
          <div class="value">${event.committedCount || 0} · ${
    event.interestedCount || 0
  } interested</div>
        </div>
        <div class="info-tile">
          <div class="label">${icon('fire', { size: 13 })} Hype</div>
          <div class="value">${event.voteScore || 0} ${
    (event.voteScore || 0) >= 0 ? '🔥' : ''
  }</div>
        </div>
      </div>

      ${addressBlock}

      ${
        friends.length
          ? `<div class="detail-section">
               <h4>Friends going</h4>
               <div class="row gap-sm" style="align-items:center">
                 ${avatarStack(friends, 6)}
                 <span class="muted small">${friends
                   .map((f) => esc(f.displayName))
                   .join(', ')}</span>
               </div>
             </div>`
          : ''
      }

      <div class="detail-section">
        <h4>The vibe</h4>
        <p>${esc(event.description || 'No description yet.')}</p>
      </div>

      ${
        interestTags
          ? `<div class="detail-section"><h4>Tags</h4><div class="tag-cloud">${interestTags}</div></div>`
          : ''
      }
      ${
        recFor
          ? `<div class="detail-section"><h4>Recommended for</h4><div class="tag-cloud">${recFor}</div></div>`
          : ''
      }

      <div class="detail-section">
        <h4>Vote</h4>
        <div class="row gap-sm" style="align-items:center">
          <span class="vote-pill">
            <button class="up${myVote === 1 ? ' is-on' : ''}"
                    data-action="vote-up" data-id="${esc(event.id)}"
                    aria-label="Upvote">${icon('fire', { size: 16 })}</button>
            <span class="score" data-score="${esc(event.id)}">${
    event.voteScore || 0
  }</span>
            <button class="down${myVote === -1 ? ' is-on' : ''}"
                    data-action="vote-down" data-id="${esc(event.id)}"
                    aria-label="Downvote">${icon('x', { size: 16 })}</button>
          </span>
          <button class="bookmark-btn${saved ? ' is-on' : ''}"
                  data-action="save" data-id="${esc(event.id)}"
                  aria-label="Save">${icon('bookmark', { size: 17 })}</button>
          <button class="btn btn-ghost btn-sm" data-action="report"
                  data-id="${esc(event.id)}">${icon('flag', {
    size: 16,
  })} Report</button>
        </div>
      </div>

      <div class="detail-section">
        <h4>Share</h4>
        <div class="share-row">
          <button class="share-btn snap" data-action="share-snap" data-id="${esc(
            event.id
          )}">${icon('snapchat', { size: 18 })} Snapchat</button>
          <button class="share-btn insta" data-action="share-insta" data-id="${esc(
            event.id
          )}">${icon('instagram', { size: 18 })} Instagram</button>
          <button class="share-btn" data-action="share-copy" data-id="${esc(
            event.id
          )}">${icon('share', { size: 18 })} Copy link</button>
        </div>
      </div>

      <div class="detail-section">
        <h4>Comments</h4>
        ${commentsHtml}
        ${
          signedIn
            ? `<form class="comment-form" data-action="comment-form" data-id="${esc(
                event.id
              )}">
                 <input name="text" placeholder="Add a comment…" maxlength="280"
                        autocomplete="off"/>
                 <button class="btn btn-primary btn-sm" type="submit">${icon(
                   'plus',
                   { size: 16 }
                 )}</button>
               </form>`
            : `<p class="muted small">Log in to comment.</p>`
        }
      </div>

      ${rsvpBar}
    </div>`;
}

function renderComment(c) {
  const when = c.createdAt ? timeAgo(c.createdAt) : '';
  return `
    <div class="comment">
      <span class="av" style="width:34px;height:34px;border-radius:50%;background:var(--surface-2);display:grid;place-items:center;font-weight:700;font-size:12px;flex:0 0 auto">${esc(
        initialsFor(c.authorName)
      )}</span>
      <div class="body">
        <div><span class="author">${esc(c.authorName || 'Someone')}</span>
          <span class="when"> · ${esc(when)}</span></div>
        <div class="text">${esc(c.text)}</div>
      </div>
    </div>`;
}
function initialsFor(name) {
  return initials(name);
}

/** Compact "2h ago" style stamp. */
function timeAgo(iso) {
  const d = iso instanceof Date ? iso : new Date(iso);
  if (isNaN(d)) return '';
  const s = Math.floor((Date.now() - d) / 1000);
  if (s < 60) return 'just now';
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  const dd = Math.floor(h / 24);
  if (dd < 7) return `${dd}d ago`;
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

// ----------------------------------------------------------------- profile

/**
 * renderProfile(user, ctx) — profile page. ctx: { going: [events], saved: [events],
 * friendsCount, isAdmin }.
 */
export function renderProfile(user, ctx = {}) {
  if (!user) {
    return emptyState({
      title: 'Not logged in',
      body: 'Log in to see your profile, your events, and your friends.',
      cta: { label: 'Log in', action: 'go-auth' },
    });
  }
  const going = ctx.going || [];
  const saved = ctx.saved || [];
  const avatar = user.avatarUrl
    ? `<img src="${esc(user.avatarUrl)}" alt=""/>`
    : esc(initials(user.displayName));

  const social = [];
  if (user.snapchatUsername)
    social.push(
      `<span class="social-pill snap">${icon('snapchat', {
        size: 16,
      })} ${esc(user.snapchatUsername)}</span>`
    );
  if (user.instagramUsername)
    social.push(
      `<span class="social-pill insta">${icon('instagram', {
        size: 16,
      })} ${esc(user.instagramUsername)}</span>`
    );

  const verifyNotice = user.emailVerified
    ? ''
    : `<div class="notice warn">${icon('clock', {
        size: 16,
      })} Verify your email to RSVP and vote. <button class="btn btn-ghost btn-sm" data-action="resend-verify">Resend</button></div>`;

  const adminLink = ctx.isAdmin
    ? `<button class="list-row" data-action="go-admin">
         <span class="lead">${icon('star', { size: 17 })}</span>
         <span class="grow"><span class="t">Admin dashboard</span>
           <span class="s">Create & manage events, reports</span></span>
         <span class="trail">${icon('chevron-right', { size: 18 })}</span>
       </button>`
    : '';

  return `
    <div class="profile-head">
      <div class="avatar-xl">${avatar}</div>
      <h2>${esc(user.displayName || 'You')}</h2>
      <div class="username">@${esc(user.username || 'you')}</div>
      ${user.bio ? `<p class="muted small" style="max-width:34ch">${esc(user.bio)}</p>` : ''}
    </div>

    <div class="profile-stats">
      <div class="stat"><div class="num">${ctx.friendsCount || 0}</div><div class="lbl">Friends</div></div>
      <div class="stat"><div class="num">${going.length}</div><div class="lbl">Going</div></div>
      <div class="stat"><div class="num">${saved.length}</div><div class="lbl">Saved</div></div>
    </div>

    ${social.length ? `<div class="social-row">${social.join('')}</div>` : ''}
    ${verifyNotice}

    <div class="section-head"><h2>Going to</h2></div>
    ${going.length ? renderFeed(going, ctx.ctxMap) : `<p class="muted small">Nothing on the calendar yet — go find something good.</p>`}

    <div class="section-head"><h2>Saved</h2></div>
    ${saved.length ? renderFeed(saved, ctx.ctxMap) : `<p class="muted small">You haven't saved anything yet.</p>`}

    <div class="section-head"><h2>Settings</h2></div>
    <div class="list">
      ${adminLink}
      <button class="list-row" data-action="edit-profile">
        <span class="lead">${icon('settings', { size: 17 })}</span>
        <span class="grow"><span class="t">Edit profile</span>
          <span class="s">Name, bio, socials, interests</span></span>
        <span class="trail">${icon('chevron-right', { size: 18 })}</span>
      </button>
      <button class="list-row" data-action="go-safety">
        <span class="lead">${icon('flag', { size: 17 })}</span>
        <span class="grow"><span class="t">Safety & guidelines</span>
          <span class="s">How to stay safe, report, block</span></span>
        <span class="trail">${icon('chevron-right', { size: 18 })}</span>
      </button>
      <button class="list-row danger" data-action="signout">
        <span class="lead">${icon('logout', { size: 17 })}</span>
        <span class="grow"><span class="t">Sign out</span></span>
        <span class="trail">${icon('chevron-right', { size: 18 })}</span>
      </button>
    </div>`;
}

// ----------------------------------------------------------------- friends

/**
 * renderFriends(data) — data: { friends: [users], requests: [users], signedIn, me }.
 */
export function renderFriends(data = {}) {
  if (!data.signedIn) {
    return emptyState({
      title: 'Find your people',
      body: 'Log in to add friends by username and see who’s going out.',
      cta: { label: 'Log in', action: 'go-auth' },
    });
  }
  const friends = data.friends || [];
  const requests = data.requests || [];
  const me = data.me || {};

  const reqHtml = requests.length
    ? `<div class="list">${requests.map((u) => friendRow(u, 'request')).join('')}</div>`
    : '';

  const friendHtml = friends.length
    ? `<div class="list">${friends.map((u) => friendRow(u, 'friend')).join('')}</div>`
    : `<p class="muted small">No friends yet. Add someone by their @username 👇</p>`;

  return `
    <div class="page-title"><h1>Friends</h1></div>

    <form class="comment-form mt-1" data-action="add-friend" style="margin-bottom:16px">
      <input name="username" placeholder="Add by @username" autocomplete="off"/>
      <button class="btn btn-primary btn-sm" type="submit">${icon('plus', {
        size: 16,
      })} Add</button>
    </form>

    ${me.snapchatUsername
      ? `<div class="notice info">${icon('snapchat', {
          size: 16,
        })} Share your Snap so friends can find you: <b>${esc(
          me.snapchatUsername
        )}</b></div>`
      : ''}

    ${requests.length ? `<div class="section-head"><h2>Requests</h2><span class="muted small">${requests.length}</span></div>${reqHtml}` : ''}

    <div class="section-head"><h2>Your friends</h2><span class="muted small">${friends.length}</span></div>
    ${friendHtml}`;
}

function friendRow(u, mode) {
  const av = u.avatarUrl
    ? `<img src="${esc(u.avatarUrl)}" alt=""/>`
    : esc(initials(u.displayName));
  const actions =
    mode === 'request'
      ? `<div class="friend-actions">
           <button class="btn btn-primary btn-sm" data-action="friend-accept" data-id="${esc(
             u.uid || u.id
           )}">${icon('check', { size: 16 })}</button>
           <button class="btn btn-sm" data-action="friend-decline" data-id="${esc(
             u.uid || u.id
           )}">${icon('x', { size: 16 })}</button>
         </div>`
      : u.snapchatUsername
      ? `<span class="social-pill snap">${icon('snapchat', { size: 14 })} ${esc(
          u.snapchatUsername
        )}</span>`
      : '';
  return `
    <div class="list-row friend-row">
      <span class="av">${av}</span>
      <span class="grow"><span class="t">${esc(u.displayName || 'Someone')}</span>
        <span class="s">@${esc(u.username || '')}</span></span>
      ${actions}
    </div>`;
}

// ----------------------------------------------------------------- auth

/**
 * renderAuth(mode, tags) — mode "login" | "signup". tags used for interest-picking on
 * signup. Returns HTML string. app.js handles the form submits + validation messaging.
 */
export function renderAuth(mode = 'login', tags = []) {
  const interests = (tags || []).filter((t) => t.kind === 'interest');
  const isSignup = mode === 'signup';

  const interestPicker = isSignup
    ? `<div class="field">
         <label>Pick a few interests</label>
         <div class="tag-picker">
           ${interests
             .map(
               (t) =>
                 `<button type="button" class="chip" data-action="toggle-interest" data-id="${esc(
                   t.id
                 )}"><span class="emoji">${esc(t.emoji || '')}</span>${esc(
                   t.label
                 )}</button>`
             )
             .join('')}
         </div>
       </div>`
    : '';

  const extraSignup = isSignup
    ? `
      <div class="field">
        <label for="au-name">Your name</label>
        <input class="input" id="au-name" name="displayName" placeholder="First Last" autocomplete="name"/>
      </div>
      <div class="field">
        <label for="au-username">Username</label>
        <input class="input" id="au-username" name="username" placeholder="yourhandle" autocomplete="off"/>
        <span class="field-error hide" data-err="username"></span>
      </div>
      <div class="row">
        <div class="field" style="flex:1">
          <label for="au-year">Birth year</label>
          <input class="input" id="au-year" name="birthYear" type="number" inputmode="numeric"
                 placeholder="2008" min="1990" max="2014"/>
        </div>
      </div>`
    : '';

  return `
    <div class="auth-wrap">
      <div class="auth-hero">
        <div class="logo-xl" style="margin-bottom:14px">${logoSVG({ size: 44 })}</div>
        <h1>${isSignup ? 'Make an account' : 'Welcome back'}</h1>
        <p class="muted">${
          isSignup
            ? "See what's good around Chicago tonight 👀"
            : 'Log in to RSVP, vote, and find your friends.'
        }</p>
      </div>

      <div class="auth-card">
        <div class="auth-tabs">
          <button class="${!isSignup ? 'is-active' : ''}" data-action="auth-mode" data-id="login">Log in</button>
          <button class="${isSignup ? 'is-active' : ''}" data-action="auth-mode" data-id="signup">Sign up</button>
        </div>

        <div class="notice error hide" data-auth-error></div>
        <div class="notice success hide" data-auth-success></div>

        <form data-action="${isSignup ? 'do-signup' : 'do-login'}">
          ${extraSignup}
          <div class="field">
            <label for="au-email">Email</label>
            <input class="input" id="au-email" name="email" type="email"
                   placeholder="you@email.com" autocomplete="email" required/>
            <span class="field-error hide" data-err="email"></span>
          </div>
          <div class="field">
            <label for="au-pass">Password</label>
            <input class="input" id="au-pass" name="password" type="password"
                   placeholder="••••••••" autocomplete="${
                     isSignup ? 'new-password' : 'current-password'
                   }" required/>
            <span class="field-error hide" data-err="password"></span>
          </div>
          ${interestPicker}

          <button class="btn btn-primary btn-block mt-1" type="submit">
            ${isSignup ? 'Create account' : 'Log in'}
          </button>
        </form>

        ${
          !isSignup
            ? `<button class="btn btn-ghost btn-block btn-sm mt-1" data-action="forgot-pass">Forgot password?</button>`
            : `<p class="muted small center mt-2">By signing up you agree to keep it chill and follow the
               <a href="#/safety">community guidelines</a>. 14–18 only.</p>`
        }
      </div>
    </div>`;
}

// ----------------------------------------------------------------- empty + skeleton

export function emptyState({ title, body, cta } = {}) {
  const btn = cta
    ? `<button class="btn btn-primary mt-2" data-action="${esc(
        cta.action
      )}">${esc(cta.label)}</button>`
    : '';
  return `
    <div class="empty">
      <div class="glyph">${starSVG({ size: 64 })}</div>
      <h3>${esc(title || 'Nothing here')}</h3>
      <p>${esc(body || '')}</p>
      ${btn}
    </div>`;
}

/** Feed skeleton loaders (n cards). */
export function renderSkeletonFeed(n = 4) {
  let out = '';
  for (let i = 0; i < n; i++) {
    out += `
      <div class="skeleton">
        <div class="sk-cover shimmer"></div>
        <div class="sk-body">
          <div class="sk-line w-80"></div>
          <div class="sk-line w-40"></div>
          <div class="sk-line w-60"></div>
        </div>
      </div>`;
  }
  return out;
}

// ----------------------------------------------------------------- toast

let toastTimer = null;
/**
 * showToast(msg, type) — pop a transient toast. type: "default"|"success"|"error".
 */
export function showToast(msg, type = 'default') {
  const host = document.getElementById('toast');
  if (!host) return;
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  const ico =
    type === 'success' ? icon('check', { size: 16 }) : type === 'error' ? icon('x', { size: 16 }) : '';
  el.innerHTML = `${ico}<span>${esc(msg)}</span>`;
  host.appendChild(el);
  // Auto-dismiss.
  const remove = () => {
    el.classList.add('is-out');
    setTimeout(() => el.remove(), 220);
  };
  setTimeout(remove, 2600);
  // Keep host from stacking forever.
  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    host.querySelectorAll('.toast').forEach((t) => t.remove());
  }, 6000);
}

// ----------------------------------------------------------------- sheet/modal

/**
 * openSheet({ title, body, onClose }) — bottom sheet/modal. body is an HTML string.
 * Returns a close() function. Clicking the overlay or the X closes it.
 */
export function openSheet({ title, body, onClose } = {}) {
  const overlay = document.createElement('div');
  overlay.className = 'sheet-overlay';
  overlay.innerHTML = `
    <div class="sheet" role="dialog" aria-modal="true" aria-label="${esc(
      title || 'Dialog'
    )}">
      <div class="grabber"></div>
      <div class="sheet-head">
        <h3>${esc(title || '')}</h3>
        <button class="close" data-action="sheet-close" aria-label="Close">${icon(
          'x',
          { size: 18 }
        )}</button>
      </div>
      <div class="sheet-body">${body || ''}</div>
    </div>`;
  const close = () => {
    overlay.remove();
    if (typeof onClose === 'function') onClose();
  };
  overlay.addEventListener('click', (e) => {
    if (e.target === overlay || e.target.closest('[data-action="sheet-close"]')) {
      close();
    }
  });
  document.body.appendChild(overlay);
  return close;
}

// ----------------------------------------------------------------- chrome

/** App bar (top). active = current route key for nothing here, just the brand + actions. */
export function renderAppBar(user) {
  const right = user
    ? `<button class="avatar-btn" data-action="go-profile" aria-label="Profile">
         <span class="av" style="width:36px;height:36px;border-radius:50%;background:var(--grad-city);display:grid;place-items:center;font-weight:700;color:#fff;overflow:hidden">${
           user.avatarUrl
             ? `<img src="${esc(user.avatarUrl)}" alt="" style="width:100%;height:100%;object-fit:cover"/>`
             : esc(initials(user.displayName))
         }</span>
       </button>`
    : `<button class="btn btn-primary btn-sm" data-action="go-auth">Log in</button>`;

  return `
    <header class="appbar">
      <div class="brand" data-action="go-feed">
        ${logoSVG({ size: 28 })}
        <div class="sub">Chicago</div>
      </div>
      <span class="spacer"></span>
      <button class="icon-btn" data-action="go-search" aria-label="Search">${icon(
        'search',
        { size: 20 }
      )}</button>
      ${right}
    </header>`;
}

/** Bottom tab bar. active: "feed"|"search"|"friends"|"profile". */
export function renderTabBar(active) {
  const tab = (key, label, ico, action) =>
    `<button class="tab${active === key ? ' is-active' : ''}" data-action="${action}">
       ${icon(ico, { size: 22 })}<span>${label}</span>
     </button>`;
  return `
    <nav class="tabbar">
      ${tab('feed', 'Feed', 'fire', 'go-feed')}
      ${tab('search', 'Search', 'search', 'go-search')}
      ${tab('friends', 'Friends', 'users', 'go-friends')}
      ${tab('profile', 'Profile', 'star', 'go-profile')}
    </nav>`;
}

/** Safety / community guidelines page (canon §8). */
export function renderSafety() {
  return `
    <div class="page-title"><h1>Safety & guidelines</h1></div>
    <p class="muted">WYD is built for Chicago teens (14–18). Keep it real, keep it safe.</p>

    <div class="list mt-2">
      <div class="list-row"><span class="lead">${icon('map-pin', {
        size: 17,
      })}</span><span class="grow"><span class="t">Addresses stay hidden</span><span class="s">Exact location only shows after you tap “Going.”</span></span></div>
      <div class="list-row"><span class="lead">${icon('users', {
        size: 17,
      })}</span><span class="grow"><span class="t">Go with people you trust</span><span class="s">Tell a friend where you're headed. Trust your gut.</span></span></div>
      <div class="list-row"><span class="lead">${icon('flag', {
        size: 17,
      })}</span><span class="grow"><span class="t">Report anything sketchy</span><span class="s">Hit report on any event, user, or comment.</span></span></div>
      <div class="list-row"><span class="lead">${icon('x', {
        size: 17,
      })}</span><span class="grow"><span class="t">No harassment or illegal stuff</span><span class="s">Hosts are accountable. Admins can cancel instantly.</span></span></div>
    </div>

    <div class="notice info mt-2">${icon('sparkles', {
      size: 16,
    })} Be kind. This is for finding fun, not drama. 💙</div>`;
}
