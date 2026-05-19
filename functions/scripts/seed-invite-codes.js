#!/usr/bin/env node

// Seed (or rotate) invite codes for the RIFF onboarding gate.
//
// Codes live at `inviteCodes/{CODE_UPPER}` and are consumed by the
// `validateInviteCode` / `redeemInviteCode` Cloud Functions in
// `functions/index.js`. After Phase B, each code also carries a
// `kind` (personal | creator | admin) that determines what happens
// post-redeem:
//
//   personal — server auto-friends the code's `createdByUid`
//   creator  — attribution-only ("joined via Bobby's launch code");
//              no friendship, no friend-slot consumption
//   admin    — attribution-only; no inviter at all
//
// Usage:
//
//   # Dry run — print 20 randomly-generated personal codes
//   node functions/scripts/seed-invite-codes.js --count=20
//
//   # Write personal codes
//   GOOGLE_APPLICATION_CREDENTIALS=path/to/service-account.json \
//     node functions/scripts/seed-invite-codes.js --count=20 --write
//
//   # Mint a creator code (e.g. Bobby's launch code)
//   node functions/scripts/seed-invite-codes.js \
//     --count=1 \
//     --kind=creator \
//     --created-by=BOBBYS_UID \
//     --campaign=launch \
//     --max-uses=unlimited \
//     --write
//
//   # Mint a stack of admin codes (no attribution)
//   node functions/scripts/seed-invite-codes.js \
//     --count=50 --kind=admin --campaign=press-mar26 --write
//
//   # Rotate: disable an old code and mint a new one with the same
//   # kind / createdByUid / campaign / maxUses metadata. The script
//   # prints the new code so you can re-distribute it.
//   node functions/scripts/seed-invite-codes.js --rotate=OLDCODE --write
//
//   # Explicit code list (e.g. for vanity codes or tests)
//   node functions/scripts/seed-invite-codes.js --codes=RIFF99,FRIEND01 --write
//
// Defaults:
//   --count=20           when neither --codes nor --rotate is supplied
//   --max-uses=1         single-use (use `unlimited` for creator codes)
//   --kind=personal      personal codes auto-friend on redeem
//   no expiry            omit `expiresAt`

const admin = require("firebase-admin");

const projectId =
  process.env.FIREBASE_PROJECT_ID ||
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  "rork-play-me";

const args = process.argv.slice(2);
const shouldWrite = args.includes("--write");

function flagValue(name) {
  const prefix = `--${name}=`;
  const hit = args.find((a) => a.startsWith(prefix));
  return hit ? hit.slice(prefix.length).trim() : null;
}

const codesArg = flagValue("codes");
const countArg = flagValue("count");
const maxUsesArg = flagValue("max-uses");
const expiresInDaysArg = flagValue("expires-in-days");
const kindArg = (flagValue("kind") || "personal").toLowerCase();
const createdByArg = flagValue("created-by");
const campaignArg = flagValue("campaign");
const rotateArg = flagValue("rotate");

const VALID_KINDS = new Set(["personal", "creator", "admin"]);
if (!VALID_KINDS.has(kindArg)) {
  console.error(`Invalid --kind=${kindArg}. Use personal | creator | admin.`);
  process.exit(1);
}
if (kindArg === "creator" && !createdByArg && !rotateArg) {
  console.error(
    "Creator codes must be attributed to a user. Pass --created-by=<UID>."
  );
  process.exit(1);
}

const explicitCodes = codesArg
  ? codesArg.split(",").map((s) => s.trim().toUpperCase()).filter(Boolean)
  : null;
const count = countArg ? parseInt(countArg, 10) : 20;

// `--max-uses=unlimited` -> 1,000,000 (effectively no cap; the
// validate/redeem CFs just do numeric comparisons against useCount).
let maxUses;
if (maxUsesArg === "unlimited") {
  maxUses = 1_000_000;
} else if (maxUsesArg) {
  maxUses = parseInt(maxUsesArg, 10);
  if (!Number.isFinite(maxUses) || maxUses < 1) {
    console.error(`Invalid --max-uses=${maxUsesArg}.`);
    process.exit(1);
  }
} else {
  maxUses = 1;
}
const expiresInDays = expiresInDaysArg ? parseInt(expiresInDaysArg, 10) : null;

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I
const CODE_LENGTH = 8; // matches generateInviteCode CF
function randomCode(length = CODE_LENGTH) {
  let out = "";
  for (let i = 0; i < length; i++) {
    out += ALPHABET[Math.floor(Math.random() * ALPHABET.length)];
  }
  return out;
}

function buildPayload(overrides = {}) {
  const payload = {
    kind: kindArg,
    redeemed: false,
    useCount: 0,
    maxUses,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (createdByArg) payload.createdByUid = createdByArg;
  if (campaignArg) payload.campaign = campaignArg;
  if (expiresInDays && Number.isFinite(expiresInDays)) {
    const expiresAt = new Date(Date.now() + expiresInDays * 24 * 60 * 60 * 1000);
    payload.expiresAt = admin.firestore.Timestamp.fromDate(expiresAt);
  }
  return { ...payload, ...overrides };
}

async function mintFreshCode(db, payload) {
  // Collision-check loop — same logic the generateInviteCode CF uses.
  for (let attempt = 0; attempt < 6; attempt++) {
    const candidate = randomCode();
    const ref = db.collection("inviteCodes").doc(candidate);
    const snap = await ref.get();
    if (snap.exists) continue;
    await ref.set(payload);
    return candidate;
  }
  throw new Error("Failed to find a non-colliding code after 6 attempts.");
}

async function rotate(db, oldCode) {
  const oldRef = db.collection("inviteCodes").doc(oldCode);
  const oldSnap = await oldRef.get();
  if (!oldSnap.exists) {
    throw new Error(`Cannot rotate: inviteCodes/${oldCode} does not exist.`);
  }
  const oldData = oldSnap.data() || {};
  // Carry forward the metadata that defines this code's purpose.
  // Things like `useCount` / `redeemedBy` are NOT copied — the new code
  // starts fresh. `expiresAt` is dropped (rotation usually means "this
  // code lasts as long as the campaign"), pass --expires-in-days again
  // if you want one on the new code.
  const carry = {
    kind: oldData.kind || "personal",
    maxUses: typeof oldData.maxUses === "number" ? oldData.maxUses : 1,
  };
  // `--created-by` on rotate overrides the old code's uid (e.g. after
  // deleting an orphan profile and signing up with a fresh Auth uid).
  if (createdByArg) {
    carry.createdByUid = createdByArg;
  } else if (oldData.createdByUid) {
    carry.createdByUid = oldData.createdByUid;
  }
  if (oldData.campaign) carry.campaign = oldData.campaign;

  const newPayload = {
    ...carry,
    redeemed: false,
    useCount: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    rotatedFrom: oldCode,
  };

  // Two-step: mint the new doc first so we never end up with the old
  // one disabled and no replacement live.
  let newCode = null;
  for (let attempt = 0; attempt < 6; attempt++) {
    const candidate = randomCode();
    const ref = db.collection("inviteCodes").doc(candidate);
    const snap = await ref.get();
    if (snap.exists) continue;
    await ref.set(newPayload);
    newCode = candidate;
    break;
  }
  if (!newCode) throw new Error("Rotate: failed to find a non-colliding code.");

  await oldRef.update({
    disabled: true,
    rotatedTo: newCode,
    rotatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { newCode, carry };
}

async function main() {
  console.log(`Project: ${projectId}`);
  console.log(`Mode:    ${shouldWrite ? "WRITE" : "dry-run (use --write to commit)"}`);

  if (rotateArg) {
    const oldCode = rotateArg.toUpperCase();
    console.log(`Action:  rotate ${oldCode}`);
    if (!shouldWrite) {
      console.log("(dry-run) would disable old code and mint a fresh one with the same metadata.");
      return;
    }
    admin.initializeApp({ projectId });
    const db = admin.firestore();
    const { newCode, carry } = await rotate(db, oldCode);
    console.log(`Old code ${oldCode} disabled.`);
    console.log(`New code: ${newCode}`);
    console.log(`Carried metadata:`, carry);
    return;
  }

  console.log(`Kind:    ${kindArg}`);
  if (createdByArg) console.log(`Creator: ${createdByArg}`);
  if (campaignArg) console.log(`Campaign:${campaignArg}`);
  console.log(`MaxUses: ${maxUses === 1_000_000 ? "unlimited (1M)" : maxUses}`);

  if (explicitCodes && explicitCodes.length > 0) {
    console.log(`Codes (${explicitCodes.length}, explicit):`);
    for (const c of explicitCodes) console.log("  -", c);
    if (!shouldWrite) return;
    admin.initializeApp({ projectId });
    const db = admin.firestore();
    const batch = db.batch();
    for (const code of explicitCodes) {
      batch.set(db.collection("inviteCodes").doc(code), buildPayload(), {
        merge: true,
      });
    }
    await batch.commit();
    console.log(`Wrote ${explicitCodes.length} invite codes.`);
    return;
  }

  // Random-code path. Print intent in dry-run; mint with collision
  // checks in write mode.
  if (!shouldWrite) {
    console.log(`Would mint ${count} random ${kindArg} code(s) of length ${CODE_LENGTH}.`);
    console.log(`Example: ${randomCode()}`);
    return;
  }
  admin.initializeApp({ projectId });
  const db = admin.firestore();
  const written = [];
  for (let i = 0; i < count; i++) {
    const code = await mintFreshCode(db, buildPayload());
    written.push(code);
    console.log("  +", code);
  }
  console.log(`Wrote ${written.length} invite codes.`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
