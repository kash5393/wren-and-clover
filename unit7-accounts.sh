#!/usr/bin/env bash
# Unit 7, step 1: accounts in the API (users, sessions, signup, login, logout).
# Run from the wren-and-clover project folder:  bash unit7-accounts.sh
set -e
if [ ! -f server/src/db.ts ]; then echo "Run this inside the wren-and-clover folder, after Unit 6 (server/src/db.ts not found)."; exit 1; fi
cd server
npm install bcryptjs cookie-parser
npm install -D @types/cookie-parser
grep -q OWNER_EMAIL .env || printf 'OWNER_EMAIL=owner@wrenandclover.test
OWNER_PASSWORD=change-this-owner-password
' >> .env
grep -q OWNER_EMAIL .env.example || printf 'OWNER_EMAIL=owner@example.com
OWNER_PASSWORD=choose-a-strong-password
' >> .env.example

cat > db/schema.sql << 'WREN_EOF'
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS sessions;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS products;

CREATE TABLE products (
  id TEXT PRIMARY KEY,
  position SERIAL,
  name TEXT NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('Soaps', 'Lotions', 'Bath', 'Gift sets')),
  price_cents INTEGER NOT NULL CHECK (price_cents > 0),
  size TEXT NOT NULL,
  scents TEXT[] NOT NULL,
  description TEXT NOT NULL,
  stock INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0)
);

CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'customer' CHECK (role IN ('customer', 'owner')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE orders (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users (id),
  order_number TEXT GENERATED ALWAYS AS ('WC-' || (1000 + id)) STORED,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  customer_name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT NOT NULL,
  address TEXT NOT NULL,
  city TEXT NOT NULL,
  state TEXT NOT NULL,
  postcode TEXT NOT NULL,
  total_cents INTEGER NOT NULL
);

CREATE TABLE order_items (
  id SERIAL PRIMARY KEY,
  order_id INTEGER NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
  product_id TEXT NOT NULL REFERENCES products (id),
  product_name TEXT NOT NULL,
  scent TEXT NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price_cents INTEGER NOT NULL
);

CREATE INDEX order_items_order_id_idx ON order_items (order_id);
CREATE INDEX orders_user_id_idx ON orders (user_id);
WREN_EOF

cat > src/auth.ts << 'WREN_EOF'
import { randomBytes } from "node:crypto";
import bcrypt from "bcryptjs";
import type { Request, Response } from "express";
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
WREN_EOF

cat > src/auth-routes.ts << 'WREN_EOF'
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
WREN_EOF

cat > src/setup-db.ts << 'WREN_EOF'
import { readFile } from "node:fs/promises";
import { hashPassword } from "./auth.js";
import { pool } from "./db.js";
import type { Product } from "./types.js";

const schemaFile = new URL("../db/schema.sql", import.meta.url);
const seedFile = new URL("../data/products.json", import.meta.url);

async function setup(): Promise<void> {
  const schema = await readFile(schemaFile, "utf-8");
  await pool.query(schema);
  console.log("Tables created.");

  const products = JSON.parse(await readFile(seedFile, "utf-8")) as Product[];

  for (const product of products) {
    await pool.query(
      `INSERT INTO products (id, name, category, price_cents, size, scents, description, stock)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        product.id,
        product.name,
        product.category,
        Math.round(product.price * 100),
        product.size,
        product.scents,
        product.description,
        product.stock,
      ]
    );
  }

  console.log(`Added ${products.length} products.`);

  const ownerEmail = process.env.OWNER_EMAIL;
  const ownerPassword = process.env.OWNER_PASSWORD;

  if (ownerEmail && ownerPassword) {
    await pool.query(
      "INSERT INTO users (email, name, password_hash, role) VALUES ($1, $2, $3, 'owner')",
      [ownerEmail.toLowerCase(), "Shop Owner", await hashPassword(ownerPassword)]
    );
    console.log(`Created owner account ${ownerEmail}.`);
  } else {
    console.log("No owner account created: set OWNER_EMAIL and OWNER_PASSWORD in .env.");
  }
}

setup()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
WREN_EOF

cat > src/index.ts << 'WREN_EOF'
import cookieParser from "cookie-parser";
import express from "express";
import type { NextFunction, Request, Response } from "express";
import { authRouter } from "./auth-routes.js";
import { createOrder, listOrders } from "./orders.js";
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

app.use(express.json());
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

app.post("/api/products", async (request, response) => {
  const result = await createProduct(request.body);

  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  response.status(201).json(result.product);
});

app.patch("/api/products/:id", async (request, response) => {
  const result = await updateProduct(request.params.id, request.body);

  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  response.json(result.product);
});

app.delete("/api/products/:id", async (request, response) => {
  const outcome = await deleteProduct(request.params.id);

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
  const result = await createOrder(request.body);

  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  console.log(`New order ${result.order.orderNumber}: $${result.order.total}`);
  response.status(201).json(result.order);
});

app.get("/api/orders", async (_request, response) => {
  response.json(await listOrders());
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
});
WREN_EOF

npm run check
npm run db:setup
echo
echo "Done. Restart the API:  cd server && npm run dev"
