import { describe, expect, it } from "vitest";
import { safeNextPath } from "./paths";

describe("safeNextPath", () => {
  it("allows pages on this site", () => {
    expect(safeNextPath("/checkout")).toBe("/checkout");
    expect(safeNextPath("/orders?page=2")).toBe("/orders?page=2");
  });

  it("refuses addresses on other websites", () => {
    expect(safeNextPath("https://evil.example.com")).toBe("/");
    expect(safeNextPath("//evil.example.com")).toBe("/");
  });

  it("falls back to the home page when nothing usable is given", () => {
    expect(safeNextPath("")).toBe("/");
    expect(safeNextPath(null)).toBe("/");
    expect(safeNextPath(undefined)).toBe("/");
    expect(safeNextPath(42)).toBe("/");
  });
});
