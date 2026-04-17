const { onRequest } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
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

async function sendPush(token, title, body, extraData = {}) {
  if (!token) return;
  try {
    await admin.messaging().send({
      token,
      notification: { title, body },
      data: extraData,
      apns: { payload: { aps: { sound: "default", badge: 1 } } },
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

  const senderName = data.sender?.firstName || "Someone";
  const songTitle = data.song?.title || "a song";

  const token = await getFCMToken(recipientId);
  await sendPush(token, "New Song 🎵", `${senderName} sent you "${songTitle}"`, {
    type: "new_share",
    shareId: event.params.shareId,
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
      const token = await getFCMToken(uid);
      await sendPush(token, senderName, text || "Sent a message", {
        type: "new_message",
        conversationId: convId,
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

    const likerName = await getUserName(likerId);
    const songTitle = shareData.song?.title || "a song";

    const token = await getFCMToken(senderId);
    await sendPush(token, "PlayMe", `${likerName} liked "${songTitle}"`, {
      type: "like",
      shareId,
    });
  }
);

exports.onNewFriend = onDocumentCreated(
  "users/{userId}/friends/{friendId}",
  async (event) => {
    const adderId = event.params.userId;
    const friendId = event.params.friendId;

    const adderName = await getUserName(adderId);
    const token = await getFCMToken(friendId);
    await sendPush(token, "PlayMe", `${adderName} added you on PlayMe`, {
      type: "friend_added",
      friendId: adderId,
    });
  }
);

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

  const myToken = await getFCMToken(uid);

  let claimed = 0;
  const pushPromises = [];

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

      // Fire a magic-moment push to the new user for every claimed share.
      pushPromises.push(
        sendPush(
          myToken,
          "PlayMe",
          `${senderFirstName || "A friend"} sent you "${song.title || "a song"}"`,
          {
            type: "new_share",
            shareId: doc.id,
            claimedFromPending: "true",
          }
        )
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

  await Promise.all(pushPromises);
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
