import { z } from "zod";
import { createTRPCRouter, publicProcedure } from "../create-context";
import { db } from "../../db";

export const sharesRouter = createTRPCRouter({
  send: publicProcedure
    .input(z.object({
      senderId: z.string(),
      recipientId: z.string(),
      songId: z.string(),
      note: z.string().nullable(),
    }))
    .mutation(async ({ input }) => {
      const share = await db.shares.create(input);
      const song = await db.songs.getById(input.songId);
      const sender = await db.users.getById(input.senderId);
      const recipient = await db.users.getById(input.recipientId);
      return { ...share, song, sender, recipient };
    }),

  getReceived: publicProcedure
    .input(z.object({ userId: z.string() }))
    .query(async ({ input }) => {
      const rawShares = await db.shares.getReceived(input.userId);
      return await Promise.all(rawShares.map(async s => ({
        ...s,
        song: await db.songs.getById(s.songId),
        sender: await db.users.getById(s.senderId),
        recipient: await db.users.getById(s.recipientId),
      })));
    }),

  getSent: publicProcedure
    .input(z.object({ userId: z.string() }))
    .query(async ({ input }) => {
      const rawShares = await db.shares.getSent(input.userId);
      return await Promise.all(rawShares.map(async s => ({
        ...s,
        song: await db.songs.getById(s.songId),
        sender: await db.users.getById(s.senderId),
        recipient: await db.users.getById(s.recipientId),
      })));
    }),

  getById: publicProcedure
    .input(z.object({ id: z.string() }))
    .query(async ({ input }) => {
      const share = await db.shares.getById(input.id);
      if (!share) return null;
      return {
        ...share,
        song: await db.songs.getById(share.songId),
        sender: await db.users.getById(share.senderId),
        recipient: await db.users.getById(share.recipientId),
      };
    }),
});
