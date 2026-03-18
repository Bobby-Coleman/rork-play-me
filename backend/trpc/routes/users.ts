import { z } from "zod";
import { createTRPCRouter, publicProcedure } from "../create-context";
import { db } from "../../db";

export const usersRouter = createTRPCRouter({
  register: publicProcedure
    .input(z.object({
      phone: z.string(),
      firstName: z.string(),
      username: z.string(),
    }))
    .mutation(async ({ input }) => {
      const existing = await db.users.getByPhone(input.phone);
      if (existing) {
        return existing;
      }
      const available = await db.users.checkUsername(input.username);
      if (!available) {
        throw new Error("Username taken");
      }
      return await db.users.create(input);
    }),

  getByPhone: publicProcedure
    .input(z.object({ phone: z.string() }))
    .query(async ({ input }) => {
      return (await db.users.getByPhone(input.phone)) ?? null;
    }),

  checkUsername: publicProcedure
    .input(z.object({ username: z.string() }))
    .query(async ({ input }) => {
      return { available: await db.users.checkUsername(input.username) };
    }),

  search: publicProcedure
    .input(z.object({ query: z.string(), excludeUserId: z.string().optional() }))
    .query(async ({ input }) => {
      let results = await db.users.searchByUsername(input.query);
      if (input.excludeUserId) {
        results = results.filter(u => u.id !== input.excludeUserId);
      }
      return results;
    }),

  getFriends: publicProcedure
    .input(z.object({ userId: z.string() }))
    .query(async ({ input }) => {
      return await db.connections.getFriends(input.userId);
    }),
});
