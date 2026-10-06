import { describe, expect, it } from "vitest";
import {
  addToCart,
  availableToAdd,
  cartCount,
  cartTotal,
  maxForLine,
  quantityInCart,
  removeFromCart,
  setQuantity,
} from "./cart-math";
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
  imageUrl: null,
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
  imageUrl: null,
};

const charcoal: Product = {
  id: "charcoal-tea-tree-soap",
  name: "Charcoal Tea Tree Soap",
  category: "Soaps",
  price: 9,
  size: "4.5 oz bar",
  scents: ["Tea tree"],
  description: "Deep-cleaning bar for oily skin.",
  stock: 12,
  imageUrl: null,
};

describe("addToCart", () => {
  it("adds a new product as its own line", () => {
    const cart = addToCart([], soap, "Lavender", 2);

    expect(cart).toEqual([
      {
        id: "lavender-oat-soap",
        name: "Lavender Oat Soap",
        price: 8,
        scent: "Lavender",
        quantity: 2,
        stock: 24,
      },
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

describe("stock limits", () => {
  it("never adds more than is in stock", () => {
    const cart = addToCart([], charcoal, "Tea tree", 30);

    expect(cart[0]?.quantity).toBe(12);
  });

  it("stops at the stock level when adding in several goes", () => {
    const first = addToCart([], charcoal, "Tea tree", 10);
    const second = addToCart(first, charcoal, "Tea tree", 10);

    expect(second[0]?.quantity).toBe(12);
  });

  it("adds nothing once the cart already holds all the stock", () => {
    const full = addToCart([], charcoal, "Tea tree", 12);
    const again = addToCart(full, charcoal, "Tea tree", 1);

    expect(again).toBe(full);
  });

  it("adds nothing for a product that is out of stock", () => {
    expect(addToCart([], { ...charcoal, stock: 0 }, "Tea tree", 1)).toEqual([]);
  });

  it("shares one stock limit across the scents of a product", () => {
    const first = addToCart([], lotion, "Lavender", 10);
    const second = addToCart(first, lotion, "Unscented", 10);

    expect(quantityInCart(second, "shea-lotion")).toBe(15);
    expect(second[1]?.quantity).toBe(5);
  });

  it("reports how many more can be added", () => {
    const cart = addToCart([], charcoal, "Tea tree", 5);

    expect(availableToAdd(cart, charcoal)).toBe(7);
    expect(availableToAdd([], charcoal)).toBe(12);
  });

  it("does not let a cart quantity be raised above the stock", () => {
    const cart = addToCart([], charcoal, "Tea tree", 2);

    expect(setQuantity(cart, 0, 30)[0]?.quantity).toBe(12);
    expect(maxForLine(cart, 0)).toBe(12);
  });

  it("takes the product's other lines into account when raising a quantity", () => {
    const cart = addToCart(addToCart([], lotion, "Lavender", 10), lotion, "Unscented", 2);

    expect(maxForLine(cart, 1)).toBe(5);
    expect(setQuantity(cart, 1, 9)[1]?.quantity).toBe(5);
  });

  it("leaves older cart lines without a stock figure unlimited", () => {
    const oldCart: CartItem[] = [
      { id: "lavender-oat-soap", name: "Lavender Oat Soap", price: 8, scent: "Lavender", quantity: 1 },
    ];

    expect(maxForLine(oldCart, 0)).toBeNull();
    expect(setQuantity(oldCart, 0, 40)[0]?.quantity).toBe(40);
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
