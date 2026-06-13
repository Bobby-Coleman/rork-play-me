#!/usr/bin/env node

// One-shot backfill for `users/{uid}/friends/{friendId}.avatarURL`.
//
// Why this exists:
//   Friend docs snapshot the friend's avatarURL at friendship creation.
//   Until the `onUserAvatarChanged` trigger shipped (June 2026), profile
//   photo changes only landed on `users/{uid}` — so existing friend docs
//   hold stale or missing avatarURLs and friends render as initials in
//   the inbox. This script syncs every reciprocal friend doc from the
//   current user docs. Going forward the trigger keeps them in sync.
//
// Safety:
//   - Idempotent. Re-running re-stamps the same values.
//   - Read-only by default. Pass --write to actually mutate.
//   - Uses `update` (never `set`) so missing reciprocal docs are skipped
//     rather than created (creation would fire onFriendCreated and
//     corrupt friendCount).
//   - Logs every change so the run is auditable.
//
// Usage:
//   # Dry run — prints what would change without writing.
//   GOOGLE_APPLICATION_CREDENTIALS=functions/scripts/service-account.json \
//     node functions/scripts/backfill-friend-avatars.js
//
//   # Live run — actually writes.
//   GOOGLE_APPLICATION_CREDENTIALS=functions/scripts/service-account.json \
//     node functions/scripts/backfill-friend-avatars.js --write
//
//   # Scope to a single user (testing).
//   GOOGLE_APPLICATION_CREDENTIALS=functions/scripts/service-account.json \
//     node functions/scripts/backfill-friend-avatars.js --uid=ABC123 --write

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

// Syncs `users/{friendId}/friends/{uid}.avatarURL` for every friend of
// `uid` to match the user doc's current avatarURL.
async function backfillOne(uid, avatarURL) {
  const friendsSnap = await db
    .collection("users")
    .doc(uid)
    .collection("friends")
    .select()
    .get();
  if (friendsSnap.empty) {
    return { uid, status: "skip_no_friends", updated: 0, missing: 0 };
  }

  const hasURL = typeof avatarURL === "string" && avatarURL.trim() !== "";
  let updated = 0;
  let alreadyCorrect = 0;
  let missing = 0;

  for (const doc of friendsSnap.docs) {
    const reciprocalRef = db
      .collection("users")
      .doc(doc.id)
      .collection("friends")
      .doc(uid);
    const reciprocal = await reciprocalRef.get();
    if (!reciprocal.exists) {
      missing += 1;
      continue;
    }
    const stored = reciprocal.data().avatarURL || null;
    const desired = hasURL ? avatarURL : null;
    if (stored === desired) {
      alreadyCorrect += 1;
      continue;
    }
    if (shouldWrite) {
      await reciprocalRef.update({
        avatarURL: hasURL ? avatarURL : admin.firestore.FieldValue.delete(),
      });
    }
    updated += 1;
  }

  const status = updated > 0 ? (shouldWrite ? "wrote" : "would_write") : "skip_already_correct";
  return { uid, status, updated, alreadyCorrect, missing };
}

async function main() {
  console.log(`Project: ${projectId}`);
  console.log(`Mode:    ${shouldWrite ? "WRITE" : "dry-run (pass --write to commit)"}`);

  // Collect (uid, avatarURL) pairs. select("avatarURL") keeps the page
  // payload minimal.
  let users = [];
  if (targetUid) {
    const snap = await db.collection("users").doc(targetUid).get();
    if (!snap.exists) {
      console.log(`No user doc for ${targetUid}`);
      return;
    }
    users = [{ uid: targetUid, avatarURL: snap.data().avatarURL || null }];
    console.log(`Scope:   single uid (${targetUid})`);
  } else {
    console.log("Scope:   all users");
    let lastDoc = null;
    while (true) {
      let q = db.collection("users").select("avatarURL").orderBy("__name__").limit(500);
      if (lastDoc) q = q.startAfter(lastDoc);
      const page = await q.get();
      if (page.empty) break;
      page.docs.forEach((d) => users.push({ uid: d.id, avatarURL: d.data().avatarURL || null }));
      lastDoc = page.docs[page.docs.length - 1];
      if (page.size < 500) break;
    }
  }

  console.log(`Users:   ${users.length}`);
  console.log("");

  // Waves of 10 — each user fans out to up to 20 reciprocal reads.
  const wave = 10;
  const summary = { wrote: 0, would_write: 0, skip_already_correct: 0, skip_no_friends: 0 };
  let totalUpdated = 0;
  let totalMissing = 0;
  for (let i = 0; i < users.length; i += wave) {
    const slice = users.slice(i, i + wave);
    const results = await Promise.all(slice.map((u) => backfillOne(u.uid, u.avatarURL)));
    for (const r of results) {
      summary[r.status] = (summary[r.status] || 0) + 1;
      totalUpdated += r.updated;
      totalMissing += r.missing || 0;
      const arrow =
        r.status === "wrote" ? "->" : r.status === "would_write" ? "?>" : "==";
      console.log(
        `  ${arrow} ${r.uid}  updated=${r.updated}  missingReciprocal=${r.missing || 0}  (${r.status})`
      );
    }
  }

  console.log("");
  console.log("Summary:");
  console.log(`  Users with writes:     ${(summary.wrote || 0) + (summary.would_write || 0)}`);
  console.log(`  Friend docs updated:   ${totalUpdated}${shouldWrite ? "" : " (dry)"}`);
  console.log(`  Missing reciprocals:   ${totalMissing}`);
  console.log(`  Already correct:       ${summary.skip_already_correct || 0}`);
  console.log(`  No friends:            ${summary.skip_no_friends || 0}`);
  console.log(`  Total processed:       ${users.length}`);

  if (!shouldWrite && totalUpdated > 0) {
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
