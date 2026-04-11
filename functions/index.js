const { onRequest } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const crypto = require("crypto");

admin.initializeApp();

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
