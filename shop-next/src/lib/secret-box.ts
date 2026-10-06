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
