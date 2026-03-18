import { z } from "zod";
import { createTRPCRouter, publicProcedure } from "../create-context";
import { db } from "@/backend/db";

export const sharesRouter = createTRPCRouter({
  send: publicProcedure
    .input(z.object({
      senderId: z.string(),
      recipientId: z.string(),
      songId: z.string(),
      note: z.string().nullable(),
    }))
    .mutation(({ input }) => {
      const share = db.shares.create(input);
      const song = db.songs.getById(input.songId);
      const sender = db.users.getById(input.senderId);
      const recipient = db.users.getById(input.recipientId);
      return { ...share, song, sender, recipient };
    }),

  getReceived: publicProcedure
    .input(z.object({ userId: z.string() }))
    .query(({ input }) => {
      const rawShares = db.shares.getReceived(input.userId);
      return rawShares.map(s => ({
        ...s,
        song: db.songs.getById(s.songId),
        sender: db.users.getById(s.senderId),
        recipient: db.users.getById(s.recipientId),
      }));
    }),

  getSent: publicProcedure
    .input(z.object({ userId: z.string() }))
    .query(({ input }) => {
      const rawShares = db.shares.getSent(input.userId);
      return rawShares.map(s => ({
        ...s,
        song: db.songs.getById(s.songId),
        sender: db.users.getById(s.senderId),
        recipient: db.users.getById(s.recipientId),
      }));
    }),

  getById: publicProcedure
    .input(z.object({ id: z.string() }))
    .query(({ input }) => {
      const share = db.shares.getById(input.id);
      if (!share) return null;
      return {
        ...share,
        song: db.songs.getById(share.songId),
        sender: db.users.getById(share.senderId),
        recipient: db.users.getById(share.recipientId),
      };
    }),
});
