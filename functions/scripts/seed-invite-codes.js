#!/usr/bin/env node

// Seed invite codes for the RIFF onboarding gate. Codes live at
// `inviteCodes/{CODE_UPPER}` and are consumed by the validateInviteCode /
// redeemInviteCode callables in `functions/index.js`.
//
// Usage:
//   # Dry run — print 20 randomly-generated codes
//   node functions/scripts/seed-invite-codes.js --count=20
//
//   # Write to Firestore
//   GOOGLE_APPLICATION_CREDENTIALS=path/to/service-account.json \
//     node functions/scripts/seed-invite-codes.js --count=20 --write
//
//   # Seed an explicit code list
//   node functions/scripts/seed-invite-codes.js --codes=RIFF99,FRIEND01,DROP07 --write
//
//   # Multi-use code (e.g. 50 redemptions)
//   node functions/scripts/seed-invite-codes.js --codes=LAUNCH --max-uses=50 --write
//
// Defaults:
//   --count=20     when neither --codes nor --count is supplied
//   --max-uses=1   single-use codes
//   no expiry      omit `expiresAt` so codes never expire

const admin = require("firebase-admin");

const projectId =
  process.env.FIREBASE_PROJECT_ID ||
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  "rork-play-me";

const args = process.argv.slice(2);
const shouldWrite = args.includes("--write");
const codesArg = args.find((a) => a.startsWith("--codes="));
const countArg = args.find((a) => a.startsWith("--count="));
const maxUsesArg = args.find((a) => a.startsWith("--max-uses="));
const expiresInDaysArg = args.find((a) => a.startsWith("--expires-in-days="));

const explicitCodes = codesArg
  ? codesArg.slice("--codes=".length).split(",").map((s) => s.trim().toUpperCase()).filter(Boolean)
  : null;
const count = countArg ? parseInt(countArg.slice("--count=".length), 10) : 20;
const maxUses = maxUsesArg ? parseInt(maxUsesArg.slice("--max-uses=".length), 10) : 1;
const expiresInDays = expiresInDaysArg ? parseInt(expiresInDaysArg.slice("--expires-in-days="), 10) : null;

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no I/O/0/1 to avoid confusion
function randomCode(length = 6) {
  let out = "";
  for (let i = 0; i < length; i++) {
    out += ALPHABET[Math.floor(Math.random() * ALPHABET.length)];
  }
  return out;
}

function buildPayload() {
  const payload = {
    redeemed: false,
    useCount: 0,
    maxUses,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (expiresInDays && Number.isFinite(expiresInDays)) {
    const expiresAt = new Date(Date.now() + expiresInDays * 24 * 60 * 60 * 1000);
    payload.expiresAt = admin.firestore.Timestamp.fromDate(expiresAt);
  }
  return payload;
}

async function main() {
  const codes = explicitCodes && explicitCodes.length > 0
    ? explicitCodes
    : Array.from({ length: count }, () => randomCode());

  console.log(`Project: ${projectId}`);
  console.log(`Mode:    ${shouldWrite ? "WRITE" : "dry-run (use --write to commit)"}`);
  console.log(`Codes (${codes.length}):`);
  for (const c of codes) console.log("  -", c);

  if (!shouldWrite) return;

  admin.initializeApp({ projectId });
  const db = admin.firestore();
  const batch = db.batch();
  for (const code of codes) {
    batch.set(db.collection("inviteCodes").doc(code), buildPayload(), { merge: true });
  }
  await batch.commit();
  console.log(`✓ Wrote ${codes.length} invite codes.`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
