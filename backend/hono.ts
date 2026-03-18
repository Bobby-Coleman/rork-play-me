import { Hono } from "hono";
import { cors } from "hono/cors";
import { trpcServer } from "@hono/trpc-server";
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

app.get("/", (c) => c.json({ status: "ok" }));

app.post("/rest/users/register", async (c) => {
  const body = await c.req.json();
  const { phone, firstName, username } = body;
  if (!phone || !firstName || !username) return c.json({ error: "Missing required fields" }, 400);
  const existing = await db.users.getByPhone(phone);
  if (existing) return c.json(existing);
  const available = await db.users.checkUsername(username);
  if (!available) return c.json({ error: "Username taken" }, 409);
  const user = await db.users.create({ phone, firstName, username });
  return c.json(user);
});

app.get("/rest/users/by-phone/:phone", async (c) => {
  const phone = c.req.param("phone");
  const user = await db.users.getByPhone(phone);
  if (!user) return c.json({ error: "Not found" }, 404);
  return c.json(user);
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
  if (excludeUserId) results = results.filter((u: any) => u.id !== excludeUserId);
  return c.json(results);
});

app.get("/rest/users/:userId/friends", async (c) => {
  const userId = c.req.param("userId");
  return c.json(await db.connections.getFriends(userId));
});

app.get("/rest/songs", async (c) => {
  const query = c.req.query("q");
  if (query) return c.json(await db.songs.search(query));
  return c.json(await db.songs.getAll());
});

app.post("/rest/shares", async (c) => {
  const body = await c.req.json();
  const { senderId, recipientId, songId, note } = body;
  if (!senderId || !recipientId || !songId) return c.json({ error: "Missing required fields" }, 400);
  const share = await db.shares.create({ senderId, recipientId, songId, note: note ?? null });
  const song = await db.songs.getById(share.songId);
  const sender = await db.users.getById(share.senderId);
  const recipient = await db.users.getById(share.recipientId);
  return c.json({ ...share, song, sender, recipient });
});

app.get("/rest/shares/received/:userId", async (c) => {
  const userId = c.req.param("userId");
  const rawShares = await db.shares.getReceived(userId);
  const enriched = await Promise.all(rawShares.map(async (s: any) => ({
    ...s,
    song: await db.songs.getById(s.songId),
    sender: await db.users.getById(s.senderId),
    recipient: await db.users.getById(s.recipientId),
  })));
  return c.json(enriched);
});

app.get("/rest/shares/sent/:userId", async (c) => {
  const userId = c.req.param("userId");
  const rawShares = await db.shares.getSent(userId);
  const enriched = await Promise.all(rawShares.map(async (s: any) => ({
    ...s,
    song: await db.songs.getById(s.songId),
    sender: await db.users.getById(s.senderId),
    recipient: await db.users.getById(s.recipientId),
  })));
  return c.json(enriched);
});

app.post("/rest/connections", async (c) => {
  const body = await c.req.json();
  const { userAId, userBId } = body;
  if (!userAId || !userBId) return c.json({ error: "Missing required fields" }, 400);
  const exists = await db.connections.exists(userAId, userBId);
  if (exists) return c.json({ message: "Already connected" });
  return c.json(await db.connections.create(userAId, userBId));
});

export default app;
