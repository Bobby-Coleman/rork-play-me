import { z } from "zod";
import { createTRPCRouter, publicProcedure } from "../create-context";
import { db } from "@/backend/db";

export const songsRouter = createTRPCRouter({
  getAll: publicProcedure.query(() => {
    return db.songs.getAll();
  }),

  search: publicProcedure
    .input(z.object({ query: z.string() }))
    .query(({ input }) => {
      return db.songs.search(input.query);
    }),
});
