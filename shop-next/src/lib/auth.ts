import "server-only";
import { randomBytes } from "node:crypto";
import bcrypt from "bcryptjs";
import { cookies } from "next/headers";
import { cache } from "react";
import { z } from "zod";
import { pool } from "./db";
import type { User } from "./types";

const SESSION_COOKIE = "session";
const SESSION_SECONDS = 7 * 24 * 60 * 60;

const ATTEMPT_LIMIT = 10;
const ATTEMPT_WINDOW_MS = 15 * 60 * 1000;
const attempts = new Map<string, { count: number; resetAt: number }>();

interface UserRow extends User {
  password_hash: string;
}

export type AuthResult = { ok: true; user: User } | { ok: false; error: string };

const signupSchema = z.object({
  name: z.string().trim().min(1, "Please enter your name."),
  email: z.email("Please enter a valid email address."),
  password: z.string().min(8, "Password must be at least 8 characters."),
});

const loginSchema = z.object({
  email: z.email(),
  password: z.string().min(1),
});

function toUser(row: UserRow): User {
  return { id: row.id, email: row.email, name: row.name, role: row.role };
}

function tooManyAttempts(key: string): boolean {
  const now = Date.now();
  const entry = attempts.get(key);

  if (!entry || entry.resetAt <= now) {
    attempts.set(key, { count: 1, resetAt: now + ATTEMPT_WINDOW_MS });
    return false;
  }

  entry.count += 1;
  return entry.count > ATTEMPT_LIMIT;
}

export async function signUp(input: unknown): Promise<AuthResult> {
  const parsed = signupSchema.safeParse(input);
  if (!parsed.success) {
    return { ok: false, error: parsed.error.issues[0]?.message ?? "Please check your details." };
  }

  const { name, password } = parsed.data;
  const email = parsed.data.email.toLowerCase();

  if (tooManyAttempts(`signup:${email}`)) {
    return { ok: false, error: "Too many attempts. Please wait 15 minutes and try again." };
  }

  const existing = await pool.query("SELECT 1 FROM users WHERE email = $1", [email]);
  if (existing.rows.length > 0) {
    return { ok: false, error: "An account with this email already exists." };
  }

  const result = await pool.query<UserRow>(
    `INSERT INTO users (email, name, password_hash)
     VALUES ($1, $2, $3)
     RETURNING id, email, name, role, password_hash`,
    [email, name, await bcrypt.hash(password, 12)]
  );

  return { ok: true, user: toUser(result.rows[0]!) };
}

export async function logIn(input: unknown): Promise<AuthResult> {
  const wrong: AuthResult = { ok: false, error: "Email or password is incorrect." };

  const parsed = loginSchema.safeParse(input);
  if (!parsed.success) {
    return wrong;
  }

  const email = parsed.data.email.toLowerCase();
  if (tooManyAttempts(`login:${email}`)) {
    return { ok: false, error: "Too many attempts. Please wait 15 minutes and try again." };
  }

  const result = await pool.query<UserRow>(
    "SELECT id, email, name, role, password_hash FROM users WHERE email = $1",
    [email]
  );
  const row = result.rows[0];
  if (!row) {
    return wrong;
  }

  const matches = await bcrypt.compare(parsed.data.password, row.password_hash);
  if (!matches) {
    return wrong;
  }

  attempts.delete(`login:${email}`);
  return { ok: true, user: toUser(row) };
}

export async function startSession(userId: number): Promise<void> {
  const sessionId = randomBytes(32).toString("hex");
  const expiresAt = new Date(Date.now() + SESSION_SECONDS * 1000);

  await pool.query("INSERT INTO sessions (id, user_id, expires_at) VALUES ($1, $2, $3)", [
    sessionId,
    userId,
    expiresAt,
  ]);

  const cookieStore = await cookies();
  cookieStore.set(SESSION_COOKIE, sessionId, {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    maxAge: SESSION_SECONDS,
    path: "/",
  });
}

export async function endSession(): Promise<void> {
  const cookieStore = await cookies();
  const sessionId = cookieStore.get(SESSION_COOKIE)?.value;

  if (sessionId) {
    await pool.query("DELETE FROM sessions WHERE id = $1", [sessionId]);
  }
  cookieStore.delete(SESSION_COOKIE);
}

export const getCurrentUser = cache(async (): Promise<User | null> => {
  const cookieStore = await cookies();
  const sessionId = cookieStore.get(SESSION_COOKIE)?.value;
  if (!sessionId) {
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
});

export function safeNextPath(value: unknown): string {
  if (typeof value === "string" && value.startsWith("/") && !value.startsWith("//")) {
    return value;
  }
  return "/";
}
