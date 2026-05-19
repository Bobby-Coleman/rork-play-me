#!/usr/bin/env node
const admin = require("firebase-admin");
const code = (process.argv[2] || "").toUpperCase();
const shouldWrite = process.argv.includes("--write");
if (!code) {
  console.error("Usage: node disable-invite-code.js CODE [--write]");
  process.exit(1);
}
admin.initializeApp({ projectId: "rork-play-me" });
const db = admin.firestore();
(async () => {
  const ref = db.collection("inviteCodes").doc(code);
  const snap = await ref.get();
  if (!snap.exists) {
    console.log(`inviteCodes/${code} not found`);
    return;
  }
  console.log("Current:", snap.data());
  if (!shouldWrite) {
    console.log("Pass --write to disable");
    return;
  }
  await ref.update({
    disabled: true,
    disabledAt: admin.firestore.FieldValue.serverTimestamp(),
    disabledReason: "replaced_by_new_launch_code",
  });
  console.log(`Disabled ${code}`);
})();
