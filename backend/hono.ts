import { trpcServer } from "@hono/trpc-server";
import { Hono } from "hono";
import { cors } from "hono/cors";

import { appRouter } from "./trpc/app-router";
import { createContext } from "./trpc/create-context";
import { db, type DbUser, type DbSong, type DbShare } from "./db";

const app = new Hono();

app.use("*", cors());

app.use(
  "/trpc/*",
  trpcServer({
    endpoint: "/api/trpc",
    router: appRouter,
    createContext,
  }),
);

function mapUser(u: DbUser) {
  return { id: u.id, phone: u.phone, firstName: u.first_name, username: u.username, createdAt: u.created_at };
}

function mapSong(s: DbSong) {
  return { id: s.id, title: s.title, artist: s.artist, albumArtURL: s.album_art_url, duration: s.duration };
}

function mapShare(s: DbShare) {
  return { id: s.id, senderId: s.sender_id, recipientId: s.recipient_id, songId: s.song_id, note: s.note, createdAt: s.created_at };
}

app.get("/", (c) => {
  return c.json({ status: "ok", message: "PlayMe API is running" });
});

app.post("/rest/users/register", async (c) => {
  const body = await c.req.json();
  const { phone, firstName, username } = body;
  if (!phone || !firstName || !username) {
    return c.json({ error: "Missing required fields" }, 400);
  }
  const existing = await db.users.getByPhone(phone);
  if (existing) {
    return c.json(mapUser(existing));
  }
  const available = await db.users.checkUsername(username);
  if (!available) {
    return c.json({ error: "Username taken" }, 409);
  }
  const user = await db.users.create({ phone, first_name: firstName, username });
  return c.json(mapUser(user));
});

app.get("/rest/users/by-phone/:phone", async (c) => {
  const phone = c.req.param("phone");
  const user = await db.users.getByPhone(phone);
  if (!user) return c.json({ error: "Not found" }, 404);
  return c.json(mapUser(user));
});

app.get("/rest/users/check-username/:username", async (c) => {
  const username = c.req.param("username");
  const available = await db.users.checkUsername(username);
  return c.json({ available });
});

app.get("/rest/users/search", async (c) => {
  const query = c.req.query("q") ?? "";
  const excludeUserId = c.req.query("excludeUserId");
  let results = await db.users.searchByUsername(query);
  if (excludeUserId) {
    results = results.filter(u => u.id !== excludeUserId);
  }
  return c.json(results.map(mapUser));
});

app.get("/rest/users/:userId/friends", async (c) => {
  const userId = c.req.param("userId");
  const friends = await db.connections.getFriends(userId);
  return c.json(friends.map(mapUser));
});

app.get("/rest/songs", async (c) => {
  const query = c.req.query("q");
  const songs = query ? await db.songs.search(query) : await db.songs.getAll();
  return c.json(songs.map(mapSong));
});

app.post("/rest/shares", async (c) => {
  const body = await c.req.json();
  const { senderId, recipientId, songId, note } = body;
  if (!senderId || !recipientId || !songId) {
    return c.json({ error: "Missing required fields" }, 400);
  }
  const share = await db.shares.create({ sender_id: senderId, recipient_id: recipientId, song_id: songId, note: note ?? null });
  const [song, sender, recipient] = await Promise.all([
    db.songs.getById(share.song_id),
    db.users.getById(share.sender_id),
    db.users.getById(share.recipient_id),
  ]);
  return c.json({
    ...mapShare(share),
    song: song ? mapSong(song) : null,
    sender: sender ? mapUser(sender) : null,
    recipient: recipient ? mapUser(recipient) : null,
  });
});

async function enrichShares(rawShares: DbShare[]) {
  return Promise.all(rawShares.map(async (s) => {
    const [song, sender, recipient] = await Promise.all([
      db.songs.getById(s.song_id),
      db.users.getById(s.sender_id),
      db.users.getById(s.recipient_id),
    ]);
    return {
      ...mapShare(s),
      song: song ? mapSong(song) : null,
      sender: sender ? mapUser(sender) : null,
      recipient: recipient ? mapUser(recipient) : null,
    };
  }));
}

app.get("/rest/shares/received/:userId", async (c) => {
  const userId = c.req.param("userId");
  const rawShares = await db.shares.getReceived(userId);
  return c.json(await enrichShares(rawShares));
});

app.get("/rest/shares/sent/:userId", async (c) => {
  const userId = c.req.param("userId");
  const rawShares = await db.shares.getSent(userId);
  return c.json(await enrichShares(rawShares));
});

app.get("/rest/shares/:id", async (c) => {
  const id = c.req.param("id");
  const share = await db.shares.getById(id);
  if (!share) return c.json({ error: "Not found" }, 404);
  const [song, sender, recipient] = await Promise.all([
    db.songs.getById(share.song_id),
    db.users.getById(share.sender_id),
    db.users.getById(share.recipient_id),
  ]);
  return c.json({
    ...mapShare(share),
    song: song ? mapSong(song) : null,
    sender: sender ? mapUser(sender) : null,
    recipient: recipient ? mapUser(recipient) : null,
  });
});

app.post("/rest/connections", async (c) => {
  const body = await c.req.json();
  const { userAId, userBId } = body;
  if (!userAId || !userBId) {
    return c.json({ error: "Missing required fields" }, 400);
  }
  const exists = await db.connections.exists(userAId, userBId);
  if (exists) {
    return c.json({ message: "Already connected" });
  }
  const conn = await db.connections.create(userAId, userBId);
  return c.json(conn);
});

export default app;
