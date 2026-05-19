#!/usr/bin/env node
// Delete an orphaned Firestore profile when Firebase Auth is already gone.
// Releases usernames/{username} and removes users/{uid} + subcollections.
//
// Usage:
//   GOOGLE_APPLICATION_CREDENTIALS=functions/scripts/service-account.json \
//     node functions/scripts/delete-orphan-firestore-user.js AVWk45EskbZoQz3XI0okFr6Louf2 --write

const admin = require("firebase-admin");

const projectId =
  process.env.FIREBASE_PROJECT_ID ||
  process.env.GCLOUD_PROJECT ||
  "rork-play-me";

const args = process.argv.slice(2);
const shouldWrite = args.includes("--write");
const uid = args.find((a) => !a.startsWith("--"));

if (!uid) {
  console.error("Usage: node delete-orphan-firestore-user.js <UID> [--write]");
  process.exit(1);
}

admin.initializeApp({ projectId });
const db = admin.firestore();

async function deleteCollection(ref, batchSize = 400) {
  let total = 0;
  while (true) {
    const snap = await ref.limit(batchSize).get();
    if (snap.empty) break;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    if (shouldWrite) await batch.commit();
    total += snap.size;
    if (snap.size < batchSize) break;
  }
  return total;
}

async function main() {
  console.log(`Project: ${projectId}`);
  console.log(`Mode:    ${shouldWrite ? "WRITE" : "dry-run"}`);
  console.log(`UID:     ${uid}`);
  console.log("");

  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    console.log("users/{uid} does not exist — nothing to delete.");
  } else {
    const data = userSnap.data() || {};
    console.log(`Found profile: @${data.username || "?"} (${data.firstName || ""} ${data.lastName || ""})`);
    console.log(`  public phone field: ${data.phone || "(empty)"}`);
  }

  const username = userSnap.exists ? (userSnap.data().username || "").toLowerCase() : "";
  if (username) {
    const unameRef = db.collection("usernames").doc(username);
    const unameSnap = await unameRef.get();
    if (unameSnap.exists) {
      const mapsTo = unameSnap.data()?.uid;
      console.log(`usernames/${username} exists → uid ${mapsTo}`);
      if (mapsTo !== uid) {
        console.warn(`  WARNING: username maps to different uid (${mapsTo})`);
      }
    } else {
      console.log(`usernames/${username} already missing`);
    }
  }

  if (!shouldWrite) {
    console.log("\nPass --write to delete.");
    return;
  }

  // Subcollections
  for (const sub of ["friends", "likes", "blocked", "outgoingFriendRequests", "friendRequests"]) {
    const n = await deleteCollection(userRef.collection(sub));
    if (n > 0) console.log(`  deleted ${n} from users/${uid}/${sub}`);
  }
  const privDeleted = await deleteCollection(userRef.collection("private"));
  if (privDeleted > 0) console.log(`  deleted ${privDeleted} from users/${uid}/private`);

  if (username) {
    await db.collection("usernames").doc(username).delete();
    console.log(`  deleted usernames/${username}`);
  }

  if (userSnap.exists) {
    await userRef.delete();
    console.log(`  deleted users/${uid}`);
  }

  console.log("\nDone. @bobby is free for a new signup if usernames/bobby was removed.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
