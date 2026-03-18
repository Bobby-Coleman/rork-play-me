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
    .mutation(async ({ input }) => {
      const share = await db.shares.create({
        sender_id: input.senderId,
        recipient_id: input.recipientId,
        song_id: input.songId,
        note: input.note,
      });
      const [song, sender, recipient] = await Promise.all([
        db.songs.getById(share.song_id),
        db.users.getById(share.sender_id),
        db.users.getById(share.recipient_id),
      ]);
      return { ...share, song, sender, recipient };
    }),

  getReceived: publicProcedure
    .input(z.object({ userId: z.string() }))
    .query(async ({ input }) => {
      const rawShares = await db.shares.getReceived(input.userId);
      return Promise.all(rawShares.map(async (s) => {
        const [song, sender, recipient] = await Promise.all([
          db.songs.getById(s.song_id),
          db.users.getById(s.sender_id),
          db.users.getById(s.recipient_id),
        ]);
        return { ...s, song, sender, recipient };
      }));
    }),

  getSent: publicProcedure
    .input(z.object({ userId: z.string() }))
    .query(async ({ input }) => {
      const rawShares = await db.shares.getSent(input.userId);
      return Promise.all(rawShares.map(async (s) => {
        const [song, sender, recipient] = await Promise.all([
          db.songs.getById(s.song_id),
          db.users.getById(s.sender_id),
          db.users.getById(s.recipient_id),
        ]);
        return { ...s, song, sender, recipient };
      }));
    }),

  getById: publicProcedure
    .input(z.object({ id: z.string() }))
    .query(async ({ input }) => {
      const share = await db.shares.getById(input.id);
      if (!share) return null;
      const [song, sender, recipient] = await Promise.all([
        db.songs.getById(share.song_id),
        db.users.getById(share.sender_id),
        db.users.getById(share.recipient_id),
      ]);
      return { ...share, song, sender, recipient };
    }),
});
