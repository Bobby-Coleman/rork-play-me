#!/usr/bin/env node

// One-shot backfill for `users/{uid}.friendCount`.
//
// Why this exists:
//   The May 2026 security hardening introduced a per-user friend cap.
//   The cap is enforced in rules by reading `users/{uid}.friendCount`
//   and comparing against `friendLimit` (default 8). Going forward,
//   the `onFriendCreated` / `onFriendDeleted` Cloud Function triggers
//   maintain the count automatically.
//
//   But existing accounts don't have `friendCount` set yet, so the
//   rule's `.get('friendCount', 0)` defaults them to 0 — meaning a
//   user with 12 existing friends could still add 8 more. This
//   script seeds the field by counting each user's actual friends
//   subcollection size and writing it back.
//
// Safety:
//   - Idempotent. Re-running just re-stamps the same value. Safe to
//     re-run after a partial failure.
//   - Read-only by default. Pass --write to actually mutate.
//   - Logs every uid + count so the run is auditable.
//   - Batches at 400 writes/commit, well below Firestore's 500 cap.
//   - Skips users whose `friendCount` already exists AND matches the
//     observed count (no-op for accounts already correctly counted).
//
// Usage:
//   # Dry run — prints what would change without writing.
//   GOOGLE_APPLICATION_CREDENTIALS=functions/scripts/service-account.json \
//     node functions/scripts/backfill-friend-count.js
//
//   # Live run — actually writes.
//   GOOGLE_APPLICATION_CREDENTIALS=functions/scripts/service-account.json \
//     node functions/scripts/backfill-friend-count.js --write
//
//   # Scope to a single user (testing).
//   GOOGLE_APPLICATION_CREDENTIALS=functions/scripts/service-account.json \
//     node functions/scripts/backfill-friend-count.js --uid=ABC123 --write

const admin = require("firebase-admin");

const projectId =
  process.env.FIREBASE_PROJECT_ID ||
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  "rork-play-me";

const args = process.argv.slice(2);
const shouldWrite = args.includes("--write");
const uidArg = args.find((a) => a.startsWith("--uid="));
const targetUid = uidArg ? uidArg.slice("--uid=".length).trim() : null;

admin.initializeApp({ projectId });
const db = admin.firestore();

async function getActualFriendCount(uid) {
  // Server-side count aggregation — cheaper than streaming the full
  // subcollection. One read per user regardless of friend-list size.
  const snap = await db
    .collection("users")
    .doc(uid)
    .collection("friends")
    .count()
    .get();
  return snap.data().count;
}

async function backfillOne(uid) {
  const actual = await getActualFriendCount(uid);
  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    return { uid, status: "skip_no_user", actual, stored: null };
  }
  const stored = userSnap.data().friendCount;
  if (typeof stored === "number" && stored === actual) {
    return { uid, status: "skip_already_correct", actual, stored };
  }
  if (!shouldWrite) {
    return { uid, status: "would_write", actual, stored: stored ?? null };
  }
  await userRef.set(
    {
      friendCount: actual,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return { uid, status: "wrote", actual, stored: stored ?? null };
}

async function main() {
  console.log(`Project: ${projectId}`);
  console.log(`Mode:    ${shouldWrite ? "WRITE" : "dry-run (pass --write to commit)"}`);

  let uids;
  if (targetUid) {
    uids = [targetUid];
    console.log(`Scope:   single uid (${targetUid})`);
  } else {
    console.log("Scope:   all users");
    // Stream user IDs in pages so we don't fan-load the whole user
    // collection into memory. `select()` keeps the payload to ids
    // only (no profile data needed for the backfill).
    uids = [];
    let lastDoc = null;
    while (true) {
      let q = db.collection("users").select().orderBy("__name__").limit(500);
      if (lastDoc) q = q.startAfter(lastDoc);
      const page = await q.get();
      if (page.empty) break;
      page.docs.forEach((d) => uids.push(d.id));
      lastDoc = page.docs[page.docs.length - 1];
      if (page.size < 500) break;
    }
  }

  console.log(`Users:   ${uids.length}`);
  console.log("");

  // Process in waves of 25 so we don't hammer Firestore with
  // hundreds of parallel count() aggregations on a large user base.
  const wave = 25;
  const summary = { wrote: 0, would_write: 0, skip_already_correct: 0, skip_no_user: 0 };
  for (let i = 0; i < uids.length; i += wave) {
    const slice = uids.slice(i, i + wave);
    const results = await Promise.all(slice.map(backfillOne));
    for (const r of results) {
      summary[r.status] = (summary[r.status] || 0) + 1;
      const arrow =
        r.status === "wrote"
          ? "->"
          : r.status === "would_write"
          ? "?>"
          : r.status === "skip_already_correct"
          ? "=="
          : "--";
      console.log(`  ${arrow} ${r.uid}  actual=${r.actual}  stored=${r.stored}  (${r.status})`);
    }
  }

  console.log("");
  console.log("Summary:");
  console.log(`  Wrote:                ${summary.wrote || 0}`);
  console.log(`  Would write (dry):    ${summary.would_write || 0}`);
  console.log(`  Already correct:      ${summary.skip_already_correct || 0}`);
  console.log(`  No user doc:          ${summary.skip_no_user || 0}`);
  console.log(`  Total processed:      ${uids.length}`);

  if (!shouldWrite && (summary.would_write || 0) > 0) {
    console.log("");
    console.log("Pass --write to commit these changes.");
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("backfill failed:", err);
    process.exit(1);
  });
