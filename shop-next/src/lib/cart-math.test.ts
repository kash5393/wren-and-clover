import { describe, expect, it } from "vitest";
import { addToCart, cartCount, cartTotal, removeFromCart, setQuantity } from "./cart-math";
import type { CartItem, Product } from "./types";

const soap: Product = {
  id: "lavender-oat-soap",
  name: "Lavender Oat Soap",
  category: "Soaps",
  price: 8,
  size: "4.5 oz bar",
  scents: ["Lavender"],
  description: "Gentle exfoliating bar with ground oats.",
  stock: 24,
};

const lotion: Product = {
  id: "shea-lotion",
  name: "Shea Hand and Body Lotion",
  category: "Lotions",
  price: 16,
  size: "8 oz bottle",
  scents: ["Lavender", "Unscented"],
  description: "Light daily lotion that absorbs quickly.",
  stock: 15,
};

describe("addToCart", () => {
  it("adds a new product as its own line", () => {
    const cart = addToCart([], soap, "Lavender", 2);

    expect(cart).toEqual([
      { id: "lavender-oat-soap", name: "Lavender Oat Soap", price: 8, scent: "Lavender", quantity: 2 },
    ]);
  });

  it("increases the quantity when the same product and scent is added again", () => {
    const once = addToCart([], soap, "Lavender", 1);
    const twice = addToCart(once, soap, "Lavender", 3);

    expect(twice).toHaveLength(1);
    expect(twice[0]?.quantity).toBe(4);
  });

  it("keeps different scents of the same product on separate lines", () => {
    const first = addToCart([], lotion, "Lavender", 1);
    const second = addToCart(first, lotion, "Unscented", 1);

    expect(second).toHaveLength(2);
  });

  it("does not change the original array", () => {
    const original: CartItem[] = [];
    addToCart(original, soap, "Lavender", 1);

    expect(original).toEqual([]);
  });
});

describe("setQuantity and removeFromCart", () => {
  const cart = addToCart(addToCart([], soap, "Lavender", 2), lotion, "Unscented", 1);

  it("changes the quantity of one line only", () => {
    const updated = setQuantity(cart, 0, 5);

    expect(updated[0]?.quantity).toBe(5);
    expect(updated[1]?.quantity).toBe(1);
  });

  it("never lets a quantity fall below 1", () => {
    expect(setQuantity(cart, 0, 0)[0]?.quantity).toBe(1);
    expect(setQuantity(cart, 0, -3)[0]?.quantity).toBe(1);
  });

  it("removes the chosen line", () => {
    const remaining = removeFromCart(cart, 0);

    expect(remaining).toHaveLength(1);
    expect(remaining[0]?.id).toBe("shea-lotion");
  });
});

describe("cart totals", () => {
  const cart = addToCart(addToCart([], soap, "Lavender", 2), lotion, "Unscented", 1);

  it("counts every item, not every line", () => {
    expect(cartCount(cart)).toBe(3);
  });

  it("adds up price times quantity", () => {
    expect(cartTotal(cart)).toBe(32);
  });

  it("gives zero for an empty cart", () => {
    expect(cartCount([])).toBe(0);
    expect(cartTotal([])).toBe(0);
  });
});
