#!/usr/bin/env node
/**
 * WYD Chicago — Firestore seed script
 * ------------------------------------
 * Uploads the canonical tag set (tags.json) and ~12 demo events (events.json)
 * into a fresh Firestore database using the Firebase Admin SDK.
 *
 * Idempotent: tag/event ids are used as document ids, so re-running it
 * overwrites instead of duplicating.
 *
 * SAFETY (PROJECT_CANON.md §8): the public events/{id} document must NEVER
 * carry `exactAddress`. This script strips `exactAddress` out of the event
 * doc and writes it to the protected sub-path events/{id}/private/location,
 * which the security rules only expose to admins + "going" attendees.
 *
 * ── How to run ───────────────────────────────────────────────────────────
 * 1. In the Firebase console: Project settings → Service accounts →
 *    "Generate new private key". Save the file as serviceAccountKey.json
 *    SOMEWHERE OUTSIDE this repo (it is gitignored, but keep it safe).
 * 2. Point the env var at it and run:
 *
 *      export GOOGLE_APPLICATION_CREDENTIALS="/abs/path/to/serviceAccountKey.json"
 *      node firebase/seed/seed.mjs
 *
 *    (Optional) override the project id:
 *      export FIREBASE_PROJECT_ID="wyd-chicago"
 *
 *    To run against the local emulator instead of production:
 *      export FIRESTORE_EMULATOR_HOST="127.0.0.1:8080"
 *      node firebase/seed/seed.mjs
 */

import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { initializeApp, applicationDefault } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

const __dirname = dirname(fileURLToPath(import.meta.url));

async function loadJson(name) {
  const raw = await readFile(join(__dirname, name), "utf8");
  return JSON.parse(raw);
}

function buildCredential() {
  const keyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  const usingEmulator = !!process.env.FIRESTORE_EMULATOR_HOST;

  if (keyPath) {
    // Explicit service-account file (production path).
    return { credential: applicationDefault() };
  }
  if (usingEmulator) {
    // Emulator doesn't validate creds; a project id is enough.
    return {};
  }
  console.error(
    "\n✗ No credentials found.\n" +
      "  Set GOOGLE_APPLICATION_CREDENTIALS to your serviceAccountKey.json path,\n" +
      "  or set FIRESTORE_EMULATOR_HOST to seed the local emulator.\n"
  );
  process.exit(1);
}

async function main() {
  const projectId = process.env.FIREBASE_PROJECT_ID || "wyd-chicago";
  const initOpts = buildCredential();
  initializeApp({ ...initOpts, projectId });

  const db = getFirestore();
  const now = Timestamp.now();

  const [tags, events] = await Promise.all([
    loadJson("tags.json"),
    loadJson("events.json"),
  ]);

  // ---- tags ---------------------------------------------------------------
  console.log(`Seeding ${tags.length} tags…`);
  let batch = db.batch();
  for (const tag of tags) {
    const { id, ...data } = tag;
    batch.set(db.collection("tags").doc(id), data, { merge: true });
  }
  await batch.commit();
  console.log("  ✓ tags written");

  // ---- events -------------------------------------------------------------
  console.log(`Seeding ${events.length} events…`);
  for (const ev of events) {
    const { id, exactAddress, startAt, endAt, ...rest } = ev;

    // Public event doc — counters zeroed, status published, NO exactAddress.
    const eventDoc = {
      ...rest,
      startAt: Timestamp.fromDate(new Date(startAt)),
      endAt: endAt ? Timestamp.fromDate(new Date(endAt)) : null,
      committedCount: 0,
      interestedCount: 0,
      upvotes: 0,
      downvotes: 0,
      voteScore: 0,
      status: "published",
      createdBy: "seed",
      createdAt: now,
      updatedAt: now,
    };

    const ref = db.collection("events").doc(id);
    await ref.set(eventDoc, { merge: true });

    // Protected exact address → events/{id}/private/location.
    if (exactAddress) {
      await ref
        .collection("private")
        .doc("location")
        .set({ exactAddress, updatedAt: now }, { merge: true });
    }
    console.log(`  ✓ ${id}`);
  }

  console.log(
    `\n✓ Done. Seeded ${tags.length} tags and ${events.length} demo events into "${projectId}".\n` +
      "  All events are fictional demo content (see PROJECT_CANON.md §9).\n"
  );
  // Touch FieldValue so linters don't flag the import as unused; it's part of
  // the public Admin surface and handy if you extend this script.
  void FieldValue;
}

main().catch((err) => {
  console.error("✗ Seed failed:", err);
  process.exit(1);
});
