const { onRequest } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const functionsV1 = require("firebase-functions/v1");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const crypto = require("crypto");

admin.initializeApp();

// --------------- Phone Normalization ---------------

// Mirror of ios/PlayMe/Utilities/PhoneNormalizer.swift so the server key
// matches what the client writes. US-centric fallback, accepts any raw form.
function normalizeE164(raw) {
  if (!raw || typeof raw !== "string") return null;
  const trimmed = raw.trim();
  if (!trimmed) return null;
  const hadPlus = trimmed.startsWith("+");
  const digits = trimmed.replace(/\D/g, "");
  if (!digits) return null;
  if (hadPlus) return `+${digits}`;
  if (digits.length === 10) return `+1${digits}`;
  if (digits.length === 11 && digits.startsWith("1")) return `+${digits}`;
  return `+${digits}`;
}

// --------------- Helpers ---------------

async function getFCMToken(uid) {
  const snap = await admin.firestore().collection("users").doc(uid).get();
  return snap.exists ? snap.data().fcmToken || null : null;
}

async function getUserName(uid) {
  const snap = await admin.firestore().collection("users").doc(uid).get();
  if (!snap.exists) return "Someone";
  const d = snap.data();
  return d.firstName || d.username || "Someone";
}

// True when `recipientUid` has disabled all notifications from their Settings
// screen. Missing flag defaults to enabled.
async function notificationsEnabledFor(recipientUid) {
  if (!recipientUid) return false;
  const snap = await admin
    .firestore()
    .collection("users")
    .doc(recipientUid)
    .get();
  if (!snap.exists) return false;
  const enabled = snap.data().notificationsEnabled;
  return enabled === undefined ? true : enabled === true;
}

// True when `recipientUid` has added `senderUid` to their blocked subcollection.
// A block fully silences pushes in either direction — callers should also check
// the inverse (blocker pushing to blocked) when relevant.
async function isBlockedBy(recipientUid, senderUid) {
  if (!recipientUid || !senderUid) return false;
  const snap = await admin
    .firestore()
    .collection("users")
    .doc(recipientUid)
    .collection("blocked")
    .doc(senderUid)
    .get();
  return snap.exists;
}

// Single-recipient push. Fetches the FCM token for `uid` internally so
// callers stay uid-centric. Every push gets:
//   - apns `apns-collapse-id` header (per-type, e.g. `msg-${convId}`),
//     which lets APNs replace an earlier banner instead of stacking a
//     duplicate on top of it.
//   - apns `thread-id`, which groups notifications together in iOS's
//     notification center AND is what the client uses to clear delivered
//     notifications surgically when the user opens the relevant screen.
//   - A `data.type` key used for deep-link routing on the client.
// We deliberately DO NOT set `aps.badge` — the client owns the badge via
// `UNUserNotificationCenter.setBadgeCount`, so omitting it here leaves
// the authoritative client value untouched.
async function sendPush(uid, opts = {}) {
  if (!uid) return;
  const { title, body, data = {}, collapseId, threadId } = opts;
  const token = await getFCMToken(uid);
  if (!token) return;

  const stringData = {};
  for (const [k, v] of Object.entries(data || {})) {
    if (v === undefined || v === null) continue;
    stringData[k] = typeof v === "string" ? v : String(v);
  }

  const aps = { sound: "default" };
  if (threadId) aps["thread-id"] = threadId;

  const apnsHeaders = {};
  if (collapseId) apnsHeaders["apns-collapse-id"] = collapseId;

  try {
    await admin.messaging().send({
      token,
      notification: { title, body },
      data: stringData,
      apns: {
        headers: apnsHeaders,
        payload: { aps },
      },
    });
  } catch (err) {
    if (
      err.code === "messaging/registration-token-not-registered" ||
      err.code === "messaging/invalid-registration-token"
    ) {
      console.log(`Stale FCM token, skipping: ${err.code}`);
    } else {
      console.error("sendPush error:", err);
    }
  }
}

// --------------- Notification Triggers ---------------

exports.onNewShare = onDocumentCreated("shares/{shareId}", async (event) => {
  const data = event.data.data();
  if (!data) return;

  const recipientId = data.recipientId;
  if (!recipientId) return;

  const senderId = data.senderId || data.sender?.id;
  if (senderId && (await isBlockedBy(recipientId, senderId))) {
    console.log(
      `onNewShare: skipping push \u2014 ${senderId} is blocked by ${recipientId}`
    );
    return;
  }
  if (!(await notificationsEnabledFor(recipientId))) return;

  const senderName = data.sender?.firstName || "Someone";
  const songTitle = data.song?.title || "a song";

  await sendPush(recipientId, {
    title: "New Song 🎵",
    body: `${senderName} sent you "${songTitle}"`,
    data: {
      type: "new_share",
      id: event.params.shareId,
      shareId: event.params.shareId,
    },
    collapseId: `share-${event.params.shareId}`,
    threadId: "shares",
  });
});

exports.onNewMessage = onDocumentCreated(
  "conversations/{convId}/messages/{msgId}",
  async (event) => {
    const msgData = event.data.data();
    if (!msgData) return;

    const senderId = msgData.senderId;
    const convId = event.params.convId;

    const convSnap = await admin
      .firestore()
      .collection("conversations")
      .doc(convId)
      .get();
    if (!convSnap.exists) return;

    const convData = convSnap.data();
    const participants = convData.participants || [];
    const names = convData.participantNames || {};
    const senderName = names[senderId] || "Someone";
    const text =
      (msgData.text || "").length > 80
        ? msgData.text.substring(0, 80) + "…"
        : msgData.text || "";

    for (const uid of participants) {
      if (uid === senderId) continue;
      if (await isBlockedBy(uid, senderId)) {
        console.log(
          `onNewMessage: skipping push \u2014 ${senderId} is blocked by ${uid}`
        );
        continue;
      }
      if (!(await notificationsEnabledFor(uid))) continue;
      await sendPush(uid, {
        title: senderName,
        body: text || "Sent a message",
        data: {
          type: "new_message",
          id: convId,
          conversationId: convId,
        },
        collapseId: `msg-${convId}`,
        threadId: `conv-${convId}`,
      });
    }
  }
);

exports.onNewLike = onDocumentCreated(
  "users/{userId}/likes/{shareId}",
  async (event) => {
    const likerId = event.params.userId;
    const shareId = event.params.shareId;

    if (shareId.startsWith("song_")) return;

    const shareSnap = await admin
      .firestore()
      .collection("shares")
      .doc(shareId)
      .get();
    if (!shareSnap.exists) return;

    const shareData = shareSnap.data();
    const senderId = shareData.senderId;
    if (!senderId || senderId === likerId) return;

    if (await isBlockedBy(senderId, likerId)) {
      console.log(
        `onNewLike: skipping push \u2014 ${likerId} is blocked by ${senderId}`
      );
      return;
    }
    if (!(await notificationsEnabledFor(senderId))) return;

    const likerName = await getUserName(likerId);
    const songTitle = shareData.song?.title || "a song";

    await sendPush(senderId, {
      title: "PlayMe",
      body: `${likerName} liked "${songTitle}"`,
      data: {
        type: "like",
        id: shareId,
        shareId,
      },
      collapseId: `like-${shareId}`,
      threadId: "likes",
    });
  }
);

exports.onNewFriend = onDocumentCreated(
  "users/{userId}/friends/{friendId}",
  async (event) => {
    const adderId = event.params.userId;
    const friendId = event.params.friendId;

    if (await isBlockedBy(friendId, adderId)) {
      console.log(
        `onNewFriend: skipping push \u2014 ${adderId} is blocked by ${friendId}`
      );
      return;
    }
    if (!(await notificationsEnabledFor(friendId))) return;

    const adderName = await getUserName(adderId);
    // `onNewFriend` mirrors on both sides of the `users/{uid}/friends` write,
    // so the person who RECEIVED the original friend request sees this fire
    // when the acceptor writes the mirrored row on their side. Phrasing it
    // as "X accepted your friend request" reads cleaner than the old generic
    // "added you" copy.
    await sendPush(friendId, {
      title: "PlayMe",
      body: `${adderName} accepted your friend request`,
      data: {
        type: "friend_accepted",
        id: adderId,
        friendId: adderId,
      },
      collapseId: `friend-${adderId}`,
      threadId: "friend-requests",
    });
  }
);

// Fires the moment an incoming friend request lands in the recipient's
// `users/{uid}/friendRequests/{fromUID}` subcollection. Gated by the
// recipient's notification prefs + block list. Collapsed per requester
// so rapid-fire duplicate requests (or a re-fire on reattach) surface as
// a single banner.
exports.onNewFriendRequest = onDocumentCreated(
  "users/{uid}/friendRequests/{fromUID}",
  async (event) => {
    const { uid, fromUID } = event.params;
    const data = event.data?.data() || {};

    if (await isBlockedBy(uid, fromUID)) {
      console.log(
        `onNewFriendRequest: skipping push \u2014 ${fromUID} is blocked by ${uid}`
      );
      return;
    }
    if (!(await notificationsEnabledFor(uid))) return;

    const displayName =
      [data.firstName, data.lastName].filter(Boolean).join(" ").trim() ||
      (data.username ? `@${data.username}` : "") ||
      "Someone";

    await sendPush(uid, {
      title: "PlayMe",
      body: `${displayName} sent you a friend request`,
      data: {
        type: "friend_request",
        id: fromUID,
        fromUID,
      },
      collapseId: `req-${fromUID}`,
      threadId: "friend-requests",
    });
  }
);

// --------------- Account Deletion (cascade cleanup) ---------------

const DELETED_USER_NAME = "Deleted user";
const DELETED_USERNAME_LABEL = "deleted";

// Commits a write batch in chunks of 450 — below the 500-op Firestore limit
// with some headroom so a caller can append a couple of final writes.
async function commitBatched(db, ops) {
  for (let i = 0; i < ops.length; i += 450) {
    const batch = db.batch();
    for (const op of ops.slice(i, i + 450)) {
      op(batch);
    }
    await batch.commit();
  }
}

// Anonymize this user's authored content instead of hard-deleting, so other
// users' conversation / share history stays intact. Deletes uniqueness index,
// subcollections, queued pending-shares keyed by their phone, and mirrored
// friend rows on every friend's side.
async function cascadeDeleteUser(uid) {
  if (!uid) return { ok: false, reason: "missing_uid" };

  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const userData = userSnap.exists ? userSnap.data() : {};
  const username = userData.username;
  const phone = userData.phone ? normalizeE164(userData.phone) : null;

  console.log(
    JSON.stringify({
      event: "cascade_delete_begin",
      uid,
      username: username || null,
      phone: phone || null,
    })
  );

  // 1) Release the username uniqueness index so the name can be reused.
  if (username) {
    try {
      await db.collection("usernames").doc(username).delete();
    } catch (err) {
      console.error("cascadeDeleteUser: username delete failed:", err.message);
    }
  }

  // 2) Delete own likes subcollection.
  try {
    const likes = await userRef.collection("likes").get();
    const ops = likes.docs.map((d) => (b) => b.delete(d.ref));
    await commitBatched(db, ops);
  } catch (err) {
    console.error("cascadeDeleteUser: likes delete failed:", err.message);
  }

  // 3) Delete own blocked subcollection.
  try {
    const blocked = await userRef.collection("blocked").get();
    const ops = blocked.docs.map((d) => (b) => b.delete(d.ref));
    await commitBatched(db, ops);
  } catch (err) {
    console.error("cascadeDeleteUser: blocked delete failed:", err.message);
  }

  // 4) Delete own friends + mirrored rows on every friend's side.
  try {
    const friends = await userRef.collection("friends").get();
    const ops = [];
    for (const f of friends.docs) {
      ops.push((b) => b.delete(f.ref));
      ops.push((b) =>
        b.delete(db.collection("users").doc(f.id).collection("friends").doc(uid))
      );
    }
    await commitBatched(db, ops);
  } catch (err) {
    console.error("cascadeDeleteUser: friends delete failed:", err.message);
  }

  // 5) Purge pending-shares queued for this user's phone (if any).
  if (phone) {
    try {
      const phoneRef = db.collection("pendingShares").doc(phone);
      const pending = await phoneRef.collection("shares").get();
      const ops = pending.docs.map((d) => (b) => b.delete(d.ref));
      await commitBatched(db, ops);
      await phoneRef.delete().catch(() => {});
    } catch (err) {
      console.error(
        "cascadeDeleteUser: pendingShares delete failed:",
        err.message
      );
    }
  }

  // 6) Anonymize shares authored by this user. Receivers keep their history
  //    but the sender is now "Deleted user". We also clear shares addressed
  //    TO this user so the sender's "Sent" tab hides personal info.
  try {
    const sent = await db
      .collection("shares")
      .where("senderId", "==", uid)
      .get();
    const sentOps = sent.docs.map((d) => (b) =>
      b.update(d.ref, {
        "sender.firstName": DELETED_USER_NAME,
        "sender.lastName": "",
        "sender.username": DELETED_USERNAME_LABEL,
      })
    );
    await commitBatched(db, sentOps);

    const received = await db
      .collection("shares")
      .where("recipientId", "==", uid)
      .get();
    const recvOps = received.docs.map((d) => (b) =>
      b.update(d.ref, {
        "recipient.firstName": DELETED_USER_NAME,
        "recipient.lastName": "",
        "recipient.username": DELETED_USERNAME_LABEL,
        recipientUsername: DELETED_USERNAME_LABEL,
      })
    );
    await commitBatched(db, recvOps);
  } catch (err) {
    console.error(
      "cascadeDeleteUser: shares anonymize failed:",
      err.message
    );
  }

  // 7) Anonymize participantNames in any conversations the user is part of.
  try {
    const convos = await db
      .collection("conversations")
      .where("participants", "array-contains", uid)
      .get();
    const ops = convos.docs.map((d) => (b) =>
      b.update(d.ref, { [`participantNames.${uid}`]: DELETED_USER_NAME })
    );
    await commitBatched(db, ops);
  } catch (err) {
    console.error(
      "cascadeDeleteUser: conversations anonymize failed:",
      err.message
    );
  }

  // 8) Finally, delete the user profile doc itself (drops fcmToken, phone,
  //    notificationsEnabled flag, etc).
  try {
    await userRef.delete();
  } catch (err) {
    console.error("cascadeDeleteUser: user doc delete failed:", err.message);
  }

  console.log(
    JSON.stringify({ event: "cascade_delete_complete", uid })
  );

  return { ok: true };
}

// Auth "user deleted" trigger \u2014 fires for EVERY Auth user deletion,
// including deletes performed from the Firebase Console. Runs the Firestore
// cascade so the username uniqueness index is released and the user's
// records are cleaned up. Uses the v1 API because Firebase Functions v2 does
// not yet expose a user-deleted trigger.
exports.onAuthUserDeleted = functionsV1.auth.user().onDelete(async (user) => {
  if (!user || !user.uid) return;
  try {
    await cascadeDeleteUser(user.uid);
  } catch (err) {
    console.error("onAuthUserDeleted: cascade failed:", err);
  }
});

// In-app "Delete Account" endpoint. The client sends its Firebase ID token in
// the Authorization header; we verify it, run the cascade, then delete the
// Auth user itself (which also fires beforeUserDeleted as a safety net).
exports.deleteAccount = onRequest(async (req, res) => {
  res.set("Cache-Control", "no-store");
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const authHeader = req.get("Authorization") || "";
  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    res.status(401).json({ error: "Missing bearer token" });
    return;
  }

  let uid;
  try {
    const decoded = await admin.auth().verifyIdToken(match[1]);
    uid = decoded.uid;
  } catch (err) {
    console.error("deleteAccount: token verification failed:", err.message);
    res.status(401).json({ error: "Invalid token" });
    return;
  }

  try {
    await cascadeDeleteUser(uid);
    await admin.auth().deleteUser(uid);
    res.json({ ok: true });
  } catch (err) {
    console.error("deleteAccount: failed:", err);
    res.status(500).json({ error: "Delete failed", details: err.message });
  }
});

// --------------- Pending Shares: server-side claim ---------------

function conversationIdFor(uidA, uidB) {
  const [a, b] = [uidA, uidB].sort();
  return `${a}_${b}`;
}

// Fans out every queued pending-share for the given phone into the recipient's
// feed, creates bidirectional friendships, a DM conversation + first message,
// deletes the pending docs, and pushes a "magic moment" notification.
// Idempotent: each pending doc maps to a deterministic shares/{pendingDocId}.
async function claimPendingSharesForUser(uid, phoneE164) {
  if (!uid || !phoneE164) {
    console.log("claimPendingSharesForUser: missing uid or phone", {
      uid,
      phoneE164,
    });
    return { count: 0 };
  }

  const db = admin.firestore();
  const baseRef = db
    .collection("pendingShares")
    .doc(phoneE164)
    .collection("shares");

  const snap = await baseRef.get();
  if (snap.empty) {
    console.log(
      JSON.stringify({
        event: "pending_share_claim_skipped",
        reason: "empty",
        uid,
        phoneE164,
      })
    );
    return { count: 0 };
  }

  // Resolve the new user's own profile once to stamp onto friend / conversation docs.
  const meSnap = await db.collection("users").doc(uid).get();
  const me = meSnap.exists ? meSnap.data() : {};
  const myUsername = me.username || "";
  const myFirstName = me.firstName || "";
  const myLastName = me.lastName || "";

  let claimed = 0;
  const pushPromises = [];
  // Track inviters (sender UIDs whose queued shares we claimed) so we can
  // deliver a single "X joined from your invite" push per inviter, rather
  // than N pushes for N queued songs from the same friend.
  const inviterIds = new Set();

  for (const doc of snap.docs) {
    const data = doc.data();
    const senderId = data.senderId;
    const songData = data.song;

    if (!senderId || !songData) {
      try {
        await doc.ref.delete();
      } catch (_) {}
      continue;
    }

    const senderFirstName = data.senderFirstName || "";
    const senderLastName = data.senderLastName || "";
    const senderUsername = data.senderUsername || "";
    const note = typeof data.note === "string" ? data.note : null;

    const song = {
      id: songData.id || doc.id,
      title: songData.title || "",
      artist: songData.artist || "",
      albumArtURL: songData.albumArtURL || "",
      duration: songData.duration || "",
      spotifyURI: songData.spotifyURI || null,
      previewURL: songData.previewURL || null,
      appleMusicURL: songData.appleMusicURL || null,
    };

    const batch = db.batch();

    const shareRef = db.collection("shares").doc(doc.id);
    batch.set(shareRef, {
      senderId,
      recipientId: uid,
      recipientUsername: myUsername,
      note,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      song,
      sender: {
        id: senderId,
        firstName: senderFirstName,
        lastName: senderLastName,
        username: senderUsername,
      },
      recipient: {
        id: uid,
        firstName: myFirstName,
        lastName: myLastName,
        username: myUsername,
      },
      claimedFromPending: true,
    });

    // Bidirectional friendship with merge so we don't clobber addedAt if re-run.
    batch.set(
      db.collection("users").doc(uid).collection("friends").doc(senderId),
      {
        username: senderUsername,
        firstName: senderFirstName,
        lastName: senderLastName,
        addedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    batch.set(
      db.collection("users").doc(senderId).collection("friends").doc(uid),
      {
        username: myUsername,
        firstName: myFirstName,
        lastName: myLastName,
        addedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    // Conversation doc (deterministic pair ID). merge:true keeps existing fields
    // if a conversation already exists between these two users.
    const convId = conversationIdFor(uid, senderId);
    const convRef = db.collection("conversations").doc(convId);
    const participants = [uid, senderId].sort();
    const messageText = note && note.length > 0 ? note : "Sent you a song";

    batch.set(
      convRef,
      {
        participants,
        participantNames: {
          [uid]: myFirstName,
          [senderId]: senderFirstName,
        },
        lastMessageText: messageText,
        lastMessageTimestamp: admin.firestore.FieldValue.serverTimestamp(),
        [`unreadCount_${uid}`]: admin.firestore.FieldValue.increment(1),
        [`unreadCount_${senderId}`]: 0,
      },
      { merge: true }
    );

    // First message: use deterministic ID (pending doc id) so retries don't dupe.
    const msgRef = convRef.collection("messages").doc(doc.id);
    batch.set(msgRef, {
      senderId,
      text: messageText,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      song,
    });

    batch.delete(doc.ref);

    try {
      await batch.commit();
      claimed += 1;
      inviterIds.add(senderId);

      // Fire a magic-moment push to the new user for every claimed share.
      pushPromises.push(
        sendPush(uid, {
          title: "PlayMe",
          body: `${senderFirstName || "A friend"} sent you "${song.title || "a song"}"`,
          data: {
            type: "new_share",
            id: doc.id,
            shareId: doc.id,
            claimedFromPending: "true",
          },
          collapseId: `share-${doc.id}`,
          threadId: "shares",
        })
      );

      console.log(
        JSON.stringify({
          event: "pending_share_claimed",
          uid,
          phoneE164,
          senderId,
          pendingDocId: doc.id,
        })
      );
    } catch (err) {
      console.error(
        JSON.stringify({
          event: "pending_share_claim_failed",
          uid,
          phoneE164,
          senderId,
          pendingDocId: doc.id,
          error: err.message,
        })
      );
    }
  }

  // "X joined from your invite" pushes — one per unique inviter. Sent in
  // parallel with the magic-moment pushes to the new user. Guarded by the
  // inviter's own notification prefs.
  const joinedFirstName = myFirstName || "A friend";
  const inviterPushes = Array.from(inviterIds).map(async (inviterUid) => {
    if (!inviterUid || inviterUid === uid) return;
    if (await isBlockedBy(inviterUid, uid)) return;
    if (!(await notificationsEnabledFor(inviterUid))) return;
    await sendPush(inviterUid, {
      title: "PlayMe",
      body: `${joinedFirstName} joined from your invite`,
      data: {
        type: "invite_joined",
        id: uid,
        joinedUID: uid,
      },
      collapseId: `join-${uid}`,
      threadId: "invites",
    });
  });

  await Promise.all([...pushPromises, ...inviterPushes]);
  return { count: claimed };
}

// Primary claim path: fires when a user profile doc is created at signup.
exports.onUserProfileCreated = onDocumentCreated(
  "users/{uid}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const uid = event.params.uid;
    const phoneE164 = normalizeE164(data.phone);
    if (!phoneE164) {
      console.log("onUserProfileCreated: no phone to normalize for", uid);
      return;
    }
    console.log(
      JSON.stringify({
        event: "pending_share_trigger_user_created",
        uid,
        phoneE164,
      })
    );
    await claimPendingSharesForUser(uid, phoneE164);
  }
);

// Fallback / retry path: signed-in clients write a claimRequest doc on every
// app launch so that shares queued AFTER signup still get claimed.
exports.onClaimRequest = onDocumentCreated(
  "claimRequests/{reqId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const uid = data.uid;
    if (!uid) return;

    const db = admin.firestore();
    const userSnap = await db.collection("users").doc(uid).get();
    if (!userSnap.exists) {
      console.log("onClaimRequest: no user profile for", uid);
      await event.data.ref.delete().catch(() => {});
      return;
    }

    const phoneE164 = normalizeE164(userSnap.data().phone);
    if (!phoneE164) {
      await event.data.ref.delete().catch(() => {});
      return;
    }

    console.log(
      JSON.stringify({
        event: "pending_share_trigger_claim_request",
        uid,
        phoneE164,
        reqId: event.params.reqId,
      })
    );
    await claimPendingSharesForUser(uid, phoneE164);
    await event.data.ref.delete().catch(() => {});
  }
);

const spotifyClientSecret = defineSecret("SPOTIFY_CLIENT_SECRET");

const SPOTIFY_CLIENT_ID = "10ac0a719f3e4135a2d3fd857c67d0f6";
const SPOTIFY_TOKEN_URL = "https://accounts.spotify.com/api/token";
const REDIRECT_URI = "playme://spotify-callback";

exports.swap = onRequest({ secrets: [spotifyClientSecret] }, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const code = req.body.code;
  if (!code) {
    res.status(400).json({ error: "Missing authorization code" });
    return;
  }

  try {
    const body = new URLSearchParams({
      grant_type: "authorization_code",
      code,
      redirect_uri: REDIRECT_URI,
      client_id: SPOTIFY_CLIENT_ID,
      client_secret: spotifyClientSecret.value(),
    });

    const response = await fetch(SPOTIFY_TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: body.toString(),
    });

    const data = await response.json();

    if (!response.ok) {
      res.status(response.status).json(data);
      return;
    }

    const codeHash = crypto.createHash("sha256").update(code).digest("hex");
    await admin.firestore().collection("tokenCache").doc(codeHash).set({
      access_token: data.access_token,
      refresh_token: data.refresh_token,
      expires_in: data.expires_in,
      created_at: Date.now(),
    });

    res.json(data);
  } catch (err) {
    res.status(500).json({ error: "Token swap failed", details: err.message });
  }
});

exports.refresh = onRequest({ secrets: [spotifyClientSecret] }, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const refreshToken = req.body.refresh_token;
  if (!refreshToken) {
    res.status(400).json({ error: "Missing refresh token" });
    return;
  }

  try {
    const body = new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: refreshToken,
      client_id: SPOTIFY_CLIENT_ID,
      client_secret: spotifyClientSecret.value(),
    });

    const response = await fetch(SPOTIFY_TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: body.toString(),
    });

    const data = await response.json();

    if (!response.ok) {
      res.status(response.status).json(data);
      return;
    }

    res.json(data);
  } catch (err) {
    res.status(500).json({ error: "Token refresh failed", details: err.message });
  }
});

exports.getTokens = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const code = req.body.code;
  if (!code) {
    res.status(400).json({ error: "Missing code" });
    return;
  }

  const codeHash = crypto.createHash("sha256").update(code).digest("hex");
  const doc = await admin.firestore().collection("tokenCache").doc(codeHash).get();

  if (!doc.exists) {
    res.status(404).json({ error: "Tokens not found" });
    return;
  }

  const tokens = doc.data();
  await admin.firestore().collection("tokenCache").doc(codeHash).delete();
  res.json({
    access_token: tokens.access_token,
    refresh_token: tokens.refresh_token,
    expires_in: tokens.expires_in,
  });
});

exports.auth = onRequest({ secrets: [spotifyClientSecret] }, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const accessToken = req.body.access_token;
  if (!accessToken) {
    res.status(400).json({ error: "Missing access_token" });
    return;
  }

  try {
    const profileRes = await fetch("https://api.spotify.com/v1/me", {
      headers: { Authorization: `Bearer ${accessToken}` },
    });

    if (!profileRes.ok) {
      res.status(401).json({ error: "Invalid Spotify access token" });
      return;
    }

    const profile = await profileRes.json();
    const spotifyUserId = profile.id;
    const uid = `spotify:${spotifyUserId}`;

    try {
      await admin.auth().getUser(uid);
    } catch {
      await admin.auth().createUser({
        uid,
        displayName: profile.display_name || spotifyUserId,
      });
    }

    const firebaseToken = await admin.auth().createCustomToken(uid);

    res.json({
      firebase_token: firebaseToken,
      spotify_uid: spotifyUserId,
      display_name: profile.display_name || spotifyUserId,
    });
  } catch (err) {
    res.status(500).json({ error: "Auth failed", details: err.message });
  }
});
