import { trpcServer } from "@hono/trpc-server";
import { Hono } from "hono";
import { cors } from "hono/cors";

import { appRouter } from "./trpc/app-router";
import { createContext } from "./trpc/create-context";
import { db } from "./db";

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

app.get("/", (c) => {
  return c.json({ status: "ok", message: "PlayMe API is running" });
});

app.post("/rest/users/register", async (c) => {
  const body = await c.req.json();
  const { phone, firstName, username } = body;
  if (!phone || !firstName || !username) {
    return c.json({ error: "Missing required fields" }, 400);
  }
  const existing = db.users.getByPhone(phone);
  if (existing) {
    return c.json(existing);
  }
  if (!db.users.checkUsername(username)) {
    return c.json({ error: "Username taken" }, 409);
  }
  const user = db.users.create({ phone, firstName, username });
  return c.json(user);
});

app.get("/rest/users/by-phone/:phone", (c) => {
  const phone = c.req.param("phone");
  const user = db.users.getByPhone(phone);
  if (!user) return c.json({ error: "Not found" }, 404);
  return c.json(user);
});

app.get("/rest/users/check-username/:username", (c) => {
  const username = c.req.param("username");
  return c.json({ available: db.users.checkUsername(username) });
});

app.get("/rest/users/search", (c) => {
  const query = c.req.query("q") ?? "";
  const excludeUserId = c.req.query("excludeUserId");
  let results = db.users.searchByUsername(query);
  if (excludeUserId) {
    results = results.filter(u => u.id !== excludeUserId);
  }
  return c.json(results);
});

app.get("/rest/users/:userId/friends", (c) => {
  const userId = c.req.param("userId");
  return c.json(db.connections.getFriends(userId));
});

app.get("/rest/songs", (c) => {
  const query = c.req.query("q");
  if (query) {
    return c.json(db.songs.search(query));
  }
  return c.json(db.songs.getAll());
});

app.post("/rest/shares", async (c) => {
  const body = await c.req.json();
  const { senderId, recipientId, songId, note } = body;
  if (!senderId || !recipientId || !songId) {
    return c.json({ error: "Missing required fields" }, 400);
  }
  const share = db.shares.create({ senderId, recipientId, songId, note: note ?? null });
  const song = db.songs.getById(share.songId);
  const sender = db.users.getById(share.senderId);
  const recipient = db.users.getById(share.recipientId);
  return c.json({ ...share, song, sender, recipient });
});

app.get("/rest/shares/received/:userId", (c) => {
  const userId = c.req.param("userId");
  const rawShares = db.shares.getReceived(userId);
  const enriched = rawShares.map(s => ({
    ...s,
    song: db.songs.getById(s.songId),
    sender: db.users.getById(s.senderId),
    recipient: db.users.getById(s.recipientId),
  }));
  return c.json(enriched);
});

app.get("/rest/shares/sent/:userId", (c) => {
  const userId = c.req.param("userId");
  const rawShares = db.shares.getSent(userId);
  const enriched = rawShares.map(s => ({
    ...s,
    song: db.songs.getById(s.songId),
    sender: db.users.getById(s.senderId),
    recipient: db.users.getById(s.recipientId),
  }));
  return c.json(enriched);
});

app.get("/rest/shares/:id", (c) => {
  const id = c.req.param("id");
  const share = db.shares.getById(id);
  if (!share) return c.json({ error: "Not found" }, 404);
  return c.json({
    ...share,
    song: db.songs.getById(share.songId),
    sender: db.users.getById(share.senderId),
    recipient: db.users.getById(share.recipientId),
  });
});

app.post("/rest/connections", async (c) => {
  const body = await c.req.json();
  const { userAId, userBId } = body;
  if (!userAId || !userBId) {
    return c.json({ error: "Missing required fields" }, 400);
  }
  if (db.connections.exists(userAId, userBId)) {
    return c.json({ message: "Already connected" });
  }
  const conn = db.connections.create(userAId, userBId);
  return c.json(conn);
});

export default app;
