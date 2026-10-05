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
