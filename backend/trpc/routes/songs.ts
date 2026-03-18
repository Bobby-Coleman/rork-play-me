import { z } from "zod";
import { createTRPCRouter, publicProcedure } from "../create-context";
import { db } from "../../db";

export const songsRouter = createTRPCRouter({
  getAll: publicProcedure.query(async () => {
    return await db.songs.getAll();
  }),

  search: publicProcedure
    .input(z.object({ query: z.string() }))
    .query(async ({ input }) => {
      return await db.songs.search(input.query);
    }),
});
