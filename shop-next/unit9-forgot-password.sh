#!/usr/bin/env bash
# Forgot password: request a reset link by email and choose a new password.
# Run from inside the shop-next folder:  bash unit9-forgot-password.sh
set -e
if [ ! -f src/lib/email.ts ] || [ ! -f .env.local ]; then echo "Run this inside the shop-next folder, after the payments step (src/lib/email.ts not found)."; exit 1; fi
mkdir -p db src/app/forgot-password src/app/reset-password

cat > db/reset-migration.sql << 'WREN_EOF'
CREATE TABLE IF NOT EXISTS password_resets (
  token_hash TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ
);
WREN_EOF
DATABASE_URL=$(grep '^DATABASE_URL=' .env.local | cut -d= -f2-)
psql "$DATABASE_URL" -q -f db/reset-migration.sql
echo "Local database updated: password reset table added."

SCHEMA=../server/db/schema.sql
if [ -f "$SCHEMA" ] && ! grep -q "CREATE TABLE password_resets" "$SCHEMA"; then
  perl -0pi -e 's|^|DROP TABLE IF EXISTS password_resets;\n|' "$SCHEMA"
  cat >> "$SCHEMA" << 'WREN_EOF'

CREATE TABLE password_resets (
  token_hash TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ
);
WREN_EOF
fi

cat > "src/lib/email.ts" << 'WREN_EOF'
import "server-only";
import nodemailer from "nodemailer";
import type { OrderReceipt } from "./orders";

export interface Email {
  to: string;
  subject: string;
  text: string;
}

export async function sendEmail(email: Email): Promise<void> {
  const smtpUrl = process.env.SMTP_URL;
  const from = process.env.EMAIL_FROM ?? "Wren & Clover <orders@wrenandclover.test>";

  if (!smtpUrl) {
    console.log(
      [
        "",
        "----- Email preview (not sent: SMTP_URL is not set) -----",
        `From: ${from}`,
        `To: ${email.to}`,
        `Subject: ${email.subject}`,
        "",
        email.text,
        "--------------------------------------------------------",
        "",
      ].join("\n")
    );
    return;
  }

  const transport = nodemailer.createTransport(smtpUrl);
  await transport.sendMail({ from, ...email });
}

function describeLines(order: OrderReceipt): string {
  return order.lines
    .map((line) => `  ${line.quantity} x ${line.name} (${line.scent})  $${line.unitPrice * line.quantity}`)
    .join("\n");
}

export async function sendOrderEmails(order: OrderReceipt): Promise<void> {
  const emails: Email[] = [
    {
      to: order.email,
      subject: `Your Wren & Clover order ${order.orderNumber}`,
      text: [
        `Hi ${order.customerName},`,
        "",
        `Thank you for your order ${order.orderNumber}.`,
        "",
        describeLines(order),
        "",
        `Total: $${order.total}`,
        "",
        `Shipping to: ${order.address}`,
        "",
        "We'll pack it within two working days.",
        "",
        "Wren & Clover Botanicals",
      ].join("\n"),
    },
  ];

  const ownerEmail = process.env.OWNER_EMAIL;
  if (ownerEmail) {
    emails.push({
      to: ownerEmail,
      subject: `New order ${order.orderNumber} ($${order.total})`,
      text: [
        `${order.customerName} <${order.email}> placed order ${order.orderNumber}.`,
        "",
        describeLines(order),
        "",
        `Total: $${order.total}`,
        `Ship to: ${order.address}`,
      ].join("\n"),
    });
  }

  for (const email of emails) {
    try {
      await sendEmail(email);
    } catch (error) {
      console.error(`Could not send email to ${email.to}:`, error);
    }
  }
}
WREN_EOF

cat > "src/lib/auth.ts" << 'WREN_EOF'
import "server-only";
import { randomBytes } from "node:crypto";
import bcrypt from "bcryptjs";
import { cookies } from "next/headers";
import { notFound, redirect } from "next/navigation";
import { cache } from "react";
import { z } from "zod";
import { pool } from "./db";
import { safeNextPath } from "./paths";
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

export function tooManyAttempts(key: string): boolean {
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

export async function requireOwner(): Promise<User> {
  const user = await getCurrentUser();

  if (!user) {
    redirect("/login?next=/admin");
  }
  if (user.role !== "owner") {
    notFound();
  }

  return user;
}

export { safeNextPath };
WREN_EOF

cat > "src/lib/password-reset.ts" << 'WREN_EOF'
import "server-only";
import { createHash, randomBytes } from "node:crypto";
import bcrypt from "bcryptjs";
import { tooManyAttempts } from "./auth";
import { pool } from "./db";
import { sendEmail } from "./email";
import { siteUrl } from "./payments";

const RESET_MINUTES = 60;

export type ResetResult = { ok: true } | { ok: false; error: string };

function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

/**
 * Starts a password reset. It never reveals whether the email has an account:
 * the caller shows the same message either way.
 */
export async function requestPasswordReset(emailInput: string): Promise<void> {
  const email = emailInput.trim().toLowerCase();
  if (email === "" || tooManyAttempts(`reset:${email}`)) {
    return;
  }

  const found = await pool.query<{ id: number; name: string }>(
    "SELECT id, name FROM users WHERE email = $1",
    [email]
  );
  const user = found.rows[0];
  if (!user) {
    return;
  }

  const token = randomBytes(32).toString("hex");
  const expiresAt = new Date(Date.now() + RESET_MINUTES * 60 * 1000);

  await pool.query("DELETE FROM password_resets WHERE user_id = $1", [user.id]);
  await pool.query(
    "INSERT INTO password_resets (token_hash, user_id, expires_at) VALUES ($1, $2, $3)",
    [hashToken(token), user.id, expiresAt]
  );

  const link = `${siteUrl()}/reset-password?token=${token}`;

  try {
    await sendEmail({
      to: email,
      subject: "Reset your Wren & Clover password",
      text: [
        `Hi ${user.name},`,
        "",
        "Someone asked to reset the password for your Wren & Clover account.",
        `Use this link within ${RESET_MINUTES} minutes to choose a new one:`,
        "",
        link,
        "",
        "If this wasn't you, you can ignore this email and your password will stay the same.",
        "",
        "Wren & Clover Botanicals",
      ].join("\n"),
    });
  } catch (error) {
    console.error("Could not send the password reset email:", error);
  }
}

export async function isResetTokenValid(token: string): Promise<boolean> {
  if (token === "") {
    return false;
  }

  const result = await pool.query(
    "SELECT 1 FROM password_resets WHERE token_hash = $1 AND used_at IS NULL AND expires_at > now()",
    [hashToken(token)]
  );
  return result.rows.length > 0;
}

export async function resetPassword(token: string, newPassword: string): Promise<ResetResult> {
  if (newPassword.length < 8) {
    return { ok: false, error: "Password must be at least 8 characters." };
  }

  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    const claimed = await client.query<{ user_id: number }>(
      `UPDATE password_resets
       SET used_at = now()
       WHERE token_hash = $1 AND used_at IS NULL AND expires_at > now()
       RETURNING user_id`,
      [hashToken(token)]
    );
    const reset = claimed.rows[0];

    if (!reset) {
      await client.query("ROLLBACK");
      return {
        ok: false,
        error: "This reset link has expired or was already used. Please request a new one.",
      };
    }

    await client.query("UPDATE users SET password_hash = $1 WHERE id = $2", [
      await bcrypt.hash(newPassword, 12),
      reset.user_id,
    ]);
    await client.query("DELETE FROM sessions WHERE user_id = $1", [reset.user_id]);

    await client.query("COMMIT");
    return { ok: true };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
WREN_EOF

cat > "src/app/auth-actions.ts" << 'WREN_EOF'
"use server";

import { redirect } from "next/navigation";
import { endSession, logIn, safeNextPath, signUp, startSession } from "@/lib/auth";
import { requestPasswordReset, resetPassword } from "@/lib/password-reset";

export interface AuthFormState {
  error: string;
}

export async function loginAction(
  _previous: AuthFormState,
  formData: FormData
): Promise<AuthFormState> {
  const result = await logIn({
    email: formData.get("email"),
    password: formData.get("password"),
  });

  if (!result.ok) {
    return { error: result.error };
  }

  await startSession(result.user.id);
  redirect(safeNextPath(formData.get("next")));
}

export async function signupAction(
  _previous: AuthFormState,
  formData: FormData
): Promise<AuthFormState> {
  const result = await signUp({
    name: formData.get("name"),
    email: formData.get("email"),
    password: formData.get("password"),
  });

  if (!result.ok) {
    return { error: result.error };
  }

  await startSession(result.user.id);
  redirect(safeNextPath(formData.get("next")));
}

export async function logoutAction(): Promise<void> {
  await endSession();
  redirect("/");
}

export interface ForgotPasswordState {
  sent: boolean;
}

export async function forgotPasswordAction(
  _previous: ForgotPasswordState,
  formData: FormData
): Promise<ForgotPasswordState> {
  await requestPasswordReset(String(formData.get("email") ?? ""));
  return { sent: true };
}

export async function resetPasswordAction(
  _previous: AuthFormState,
  formData: FormData
): Promise<AuthFormState> {
  const password = String(formData.get("password") ?? "");
  const confirm = String(formData.get("confirm") ?? "");

  if (password !== confirm) {
    return { error: "The two passwords do not match." };
  }

  const result = await resetPassword(String(formData.get("token") ?? ""), password);
  if (!result.ok) {
    return { error: result.error };
  }

  redirect("/login?reset=done");
}
WREN_EOF

cat > "src/components/AuthForm.tsx" << 'WREN_EOF'
"use client";

import Link from "next/link";
import { useActionState } from "react";
import { loginAction, signupAction } from "@/app/auth-actions";
import type { AuthFormState } from "@/app/auth-actions";

interface AuthFormProps {
  mode: "login" | "signup";
  nextPath: string;
  defaultEmail?: string;
}

const initialState: AuthFormState = { error: "" };

export default function AuthForm({ mode, nextPath, defaultEmail = "" }: AuthFormProps) {
  const isSignup = mode === "signup";
  const [state, formAction, pending] = useActionState(
    isSignup ? signupAction : loginAction,
    initialState
  );
  const nextQuery = `?next=${encodeURIComponent(nextPath)}`;

  return (
    <>
      <form className="contact-form" action={formAction}>
        <input type="hidden" name="next" value={nextPath} />

        {isSignup && (
          <div className="field">
            <label htmlFor="name">Name</label>
            <input id="name" name="name" type="text" autoComplete="name" required />
          </div>
        )}

        <div className="field">
          <label htmlFor="email">Email</label>
          <input
            id="email"
            name="email"
            type="email"
            autoComplete="email"
            defaultValue={defaultEmail}
            required
          />
        </div>

        <div className="field">
          <label htmlFor="password">
            {isSignup ? "Password (at least 8 characters)" : "Password"}
          </label>
          <input
            id="password"
            name="password"
            type="password"
            autoComplete={isSignup ? "new-password" : "current-password"}
            minLength={isSignup ? 8 : undefined}
            required
          />
        </div>

        {state.error && (
          <p className="field-error" role="alert">
            {state.error}
          </p>
        )}

        <button className="button button-full" type="submit" disabled={pending}>
          {pending ? "Please wait..." : isSignup ? "Create account" : "Sign in"}
        </button>
      </form>

      {isSignup ? (
        <p>
          Already have an account? <Link href={`/login${nextQuery}`}>Sign in</Link>
        </p>
      ) : (
        <>
          <p>
            <Link href="/forgot-password">Forgot your password?</Link>
          </p>
          <p>
            New here? <Link href={`/signup${nextQuery}`}>Create an account</Link>
          </p>
        </>
      )}
    </>
  );
}
WREN_EOF

cat > "src/components/ForgotPasswordForm.tsx" << 'WREN_EOF'
"use client";

import Link from "next/link";
import { useActionState } from "react";
import { forgotPasswordAction } from "@/app/auth-actions";
import type { ForgotPasswordState } from "@/app/auth-actions";

const initialState: ForgotPasswordState = { sent: false };

export default function ForgotPasswordForm() {
  const [state, formAction, pending] = useActionState(forgotPasswordAction, initialState);

  if (state.sent) {
    return (
      <>
        <p className="form-status" role="status">
          If that email has an account, a reset link is on its way. It works for 60 minutes.
        </p>
        <p>
          <Link href="/login">Back to sign in</Link>
        </p>
      </>
    );
  }

  return (
    <>
      <p>Enter the email you signed up with and we&apos;ll send you a link to choose a new password.</p>
      <form className="contact-form" action={formAction}>
        <div className="field">
          <label htmlFor="email">Email</label>
          <input id="email" name="email" type="email" autoComplete="email" required />
        </div>
        <button className="button button-full" type="submit" disabled={pending}>
          {pending ? "Please wait..." : "Send reset link"}
        </button>
      </form>
      <p>
        <Link href="/login">Back to sign in</Link>
      </p>
    </>
  );
}
WREN_EOF

cat > "src/components/ResetPasswordForm.tsx" << 'WREN_EOF'
"use client";

import { useActionState } from "react";
import { resetPasswordAction } from "@/app/auth-actions";
import type { AuthFormState } from "@/app/auth-actions";

interface ResetPasswordFormProps {
  token: string;
}

const initialState: AuthFormState = { error: "" };

export default function ResetPasswordForm({ token }: ResetPasswordFormProps) {
  const [state, formAction, pending] = useActionState(resetPasswordAction, initialState);

  return (
    <form className="contact-form" action={formAction}>
      <input type="hidden" name="token" value={token} />

      <div className="field">
        <label htmlFor="password">New password (at least 8 characters)</label>
        <input
          id="password"
          name="password"
          type="password"
          autoComplete="new-password"
          minLength={8}
          required
        />
      </div>

      <div className="field">
        <label htmlFor="confirm">Type the new password again</label>
        <input
          id="confirm"
          name="confirm"
          type="password"
          autoComplete="new-password"
          minLength={8}
          required
        />
      </div>

      {state.error && (
        <p className="field-error" role="alert">
          {state.error}
        </p>
      )}

      <button className="button button-full" type="submit" disabled={pending}>
        {pending ? "Saving..." : "Change password"}
      </button>
    </form>
  );
}
WREN_EOF

cat > "src/app/login/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import { redirect } from "next/navigation";
import AuthForm from "@/components/AuthForm";
import { getCurrentUser, safeNextPath } from "@/lib/auth";

export const metadata: Metadata = {
  title: "Sign in",
};

function first(value: string | string[] | undefined): string {
  return Array.isArray(value) ? (value[0] ?? "") : (value ?? "");
}

export default async function LoginPage(props: PageProps<"/login">) {
  const query = await props.searchParams;
  const nextPath = safeNextPath(first(query.next));

  if (await getCurrentUser()) {
    redirect(nextPath);
  }

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Sign in</h1>
        {first(query.reset) === "done" && (
          <p className="form-status" role="status">
            Your password has been changed. Sign in with the new one.
          </p>
        )}
        <AuthForm mode="login" nextPath={nextPath} defaultEmail={first(query.email)} />
      </div>
    </section>
  );
}
WREN_EOF

cat > "src/app/forgot-password/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import ForgotPasswordForm from "@/components/ForgotPasswordForm";

export const metadata: Metadata = {
  title: "Forgot password",
};

export default function ForgotPasswordPage() {
  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Forgot your password?</h1>
        <ForgotPasswordForm />
      </div>
    </section>
  );
}
WREN_EOF

cat > "src/app/reset-password/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import Link from "next/link";
import ResetPasswordForm from "@/components/ResetPasswordForm";
import { isResetTokenValid } from "@/lib/password-reset";

export const metadata: Metadata = {
  title: "Choose a new password",
  robots: { index: false },
  referrer: "no-referrer",
};

export default async function ResetPasswordPage(props: PageProps<"/reset-password">) {
  const query = await props.searchParams;
  const token = typeof query.token === "string" ? query.token : "";
  const valid = await isResetTokenValid(token);

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Choose a new password</h1>

        {valid ? (
          <ResetPasswordForm token={token} />
        ) : (
          <>
            <p>This reset link has expired or was already used.</p>
            <Link className="button" href="/forgot-password">Request a new link</Link>
          </>
        )}
      </div>
    </section>
  );
}
WREN_EOF

echo
echo "Done. Restart the dev server:  npm run dev"
