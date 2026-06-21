// icons.js — inline SVG icon set (Lucide-style line icons) + the WYD wordmark/star logo.
// Everything returns an SVG *string* so it can be dropped into innerHTML or template literals.
// Colors use `currentColor` so icons inherit text color; size defaults to 24 and can be
// overridden via attrs. Keep these lightweight — no external requests.

// Raw path/contents for each icon (without the wrapping <svg>). Stroke-based, 24x24 viewBox.
const PATHS = {
  search: '<circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/>',
  heart:
    '<path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.29 1.51 4.04 3 5.5l7 7Z"/>',
  bookmark: '<path d="m19 21-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2Z"/>',
  fire:
    '<path d="M12 2c1 3 4 4.5 4 8a4 4 0 0 1-8 0c0-1 .3-1.8.7-2.5C7 8.5 6 10 6 12.5a6 6 0 1 0 12 0c0-4.5-3.5-7.5-6-10.5Z"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  users:
    '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  star:
    '<path d="m12 2 2.9 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l7.1-1.01L12 2Z"/>',
  'chevron-right': '<path d="m9 18 6-6-6-6"/>',
  'chevron-left': '<path d="m15 18-6-6 6-6"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  share:
    '<circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><path d="m8.6 13.5 6.8 4M15.4 6.5l-6.8 4"/>',
  check: '<path d="M20 6 9 17l-5-5"/>',
  x: '<path d="M18 6 6 18M6 6l12 12"/>',
  settings:
    '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1Z"/>',
  logout:
    '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5"/><path d="M21 12H9"/>',
  snapchat:
    '<path d="M12 2c2.5 0 4 1.8 4 4.4 0 .9-.1 1.7-.1 2 .3.2.8.3 1.2.1.6-.2 1.1.6.5 1.1-.5.4-1.4.6-1.6 1.1-.2.6.9 2 2.6 2.6.5.2.4.9-.1 1-1 .2-1.2.4-1.4.9-.1.4.2.8-.3 1-.5.2-1.3-.2-2.2 0-.8.2-1.3 1.3-2.6 1.3s-1.8-1.1-2.6-1.3c-.9-.2-1.7.2-2.2 0-.5-.2-.2-.6-.3-1-.2-.5-.4-.7-1.4-.9-.5-.1-.6-.8-.1-1 1.7-.6 2.8-2 2.6-2.6-.2-.5-1.1-.7-1.6-1.1-.6-.5-.1-1.3.5-1.1.4.2.9.1 1.2-.1 0-.3-.1-1.1-.1-2C8 3.8 9.5 2 12 2Z"/>',
  instagram:
    '<rect x="3" y="3" width="18" height="18" rx="5"/><circle cx="12" cy="12" r="4"/><circle cx="17.5" cy="6.5" r="1" fill="currentColor" stroke="none"/>',
  'map-pin':
    '<path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/>',
  filter: '<path d="M22 3H2l8 9.46V19l4 2v-8.54L22 3Z"/>',
  sparkles:
    '<path d="M12 3l1.9 4.6L18.5 9.5 13.9 11.4 12 16l-1.9-4.6L5.5 9.5l4.6-1.9L12 3Z"/><path d="M19 14l.8 2 2 .8-2 .8-.8 2-.8-2-2-.8 2-.8.8-2Z"/><path d="M5 14l.6 1.5L7 16l-1.4.5L5 18l-.5-1.5L3 16l1.5-.5L5 14Z"/>',
  comment:
    '<path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5Z"/>',
  flag:
    '<path d="M4 22V4s1-1 4-1 5 2 8 2 4-1 4-1v11s-1 1-4 1-5-2-8-2-4 1-4 1"/>',
};

/**
 * icon(name, attrs) -> SVG string.
 * @param {string} name  one of the keys in PATHS
 * @param {object} attrs optional: { size, class, stroke-width, ...any svg attr }
 */
export function icon(name, attrs = {}) {
  const body = PATHS[name];
  if (!body) {
    // Fail soft — unknown icons render an empty (but valid) svg so the UI never breaks.
    return '<svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true"></svg>';
  }
  const size = attrs.size != null ? attrs.size : 24;
  const cls = attrs.class ? ` class="${attrs.class}"` : '';
  const sw = attrs['stroke-width'] != null ? attrs['stroke-width'] : 2;
  // Collect any extra passthrough attributes (skip the ones we handle explicitly).
  const skip = new Set(['size', 'class', 'stroke-width']);
  const extra = Object.keys(attrs)
    .filter((k) => !skip.has(k))
    .map((k) => ` ${k}="${attrs[k]}"`)
    .join('');
  return (
    `<svg${cls} viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" ` +
    `stroke="currentColor" stroke-width="${sw}" stroke-linecap="round" ` +
    `stroke-linejoin="round" aria-hidden="true"${extra}>${body}</svg>`
  );
}

/**
 * The Chicago six-pointed star as a standalone SVG string. Optionally filled with the
 * city-night gradient. Used as the logo accent and the empty-state motif.
 */
export function starSVG(attrs = {}) {
  const size = attrs.size != null ? attrs.size : 28;
  const gradId = `wyd-star-grad-${Math.random().toString(36).slice(2, 8)}`;
  const fill = attrs.gradient === false ? 'currentColor' : `url(#${gradId})`;
  // A clean six-pointed (Star of David style) star matching the Chicago flag motif.
  const points = '12 1 14.6 8.2 22 8.2 16 12.9 18.3 20 12 15.6 5.7 20 8 12.9 2 8.2 9.4 8.2';
  return (
    `<svg class="${attrs.class || ''}" viewBox="0 0 24 24" width="${size}" height="${size}" ` +
    `aria-hidden="true" xmlns="http://www.w3.org/2000/svg">` +
    `<defs><linearGradient id="${gradId}" x1="0" y1="0" x2="1" y2="1">` +
    `<stop offset="0" stop-color="#5B8CFF"/>` +
    `<stop offset="0.55" stop-color="#C44CFF"/>` +
    `<stop offset="1" stop-color="#FF4D6D"/>` +
    `</linearGradient></defs>` +
    `<polygon points="${points}" fill="${fill}"/></svg>`
  );
}

/**
 * logoSVG() -> the full WYD wordmark with the gradient + the six-pointed star accent.
 * Returns inline SVG so it scales crisply in the app bar and the hero.
 */
export function logoSVG(attrs = {}) {
  const h = attrs.size != null ? attrs.size : 30;
  const gradId = `wyd-logo-grad-${Math.random().toString(36).slice(2, 8)}`;
  // viewBox sized to fit "WYD" + a star. Star drawn as a polygon at the right.
  const star = '110 6 112 12 118 12 113 16 115 22 110 18.5 105 22 107 16 102 12 108 12';
  return (
    `<svg class="wyd-logo ${attrs.class || ''}" viewBox="-2 0 124 32" height="${h}" ` +
    `role="img" aria-label="WYD Chicago" xmlns="http://www.w3.org/2000/svg">` +
    `<defs><linearGradient id="${gradId}" x1="0" y1="0" x2="1" y2="1">` +
    `<stop offset="0" stop-color="#5B8CFF"/>` +
    `<stop offset="0.55" stop-color="#C44CFF"/>` +
    `<stop offset="1" stop-color="#FF4D6D"/>` +
    `</linearGradient></defs>` +
    `<text x="0" y="25" font-family="'Space Grotesk', sans-serif" font-weight="700" ` +
    `font-size="26" letter-spacing="-1" fill="url(#${gradId})">WYD</text>` +
    `<polygon points="${star}" fill="url(#${gradId})"/></svg>`
  );
}
