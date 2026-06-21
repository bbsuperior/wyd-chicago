/**
 * WYD Chicago — Cloud Functions (v2, JavaScript, Node 20)
 * =======================================================
 * Responsibilities (PROJECT_CANON.md §4 "Counters & recommendation", §7):
 *
 *  1. Keep event counters denormalized & accurate:
 *       - attendees subcollection  -> committedCount / interestedCount
 *       - votes subcollection      -> upvotes / downvotes / voteScore
 *     We use atomic FieldValue.increment() so concurrent RSVPs/votes don't
 *     clobber each other (a lightweight distributed-counter pattern: each
 *     write applies a delta rather than reading-then-writing the total).
 *
 *  2. Bootstrap a default users/{uid} profile when a new auth user is created.
 *
 *  3. setUserRole — a callable that lets an EXISTING admin promote a user to
 *     "host" or "admin" (sets both the custom claim and users/{uid}.role).
 *
 *  4. refreshRecommendations — an OPTIONAL nightly scheduled stub.
 *
 * NOTE ON EMAIL VERIFICATION: Firebase has no native "email verified" trigger.
 * The welcome message is best handled client-side right after the user clicks
 * the verification link, or via a beforeUserSignedIn blocking function. A
 * documented stub (markWelcomeOnVerify) is provided below for the client to
 * call once.
 *
 * DEPLOYMENT: Functions require the Blaze (pay-as-you-go) plan. See README.md.
 */

const { onDocumentCreated, onDocumentDeleted, onDocumentUpdated } =
  require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { beforeUserCreated } = require("firebase-functions/v2/identity");
const { setGlobalOptions } = require("firebase-functions/v2");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();
const { FieldValue } = admin.firestore;

// Keep all functions in one region for predictable latency/costs.
setGlobalOptions({ region: "us-central1", maxInstances: 10 });

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Apply a set of FieldValue.increment deltas to an event doc, ignoring
 * "not found" (the event may have been deleted in the same window).
 */
async function bumpEvent(eventId, deltas) {
  const ref = db.collection("events").doc(eventId);
  try {
    await ref.set(
      { ...deltas, updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
  } catch (err) {
    logger.warn(`bumpEvent failed for ${eventId}`, err);
  }
}

// Maps an attendee status to the counter field it affects.
function attendeeField(status) {
  if (status === "going") return "committedCount";
  if (status === "interested") return "interestedCount";
  return null;
}

// ---------------------------------------------------------------------------
// 1a. Attendee counters: events/{eventId}/attendees/{uid}
// ---------------------------------------------------------------------------

exports.onAttendeeCreated = onDocumentCreated(
  "events/{eventId}/attendees/{uid}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const field = attendeeField(data.status);
    if (!field) return;
    await bumpEvent(event.params.eventId, { [field]: FieldValue.increment(1) });
  }
);

exports.onAttendeeDeleted = onDocumentDeleted(
  "events/{eventId}/attendees/{uid}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const field = attendeeField(data.status);
    if (!field) return;
    await bumpEvent(event.params.eventId, { [field]: FieldValue.increment(-1) });
  }
);

exports.onAttendeeUpdated = onDocumentUpdated(
  "events/{eventId}/attendees/{uid}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === after.status) return; // no counter-relevant change

    const deltas = {};
    const oldField = attendeeField(before.status);
    const newField = attendeeField(after.status);
    if (oldField) deltas[oldField] = FieldValue.increment(-1);
    if (newField) {
      // If both map to the same field this cancels out to 0 — but statuses
      // differ here, so they never collide.
      deltas[newField] = FieldValue.increment(1);
    }
    if (Object.keys(deltas).length) {
      await bumpEvent(event.params.eventId, deltas);
    }
  }
);

// ---------------------------------------------------------------------------
// 1b. Vote counters: events/{eventId}/votes/{uid}
//     dir: 1 (up) | -1 (down). voteScore = upvotes - downvotes.
// ---------------------------------------------------------------------------

function voteDeltas(dir, sign) {
  // sign = +1 when adding this vote, -1 when removing it.
  const deltas = { voteScore: FieldValue.increment(dir * sign) };
  if (dir === 1) deltas.upvotes = FieldValue.increment(sign);
  else if (dir === -1) deltas.downvotes = FieldValue.increment(sign);
  return deltas;
}

exports.onVoteCreated = onDocumentCreated(
  "events/{eventId}/votes/{uid}",
  async (event) => {
    const data = event.data?.data();
    if (!data || (data.dir !== 1 && data.dir !== -1)) return;
    await bumpEvent(event.params.eventId, voteDeltas(data.dir, 1));
  }
);

exports.onVoteDeleted = onDocumentDeleted(
  "events/{eventId}/votes/{uid}",
  async (event) => {
    const data = event.data?.data();
    if (!data || (data.dir !== 1 && data.dir !== -1)) return;
    await bumpEvent(event.params.eventId, voteDeltas(data.dir, -1));
  }
);

exports.onVoteUpdated = onDocumentUpdated(
  "events/{eventId}/votes/{uid}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.dir === after.dir) return; // flipped vote only

    // Compute the net change numerically (we can't read increment sentinels),
    // then emit one FieldValue.increment per affected field. We remove the old
    // vote's effect (-1) and add the new vote's effect (+1).
    const numeric = {};
    function addNumeric(dir, sign) {
      numeric.voteScore = (numeric.voteScore || 0) + dir * sign;
      if (dir === 1) numeric.upvotes = (numeric.upvotes || 0) + sign;
      else if (dir === -1) numeric.downvotes = (numeric.downvotes || 0) + sign;
    }
    addNumeric(before.dir, -1);
    addNumeric(after.dir, 1);

    const finalDeltas = {};
    for (const [k, n] of Object.entries(numeric)) {
      if (n !== 0) finalDeltas[k] = FieldValue.increment(n);
    }
    if (Object.keys(finalDeltas).length) {
      await bumpEvent(event.params.eventId, finalDeltas);
    }
  }
);

// ---------------------------------------------------------------------------
// 2. New-user profile bootstrap (blocking beforeUserCreated)
//    Writes a default users/{uid} doc with role "user". A blocking function
//    runs synchronously at sign-up, so the profile exists before the client's
//    first read. (Requires Identity Platform / Blaze.)
// ---------------------------------------------------------------------------

exports.onUserCreate = beforeUserCreated(async (event) => {
  const user = event.data;
  if (!user) return;

  const uid = user.uid;
  const email = user.email || null;

  // Derive a starter username from the email local-part, sanitized to the
  // canonical handle charset [a-z0-9_], 3–20 chars. Users can change it later.
  let base = (email ? email.split("@")[0] : "wyd_user")
    .toLowerCase()
    .replace(/[^a-z0-9_]/g, "")
    .slice(0, 20);
  if (base.length < 3) base = `wyd_${uid.slice(0, 6).toLowerCase()}`;

  const profile = {
    displayName: user.displayName || base,
    username: base,
    avatarUrl: user.photoURL || null,
    bio: "",
    birthYear: null,
    gradeYear: null,
    neighborhood: null,
    interests: [],
    snapchatUsername: null,
    instagramUsername: null,
    role: "user",
    savedEvents: [],
    emailVerified: !!user.emailVerified,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  try {
    // Don't clobber an existing profile (e.g. provider re-link).
    await db.collection("users").doc(uid).set(profile, { merge: true });
    logger.info(`Bootstrapped profile for ${uid}`);
  } catch (err) {
    // Never block sign-up on a profile-write hiccup; log and continue.
    logger.error(`Failed to bootstrap profile for ${uid}`, err);
  }
  // Returning nothing accepts the user creation unchanged.
});

// ---------------------------------------------------------------------------
// 3. setUserRole — callable, admin-only role management.
//    An existing admin promotes/demotes a target user to "user"|"host"|"admin".
//    Sets the custom claim (admin/host) AND mirrors users/{uid}.role.
// ---------------------------------------------------------------------------

const VALID_ROLES = ["user", "host", "admin"];

exports.setUserRole = onCall(async (request) => {
  // Reject anyone whose token is not admin:true (the "master login").
  if (request.auth?.token?.admin !== true) {
    throw new HttpsError(
      "permission-denied",
      "Only an existing admin can change user roles."
    );
  }

  const { uid, role } = request.data || {};
  if (typeof uid !== "string" || !uid) {
    throw new HttpsError("invalid-argument", "A target 'uid' is required.");
  }
  if (!VALID_ROLES.includes(role)) {
    throw new HttpsError(
      "invalid-argument",
      `'role' must be one of: ${VALID_ROLES.join(", ")}.`
    );
  }

  // Custom claims map: admin implies host privileges too.
  const claims = {
    admin: role === "admin",
    host: role === "admin" || role === "host",
  };

  try {
    await admin.auth().setCustomUserClaims(uid, claims);
    await db
      .collection("users")
      .doc(uid)
      .set(
        { role, updatedAt: FieldValue.serverTimestamp() },
        { merge: true }
      );
  } catch (err) {
    logger.error(`setUserRole failed for ${uid}`, err);
    throw new HttpsError("internal", "Could not update the user's role.");
  }

  logger.info(`Admin ${request.auth.uid} set ${uid} -> ${role}`);
  return {
    ok: true,
    uid,
    role,
    note: "The target must refresh their ID token for the new claim to apply.",
  };
});

// ---------------------------------------------------------------------------
// 3b. markWelcomeOnVerify — callable the CLIENT calls once, right after the
//     user verifies their email (Firebase has no server-side verify trigger).
//     Mirrors emailVerified onto the profile and flags the welcome as sent.
// ---------------------------------------------------------------------------

exports.markWelcomeOnVerify = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  if (request.auth.token.email_verified !== true) {
    throw new HttpsError(
      "failed-precondition",
      "Email isn't verified yet — verify, then call this again."
    );
  }
  const uid = request.auth.uid;
  await db.collection("users").doc(uid).set(
    {
      emailVerified: true,
      welcomeSentAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return { ok: true };
});

// ---------------------------------------------------------------------------
// 4. refreshRecommendations — OPTIONAL nightly scheduled stub.
//    The recommendation score is client-computable today (PROJECT_CANON.md §4);
//    this is where a server-side precompute would live later. Left as a
//    documented no-op so the schedule exists and deploys cleanly.
// ---------------------------------------------------------------------------

exports.refreshRecommendations = onSchedule(
  { schedule: "every day 04:00", timeZone: "America/Chicago" },
  async () => {
    // OPTIONAL / FUTURE: precompute per-user or per-event recommendation
    // signals (e.g. trending decay on voteScore, neighborhood popularity).
    // For now the clients compute recommendScore on the fly, so this is a
    // documented stub that simply logs a heartbeat.
    logger.info("refreshRecommendations heartbeat — no-op stub (optional).");
  }
);
