import { z } from "zod";
import { createTRPCRouter, publicProcedure } from "../create-context";
import { db } from "@/backend/db";

export const usersRouter = createTRPCRouter({
  register: publicProcedure
    .input(z.object({
      phone: z.string(),
      firstName: z.string(),
      username: z.string(),
    }))
    .mutation(({ input }) => {
      const existing = db.users.getByPhone(input.phone);
      if (existing) {
        return existing;
      }
      if (!db.users.checkUsername(input.username)) {
        throw new Error("Username taken");
      }
      return db.users.create(input);
    }),

  getByPhone: publicProcedure
    .input(z.object({ phone: z.string() }))
    .query(({ input }) => {
      return db.users.getByPhone(input.phone) ?? null;
    }),

  checkUsername: publicProcedure
    .input(z.object({ username: z.string() }))
    .query(({ input }) => {
      return { available: db.users.checkUsername(input.username) };
    }),

  search: publicProcedure
    .input(z.object({ query: z.string(), excludeUserId: z.string().optional() }))
    .query(({ input }) => {
      let results = db.users.searchByUsername(input.query);
      if (input.excludeUserId) {
        results = results.filter(u => u.id !== input.excludeUserId);
      }
      return results;
    }),

  getFriends: publicProcedure
    .input(z.object({ userId: z.string() }))
    .query(({ input }) => {
      return db.connections.getFriends(input.userId);
    }),
});
