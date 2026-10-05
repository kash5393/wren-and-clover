#!/usr/bin/env bash
# Unit 7, final step: security pass for the API.
# Run from the wren-and-clover project folder:  bash unit7-security.sh
set -e
if ! grep -q "getSavedShipping" server/src/index.ts 2>/dev/null; then echo "Run this inside the wren-and-clover folder, after the saved-details step."; exit 1; fi
(cd server && npm install express-rate-limit helmet)
cat > server/src/auth.ts << 'WREN_EOF'
import { randomBytes } from "node:crypto";
import bcrypt from "bcryptjs";
import type { NextFunction, Request, Response } from "express";
import { z } from "zod";
import { pool } from "./db.js";

export const SESSION_COOKIE = "session";
const SESSION_DAYS = 7;
const SESSION_MS = SESSION_DAYS * 24 * 60 * 60 * 1000;

export interface User {
  id: number;
  email: string;
  name: string;
  role: "customer" | "owner";
}

interface UserRow extends User {
  password_hash: string;
}

type AuthResult =
  | { ok: true; user: User }
  | { ok: false; status: number; error: string };

const signupSchema = z.object({
  name: z.string().trim().min(1, "Name is required"),
  email: z.email("A valid email is required"),
  password: z.string().min(8, "Password must be at least 8 characters"),
});

const loginSchema = z.object({
  email: z.email("A valid email is required"),
  password: z.string().min(1, "Password is required"),
});

function toUser(row: UserRow): User {
  return { id: row.id, email: row.email, name: row.name, role: row.role };
}

export async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, 12);
}

export async function signUp(body: unknown): Promise<AuthResult> {
  const parsed = signupSchema.safeParse(body);
  if (!parsed.success) {
    return { ok: false, status: 400, error: parsed.error.issues[0]?.message ?? "Invalid details" };
  }

  const { name, password } = parsed.data;
  const email = parsed.data.email.toLowerCase();

  const existing = await pool.query("SELECT 1 FROM users WHERE email = $1", [email]);
  if (existing.rowCount && existing.rowCount > 0) {
    return { ok: false, status: 409, error: "An account with this email already exists" };
  }

  const result = await pool.query<UserRow>(
    `INSERT INTO users (email, name, password_hash)
     VALUES ($1, $2, $3)
     RETURNING id, email, name, role, password_hash`,
    [email, name, await hashPassword(password)]
  );

  return { ok: true, user: toUser(result.rows[0]!) };
}

export async function logIn(body: unknown): Promise<AuthResult> {
  const parsed = loginSchema.safeParse(body);
  const wrong: AuthResult = { ok: false, status: 401, error: "Email or password is incorrect" };
  if (!parsed.success) {
    return wrong;
  }

  const result = await pool.query<UserRow>(
    "SELECT id, email, name, role, password_hash FROM users WHERE email = $1",
    [parsed.data.email.toLowerCase()]
  );
  const row = result.rows[0];
  if (!row) {
    return wrong;
  }

  const matches = await bcrypt.compare(parsed.data.password, row.password_hash);
  return matches ? { ok: true, user: toUser(row) } : wrong;
}

export async function startSession(response: Response, userId: number): Promise<void> {
  const sessionId = randomBytes(32).toString("hex");
  const expiresAt = new Date(Date.now() + SESSION_MS);

  await pool.query("INSERT INTO sessions (id, user_id, expires_at) VALUES ($1, $2, $3)", [
    sessionId,
    userId,
    expiresAt,
  ]);

  response.cookie(SESSION_COOKIE, sessionId, {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    maxAge: SESSION_MS,
    path: "/",
  });
}

export async function deleteExpiredSessions(): Promise<number> {
  const result = await pool.query("DELETE FROM sessions WHERE expires_at <= now()");
  return result.rowCount ?? 0;
}

export async function endSession(request: Request, response: Response): Promise<void> {
  const sessionId: unknown = request.cookies?.[SESSION_COOKIE];
  if (typeof sessionId === "string") {
    await pool.query("DELETE FROM sessions WHERE id = $1", [sessionId]);
  }
  response.clearCookie(SESSION_COOKIE, { path: "/" });
}

export async function currentUser(request: Request): Promise<User | null> {
  const sessionId: unknown = request.cookies?.[SESSION_COOKIE];
  if (typeof sessionId !== "string") {
    return null;
  }

  const result = await pool.query<User>(
    `SELECT u.id, u.email, u.name, u.role
     FROM sessions s
     JOIN users u ON u.id = s.user_id
     WHERE s.id = $1 AND s.expires_at > now()`,
    [sessionId]
  );

  return result.rows[0] ?? null;
}

export async function requireUser(
  request: Request,
  response: Response,
  next: NextFunction
): Promise<void> {
  const user = await currentUser(request);

  if (!user) {
    response.status(401).json({ error: "Please sign in first" });
    return;
  }

  response.locals.user = user;
  next();
}

export async function requireOwner(
  request: Request,
  response: Response,
  next: NextFunction
): Promise<void> {
  const user = await currentUser(request);

  if (!user) {
    response.status(401).json({ error: "Please sign in first" });
    return;
  }
  if (user.role !== "owner") {
    response.status(403).json({ error: "Only the shop owner can do this" });
    return;
  }

  response.locals.user = user;
  next();
}
WREN_EOF

cat > server/src/auth-routes.ts << 'WREN_EOF'
import { Router } from "express";
import { rateLimit } from "express-rate-limit";
import { currentUser, endSession, logIn, signUp, startSession } from "./auth.js";

export const authRouter = Router();

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many attempts. Please wait 15 minutes and try again." },
});

authRouter.post("/signup", authLimiter, async (request, response) => {
  const result = await signUp(request.body);

  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  await startSession(response, result.user.id);
  response.status(201).json({ user: result.user });
});

authRouter.post("/login", authLimiter, async (request, response) => {
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
WREN_EOF

cat > server/src/index.ts << 'WREN_EOF'
import cookieParser from "cookie-parser";
import express from "express";
import helmet from "helmet";
import type { NextFunction, Request, Response } from "express";
import { authRouter } from "./auth-routes.js";
import { currentUser, deleteExpiredSessions, requireOwner, requireUser } from "./auth.js";
import type { User } from "./auth.js";
import { createOrder, getSavedShipping, listAllOrders, listOrdersForUser } from "./orders.js";
import {
  createProduct,
  deleteProduct,
  getProduct,
  listCategories,
  loadProducts,
  updateProduct,
} from "./products.js";

const app = express();
const port = Number(process.env.PORT) || 4000;

app.disable("x-powered-by");
app.use(helmet());
app.use(express.json({ limit: "100kb" }));
app.use(cookieParser());

app.use("/api/auth", authRouter);

app.get("/api/health", (_request, response) => {
  response.json({ status: "ok" });
});

app.get("/api/products", async (request, response) => {
  const { category, search, inStock } = request.query;

  const products = await loadProducts({
    category: typeof category === "string" ? category : undefined,
    search: typeof search === "string" ? search.trim() : undefined,
    inStock: inStock === "true",
  });

  response.json(products);
});

app.get("/api/products/:id", async (request, response) => {
  const product = await getProduct(request.params.id);

  if (!product) {
    response.status(404).json({ error: "Product not found" });
    return;
  }

  response.json(product);
});

app.post("/api/products", requireOwner, async (request, response) => {
  const result = await createProduct(request.body);

  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  response.status(201).json(result.product);
});

app.patch("/api/products/:id", requireOwner, async (request, response) => {
  const result = await updateProduct(String(request.params.id), request.body);

  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  response.json(result.product);
});

app.delete("/api/products/:id", requireOwner, async (request, response) => {
  const outcome = await deleteProduct(String(request.params.id));

  if (outcome === "not-found") {
    response.status(404).json({ error: "Product not found" });
    return;
  }
  if (outcome === "in-use") {
    response
      .status(409)
      .json({ error: "This product appears in past orders, so it cannot be deleted" });
    return;
  }

  response.status(204).end();
});

app.get("/api/categories", async (_request, response) => {
  response.json(await listCategories());
});

app.post("/api/orders", async (request, response) => {
  const user = await currentUser(request);
  const result = await createOrder(request.body, user ? user.id : null);

  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  console.log(`New order ${result.order.orderNumber}: $${result.order.total}`);
  response.status(201).json(result.order);
});

app.get("/api/account/shipping", requireUser, async (_request, response) => {
  const user = response.locals.user as User;
  response.json({ shipping: await getSavedShipping(user.id) });
});

app.get("/api/orders/mine", requireUser, async (_request, response) => {
  const user = response.locals.user as User;
  response.json(await listOrdersForUser(user.id));
});

app.get("/api/orders", requireOwner, async (_request, response) => {
  response.json(await listAllOrders());
});

app.use((_request, response) => {
  response.status(404).json({ error: "Not found" });
});

app.use((error: unknown, _request: Request, response: Response, _next: NextFunction) => {
  if (error instanceof SyntaxError) {
    response.status(400).json({ error: "The request body is not valid JSON" });
    return;
  }

  console.error(error);
  response.status(500).json({ error: "Something went wrong on the server" });
});

app.listen(port, () => {
  console.log(`Shop API running at http://localhost:${port}`);

  deleteExpiredSessions()
    .then((count) => {
      if (count > 0) {
        console.log(`Removed ${count} expired sessions.`);
      }
    })
    .catch((error: unknown) => console.error(error));
});
WREN_EOF

(cd server && npm run check)
echo
echo "Done. Restart the API:  cd server && npm run dev"
