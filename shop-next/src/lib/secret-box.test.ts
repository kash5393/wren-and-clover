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
