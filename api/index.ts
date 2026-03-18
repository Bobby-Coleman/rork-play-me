import { Hono } from "hono";
import backendApp from "../backend/hono";

const app = new Hono();
app.route("/api", backendApp);

export default app;
