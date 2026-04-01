const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");

admin.initializeApp();

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
