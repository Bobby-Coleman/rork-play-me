import { createTRPCRouter } from "./create-context";
import { usersRouter } from "./routes/users";
import { songsRouter } from "./routes/songs";
import { sharesRouter } from "./routes/shares";

export const appRouter = createTRPCRouter({
  users: usersRouter,
  songs: songsRouter,
  shares: sharesRouter,
});

export type AppRouter = typeof appRouter;
