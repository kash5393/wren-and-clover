#!/usr/bin/env bash
# Admin settings: manage the Stripe key, webhook secret, email server and site address from the admin portal.
# Run from inside the shop-next folder:  bash unit10-settings.sh
set -e
if [ ! -f src/lib/product-images.ts ] || [ ! -f src/lib/password-reset.ts ] || [ ! -f .env.local ]; then echo "Run this inside the shop-next folder, after the forgot-password and product photo steps."; exit 1; fi
mkdir -p db src/app/admin/settings src/app/api/stripe/webhook

cat > db/settings-migration.sql << 'WREN_EOF'
CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
WREN_EOF
DATABASE_URL=$(grep '^DATABASE_URL=' .env.local | cut -d= -f2-)
psql "$DATABASE_URL" -q -f db/settings-migration.sql
echo "Local database updated: settings table added."

if ! grep -q '^SETTINGS_ENCRYPTION_KEY=' .env.local; then
  printf '\n# Master key that encrypts the settings saved in the admin portal. Keep it secret and never change it.\nSETTINGS_ENCRYPTION_KEY=%s\n' "$(openssl rand -hex 32)" >> .env.local
  echo "Created a local SETTINGS_ENCRYPTION_KEY in .env.local."
fi

SCHEMA=../server/db/schema.sql
if [ -f "$SCHEMA" ] && ! grep -q "CREATE TABLE app_settings" "$SCHEMA"; then
  perl -0pi -e 's|^|DROP TABLE IF EXISTS app_settings;\n|' "$SCHEMA"
  cat >> "$SCHEMA" << 'WREN_EOF'

CREATE TABLE app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
WREN_EOF
fi

cat > "src/lib/secret-box.ts" << 'WREN_EOF'
import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";

/**
 * Encrypts and decrypts small secrets (API keys and the like) with AES-256-GCM.
 * The master key comes from the SETTINGS_ENCRYPTION_KEY environment variable.
 */

function toKey(masterKey: string): Buffer {
  const trimmed = masterKey.trim();
  if (/^[0-9a-fA-F]{64}$/.test(trimmed)) {
    return Buffer.from(trimmed, "hex");
  }
  return createHash("sha256").update(trimmed).digest();
}

export function isUsableMasterKey(masterKey: string | undefined): masterKey is string {
  return typeof masterKey === "string" && masterKey.trim().length >= 32;
}

export function encryptSecret(plainText: string, masterKey: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", toKey(masterKey), iv);
  const encrypted = Buffer.concat([cipher.update(plainText, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();

  return ["v1", iv.toString("base64"), tag.toString("base64"), encrypted.toString("base64")].join(":");
}

export function decryptSecret(stored: string, masterKey: string): string | null {
  const [version, iv, tag, encrypted] = stored.split(":");
  if (version !== "v1" || !iv || !tag || encrypted === undefined) {
    return null;
  }

  try {
    const decipher = createDecipheriv("aes-256-gcm", toKey(masterKey), Buffer.from(iv, "base64"));
    decipher.setAuthTag(Buffer.from(tag, "base64"));
    const decrypted = Buffer.concat([
      decipher.update(Buffer.from(encrypted, "base64")),
      decipher.final(),
    ]);
    return decrypted.toString("utf8");
  } catch {
    return null;
  }
}

/** Shows only the last four characters, for display in the admin portal. */
export function maskSecret(value: string): string {
  return value.length <= 8 ? "••••" : `••••${value.slice(-4)}`;
}
WREN_EOF

cat > "src/lib/secret-box.test.ts" << 'WREN_EOF'
import { describe, expect, it } from "vitest";
import { decryptSecret, encryptSecret, isUsableMasterKey, maskSecret } from "./secret-box";

const masterKey = "a".repeat(64);
const otherKey = "b".repeat(64);

describe("encryptSecret and decryptSecret", () => {
  it("gets the original value back with the right key", () => {
    const stored = encryptSecret("sk_test_example123", masterKey);

    expect(decryptSecret(stored, masterKey)).toBe("sk_test_example123");
  });

  it("does not contain the secret in what is stored", () => {
    const stored = encryptSecret("sk_test_example123", masterKey);

    expect(stored).not.toContain("sk_test_example123");
  });

  it("produces a different result each time, even for the same secret", () => {
    expect(encryptSecret("same", masterKey)).not.toBe(encryptSecret("same", masterKey));
  });

  it("returns null with the wrong key", () => {
    const stored = encryptSecret("sk_test_example123", masterKey);

    expect(decryptSecret(stored, otherKey)).toBeNull();
  });

  it("returns null if the stored value was tampered with", () => {
    const stored = encryptSecret("sk_test_example123", masterKey);
    const tampered = stored.slice(0, -4) + "AAAA";

    expect(decryptSecret(tampered, masterKey)).toBeNull();
  });

  it("returns null for anything that is not in the expected format", () => {
    expect(decryptSecret("not-encrypted", masterKey)).toBeNull();
    expect(decryptSecret("", masterKey)).toBeNull();
  });

  it("accepts a passphrase as the master key, not only 64 hex characters", () => {
    const passphrase = "a long passphrase that is not hexadecimal at all";
    const stored = encryptSecret("value", passphrase);

    expect(decryptSecret(stored, passphrase)).toBe("value");
  });
});

describe("isUsableMasterKey", () => {
  it("needs at least 32 characters", () => {
    expect(isUsableMasterKey(undefined)).toBe(false);
    expect(isUsableMasterKey("too-short")).toBe(false);
    expect(isUsableMasterKey(masterKey)).toBe(true);
  });
});

describe("maskSecret", () => {
  it("shows only the last four characters", () => {
    expect(maskSecret("sk_test_abcdefgh1234")).toBe("••••1234");
  });

  it("hides short values completely", () => {
    expect(maskSecret("short")).toBe("••••");
  });
});
WREN_EOF

cat > "src/lib/settings.ts" << 'WREN_EOF'
import "server-only";
import { cache } from "react";
import { pool } from "./db";
import { decryptSecret, encryptSecret, isUsableMasterKey, maskSecret } from "./secret-box";

export const settingKeys = [
  "stripeSecretKey",
  "stripeWebhookSecret",
  "smtpUrl",
  "emailFrom",
  "siteUrl",
] as const;

export type SettingKey = (typeof settingKeys)[number];

export type Settings = Partial<Record<SettingKey, string>>;

const environmentNames: Record<SettingKey, string> = {
  stripeSecretKey: "STRIPE_SECRET_KEY",
  stripeWebhookSecret: "STRIPE_WEBHOOK_SECRET",
  smtpUrl: "SMTP_URL",
  emailFrom: "EMAIL_FROM",
  siteUrl: "SITE_URL",
};

const secretKeys: SettingKey[] = ["stripeSecretKey", "stripeWebhookSecret", "smtpUrl"];

export interface SettingStatus {
  source: "admin" | "environment" | "none";
  display: string;
}

function masterKey(): string | null {
  const key = process.env.SETTINGS_ENCRYPTION_KEY;
  return isUsableMasterKey(key) ? key : null;
}

export function encryptionReady(): boolean {
  return masterKey() !== null;
}

function fromEnvironment(key: SettingKey): string | undefined {
  const value = process.env[environmentNames[key]]?.trim();
  return value ? value : undefined;
}

async function readStored(): Promise<Settings> {
  const key = masterKey();
  if (!key) {
    return {};
  }

  let rows: { key: string; value: string }[];
  try {
    const result = await pool.query<{ key: string; value: string }>(
      "SELECT key, value FROM app_settings"
    );
    rows = result.rows;
  } catch (error) {
    console.error("Could not read saved settings:", error);
    return {};
  }

  const stored: Settings = {};
  for (const row of rows) {
    if ((settingKeys as readonly string[]).includes(row.key)) {
      const value = decryptSecret(row.value, key);
      if (value) {
        stored[row.key as SettingKey] = value;
      }
    }
  }
  return stored;
}

/** Settings saved in the admin portal win; environment variables are the fallback. */
export const getSettings = cache(async (): Promise<Settings> => {
  const stored = await readStored();
  const settings: Settings = {};

  for (const key of settingKeys) {
    const value = stored[key] ?? fromEnvironment(key);
    if (value) {
      settings[key] = value;
    }
  }
  return settings;
});

export async function describeSettings(): Promise<Record<SettingKey, SettingStatus>> {
  const stored = await readStored();
  const statuses = {} as Record<SettingKey, SettingStatus>;

  for (const key of settingKeys) {
    const adminValue = stored[key];
    const environmentValue = fromEnvironment(key);
    const value = adminValue ?? environmentValue;

    statuses[key] = {
      source: adminValue ? "admin" : environmentValue ? "environment" : "none",
      display: value ? (secretKeys.includes(key) ? maskSecret(value) : value) : "",
    };
  }
  return statuses;
}

export async function saveSetting(key: SettingKey, value: string): Promise<void> {
  const master = masterKey();
  if (!master) {
    throw new Error("SETTINGS_ENCRYPTION_KEY is not set.");
  }

  await pool.query(
    `INSERT INTO app_settings (key, value)
     VALUES ($1, $2)
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
    [key, encryptSecret(value, master)]
  );
}

export async function clearSetting(key: SettingKey): Promise<void> {
  await pool.query("DELETE FROM app_settings WHERE key = $1", [key]);
}

/** Returns an error message if the value does not look right, or null if it is fine. */
export function validateSetting(key: SettingKey, value: string): string | null {
  switch (key) {
    case "stripeSecretKey":
      return /^(sk|rk)_(test|live)_\S{10,}$/.test(value)
        ? null
        : "The Stripe secret key should start with sk_test_ (or sk_live_ once you take real payments).";
    case "stripeWebhookSecret":
      return /^whsec_\S{10,}$/.test(value)
        ? null
        : "The webhook signing secret should start with whsec_.";
    case "smtpUrl":
      return /^smtps?:\/\/\S+$/.test(value)
        ? null
        : "The email server address should start with smtp:// or smtps://.";
    case "emailFrom":
      return /\S+@\S+/.test(value) ? null : "The sender should include an email address.";
    case "siteUrl":
      return /^https?:\/\/\S+$/.test(value)
        ? null
        : "The site address should start with https://.";
  }
}
WREN_EOF

cat > "src/lib/payments.ts" << 'WREN_EOF'
import "server-only";
import Stripe from "stripe";
import type { CreatedOrder } from "./orders";
import { getSettings } from "./settings";

const stripeClients = new Map<string, Stripe>();

export async function paymentsEnabled(): Promise<boolean> {
  return Boolean((await getSettings()).stripeSecretKey);
}

export async function getStripe(): Promise<Stripe> {
  const secretKey = (await getSettings()).stripeSecretKey;
  if (!secretKey) {
    throw new Error("No Stripe secret key is set.");
  }

  let client = stripeClients.get(secretKey);
  if (!client) {
    client = new Stripe(secretKey);
    stripeClients.set(secretKey, client);
  }
  return client;
}

/** Tidies a site address so a small typo in the setting can't break payment links. */
export function tidySiteUrl(value: string | undefined): string {
  let url = (value ?? "").trim().replace(/^["']+|["']+$/g, "").trim();

  if (!url && process.env.VERCEL_PROJECT_PRODUCTION_URL) {
    url = process.env.VERCEL_PROJECT_PRODUCTION_URL;
  }
  if (!url) {
    url = "http://localhost:3005";
  }
  if (!/^https?:\/\//i.test(url)) {
    url = `https://${url}`;
  }

  return url.replace(/\/+$/, "");
}

export async function siteUrl(): Promise<string> {
  return tidySiteUrl((await getSettings()).siteUrl);
}

export async function createPaymentPage(
  order: CreatedOrder,
  customerEmail: string
): Promise<{ sessionId: string; url: string }> {
  const stripe = await getStripe();
  const base = await siteUrl();

  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    customer_email: customerEmail,
    client_reference_id: order.orderNumber,
    line_items: order.lines.map((line) => ({
      quantity: line.quantity,
      price_data: {
        currency: "usd",
        unit_amount: line.unitPriceCents,
        product_data: { name: `${line.name} (${line.scent})` },
      },
    })),
    success_url: `${base}/checkout/success?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${base}/checkout/cancelled?token=${order.paymentToken}`,
  });

  if (!session.url) {
    throw new Error("Stripe did not return a payment page address.");
  }

  return { sessionId: session.id, url: session.url };
}

export async function isSessionPaid(sessionId: string): Promise<boolean> {
  const session = await (await getStripe()).checkout.sessions.retrieve(sessionId);
  return session.payment_status === "paid";
}

export async function closePaymentPage(sessionId: string): Promise<void> {
  try {
    await (await getStripe()).checkout.sessions.expire(sessionId);
  } catch (error) {
    console.error("Could not expire the Stripe session:", error);
  }
}

/** Checks that the saved Stripe key works, for the Test connection button. */
export async function testStripeConnection(): Promise<{ ok: boolean; message: string }> {
  try {
    const stripe = await getStripe();
    const balance = await stripe.balance.retrieve();
    return {
      ok: true,
      message: balance.livemode
        ? "Connected to Stripe in LIVE mode. Real cards will be charged."
        : "Connected to Stripe in test mode. No real money will move.",
    };
  } catch (error) {
    const reason = error instanceof Error ? error.message : "Unknown error";
    return { ok: false, message: `Stripe did not accept the key: ${reason}` };
  }
}
WREN_EOF

cat > "src/lib/email.ts" << 'WREN_EOF'
import "server-only";
import nodemailer from "nodemailer";
import type { OrderReceipt } from "./orders";
import { getSettings } from "./settings";

export interface Email {
  to: string;
  subject: string;
  text: string;
}

export async function sendEmail(email: Email): Promise<void> {
  const settings = await getSettings();
  const smtpUrl = settings.smtpUrl;
  const from = settings.emailFrom ?? "Wren & Clover <orders@wrenandclover.test>";

  if (!smtpUrl) {
    console.log(
      [
        "",
        "----- Email preview (not sent: no email server is set) -----",
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

  const link = `${await siteUrl()}/reset-password?token=${token}`;

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

cat > "src/app/checkout/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import { getCurrentUser } from "@/lib/auth";
import { getSavedShipping } from "@/lib/orders";
import { paymentsEnabled } from "@/lib/payments";
import CheckoutForm from "./CheckoutForm";

export const metadata: Metadata = {
  title: "Checkout",
};

export default async function CheckoutPage() {
  const user = await getCurrentUser();
  const savedShipping = user ? await getSavedShipping(user.id) : null;

  return (
    <section className="section">
      <div className="container">
        <CheckoutForm
          user={user ? { name: user.name, email: user.email } : null}
          savedShipping={savedShipping}
          paymentsOn={await paymentsEnabled()}
        />
      </div>
    </section>
  );
}
WREN_EOF

cat > "src/app/checkout/actions.ts" << 'WREN_EOF'
"use server";

import { getCurrentUser } from "@/lib/auth";
import { sendOrderEmails } from "@/lib/email";
import { attachStripeSession, cancelPendingOrder, createOrder, getReceiptById } from "@/lib/orders";
import { createPaymentPage, paymentsEnabled } from "@/lib/payments";

export interface OrderRequest {
  customer: {
    name: string;
    email: string;
    phone: string;
    address: string;
    city: string;
    state: string;
    postcode: string;
  };
  items: { id: string; scent: string; quantity: number }[];
}

export type PlaceOrderResult =
  | { ok: true; kind: "placed"; orderNumber: string; total: number }
  | { ok: true; kind: "payment"; paymentUrl: string }
  | { ok: false; error: string };

export async function placeOrder(request: OrderRequest): Promise<PlaceOrderResult> {
  try {
    const user = await getCurrentUser();
    const takePayment = await paymentsEnabled();

    const result = await createOrder(request, user ? user.id : null, takePayment ? "pending" : "new");
    if (!result.ok) {
      return result;
    }
    const order = result.order;

    if (!takePayment) {
      console.log(`New order ${order.orderNumber}: $${order.total} (payments are switched off)`);
      const receipt = await getReceiptById(order.id);
      if (receipt) {
        await sendOrderEmails(receipt);
      }
      return { ok: true, kind: "placed", orderNumber: order.orderNumber, total: order.total };
    }

    try {
      const payment = await createPaymentPage(order, request.customer.email);
      await attachStripeSession(order.id, payment.sessionId);
      return { ok: true, kind: "payment", paymentUrl: payment.url };
    } catch (error) {
      console.error(error);
      await cancelPendingOrder(order.id);
      return { ok: false, error: "The payment page could not be opened. Please try again." };
    }
  } catch (error) {
    console.error(error);
    return { ok: false, error: "Something went wrong placing the order. Please try again." };
  }
}
WREN_EOF

cat > "src/app/checkout/success/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import Link from "next/link";
import ClearCart from "@/components/ClearCart";
import { sendOrderEmails } from "@/lib/email";
import { getReceiptBySession, markOrderPaid } from "@/lib/orders";
import { isSessionPaid, paymentsEnabled } from "@/lib/payments";

export const metadata: Metadata = {
  title: "Order confirmed",
};

function Problem({ message }: { message: string }) {
  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">We couldn&apos;t confirm that payment</h1>
        <p>{message}</p>
        <Link className="button" href="/cart">Back to your cart</Link>
      </div>
    </section>
  );
}

export default async function CheckoutSuccessPage(props: PageProps<"/checkout/success">) {
  const query = await props.searchParams;
  const sessionId = typeof query.session_id === "string" ? query.session_id : "";

  if (!sessionId || !(await paymentsEnabled())) {
    return <Problem message="This page is only shown after a payment." />;
  }

  const order = await getReceiptBySession(sessionId);
  if (!order) {
    return <Problem message="No order matches this payment." />;
  }

  if (order.status === "cancelled") {
    return <Problem message="This order was cancelled. If you were charged, please contact us." />;
  }

  if (order.status === "pending") {
    if (!(await isSessionPaid(sessionId))) {
      return <Problem message="The payment has not completed. You have not been charged." />;
    }

    const firstTime = await markOrderPaid(order.id);
    if (firstTime) {
      console.log(`Order ${order.orderNumber} paid: $${order.total}`);
      await sendOrderEmails(order);
    }
  }

  return (
    <section className="section">
      <div className="container prose">
        <ClearCart />
        <h1 className="page-title">Thank you, {order.customerName}</h1>
        <p>
          Your payment went through and order <strong>{order.orderNumber}</strong> for{" "}
          <strong>${order.total}</strong> is confirmed. A confirmation has been sent to {order.email}.
        </p>
        <ul>
          {order.lines.map((line) => (
            <li key={`${line.name}-${line.scent}`}>
              {line.quantity} x {line.name} ({line.scent})
            </li>
          ))}
        </ul>
        <p>Shipping to: {order.address}</p>
        <Link className="button" href="/shop">Back to the shop</Link>
      </div>
    </section>
  );
}
WREN_EOF

cat > "src/app/checkout/cancelled/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import Link from "next/link";
import { cancelPendingOrder, getReceiptByToken, getStripeSessionId } from "@/lib/orders";
import { closePaymentPage, isSessionPaid, paymentsEnabled } from "@/lib/payments";

export const metadata: Metadata = {
  title: "Payment cancelled",
};

export default async function CheckoutCancelledPage(props: PageProps<"/checkout/cancelled">) {
  const query = await props.searchParams;
  const token = typeof query.token === "string" ? query.token : "";

  if (token && (await paymentsEnabled())) {
    const order = await getReceiptByToken(token);

    if (order && order.status === "pending") {
      const sessionId = await getStripeSessionId(order.id);
      const paid = sessionId ? await isSessionPaid(sessionId) : false;

      if (!paid) {
        if (sessionId) {
          await closePaymentPage(sessionId);
        }
        await cancelPendingOrder(order.id);
      }
    }
  }

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Payment cancelled</h1>
        <p>
          You left the payment page, so no money was taken and the order was not placed. Your cart
          is still saved.
        </p>
        <div className="cart-actions">
          <Link className="button" href="/checkout">Try again</Link>
          <Link href="/cart">Edit cart</Link>
        </div>
      </div>
    </section>
  );
}
WREN_EOF

cat > "src/app/api/stripe/webhook/route.ts" << 'WREN_EOF'
import { sendOrderEmails } from "@/lib/email";
import { cancelPendingOrder, getReceiptBySession, markOrderPaid } from "@/lib/orders";
import { getStripe, paymentsEnabled } from "@/lib/payments";
import { getSettings } from "@/lib/settings";

export async function POST(request: Request): Promise<Response> {
  const webhookSecret = (await getSettings()).stripeWebhookSecret;
  if (!webhookSecret || !(await paymentsEnabled())) {
    return new Response("Webhook is not configured", { status: 400 });
  }

  const signature = request.headers.get("stripe-signature") ?? "";
  const body = await request.text();

  let event;
  try {
    event = (await getStripe()).webhooks.constructEvent(body, signature, webhookSecret);
  } catch {
    return new Response("Invalid signature", { status: 400 });
  }

  if (
    event.type === "checkout.session.completed" ||
    event.type === "checkout.session.async_payment_succeeded"
  ) {
    const session = event.data.object;

    if (session.payment_status === "paid") {
      const order = await getReceiptBySession(session.id);

      if (order && order.status === "pending") {
        const firstTime = await markOrderPaid(order.id);
        if (firstTime) {
          console.log(`Order ${order.orderNumber} paid (confirmed by Stripe webhook)`);
          await sendOrderEmails(order);
        }
      }
    }
  }

  if (event.type === "checkout.session.expired") {
    const order = await getReceiptBySession(event.data.object.id);

    if (order && order.status === "pending") {
      await cancelPendingOrder(order.id);
      console.log(`Order ${order.orderNumber} cancelled: its payment page expired`);
    }
  }

  return Response.json({ received: true });
}
WREN_EOF

cat > "src/app/admin/actions.ts" << 'WREN_EOF'
"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { setOrderStatus } from "@/lib/admin";
import { requireOwner } from "@/lib/auth";
import { sendEmail } from "@/lib/email";
import { testStripeConnection } from "@/lib/payments";
import { deleteProductImage, saveProductImage } from "@/lib/product-images";
import { addStock, createProduct, deleteProduct, updateProduct } from "@/lib/products";
import {
  clearSetting,
  encryptionReady,
  getSettings,
  saveSetting,
  settingKeys,
  validateSetting,
} from "@/lib/settings";
import type { SettingKey } from "@/lib/settings";

export interface ProductFormState {
  error: string;
}

function readProduct(formData: FormData) {
  return {
    id: String(formData.get("id") ?? ""),
    name: String(formData.get("name") ?? ""),
    category: String(formData.get("category") ?? ""),
    price: Number(formData.get("price")),
    size: String(formData.get("size") ?? ""),
    scents: String(formData.get("scents") ?? "")
      .split(",")
      .map((scent) => scent.trim())
      .filter((scent) => scent !== ""),
    description: String(formData.get("description") ?? ""),
    stock: Number(formData.get("stock")),
  };
}

export async function createProductAction(
  _previous: ProductFormState,
  formData: FormData
): Promise<ProductFormState> {
  await requireOwner();

  const result = await createProduct(readProduct(formData));
  if (!result.ok) {
    return { error: result.error };
  }

  revalidatePath("/admin/products");
  redirect("/admin/products");
}

export async function updateProductAction(
  _previous: ProductFormState,
  formData: FormData
): Promise<ProductFormState> {
  await requireOwner();

  const product = readProduct(formData);
  const result = await updateProduct(product.id, product);
  if (!result.ok) {
    return { error: result.error };
  }

  revalidatePath("/admin/products");
  redirect("/admin/products");
}

export async function deleteProductAction(formData: FormData): Promise<void> {
  await requireOwner();

  const id = String(formData.get("id") ?? "");
  const result = await deleteProduct(id);

  revalidatePath("/admin/products");
  if (!result.ok) {
    redirect(`/admin/products?error=${encodeURIComponent(result.error)}`);
  }
  redirect("/admin/products");
}

export async function setOrderStatusAction(formData: FormData): Promise<void> {
  await requireOwner();

  const orderId = Number(formData.get("orderId"));
  const status = formData.get("status") === "shipped" ? "shipped" : "new";

  if (Number.isInteger(orderId)) {
    await setOrderStatus(orderId, status);
  }

  revalidatePath("/admin/orders");
}

export interface ImageFormState {
  error: string;
  saved: boolean;
}

export async function uploadProductImageAction(
  _previous: ImageFormState,
  formData: FormData
): Promise<ImageFormState> {
  await requireOwner();

  const productId = String(formData.get("productId") ?? "");
  const result = await saveProductImage(productId, formData.get("photo"));
  if (!result.ok) {
    return { error: result.error, saved: false };
  }

  revalidatePath("/", "layout");
  return { error: "", saved: true };
}

export async function removeProductImageAction(formData: FormData): Promise<void> {
  await requireOwner();

  await deleteProductImage(String(formData.get("productId") ?? ""));
  revalidatePath("/", "layout");
}

export async function restockAction(formData: FormData): Promise<void> {
  await requireOwner();

  const id = String(formData.get("id") ?? "");
  const amount = Number(formData.get("amount"));

  if (id !== "" && Number.isInteger(amount) && amount > 0 && amount <= 1000) {
    await addStock(id, amount);
  }

  revalidatePath("/admin/products");
}

export interface SettingsFormState {
  error: string;
  message: string;
}

export async function saveSettingsAction(
  _previous: SettingsFormState,
  formData: FormData
): Promise<SettingsFormState> {
  await requireOwner();

  if (!encryptionReady()) {
    return { error: "Settings can't be saved until SETTINGS_ENCRYPTION_KEY is set.", message: "" };
  }

  const changes: { key: SettingKey; value: string }[] = [];

  for (const key of settingKeys) {
    const value = String(formData.get(key) ?? "").trim();
    if (value === "") {
      continue;
    }

    const problem = validateSetting(key, value);
    if (problem) {
      return { error: problem, message: "" };
    }
    changes.push({ key, value });
  }

  if (changes.length === 0) {
    return { error: "", message: "Nothing to save: every box was empty." };
  }

  for (const change of changes) {
    await saveSetting(change.key, change.value);
  }

  revalidatePath("/", "layout");
  return {
    error: "",
    message: `Saved ${changes.length} ${changes.length === 1 ? "setting" : "settings"}.`,
  };
}

export async function clearSettingAction(formData: FormData): Promise<void> {
  await requireOwner();

  const key = String(formData.get("key") ?? "");
  if ((settingKeys as readonly string[]).includes(key)) {
    await clearSetting(key as SettingKey);
  }

  revalidatePath("/", "layout");
}

export async function testStripeAction(): Promise<SettingsFormState> {
  await requireOwner();

  const result = await testStripeConnection();
  return result.ok
    ? { error: "", message: result.message }
    : { error: result.message, message: "" };
}

export async function testEmailAction(): Promise<SettingsFormState> {
  const owner = await requireOwner();
  const settings = await getSettings();

  try {
    await sendEmail({
      to: owner.email,
      subject: "Test email from your Wren & Clover shop",
      text: "If you can read this, your shop's email settings are working.",
    });
  } catch (error) {
    const reason = error instanceof Error ? error.message : "Unknown error";
    return { error: `The email could not be sent: ${reason}`, message: "" };
  }

  return settings.smtpUrl
    ? { error: "", message: `Test email sent to ${owner.email}.` }
    : {
        error: "",
        message: "No email server is set, so the test email was printed in the server log instead.",
      };
}
WREN_EOF

cat > "src/app/admin/layout.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";
import { requireOwner } from "@/lib/auth";

export const metadata: Metadata = {
  title: {
    default: "Admin",
    template: "%s | Admin | Wren & Clover",
  },
  robots: { index: false },
};

interface AdminLayoutProps {
  children: ReactNode;
}

export default async function AdminLayout({ children }: AdminLayoutProps) {
  const owner = await requireOwner();

  return (
    <section className="section">
      <div className="container">
        <p className="admin-signed-in">Admin area, signed in as {owner.name}</p>
        <nav className="filters" aria-label="Admin">
          <Link className="chip" href="/admin">Dashboard</Link>
          <Link className="chip" href="/admin/products">Products</Link>
          <Link className="chip" href="/admin/orders">Orders</Link>
          <Link className="chip" href="/admin/messages">Messages</Link>
          <Link className="chip" href="/admin/settings">Settings</Link>
        </nav>
        {children}
      </div>
    </section>
  );
}
WREN_EOF

cat > "src/components/SettingsForm.tsx" << 'WREN_EOF'
"use client";

import { useActionState } from "react";
import {
  clearSettingAction,
  saveSettingsAction,
  testEmailAction,
  testStripeAction,
} from "@/app/admin/actions";
import type { SettingsFormState } from "@/app/admin/actions";
import type { SettingKey, SettingStatus } from "@/lib/settings";

interface SettingsFormProps {
  statuses: Record<SettingKey, SettingStatus>;
  webhookUrl: string;
  canSave: boolean;
}

const initialState: SettingsFormState = { error: "", message: "" };

const sourceLabels = {
  admin: "Saved here",
  environment: "From the hosting settings",
  none: "Not set",
};

function Feedback({ state }: { state: SettingsFormState }) {
  return (
    <>
      {state.error && (
        <p className="field-error" role="alert">
          {state.error}
        </p>
      )}
      {state.message && (
        <p className="form-status" role="status">
          {state.message}
        </p>
      )}
    </>
  );
}

function Current({ id, status }: { id: SettingKey; status: SettingStatus }) {
  return (
    <p className="setting-current">
      {sourceLabels[status.source]}
      {status.display && `: ${status.display}`}
      {status.source === "admin" && (
        <>
          {" "}
          <button className="link-button" type="submit" form={`clear-${id}`}>
            Remove
          </button>
        </>
      )}
    </p>
  );
}

export default function SettingsForm({ statuses, webhookUrl, canSave }: SettingsFormProps) {
  const [saveState, saveAction, saving] = useActionState(saveSettingsAction, initialState);
  const [stripeState, stripeAction, testingStripe] = useActionState(testStripeAction, initialState);
  const [emailState, emailAction, testingEmail] = useActionState(testEmailAction, initialState);

  const fields: { id: SettingKey; label: string; secret: boolean; placeholder: string }[] = [
    { id: "stripeSecretKey", label: "Stripe secret key", secret: true, placeholder: "sk_test_..." },
    {
      id: "stripeWebhookSecret",
      label: "Stripe webhook signing secret",
      secret: true,
      placeholder: "whsec_...",
    },
    {
      id: "smtpUrl",
      label: "Email server address",
      secret: true,
      placeholder: "smtps://user:password@smtp.example.com:465",
    },
    {
      id: "emailFrom",
      label: "Emails are sent from",
      secret: false,
      placeholder: "Wren & Clover <orders@yourdomain.com>",
    },
    { id: "siteUrl", label: "Site address", secret: false, placeholder: "https://yourshop.com" },
  ];

  const sections: { title: string; intro: string; keys: SettingKey[] }[] = [
    {
      title: "Payments",
      intro:
        "With a Stripe secret key, checkout sends customers to Stripe's payment page. Without one, orders complete without payment.",
      keys: ["stripeSecretKey"],
    },
    {
      title: "Webhook",
      intro:
        "A webhook lets Stripe tell the shop about a payment even if the customer closes the page before returning.",
      keys: ["stripeWebhookSecret"],
    },
    {
      title: "Email",
      intro:
        "With an email server, order confirmations and password resets are really sent. Without one, they are only written to the server log.",
      keys: ["smtpUrl", "emailFrom"],
    },
    {
      title: "Site",
      intro: "The public address of the shop, used in payment and email links.",
      keys: ["siteUrl"],
    },
  ];

  return (
    <>
      {fields.map((field) => (
        <form key={field.id} id={`clear-${field.id}`} action={clearSettingAction}>
          <input type="hidden" name="key" value={field.id} />
        </form>
      ))}

      <form className="settings-form" action={saveAction}>
        {sections.map((section) => (
          <section className="settings-section" key={section.title}>
            <h2>{section.title}</h2>
            <p>{section.intro}</p>

            {section.title === "Webhook" && (
              <div className="setting-current">
                <p>
                  In Stripe, add a webhook endpoint with this address, and choose the events{" "}
                  <code>checkout.session.completed</code>,{" "}
                  <code>checkout.session.async_payment_succeeded</code> and{" "}
                  <code>checkout.session.expired</code>:
                </p>
                <p>
                  <code>{webhookUrl}</code>
                </p>
              </div>
            )}

            {section.keys.map((key) => {
              const field = fields.find((item) => item.id === key);
              if (!field) {
                return null;
              }
              return (
                <div className="field" key={field.id}>
                  <label htmlFor={field.id}>{field.label}</label>
                  <Current id={field.id} status={statuses[field.id]} />
                  <input
                    id={field.id}
                    name={field.id}
                    type={field.secret ? "password" : "text"}
                    autoComplete="off"
                    placeholder={field.placeholder}
                    disabled={!canSave}
                  />
                </div>
              );
            })}
          </section>
        ))}

        <p className="setting-current">Leave a box empty to keep its current value.</p>
        <Feedback state={saveState} />
        <div className="cart-actions">
          <button className="button" type="submit" disabled={!canSave || saving}>
            {saving ? "Saving..." : "Save settings"}
          </button>
        </div>
      </form>

      <section className="settings-section">
        <h2>Check that it works</h2>
        <div className="cart-actions">
          <form action={stripeAction}>
            <button className="button" type="submit" disabled={testingStripe}>
              {testingStripe ? "Checking..." : "Test Stripe connection"}
            </button>
          </form>
          <form action={emailAction}>
            <button className="button" type="submit" disabled={testingEmail}>
              {testingEmail ? "Sending..." : "Send a test email"}
            </button>
          </form>
        </div>
        <Feedback state={stripeState} />
        <Feedback state={emailState} />
      </section>
    </>
  );
}
WREN_EOF

cat > "src/app/admin/settings/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import SettingsForm from "@/components/SettingsForm";
import { requireOwner } from "@/lib/auth";
import { siteUrl } from "@/lib/payments";
import { describeSettings, encryptionReady } from "@/lib/settings";

export const metadata: Metadata = {
  title: "Settings",
};

export default async function AdminSettingsPage() {
  await requireOwner();

  const statuses = await describeSettings();
  const canSave = encryptionReady();
  const webhookUrl = `${await siteUrl()}/api/stripe/webhook`;

  return (
    <div className="prose">
      <h1 className="page-title">Settings</h1>

      {!canSave && (
        <p className="field-error" role="alert">
          Settings can&apos;t be saved here yet. Add a SETTINGS_ENCRYPTION_KEY to the hosting
          settings first. It is the master key that keeps everything on this page encrypted.
        </p>
      )}

      <p>
        Keys saved here are encrypted before they are stored, and are never shown again in full.
        Only the last four characters are displayed.
      </p>

      <SettingsForm statuses={statuses} webhookUrl={webhookUrl} canSave={canSave} />
    </div>
  );
}
WREN_EOF

grep -q "settings-section" src/app/globals.css || cat >> src/app/globals.css << 'WREN_EOF'

/* Admin settings */
.settings-form {
  display: grid;
  gap: var(--space-3);
}

.settings-section {
  display: grid;
  gap: var(--space-2);
  padding: var(--space-3);
  margin-top: var(--space-3);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius);
}

.settings-section h2,
.settings-section p {
  margin: 0;
}

.setting-current {
  margin: 0;
  color: var(--color-muted);
  font-size: 0.9rem;
}

.setting-current .link-button {
  padding: 0;
}

code {
  padding: 0.1rem 0.3rem;
  font-size: 0.9em;
  overflow-wrap: anywhere;
  background: var(--color-bg);
  border: 1px solid var(--color-border);
  border-radius: 4px;
}
WREN_EOF

npm run lint
npm test
echo
echo "Done. Restart the dev server:  npm run dev"
