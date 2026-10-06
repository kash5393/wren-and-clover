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
