import { Router } from "express";
import { currentUser, endSession, logIn, signUp, startSession } from "./auth.js";

export const authRouter = Router();

authRouter.post("/signup", async (request, response) => {
  const result = await signUp(request.body);

  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  await startSession(response, result.user.id);
  response.status(201).json({ user: result.user });
});

authRouter.post("/login", async (request, response) => {
  const result = await logIn(request.body);

  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  await startSession(response, result.user.id);
  response.json({ user: result.user });
});

authRouter.post("/logout", async (request, response) => {
  await endSession(request, response);
  response.status(204).end();
});

authRouter.get("/me", async (request, response) => {
  const user = await currentUser(request);

  if (!user) {
    response.status(401).json({ error: "Not signed in" });
    return;
  }

  response.json({ user });
});
