#!/usr/bin/env node

/**
 * Removes legacy public `users/{uid}.phone` values.
 *
 * Run against staging first:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/staging-service-account.json \
 *   FIREBASE_PROJECT_ID=riff-staging \
 *   node scripts/cleanup-public-user-phone.js --dry-run
 *
 * Then remove --dry-run to apply. Never run this without explicitly setting
 * FIREBASE_PROJECT_ID so production cleanup is intentional.
 */

const admin = require("firebase-admin");

const DRY_RUN = process.argv.includes("--dry-run");
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID;

if (!PROJECT_ID) {
  console.error("Set FIREBASE_PROJECT_ID before running cleanup-public-user-phone.js");
  process.exit(1);
}

admin.initializeApp({ projectId: PROJECT_ID });

async function main() {
  const db = admin.firestore();
  let scanned = 0;
  let cleaned = 0;
  let cursor = null;

  for (;;) {
    let query = db.collection("users").orderBy(admin.firestore.FieldPath.documentId()).limit(500);
    if (cursor) query = query.startAfter(cursor);

    const snap = await query.get();
    if (snap.empty) break;

    const batch = db.batch();
    for (const doc of snap.docs) {
      scanned += 1;
      cursor = doc;
      const data = doc.data() || {};
      if (!Object.prototype.hasOwnProperty.call(data, "phone")) continue;

      cleaned += 1;
      if (!DRY_RUN) {
        batch.update(doc.ref, {
          phone: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    if (!DRY_RUN) await batch.commit();
    if (snap.size < 500) break;
  }

  console.log(
    JSON.stringify({
      event: "cleanup_public_user_phone_complete",
      projectId: PROJECT_ID,
      dryRun: DRY_RUN,
      scanned,
      cleaned,
    })
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
