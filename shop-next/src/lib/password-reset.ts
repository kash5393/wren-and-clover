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
