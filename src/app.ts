import express, { type Express } from "express";
import morgan from "morgan";

import { routerAPI } from "./routes/index.js";

const app: Express = express();


// Config morgan middleware to add logs
app.use(morgan("dev"));

// Config json middleware
app.use(express.json());

// Adding the main router
routerAPI(app);

export default app;