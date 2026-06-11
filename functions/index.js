const { onRequest } = require("firebase-functions/v2/https");
const {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const functionsV1 = require("firebase-functions/v1");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const crypto = require("crypto");
const jwt = require("jsonwebtoken");

admin.initializeApp();

// --------------- Structured Logging ---------------
//
// Keep production logs indexable in Cloud Logging without dumping request
// bodies, phone numbers, secrets, message text, or invite-code contents.
function compactLogPayload(payload = {}) {
  const out = {};
  for (const [key, value] of Object.entries(payload)) {
    if (value === undefined || value === null || value === "") continue;
    out[key] = value;
  }
  return out;
}

function logEvent(event, payload = {}) {
  console.log(JSON.stringify({ event, ...compactLogPayload(payload) }));
}

function logWarn(event, payload = {}) {
  console.warn(JSON.stringify({ event, ...compactLogPayload(payload) }));
}

function logError(event, err, payload = {}) {
  console.error(
    JSON.stringify({
      event,
      message: err && err.message ? err.message : String(err),
      ...compactLogPayload(payload),
    })
  );
}

function hashForLog(value) {
  return crypto.createHash("sha256").update(String(value || "")).digest("hex").slice(0, 12);
}

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

function fetchWithTimeout(url, options = {}, timeoutMs = 10000) {
  return fetch(url, {
    ...options,
    signal: AbortSignal.timeout(timeoutMs),
  });
}

async function getFCMToken(uid) {
  const db = admin.firestore();
  const privateSnap = await db
    .collection("users")
    .doc(uid)
    .collection("private")
    .doc("profile")
    .get();
  if (privateSnap.exists && privateSnap.data().fcmToken) {
    return privateSnap.data().fcmToken;
  }

  // Legacy fallback while existing installs migrate tokens to the private doc.
  const snap = await db.collection("users").doc(uid).get();
  return snap.exists ? snap.data().fcmToken || null : null;
}

async function clearFCMToken(uid) {
  if (!uid) return;
  const db = admin.firestore();
  await db
    .collection("users")
    .doc(uid)
    .collection("private")
    .doc("profile")
    .set(
      {
        fcmToken: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  await db.collection("users").doc(uid).update({ fcmToken: admin.firestore.FieldValue.delete() }).catch(() => {});
}

async function getPrivatePhone(uid) {
  const db = admin.firestore();
  const privateSnap = await db
    .collection("users")
    .doc(uid)
    .collection("private")
    .doc("profile")
    .get();
  if (privateSnap.exists && privateSnap.data().phone) {
    return privateSnap.data().phone;
  }

  // Legacy fallback for profiles created before phone moved private.
  const userSnap = await db.collection("users").doc(uid).get();
  return userSnap.exists ? userSnap.data().phone || null : null;
}

async function getUserName(uid) {
  const snap = await admin.firestore().collection("users").doc(uid).get();
  if (!snap.exists) return "Someone";
  const d = snap.data();
  return d.firstName || d.username || "Someone";
}

function publicUserPayload(uid, data = {}) {
  if (!uid) return null;
  return {
    id: uid,
    username: data.username || "",
    firstName: data.firstName || "",
    lastName: data.lastName || "",
    avatarURL: data.avatarURL || "",
  };
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
  const { title, body, data = {}, collapseId, threadId, mutableContent } =
    opts;
  const token = await getFCMToken(uid);
  if (!token) return;

  const stringData = {};
  for (const [k, v] of Object.entries(data || {})) {
    if (v === undefined || v === null) continue;
    stringData[k] = typeof v === "string" ? v : String(v);
  }

  // Base APS payload. We deliberately DO NOT set `badge` — the client owns
  // badge counts via `UNUserNotificationCenter.setBadgeCount`, so omitting
  // it here leaves the last authoritative client value untouched.
  const aps = { sound: "default" };
  if (threadId) aps["thread-id"] = threadId;
  // `mutable-content: 1` is what wakes the Notification Service Extension
  // before the banner lands. We only flip it for push types that carry
  // extension work (e.g. widget refresh on `new_share`); every other push
  // skips the extra round trip.
  if (mutableContent) aps["mutable-content"] = 1;

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
    logEvent("push_sent", { uid, type: stringData.type, collapseId, threadId });
  } catch (err) {
    if (
      err.code === "messaging/registration-token-not-registered" ||
      err.code === "messaging/invalid-registration-token"
    ) {
      logWarn("push_stale_token", { uid, code: err.code });
      await clearFCMToken(uid).catch((clearErr) => {
        logError("push_stale_token_cleanup_failed", clearErr, { uid });
      });
    } else {
      logError("push_send_failed", err, { uid, type: stringData.type });
    }
  }
}

async function shouldSendPush(key, ttlHours = 24) {
  if (!key) return true;
  const safeKey = crypto.createHash("sha256").update(key).digest("hex");
  const ref = admin.firestore().collection("pushDedupe").doc(safeKey);
  try {
    return await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.exists) return false;
      tx.set(ref, {
        key,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromMillis(
          Date.now() + ttlHours * 60 * 60 * 1000
        ),
      });
      return true;
    });
  } catch (err) {
    logError("push_dedupe_failed_open", err);
    return true;
  }
}

// --------------- Rate limiting (per-IP + per-UID) ---------------
//
// Lightweight Firestore-backed token-bucket throttle used by HTTP
// callables that don't otherwise enforce a quota. Buckets live at
// `rateLimits/{namespace}__{key}` and store `count` + `resetAt`.
// Buckets reset at `resetAt`; counts above the cap return false so
// the caller can respond 429. The throttle deliberately "fails open"
// on read errors so a Firestore outage doesn't lock new users out of
// onboarding — abuse is still gated by Firebase Auth's own SMS
// limits + invite code checks.
//
// The IP-based variant is best-effort — Cloud Functions HTTP runs
// behind a proxy that sets `x-forwarded-for`; the leftmost entry is
// the original client. This is sufficient to slow down casual abuse;
// determined attackers behind rotating IPs still need an invite code
// and a real phone number to do harm.
function clientIPFor(req) {
  const fwd = req.headers["x-forwarded-for"];
  if (typeof fwd === "string" && fwd.length > 0) {
    return fwd.split(",")[0].trim();
  }
  return req.ip || "unknown";
}

async function consumeRateLimitToken(namespace, key, opts = {}) {
  if (!namespace || !key) return true;
  const max = typeof opts.max === "number" ? opts.max : 10;
  const windowSeconds = typeof opts.windowSeconds === "number" ? opts.windowSeconds : 60;
  const safeKey = crypto.createHash("sha256").update(key).digest("hex");
  const ref = admin
    .firestore()
    .collection("rateLimits")
    .doc(`${namespace}__${safeKey}`);
  try {
    return await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const now = Date.now();
      const data = snap.exists ? snap.data() : null;
      const resetAtMs = data?.resetAt?.toMillis?.() || 0;
      if (!data || resetAtMs <= now) {
        tx.set(ref, {
          count: 1,
          resetAt: admin.firestore.Timestamp.fromMillis(now + windowSeconds * 1000),
          namespace,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return true;
      }
      const count = typeof data.count === "number" ? data.count : 0;
      if (count >= max) return false;
      tx.update(ref, {
        count: count + 1,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return true;
    });
  } catch (err) {
    logError("rate_limit_failed_open", err, { namespace });
    return true;
  }
}

// --------------- Notification Triggers ---------------

// Returns the yyyy-MM-dd one calendar day before the given yyyy-MM-dd string.
function previousLocalDayString(day) {
  if (!day || typeof day !== "string") return null;
  const parts = day.split("-").map(Number);
  if (parts.length !== 3 || parts.some((n) => Number.isNaN(n))) return null;
  const [y, m, d] = parts;
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() - 1);
  const yy = dt.getUTCFullYear();
  const mm = String(dt.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(dt.getUTCDate()).padStart(2, "0");
  return `${yy}-${mm}-${dd}`;
}

// Maintains the sender's global stats on a share create:
//  - uniqueSongsSentCount: incremented only the first time a given song.id is
//    sent (one song to 10 friends counts as 1) via users/{uid}/sentSongIndex.
//  - sendDayStreakCount / sendDayStreakLastDay: consecutive local-day streak,
//    using the sender-provided senderLocalDay (their timezone).
// Idempotent for the unique count; safe to run once per share create.
async function applySenderSendStats(senderId, songId, senderLocalDay) {
  if (!senderId || !songId) return;
  const db = admin.firestore();
  const userRef = db.collection("users").doc(senderId);
  const indexRef = userRef.collection("sentSongIndex").doc(songId);
  try {
    await db.runTransaction(async (tx) => {
      const [userSnap, indexSnap] = await Promise.all([
        tx.get(userRef),
        tx.get(indexRef),
      ]);
      const updates = {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (!indexSnap.exists) {
        tx.set(indexRef, {
          firstSentAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        updates.uniqueSongsSentCount =
          admin.firestore.FieldValue.increment(1);
      }
      if (senderLocalDay) {
        const data = userSnap.exists ? userSnap.data() : {};
        const lastDay = data.sendDayStreakLastDay;
        const count =
          typeof data.sendDayStreakCount === "number"
            ? data.sendDayStreakCount
            : 0;
        if (lastDay !== senderLocalDay) {
          let newCount;
          if (!lastDay) newCount = 1;
          else if (lastDay === previousLocalDayString(senderLocalDay))
            newCount = count + 1;
          else newCount = 1;
          updates.sendDayStreakCount = newCount;
          updates.sendDayStreakLastDay = senderLocalDay;
        }
      }
      tx.set(userRef, updates, { merge: true });
    });
  } catch (err) {
    logError("apply_sender_send_stats_failed", err, { senderId, songId });
  }
}

exports.onNewShare = onDocumentCreated("shares/{shareId}", async (event) => {
  const data = event.data.data();
  if (!data) return;

  const recipientId = data.recipientId;
  if (!recipientId) return;

  const senderId = data.senderId || data.sender?.id;

  // Update the sender's global stats first, before any notification gating
  // so counters advance even when the recipient has pushes disabled or has
  // blocked the sender.
  await applySenderSendStats(senderId, data.song?.id, data.senderLocalDay);

  if (senderId && (await isBlockedBy(recipientId, senderId))) {
    console.log(
      `onNewShare: skipping push \u2014 ${senderId} is blocked by ${recipientId}`
    );
    return;
  }
  if (!(await notificationsEnabledFor(recipientId))) return;

  const senderName = data.sender?.firstName || "Someone";
  const songTitle = data.song?.title || "a song";

  if (!(await shouldSendPush(`new_share:${event.params.shareId}:${recipientId}`))) return;
  await sendPush(recipientId, {
    title: "New Song 🎵",
    body: `${senderName} sent you "${songTitle}"`,
    // Widget payload: the NSE reads these keys to refresh the home-screen
    // widget before the banner is delivered, so the widget updates even
    // when the app is suspended or cold-terminated. Keep these keys in
    // sync with ios/PlayMeNotificationService/NotificationService.swift.
    mutableContent: true,
    data: {
      type: "new_share",
      id: event.params.shareId,
      shareId: event.params.shareId,
      widgetSongTitle: songTitle,
      widgetSongArtist: data.song?.artist || "",
      widgetSenderFirstName: senderName,
      widgetSenderAvatarURL: data.sender?.avatarURL || "",
      widgetNote: data.note || "",
      widgetAlbumArtURL: data.song?.albumArtURL || "",
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

    // Song sends create a chat message with id `share-{shareId}` AND a
    // `shares/{shareId}` doc, the latter triggering onNewShare ("New Song").
    // Skip the duplicate message push for these so a song send produces a
    // single notification and no Messages badge.
    if ((event.params.msgId || "").startsWith("share-")) return;

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
      if (!(await shouldSendPush(`new_message:${convId}:${event.params.msgId}:${uid}`))) continue;
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

    // Denormalize the recipient's like onto the share doc so the SENDER's
    // sent feed card can show the liker's avatar + heart. Recipient is
    // already embedded on the share, so a boolean flag is enough.
    if (likerId === shareData.recipientId) {
      try {
        await shareSnap.ref.update({
          recipientLiked: true,
          recipientLikedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (e) {
        console.log("onNewLike: failed to denormalize like onto share", e);
      }
    }

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

    if (!(await shouldSendPush(`like:${shareId}:${likerId}:${senderId}`))) return;
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

// Mirror of onNewLike: when the recipient unlikes, clear the denormalized
// flag so the sender's feed card stops showing their like.
exports.onLikeRemoved = onDocumentDeleted(
  "users/{userId}/likes/{shareId}",
  async (event) => {
    const likerId = event.params.userId;
    const shareId = event.params.shareId;
    if (shareId.startsWith("song_")) return;

    const ref = admin.firestore().collection("shares").doc(shareId);
    const snap = await ref.get();
    if (!snap.exists) return;
    if (likerId !== snap.data().recipientId) return;

    try {
      await ref.update({
        recipientLiked: false,
        recipientLikedAt: admin.firestore.FieldValue.delete(),
      });
    } catch (e) {
      console.log("onLikeRemoved: failed to clear like on share", e);
    }
  }
);

exports.onShareListened = onDocumentUpdated(
  "shares/{shareId}",
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    const shareId = event.params.shareId;

    // Notify only on the first listen receipt. Later source updates
    // (preview + external) should update history without stacking pushes.
    if (before.recipientListenedAt || !after.recipientListenedAt) return;

    const senderId = after.senderId;
    const recipientId = after.recipientId;
    if (!senderId || !recipientId || senderId === recipientId) return;

    if (await isBlockedBy(senderId, recipientId)) {
      console.log(
        `onShareListened: skipping push — ${recipientId} is blocked by ${senderId}`
      );
      return;
    }
    if (!(await notificationsEnabledFor(senderId))) return;

    const listenerName =
      after.recipient?.firstName || (await getUserName(recipientId));
    const songTitle = after.song?.title || "your song";

    if (!(await shouldSendPush(`share_listened:${shareId}:${recipientId}:${senderId}`))) return;
    await sendPush(senderId, {
      title: "PlayMe",
      body: `${listenerName} listened to "${songTitle}"`,
      data: {
        type: "share_listened",
        id: shareId,
        shareId,
        listenerId: recipientId,
      },
      collapseId: `listen-${shareId}`,
      threadId: "listens",
    });
  }
);

exports.onNewFriend = onDocumentCreated(
  "users/{userId}/friends/{friendId}",
  async (event) => {
    const adderId = event.params.userId;
    const friendId = event.params.friendId;
    const data = event.data?.data() || {};

    // Accepting writes mirrored friendship rows. Only the row owned by the
    // acceptor should notify the original requester.
    if (data.acceptedBy && data.acceptedBy !== adderId) return;
    if (!data.acceptedBy) return;

    if (await isBlockedBy(friendId, adderId)) {
      console.log(
        `onNewFriend: skipping push \u2014 ${adderId} is blocked by ${friendId}`
      );
      return;
    }
    if (!(await notificationsEnabledFor(friendId))) return;

    const adderName = await getUserName(adderId);
    if (!(await shouldSendPush(`friend_accepted:${adderId}:${friendId}`))) return;
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

    if (!(await shouldSendPush(`friend_request:${fromUID}:${uid}`))) return;
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

// --------------- Friend count maintenance + hard cap ---------------
//
// Two-tier enforcement of the per-user friend cap:
//
//  1) Soft cap (rules-level): `firestore.rules`'s `friends/{friendId}`
//     create rule checks `friendCount < friendLimit` BEFORE accepting
//     the write. This blocks the obvious case where the user is
//     already at their cap.
//
//  2) Hard cap (this function): a brief race window exists where two
//     near-simultaneous accept-friend-request writes could each see
//     `friendCount = 19` and pass the rule, landing the user at 21.
//     `onFriendCreated` is the safety net: after the write lands it
//     re-reads the current count, and if it's > limit it removes the
//     most recently-added friend doc from both sides. The rule's
//     soft cap means this is exceptionally rare; the safety net
//     guarantees the invariant always converges to <= limit.
//
// `friendLimit` defaults to 20 and is stored on the user's `users/{uid}`
// doc. Premium subscribers (or other elevated tiers) get a higher
// limit by setting this field server-side via the Admin SDK.

const DEFAULT_FRIEND_LIMIT = 20;

exports.onFriendCreated = onDocumentCreated(
  "users/{userId}/friends/{friendId}",
  async (event) => {
    const { userId, friendId } = event.params;
    if (!userId || !friendId || userId === friendId) return;

    const db = admin.firestore();
    const userRef = db.collection("users").doc(userId);

    // Increment first so the soft cap on the NEXT write sees the
    // post-increment count. A failure here must NOT abort the function:
    // queued songs still need to be delivered once the friendship exists.
    try {
      await userRef.set(
        {
          friendCount: admin.firestore.FieldValue.increment(1),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } catch (err) {
      console.error("onFriendCreated: friendCount increment failed:", err.message);
    }

    // Hard cap check. Re-read the user doc and, if the count now
    // exceeds the per-user limit, undo this specific friend doc on
    // both sides. The race-loser is the friendship that lost the
    // tie — last write to arrive. Acceptable UX for an edge case
    // that should occur < 0.01% of the time.
    try {
      const snap = await userRef.get();
      const data = snap.data() || {};
      const count = typeof data.friendCount === "number" ? data.friendCount : 0;
      const limit =
        typeof data.friendLimit === "number" ? data.friendLimit : DEFAULT_FRIEND_LIMIT;
      if (count <= limit) {
        // Friendship is valid. Continue below so queued songs that were
        // selected while the request was pending can now be delivered.
      } else {
        console.log(
          JSON.stringify({
            event: "friend_cap_exceeded",
            userId,
            friendId,
            count,
            limit,
          })
        );

        const batch = db.batch();
        batch.delete(userRef.collection("friends").doc(friendId));
        batch.delete(
          db.collection("users").doc(friendId).collection("friends").doc(userId)
        );
        await batch.commit();
        // The companion onFriendDeleted triggers will decrement both
        // sides' friendCount back into range.
        return;
      }
    } catch (err) {
      console.error("onFriendCreated: hard cap check failed:", err.message);
    }

    // Both mirrored friend docs fire this trigger; the lexical guard makes
    // pending-song delivery run once per accepted pair.
    if (userId < friendId) {
      await deliverPendingFriendSharesForPair(userId, friendId);
    }
  }
);

exports.onFriendDeleted = onDocumentDeleted(
  "users/{userId}/friends/{friendId}",
  async (event) => {
    const { userId } = event.params;
    if (!userId) return;
    try {
      await admin
        .firestore()
        .collection("users")
        .doc(userId)
        .set(
          {
            friendCount: admin.firestore.FieldValue.increment(-1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
    } catch (err) {
      console.error("onFriendDeleted: friendCount decrement failed:", err.message);
    }
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
  const phone = normalizeE164(userData.phone || (await getPrivatePhone(uid)));

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

  // 5) Delete pending friend requests involving this account, including
  //    mirrored request docs on the other user's side. Deleting a Firestore
  //    document does not delete its subcollections, so these would otherwise
  //    leave "Requested" ghosts for users who tried to add a deleted account.
  try {
    const [incoming, outgoing] = await Promise.all([
      userRef.collection("friendRequests").get(),
      userRef.collection("outgoingFriendRequests").get(),
    ]);
    const ops = [];
    for (const req of incoming.docs) {
      ops.push((b) => b.delete(req.ref));
      ops.push((b) =>
        b.delete(db.collection("users").doc(req.id).collection("outgoingFriendRequests").doc(uid))
      );
    }
    for (const req of outgoing.docs) {
      ops.push((b) => b.delete(req.ref));
      ops.push((b) =>
        b.delete(db.collection("users").doc(req.id).collection("friendRequests").doc(uid))
      );
    }
    await commitBatched(db, ops);
  } catch (err) {
    console.error("cascadeDeleteUser: friend request delete failed:", err.message);
  }

  // 6) Purge pending-shares queued for this user's phone (if any).
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

  // 7) Anonymize shares authored by this user. Receivers keep their history
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
        "sender.avatarURL": admin.firestore.FieldValue.delete(),
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
        "recipient.avatarURL": admin.firestore.FieldValue.delete(),
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

  // 8) Anonymize participantNames in any conversations the user is part of.
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

  // 9) Delete profile photo storage objects.
  try {
    await admin.storage().bucket().deleteFiles({ prefix: `profile-photos/${uid}/` });
  } catch (err) {
    console.error("cascadeDeleteUser: profile photo delete failed:", err.message);
  }

  // 10) Delete private profile metadata and then the public user profile doc.
  try {
    await userRef.collection("private").doc("profile").delete().catch(() => {});
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

  if (!(await verifyAppCheckHeader(req, "deleteAccount"))) {
    res.status(401).json({ error: "Invalid App Check token" });
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
    res.status(500).json({ error: "Delete failed" });
  }
});

// --------------- Pending Shares: server-side claim ---------------

function conversationIdFor(uidA, uidB) {
  const [a, b] = [uidA, uidB].sort();
  return `${a}_${b}`;
}

function friendPairKey(uidA, uidB) {
  return [uidA, uidB].sort().join("_");
}

async function deliverPendingFriendSharesForPair(uidA, uidB) {
  if (!uidA || !uidB || uidA === uidB) return { count: 0 };

  const db = admin.firestore();
  const pairKey = friendPairKey(uidA, uidB);
  const [aFriend, bFriend] = await Promise.all([
    db.collection("users").doc(uidA).collection("friends").doc(uidB).get(),
    db.collection("users").doc(uidB).collection("friends").doc(uidA).get(),
  ]);
  if (!aFriend.exists || !bFriend.exists) {
    logEvent("pending_delivery_skipped_no_friendship", {
      pairKey,
      uidA,
      uidB,
      aFriendExists: aFriend.exists,
      bFriendExists: bFriend.exists,
    });
    return { count: 0 };
  }

  const [aQueued, bQueued] = await Promise.all([
    db
      .collection("users")
      .doc(uidA)
      .collection("pendingFriendShares")
      .where("recipientId", "==", uidB)
      .limit(100)
      .get(),
    db
      .collection("users")
      .doc(uidB)
      .collection("pendingFriendShares")
      .where("recipientId", "==", uidA)
      .limit(100)
      .get(),
  ]);
  const pendingDocs = [...aQueued.docs, ...bQueued.docs];
  if (pendingDocs.length === 0) return { count: 0 };

  let delivered = 0;
  const pushPromises = [];

  for (const doc of pendingDocs) {
    const data = doc.data() || {};
    const senderId = data.senderId;
    const recipientId = data.recipientId;
    const song = data.song;
    if (!senderId || !recipientId || !song) {
      await doc.ref.delete().catch(() => {});
      continue;
    }
    if (
      !(
        (senderId === uidA && recipientId === uidB) ||
        (senderId === uidB && recipientId === uidA)
      )
    ) {
      continue;
    }
    if (await isBlockedBy(recipientId, senderId)) {
      await doc.ref.delete().catch(() => {});
      continue;
    }

    const sender = data.sender || {};
    const recipient = data.recipient || {};
    const note = typeof data.note === "string" ? data.note : null;
    const batch = db.batch();
    const shareRef = db.collection("shares").doc(doc.id);

    batch.set(shareRef, {
      senderId,
      recipientId,
      recipientUsername: recipient.username || data.recipientUsername || "",
      note,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      // Carry the sender's local day from the queued pending share so the
      // onNewShare counter logic credits the global send-day streak.
      senderLocalDay: data.senderLocalDay || null,
      song,
      sender: {
        id: senderId,
        firstName: sender.firstName || "",
        lastName: sender.lastName || "",
        username: sender.username || "",
        avatarURL: sender.avatarURL || "",
      },
      recipient: {
        id: recipientId,
        firstName: recipient.firstName || "",
        lastName: recipient.lastName || "",
        username: recipient.username || "",
        avatarURL: recipient.avatarURL || "",
      },
      queuedFromPendingFriendRequest: true,
      pendingFriendShareId: doc.id,
    });

    const convId = conversationIdFor(senderId, recipientId);
    const convRef = db.collection("conversations").doc(convId);
    const participants = [senderId, recipientId].sort();
    const messageText = note && note.trim().length > 0 ? note : "";
    const lastMessageText = messageText || song.title || "";

    batch.set(
      convRef,
      {
        participants,
        participantNames: {
          [senderId]: sender.firstName || "",
          [recipientId]: recipient.firstName || "",
        },
        lastMessageText,
        lastMessageTimestamp: admin.firestore.FieldValue.serverTimestamp(),
        [`unreadCount_${recipientId}`]: admin.firestore.FieldValue.increment(1),
        [`unreadCount_${senderId}`]: 0,
      },
      { merge: true }
    );

    batch.set(convRef.collection("messages").doc(doc.id), {
      senderId,
      text: messageText,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      song,
      queuedFromPendingFriendRequest: true,
    });
    batch.delete(doc.ref);

    try {
      await batch.commit();
      delivered += 1;
      pushPromises.push(
        (async () => {
          if (!(await shouldSendPush(`pending_friend_share:${doc.id}:${recipientId}`))) return;
          await sendPush(recipientId, {
            title: "PlayMe",
            body: `${sender.firstName || "A friend"} sent you "${song.title || "a song"}"`,
            mutableContent: true,
            data: {
              type: "new_share",
              id: doc.id,
              shareId: doc.id,
              queuedFromPendingFriendRequest: "true",
              widgetSongTitle: song.title || "",
              widgetSongArtist: song.artist || "",
              widgetSenderFirstName: sender.firstName || "",
              widgetSenderAvatarURL: sender.avatarURL || "",
              widgetNote: note || "",
              widgetAlbumArtURL: song.albumArtURL || "",
            },
            collapseId: `share-${doc.id}`,
            threadId: "shares",
          });
        })()
      );
    } catch (err) {
      logError("pending_friend_share_delivery_failed", err, {
        senderId,
        recipientId,
        pendingFriendShareId: doc.id,
      });
    }
  }

  await Promise.allSettled(pushPromises);
  if (delivered > 0) {
    logEvent("pending_friend_shares_delivered", { pairKey, delivered });
  }
  return { count: delivered };
}

// Converts phone-keyed pending shares into accepted-only friend-request queues.
// The joining user gets a normal incoming friend request, and the song moves
// into users/{sender}/pendingFriendShares. Actual share delivery happens only
// after the request is accepted and friend docs exist.
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
  const myAvatarURL = me.avatarURL || "";

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
    const senderAvatarURL = data.senderAvatarURL || "";
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
    const ts = admin.firestore.FieldValue.serverTimestamp();

    batch.set(
      db.collection("users").doc(uid).collection("friendRequests").doc(senderId),
      {
        username: senderUsername,
        firstName: senderFirstName,
        lastName: senderLastName,
        avatarURL: senderAvatarURL,
        createdAt: ts,
      },
      { merge: true }
    );
    batch.set(
      db.collection("users").doc(senderId).collection("outgoingFriendRequests").doc(uid),
      {
        username: myUsername,
        firstName: myFirstName,
        lastName: myLastName,
        avatarURL: myAvatarURL,
        createdAt: ts,
      },
      { merge: true }
    );
    batch.set(
      db.collection("users").doc(senderId).collection("pendingFriendShares").doc(doc.id),
      {
        senderId,
        recipientId: uid,
        recipientUsername: myUsername,
        pairKey: friendPairKey(senderId, uid),
        note,
        createdAt: ts,
        song,
        sender: {
          id: senderId,
          firstName: senderFirstName,
          lastName: senderLastName,
          username: senderUsername,
          avatarURL: senderAvatarURL,
        },
        recipient: {
          id: uid,
          firstName: myFirstName,
          lastName: myLastName,
          username: myUsername,
          avatarURL: myAvatarURL,
        },
        claimedFromPhoneInvite: true,
      },
      { merge: true }
    );

    batch.delete(doc.ref);

    try {
      await batch.commit();
      claimed += 1;
      inviterIds.add(senderId);

      console.log(
        JSON.stringify({
          event: "pending_share_converted_to_friend_request",
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
    if (!(await shouldSendPush(`invite_joined:${uid}:${inviterUid}`))) return;
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
    const phoneE164 = normalizeE164(data.phone || (await getPrivatePhone(uid)));
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

    const phoneE164 = normalizeE164(await getPrivatePhone(uid));
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

// -------- Legacy Spotify OAuth endpoints (DEPRECATED) --------
//
// `swap`, `refresh`, `getTokens`, `auth` are leftover from an earlier
// iteration where Spotify served as the primary OAuth identity provider.
// The iOS client does NOT call these in the current shipping flow —
// Spotify is server-resolved via `resolveSpotifyTrack` (Firebase
// ID-token-auth'd) and Spotify-as-Firebase-identity isn't used at all.
//
// They are deliberately hard-disabled here rather than deleted to
// avoid surprising any old TestFlight build still in the wild that
// might call them. Restoring them requires re-introducing real
// authentication + App Check.
//
// All four return 410 Gone with a clear message.

function rejectDeprecatedSpotifyEndpoint(req, res, name) {
  console.warn(
    JSON.stringify({
      event: "deprecated_spotify_endpoint_called",
      endpoint: name,
      ip: clientIPFor(req),
    })
  );
  res.status(410).json({
    error: "endpoint_disabled",
    detail:
      "This Spotify OAuth endpoint has been disabled. Use the in-app Spotify deep link or the resolveSpotifyTrack callable.",
  });
}

exports.swap = onRequest(async (req, res) => {
  rejectDeprecatedSpotifyEndpoint(req, res, "swap");
});

exports.refresh = onRequest(async (req, res) => {
  rejectDeprecatedSpotifyEndpoint(req, res, "refresh");
});

exports.getTokens = onRequest(async (req, res) => {
  rejectDeprecatedSpotifyEndpoint(req, res, "getTokens");
});

exports.auth = onRequest(async (req, res) => {
  rejectDeprecatedSpotifyEndpoint(req, res, "auth");
});

// --------------- Spotify Track Resolution (Client Credentials) ---------------
//
// Cross-platform resolver used by the iOS client's "Open in Spotify" flow.
// The client sends { title, artist, amURL } and we return the Spotify track
// ID + canonical URL. This is the PRIMARY resolution path; Odesli (song.link)
// is only consulted client-side as a fallback if this function fails.
//
// Auth model:
//   - Client: requires a valid Firebase ID token (Bearer) so randoms on the
//     internet can't grind our Spotify rate limit on our dime.
//   - Server: Client Credentials flow to Spotify (no user auth required,
//     no scopes, no 5-user dev-mode cap). The app-level access token is
//     cached in module memory across invocations of this function instance
//     and refreshed 60 s before expiry. Cold starts re-mint it.
//
// Scale math:
//   Spotify Dev Mode rate limit: ~180 req/min app-wide (rolling window).
//   Combined with the iOS client's local cache + Firestore global
//   `spotifyResolutions` cache, the client only ever calls this function
//   on TRUE cache misses — which, after a few days of catalog warm-up, is
//   a rounding error on total traffic. Comfortable headroom for ~100K MAU.

const SPOTIFY_SEARCH_URL = "https://api.spotify.com/v1/search";

// Module-scope token cache. Survives warm function invocations; rebuilt
// on cold start. Never written to Firestore because (a) the secret to
// mint it is cheap and fast, and (b) storing short-lived bearer tokens
// in Firestore is a minor security smell.
let cachedAppAccessToken = null;
let cachedAppAccessTokenExpiresAt = 0;

async function getSpotifyAppAccessToken(secretValue) {
  const now = Date.now();
  // 60 s skew buffer — never hand out a token that's about to expire
  // mid-request, since the Spotify API call downstream takes a moment.
  if (cachedAppAccessToken && now < cachedAppAccessTokenExpiresAt - 60_000) {
    return cachedAppAccessToken;
  }

  const body = new URLSearchParams({ grant_type: "client_credentials" });
  const basicAuth = Buffer.from(`${SPOTIFY_CLIENT_ID}:${secretValue}`).toString("base64");

  const response = await fetch(SPOTIFY_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: `Basic ${basicAuth}`,
    },
    body: body.toString(),
  });

  if (!response.ok) {
    const errBody = await response.text().catch(() => "");
    throw new Error(`Spotify token request failed: HTTP ${response.status} ${errBody.slice(0, 200)}`);
  }

  const data = await response.json();
  if (!data.access_token || !data.expires_in) {
    throw new Error(`Spotify token response missing fields: ${JSON.stringify(data).slice(0, 200)}`);
  }

  cachedAppAccessToken = data.access_token;
  cachedAppAccessTokenExpiresAt = now + data.expires_in * 1000;
  return cachedAppAccessToken;
}

// Normalize a name ("Love On The Brain (feat. X)", "Drop Dead - Single
// Version", etc.) down to a comparable base so we can tell if Spotify's
// match is genuinely the same song the user asked for. Removes
// parentheticals, bracketed suffixes, dash suffixes, and lowercases.
function normalizeTrackName(raw) {
  if (!raw || typeof raw !== "string") return "";
  return raw
    .toLowerCase()
    .replace(/\s*\(.*?\)\s*/g, " ")
    .replace(/\s*\[.*?\]\s*/g, " ")
    .replace(/\s+-\s+.*/, " ")
    .replace(/[^\w\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

// Best-match picker. Spotify's /search is pretty well-ranked, but the top
// result is occasionally a different-artist remix or cover; we want the
// official Rihanna version when the user asked for Rihanna. Strategy:
//   1. First result whose artist list contains the requested artist
//      (case-insensitive substring either way).
//   2. Otherwise, first result whose track name normalizes to the same
//      base as the requested title (catches remix/version drift).
//   3. Otherwise, Spotify's top result — best we can do.
function pickBestMatch(tracks, requestedTitle, requestedArtist) {
  if (!Array.isArray(tracks) || tracks.length === 0) return null;

  const normArtist = (requestedArtist || "").toLowerCase().trim();
  const normTitle = normalizeTrackName(requestedTitle || "");

  if (normArtist) {
    for (const t of tracks) {
      const artistNames = (t.artists || []).map((a) => (a.name || "").toLowerCase());
      if (
        artistNames.some((a) => a && (a.includes(normArtist) || normArtist.includes(a)))
      ) {
        return t;
      }
    }
  }

  if (normTitle) {
    for (const t of tracks) {
      if (normalizeTrackName(t.name) === normTitle) return t;
    }
  }

  return tracks[0];
}

exports.resolveSpotifyTrack = onRequest({ secrets: [spotifyClientSecret] }, async (req, res) => {
  res.set("Cache-Control", "no-store");

  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  if (!(await verifyAppCheckHeader(req, "resolveSpotifyTrack"))) {
    res.status(401).json({ error: "Invalid App Check token" });
    return;
  }

  // Auth: require Firebase ID token so abuse is traceable to a real user.
  const authHeader = req.get("Authorization") || "";
  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    res.status(401).json({ error: "Missing bearer token" });
    return;
  }
  try {
    await admin.auth().verifyIdToken(match[1]);
  } catch (err) {
    logError("resolve_spotify_auth_failed", err);
    res.status(401).json({ error: "Invalid token" });
    return;
  }

  const title = typeof req.body.title === "string" ? req.body.title.trim() : "";
  const artist = typeof req.body.artist === "string" ? req.body.artist.trim() : "";
  const amURL = typeof req.body.amURL === "string" ? req.body.amURL.trim() : "";

  if (!title || !artist) {
    res.status(400).json({ error: "Missing title or artist" });
    return;
  }

  let accessToken;
  try {
    accessToken = await getSpotifyAppAccessToken(spotifyClientSecret.value());
  } catch (err) {
    logError("resolve_spotify_token_mint_failed", err);
    res.status(502).json({ error: "Spotify token mint failed", details: err.message });
    return;
  }

  // Spotify search query. Quoting the field values keeps them as phrase
  // searches, which gives noticeably better match quality than bare
  // concatenation (especially for short or common titles).
  const q = `track:"${title.replace(/"/g, '')}" artist:"${artist.replace(/"/g, '')}"`;
  const searchParams = new URLSearchParams({
    q,
    type: "track",
    market: "US",
    limit: "10",
  });
  const searchURL = `${SPOTIFY_SEARCH_URL}?${searchParams.toString()}`;

  let searchJson;
  try {
    const searchRes = await fetch(searchURL, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });

    if (searchRes.status === 429) {
      const retryAfter = searchRes.headers.get("Retry-After") || "";
      logWarn("resolve_spotify_rate_limited", { retryAfter });
      res.status(503).json({ error: "Rate limited", retryAfter });
      return;
    }

    if (searchRes.status === 401) {
      // Cached app token rejected — invalidate and retry once.
      cachedAppAccessToken = null;
      cachedAppAccessTokenExpiresAt = 0;
      try {
        accessToken = await getSpotifyAppAccessToken(spotifyClientSecret.value());
      } catch (err) {
        logError("resolve_spotify_token_remint_failed", err);
        res.status(502).json({ error: "Spotify token re-mint failed" });
        return;
      }
      const retryRes = await fetch(searchURL, {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
      if (!retryRes.ok) {
        res.status(retryRes.status).json({ error: `Spotify search failed after re-auth: HTTP ${retryRes.status}` });
        return;
      }
      searchJson = await retryRes.json();
    } else if (!searchRes.ok) {
      const body = await searchRes.text().catch(() => "");
      logError("resolve_spotify_http_failed", new Error(`HTTP ${searchRes.status}`), {
        status: searchRes.status,
        bodyPreview: body.slice(0, 200),
      });
      res.status(502).json({ error: `Spotify search failed: HTTP ${searchRes.status}` });
      return;
    } else {
      searchJson = await searchRes.json();
    }
  } catch (err) {
    logError("resolve_spotify_network_failed", err);
    res.status(502).json({ error: "Spotify search network error", details: err.message });
    return;
  }

  const tracks = (searchJson && searchJson.tracks && searchJson.tracks.items) || [];
  const best = pickBestMatch(tracks, title, artist);

  if (!best || !best.id) {
    logEvent("resolve_spotify_no_match", {
      hasAppleMusicURL: Boolean(amURL),
      titleLength: title.length,
      artistLength: artist.length,
    });
    res.json({ error: "no_match" });
    return;
  }

  const trackId = best.id;
  const spotifyURL = (best.external_urls && best.external_urls.spotify) || `https://open.spotify.com/track/${trackId}`;
  const matchedTitle = best.name || "";
  const matchedArtist = (best.artists || []).map((a) => a.name || "").join(", ");

  // Persist into the global `spotifyResolutions` cache server-side so
  // every other client that asks for the same song gets the answer
  // without re-hitting Spotify. The collection is now admin-write-only
  // (see firestore.rules) — this is the canonical writer. Failure to
  // cache is logged but does not affect the response, since the
  // resolution itself succeeded.
  if (amURL) {
    try {
      const cacheKey = crypto
        .createHash("sha256")
        .update(amURL)
        .digest("hex");
      await admin
        .firestore()
        .collection("spotifyResolutions")
        .doc(cacheKey)
        .set(
          {
            trackId,
            spotifyURL,
            amURL,
            matchedTitle,
            matchedArtist,
            resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
            source: "cloudfn",
          },
          { merge: true }
        );
    } catch (err) {
      logError("resolve_spotify_cache_write_failed", err);
    }
  }

  logEvent("resolve_spotify_success", {
    trackId,
    hasAppleMusicURL: Boolean(amURL),
    matchedTitleLength: matchedTitle.length,
    matchedArtistLength: matchedArtist.length,
  });
  res.json({ trackId, spotifyURL, matchedTitle, matchedArtist });
});

// --------------- Apple Music developer token ---------------
//
// Mints short-lived (~1 h) JWTs for the Apple Music HTTP API
// (`api.music.apple.com/v1/catalog/...`) so the iOS client can perform
// catalog search and artist-details reads without ever prompting the
// user for MusicKit authorization. The .p8 private key lives only here
// in Functions secrets — it never ships in the iOS binary.
//
// Auth: requires a valid Firebase ID token in the `Authorization` header
// so anonymous callers can't drain rate limits. Same pattern as
// `redeemInviteCode` and `resolveSpotifyTrack`.
//
// Token lifetime is intentionally short (1 h) even though Apple permits
// up to 180 days — the client refreshes silently on near-expiry / 401 /
// cache miss, so a leaked token is bounded to roughly an hour of damage.

const appleMusicKeyId = defineSecret("APPLE_MUSIC_KEY_ID");
const appleMusicTeamId = defineSecret("APPLE_MUSIC_TEAM_ID");
const appleMusicPrivateKey = defineSecret("APPLE_MUSIC_PRIVATE_KEY");

const APPLE_MUSIC_TOKEN_LIFETIME_SECONDS = 60 * 60;

exports.getMusicKitDeveloperToken = onRequest(
  {
    secrets: [appleMusicKeyId, appleMusicTeamId, appleMusicPrivateKey],
  },
  async (req, res) => {
    res.set("Cache-Control", "no-store");

    if (req.method !== "POST" && req.method !== "GET") {
      res.status(405).json({ error: "method_not_allowed" });
      return;
    }

    if (!(await verifyAppCheckHeader(req, "getMusicKitDeveloperToken"))) {
      res.status(401).json({ error: "invalid_app_check" });
      return;
    }

    const uid = await verifyAuthHeader(req);
    if (!uid) {
      res.status(401).json({ error: "unauthenticated" });
      return;
    }

    let keyId, teamId, privateKey;
    try {
      keyId = appleMusicKeyId.value();
      teamId = appleMusicTeamId.value();
      privateKey = appleMusicPrivateKey.value();
    } catch (err) {
      console.error(
        "getMusicKitDeveloperToken: secret read failed:",
        err && err.message ? err.message : err
      );
      res.status(503).json({ error: "unconfigured" });
      return;
    }

    if (!keyId || !teamId || !privateKey) {
      res.status(503).json({ error: "unconfigured" });
      return;
    }

    const now = Math.floor(Date.now() / 1000);
    const exp = now + APPLE_MUSIC_TOKEN_LIFETIME_SECONDS;

    try {
      const token = jwt.sign(
        { iss: teamId, iat: now, exp },
        privateKey,
        {
          algorithm: "ES256",
          header: { alg: "ES256", kid: keyId },
        }
      );
      res.json({ token, expiresAt: exp });
    } catch (err) {
      console.error(
        "getMusicKitDeveloperToken: sign failed:",
        err && err.message ? err.message : err
      );
      res.status(500).json({ error: "sign_failed" });
    }
  }
);

// --------------- Invite code gate ---------------

// Gen2 HTTP handlers sometimes deliver `req.body` as a Buffer or string instead
// of a parsed object. Normalize so `{ code: "…" }` is always readable.
function inviteRequestBody(req) {
  const b = req.body;
  if (b && typeof b === "object" && !Buffer.isBuffer(b)) {
    return b;
  }
  if (Buffer.isBuffer(b)) {
    try {
      return JSON.parse(b.toString("utf8"));
    } catch (_) {
      return {};
    }
  }
  if (typeof b === "string" && b.trim()) {
    try {
      return JSON.parse(b);
    } catch (_) {
      return {};
    }
  }
  if (req.rawBody && Buffer.isBuffer(req.rawBody)) {
    try {
      return JSON.parse(req.rawBody.toString("utf8"));
    } catch (_) {
      return {};
    }
  }
  return {};
}

// Helper: verify Firebase ID token from the standard `Authorization: Bearer …`
// header used by the deleteAccount endpoint. Returns the uid or null.
async function verifyAuthHeader(req) {
  const header = req.get("Authorization") || "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) return null;
  try {
    const decoded = await admin.auth().verifyIdToken(match[1]);
    return decoded && decoded.uid ? decoded.uid : null;
  } catch (err) {
    console.log("verifyAuthHeader: token rejected:", err && err.message ? err.message : err);
    return null;
  }
}

function appCheckMode() {
  const raw = (process.env.APP_CHECK_MODE || "monitor").toLowerCase();
  return raw === "enforce" ? "enforce" : "monitor";
}

async function verifyAppCheckHeader(req, endpoint) {
  const token = req.get("X-Firebase-AppCheck") || "";
  const mode = appCheckMode();
  if (!token) {
    logWarn("app_check_missing", { endpoint, mode });
    return mode !== "enforce";
  }

  try {
    await admin.appCheck().verifyToken(token);
    return true;
  } catch (err) {
    logWarn("app_check_invalid", { endpoint, mode, message: err.message });
    return mode !== "enforce";
  }
}

// Invite-code constants shared by validate / redeem / generate.
//
// Schema for `inviteCodes/{CODE_UPPER}`:
//   {
//     // Original fields
//     disabled?:   bool,
//     redeemed?:   bool,
//     redeemedBy?: string,         // last redeemer's uid (overwritten on multi-use)
//     redeemedAt?: timestamp,
//     expiresAt?:  timestamp,
//     maxUses?:    int (default 1),
//     useCount?:   int (default 0),
//     // Phase B additions (all optional, backward-compatible)
//     kind?:         "personal" | "creator" | "admin"   // default "personal"
//     createdByUid?: string                              // attribution
//     campaign?:     string                              // free-form tag
//   }
//
// Redeem behavior by kind:
//   personal → write users/{uid}.invitedByUid + return inviter as a suggestion
//   creator  → write users/{uid}.invitedByUid + invitedByKind; no friendship
//   admin    → write users/{uid}.invitedByKind only; no invitedByUid; no friendship
const INVITE_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I
const INVITE_CODE_LENGTH = 8;
const INVITE_KINDS = new Set(["personal", "creator", "admin"]);

function inviteKindFromDoc(data) {
  const raw = typeof data.kind === "string" ? data.kind : "personal";
  return INVITE_KINDS.has(raw) ? raw : "personal";
}

function randomInviteCode() {
  const bytes = crypto.randomBytes(INVITE_CODE_LENGTH);
  let out = "";
  for (let i = 0; i < INVITE_CODE_LENGTH; i++) {
    out += INVITE_CODE_ALPHABET[bytes[i] % INVITE_CODE_ALPHABET.length];
  }
  return out;
}

// `validateInviteCode` (POST { code }) — non-destructive read used by the
// onboarding invite gate to fail fast before we burn an SMS verification.
// Does NOT mark the code redeemed; that happens inside `redeemInviteCode`
// once the user actually completes signup. On success returns the code
// `kind` so the client can show kind-specific confirmation copy.
exports.validateInviteCode = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ valid: false, reason: "method_not_allowed" });
    return;
  }

  if (!(await verifyAppCheckHeader(req, "validateInviteCode"))) {
    res.status(401).json({ valid: false, reason: "invalid_app_check" });
    return;
  }

  // The onboarding gate is the one endpoint we can't strictly require
  // a Firebase Bearer token on — the user hasn't signed in yet. We
  // rate-limit by client IP instead: 20 checks per IP per 10 minutes
  // is generous for legitimate "did I typo my code?" retries and
  // brutal for brute force (each guess is upper-cased + has limited
  // entropy, so 20/600s makes exhausting the code space economically
  // infeasible).
  const ip = clientIPFor(req);
  const allowed = await consumeRateLimitToken("validateInviteCode", ip, {
    max: 20,
    windowSeconds: 600,
  });
  if (!allowed) {
    logWarn("validate_invite_rate_limited", { ip });
    res.status(429).json({ valid: false, reason: "rate_limited" });
    return;
  }

  const body = inviteRequestBody(req);
  const code = typeof body.code === "string" ? body.code.trim().toUpperCase() : "";
  if (!code) {
    res.status(400).json({ valid: false, reason: "missing_code" });
    return;
  }
  try {
    const db = admin.firestore();
    const snap = await db.collection("inviteCodes").doc(code).get();
    if (!snap.exists) {
      const missAllowed = await consumeRateLimitToken("validateInviteCodeMiss", code, {
        max: 5,
        windowSeconds: 3600,
      });
      if (!missAllowed) {
        logWarn("validate_invite_probe_burst", { codeHash: hashForLog(code) });
        res.status(429).json({ valid: false, reason: "rate_limited" });
        return;
      }
      logEvent("validate_invite_rejected", { reason: "not_found" });
      res.json({ valid: false, reason: "not_found" });
      return;
    }
    const data = snap.data() || {};
    if (data.disabled === true) {
      logEvent("validate_invite_rejected", { reason: "disabled" });
      res.json({ valid: false, reason: "disabled" });
      return;
    }
    if (data.expiresAt && data.expiresAt.toMillis && data.expiresAt.toMillis() < Date.now()) {
      logEvent("validate_invite_rejected", { reason: "expired" });
      res.json({ valid: false, reason: "expired" });
      return;
    }
    const maxUses = typeof data.maxUses === "number" ? data.maxUses : 1;
    const useCount = typeof data.useCount === "number" ? data.useCount : 0;
    if (useCount >= maxUses) {
      logEvent("validate_invite_rejected", { reason: "exhausted", kind: inviteKindFromDoc(data) });
      res.json({ valid: false, reason: "exhausted" });
      return;
    }
    logEvent("validate_invite_success", { kind: inviteKindFromDoc(data) });
    res.json({ valid: true, kind: inviteKindFromDoc(data) });
  } catch (err) {
    logError("validate_invite_failed", err);
    res.status(500).json({ valid: false, reason: "server_error" });
  }
});

// --------------- Scheduled cleanup: pushDedupe TTL ---------------
//
// `pushDedupe` docs are written by `shouldSendPush` with a 24h
// `expiresAt`. Nothing reads them after their dedupe window passes,
// but they accumulate indefinitely without a sweeper. This scheduled
// job runs once a day and deletes anything whose `expiresAt` is in
// the past. Bounded batch size keeps invocations short.
exports.cleanupPushDedupe = onSchedule(
  {
    schedule: "every 24 hours",
    timeZone: "Etc/UTC",
    memory: "256MiB",
  },
  async () => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    let totalDeleted = 0;
    // Page in chunks so we don't try to delete millions in one shot
    // if the table is very stale on first deploy.
    for (let i = 0; i < 20; i++) {
      const snap = await db
        .collection("pushDedupe")
        .where("expiresAt", "<", now)
        .limit(500)
        .get();
      if (snap.empty) break;
      const batch = db.batch();
      snap.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
      totalDeleted += snap.size;
      if (snap.size < 500) break;
    }
    if (totalDeleted > 0) {
      console.log(`cleanupPushDedupe: deleted ${totalDeleted} expired entries`);
    }
  }
);

// Recovery sweep for queued songs that should have been delivered when a
// friendship was accepted but weren't (functions not live at accept time, a
// transient read miss, or an early return in onFriendCreated). The single
// onFriendCreated delivery attempt has no retry, so this periodically scans
// pendingFriendShares and re-runs the idempotent pair delivery for any pair
// whose friendship now exists. On its first run after deploy this also
// backfills songs that were stuck before this fix shipped.
exports.retryPendingFriendShares = onSchedule(
  {
    schedule: "every 10 minutes",
    timeZone: "Etc/UTC",
    memory: "256MiB",
  },
  async () => {
    const db = admin.firestore();
    const snap = await db
      .collectionGroup("pendingFriendShares")
      .limit(500)
      .get();
    if (snap.empty) return;

    // Collapse to unique sender/recipient pairs; deliverPendingFriendSharesForPair
    // handles every queued doc for the pair in one call and is idempotent.
    const pairs = new Map();
    for (const doc of snap.docs) {
      const senderId = doc.ref.parent.parent && doc.ref.parent.parent.id;
      const recipientId = (doc.data() || {}).recipientId;
      if (!senderId || !recipientId || senderId === recipientId) continue;
      pairs.set(friendPairKey(senderId, recipientId), { senderId, recipientId });
    }

    let delivered = 0;
    for (const { senderId, recipientId } of pairs.values()) {
      try {
        const res = await deliverPendingFriendSharesForPair(senderId, recipientId);
        delivered += (res && res.count) || 0;
      } catch (err) {
        logError("retry_pending_friend_shares_failed", err, {
          senderId,
          recipientId,
        });
      }
    }

    logEvent("retry_pending_friend_shares_swept", {
      scanned: snap.size,
      pairs: pairs.size,
      delivered,
    });
  }
);

// `redeemInviteCode` (POST { code }) — atomic gateway redeem called from the
// client immediately after profile creation. Bumps `useCount`, stamps
// attribution fields on the new user's doc, and returns the inviter as a
// suggestion when present. It intentionally does NOT create friendships.
exports.redeemInviteCode = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ redeemed: false, reason: "method_not_allowed" });
    return;
  }
  if (!(await verifyAppCheckHeader(req, "redeemInviteCode"))) {
    res.status(401).json({ redeemed: false, reason: "invalid_app_check" });
    return;
  }
  const uid = await verifyAuthHeader(req);
  if (!uid) {
    res.status(401).json({ redeemed: false, reason: "unauthenticated" });
    return;
  }
  const body = inviteRequestBody(req);
  const code = typeof body.code === "string" ? body.code.trim().toUpperCase() : "";
  if (!code) {
    res.status(400).json({ redeemed: false, reason: "missing_code" });
    return;
  }

  const db = admin.firestore();
  const codeRef = db.collection("inviteCodes").doc(code);
  const userRef = db.collection("users").doc(uid);

  try {
    const outcome = await db.runTransaction(async (txn) => {
      const codeSnap = await txn.get(codeRef);
      if (!codeSnap.exists) {
        const err = new Error("not_found");
        err.code = 404;
        throw err;
      }
      const data = codeSnap.data() || {};
      if (data.disabled === true) {
        const err = new Error("disabled");
        err.code = 409;
        throw err;
      }
      if (data.expiresAt && data.expiresAt.toMillis && data.expiresAt.toMillis() < Date.now()) {
        const err = new Error("expired");
        err.code = 409;
        throw err;
      }
      const maxUses = typeof data.maxUses === "number" ? data.maxUses : 1;
      const useCount = typeof data.useCount === "number" ? data.useCount : 0;
      if (useCount >= maxUses) {
        const err = new Error("exhausted");
        err.code = 409;
        throw err;
      }

      const kind = inviteKindFromDoc(data);
      const createdByUid = typeof data.createdByUid === "string" ? data.createdByUid : null;

      let inviterSnap = null;
      if (createdByUid && kind !== "admin" && createdByUid !== uid) {
        inviterSnap = await txn.get(db.collection("users").doc(createdByUid));
      }

      // ----- Writes -----
      txn.update(codeRef, {
        useCount: useCount + 1,
        redeemedBy: uid,
        redeemedAt: admin.firestore.FieldValue.serverTimestamp(),
        redeemed: useCount + 1 >= maxUses,
      });

      // Build user-doc patch. Admin codes get no `invitedByUid` because
      // there's no inviter to attribute to.
      const userPatch = {
        invitedBy: code,
        invitedByKind: kind,
        invitedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (createdByUid && kind !== "admin") {
        userPatch.invitedByUid = createdByUid;
      }
      txn.set(userRef, userPatch, { merge: true });

      const suggestedInviter =
        inviterSnap && inviterSnap.exists
          ? publicUserPayload(createdByUid, inviterSnap.data() || {})
          : null;

      return { kind, suggestedInviter };
    });

    res.json({
      redeemed: true,
      kind: outcome.kind,
      suggestedInviter: outcome.suggestedInviter || null,
    });
    logEvent("redeem_invite_success", {
      uid,
      kind: outcome.kind,
      hasSuggestedInviter: !!outcome.suggestedInviter,
    });
  } catch (err) {
    const status = err && typeof err.code === "number" ? err.code : 500;
    const reason = err && err.message ? err.message : "server_error";
    logWarn("redeem_invite_failed", { uid, status, reason });
    res.status(status).json({ redeemed: false, reason });
  }
});

// `matchContacts` (POST { phones: string[] }) — authenticated lookup used by
// onboarding to suggest contacts who already have Riff accounts. Phone numbers
// are stored in users/{uid}/private/profile and never returned to the client;
// the response contains only safe public profile fields.
exports.matchContacts = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ ok: false, reason: "method_not_allowed" });
    return;
  }
  if (!(await verifyAppCheckHeader(req, "matchContacts"))) {
    res.status(401).json({ ok: false, reason: "invalid_app_check" });
    return;
  }
  const uid = await verifyAuthHeader(req);
  if (!uid) {
    res.status(401).json({ ok: false, reason: "unauthenticated" });
    return;
  }

  const body = inviteRequestBody(req);
  const rawPhones = Array.isArray(body.phones) ? body.phones : [];
  const phones = Array.from(
    new Set(
      rawPhones
        .slice(0, 500)
        .map((phone) => normalizeE164(String(phone || "")))
        .filter(Boolean)
    )
  );

  if (phones.length === 0) {
    res.json({ ok: true, users: [] });
    return;
  }

  const allowed = await consumeRateLimitToken("matchContacts", uid, {
    max: 30,
    windowSeconds: 3600,
  });
  if (!allowed) {
    logWarn("match_contacts_rate_limited", { uid });
    res.status(429).json({ ok: false, reason: "rate_limited" });
    return;
  }

  const db = admin.firestore();
  try {
    const blockedSnap = await db.collection("users").doc(uid).collection("blocked").get();
    const blockedByMe = new Set(blockedSnap.docs.map((doc) => doc.id));
    const matchedUids = new Set();
    const chunkSize = 30;

    // Fire every chunk's collection-group query concurrently. Phone lists can
    // span up to ~17 chunks (500 phones / 30); running them serially added
    // multiple seconds of round-trip latency to onboarding. Promise.all
    // collapses that to roughly a single round-trip.
    const chunkQueries = [];
    for (let i = 0; i < phones.length; i += chunkSize) {
      const chunk = phones.slice(i, i + chunkSize);
      chunkQueries.push(
        db.collectionGroup("private").where("phone", "in", chunk).get()
      );
    }
    const chunkSnaps = await Promise.all(chunkQueries);

    for (const privateMatches of chunkSnaps) {
      for (const doc of privateMatches.docs) {
        if (doc.id !== "profile") continue;
        const userRef = doc.ref.parent.parent;
        const matchedUid = userRef ? userRef.id : null;
        if (!matchedUid || matchedUid === uid || blockedByMe.has(matchedUid)) continue;
        matchedUids.add(matchedUid);
      }
    }

    const profileRefs = Array.from(matchedUids).map((matchedUid) =>
      db.collection("users").doc(matchedUid)
    );
    const publicSnaps = profileRefs.length > 0 ? await db.getAll(...profileRefs) : [];

    // Run the reverse block checks concurrently rather than awaiting one per
    // matched user in series.
    const candidates = publicSnaps.filter((snap) => snap.exists);
    const blockChecks = await Promise.all(
      candidates.map((snap) => isBlockedBy(snap.id, uid))
    );
    const users = [];
    candidates.forEach((snap, idx) => {
      if (blockChecks[idx]) return;
      const payload = publicUserPayload(snap.id, snap.data() || {});
      if (payload && payload.username) users.push(payload);
    });

    logEvent("match_contacts_success", {
      uid,
      inputCount: phones.length,
      matchCount: users.length,
    });
    res.json({ ok: true, users });
  } catch (err) {
    logError("match_contacts_failed", err, { uid, inputCount: phones.length });
    res.status(500).json({ ok: false, reason: "server_error" });
  }
});

// `generateInviteCode` (POST, auth required) — mints a fresh `personal`
// invite code for the calling user. Returns `{ code, destinationURL }`
// which the iOS client wraps in a ChottuLink shortlink via
// `CLDynamicLinkBuilder` (same pattern as the existing referral link).
//
// Rate limit: 10 codes / UID / 24h. Generous for the friend-invite UX
// (each personal invite consumes one because it's single-use) but cheap
// to throttle abuse if a compromised account tries to mint a corpus of
// codes.
//
// Collision handling: 5 retries on doc-already-exists. The 32-char
// alphabet * 8 chars = ~1.1 trillion codes, so collisions are
// astronomically rare. Failures past retry surface as `server_error`
// rather than silently picking a "close enough" code.
exports.generateInviteCode = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ ok: false, reason: "method_not_allowed" });
    return;
  }
  if (!(await verifyAppCheckHeader(req, "generateInviteCode"))) {
    res.status(401).json({ ok: false, reason: "invalid_app_check" });
    return;
  }
  const uid = await verifyAuthHeader(req);
  if (!uid) {
    res.status(401).json({ ok: false, reason: "unauthenticated" });
    return;
  }

  const allowed = await consumeRateLimitToken("generateInviteCode", uid, {
    max: 10,
    windowSeconds: 86400,
  });
  if (!allowed) {
    logWarn("generate_invite_rate_limited", { uid });
    res.status(429).json({ ok: false, reason: "rate_limited" });
    return;
  }

  const db = admin.firestore();
  // Hard-coded for now. If you ever move the TestFlight join link, also
  // update `DeepLinkService.publicTestFlightInviteURL` on iOS so the
  // ChottuLink destination matches what we hand to the client.
  const TESTFLIGHT_URL = "https://testflight.apple.com/join/yRycD1gD";

  try {
    let code = null;
    for (let attempt = 0; attempt < 5; attempt++) {
      const candidate = randomInviteCode();
      const ref = db.collection("inviteCodes").doc(candidate);
      const snap = await ref.get();
      if (snap.exists) continue;
      await ref.set({
        kind: "personal",
        createdByUid: uid,
        redeemed: false,
        useCount: 0,
        maxUses: 1,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      code = candidate;
      break;
    }
    if (!code) {
      logError("generate_invite_collision_exhausted", new Error("collision_exhausted"), { uid });
      res.status(500).json({ ok: false, reason: "server_error" });
      return;
    }

    const destinationURL = `${TESTFLIGHT_URL}?code=${code}`;
    logEvent("generate_invite_success", { uid, kind: "personal" });
    res.json({ ok: true, code, destinationURL });
  } catch (err) {
    logError("generate_invite_failed", err, { uid });
    res.status(500).json({ ok: false, reason: "server_error" });
  }
});
