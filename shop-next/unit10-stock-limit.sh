#!/usr/bin/env bash
# Fix: a customer can no longer put more of a product in the cart than is in stock.
# Run from inside the shop-next folder:  bash unit10-stock-limit.sh
set -e
if [ ! -f src/lib/cart-math.ts ] || [ ! -f src/lib/product-images.ts ]; then echo "Run this inside the shop-next folder, after the tests and product photo steps."; exit 1; fi
cat > "src/lib/types.ts" << 'WREN_EOF'
export type Category = "Soaps" | "Lotions" | "Bath" | "Gift sets";

export const categories: Category[] = ["Soaps", "Lotions", "Bath", "Gift sets"];

export interface Product {
  id: string;
  name: string;
  category: Category;
  price: number;
  size: string;
  scents: string[];
  description: string;
  stock: number;
  imageUrl: string | null;
}

export interface CartItem {
  id: string;
  name: string;
  price: number;
  scent: string;
  quantity: number;
  /** How many of this product were in stock when it was added. Older carts may not have it. */
  stock?: number;
}

export interface User {
  id: number;
  email: string;
  name: string;
  role: "customer" | "owner";
}

export interface ShippingDetails {
  name: string;
  email: string;
  phone: string;
  address: string;
  city: string;
  state: string;
  postcode: string;
}
WREN_EOF

cat > "src/lib/cart-math.ts" << 'WREN_EOF'
import type { CartItem, Product } from "./types";

/** How many of one product are in the cart, across all its scents. */
export function quantityInCart(items: CartItem[], productId: string): number {
  return items
    .filter((item) => item.id === productId)
    .reduce((sum, item) => sum + item.quantity, 0);
}

/** How many more of a product can still be added before the cart holds all the stock. */
export function availableToAdd(items: CartItem[], product: Product): number {
  return Math.max(0, product.stock - quantityInCart(items, product.id));
}

/** The largest quantity one cart line may have, given the stock and the product's other lines. */
export function maxForLine(items: CartItem[], index: number): number | null {
  const line = items[index];
  if (!line || line.stock === undefined) {
    return null;
  }

  const onOtherLines = quantityInCart(items, line.id) - line.quantity;
  return Math.max(1, line.stock - onOtherLines);
}

export function addToCart(
  items: CartItem[],
  product: Product,
  scent: string,
  quantity: number
): CartItem[] {
  const toAdd = Math.min(quantity, availableToAdd(items, product));
  if (toAdd <= 0) {
    return items;
  }

  const exists = items.some((item) => item.id === product.id && item.scent === scent);

  const updated = items.map((item) => {
    if (item.id !== product.id) {
      return item;
    }
    return {
      ...item,
      stock: product.stock,
      quantity: item.scent === scent ? item.quantity + toAdd : item.quantity,
    };
  });

  if (exists) {
    return updated;
  }

  return [
    ...updated,
    {
      id: product.id,
      name: product.name,
      price: product.price,
      scent: scent,
      quantity: toAdd,
      stock: product.stock,
    },
  ];
}

export function setQuantity(items: CartItem[], index: number, quantity: number): CartItem[] {
  const max = maxForLine(items, index);
  const wanted = Math.max(1, Math.floor(quantity) || 1);
  const allowed = max === null ? wanted : Math.min(wanted, max);

  return items.map((item, itemIndex) =>
    itemIndex === index ? { ...item, quantity: allowed } : item
  );
}

export function removeFromCart(items: CartItem[], index: number): CartItem[] {
  return items.filter((_, itemIndex) => itemIndex !== index);
}

export function cartCount(items: CartItem[]): number {
  return items.reduce((sum, item) => sum + item.quantity, 0);
}

export function cartTotal(items: CartItem[]): number {
  return items.reduce((sum, item) => sum + item.price * item.quantity, 0);
}
WREN_EOF

cat > "src/lib/cart-math.test.ts" << 'WREN_EOF'
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
WREN_EOF

cat > "src/components/AddToCartForm.tsx" << 'WREN_EOF'
"use client";

import { useState } from "react";
import { useCart } from "@/components/CartProvider";
import { availableToAdd, quantityInCart } from "@/lib/cart-math";
import type { Product } from "@/lib/types";

interface AddToCartFormProps {
  product: Product;
}

export default function AddToCartForm({ product }: AddToCartFormProps) {
  const { items, addItem } = useCart();
  const [scent, setScent] = useState(product.scents[0] ?? "");
  const [quantity, setQuantity] = useState(1);
  const [justAdded, setJustAdded] = useState(false);

  const inCart = quantityInCart(items, product.id);
  const available = availableToAdd(items, product);
  const soldOut = product.stock === 0;
  const canAdd = available > 0;
  const chosen = Math.min(quantity, Math.max(1, available));

  function handleAdd() {
    if (!canAdd) {
      return;
    }
    addItem(product, scent, chosen);
    setQuantity(1);
    setJustAdded(true);
    setTimeout(() => setJustAdded(false), 1500);
  }

  let buttonText = "Add to cart";
  if (soldOut) {
    buttonText = "Out of stock";
  } else if (justAdded) {
    buttonText = "Added to cart";
  } else if (!canAdd) {
    buttonText = "All available stock is in your cart";
  }

  let stockNote = "";
  if (!soldOut) {
    stockNote = product.stock <= 10 ? `Only ${product.stock} left in stock.` : `${product.stock} in stock.`;
    if (inCart > 0) {
      stockNote += ` You have ${inCart} in your cart.`;
    }
  }

  return (
    <form className="product-form">
      <div className="field">
        <label htmlFor="scent">Scent</label>
        <select id="scent" value={scent} onChange={(event) => setScent(event.target.value)}>
          {product.scents.map((option) => (
            <option key={option}>{option}</option>
          ))}
        </select>
      </div>

      <div className="field">
        <label htmlFor="quantity">Quantity</label>
        <input
          id="quantity"
          type="number"
          min="1"
          max={Math.max(1, available)}
          value={chosen}
          disabled={!canAdd}
          aria-describedby="stock-note"
          onChange={(event) => {
            const typed = Math.floor(Number(event.target.value)) || 1;
            setQuantity(Math.min(Math.max(1, typed), Math.max(1, available)));
          }}
        />
        <span id="stock-note" className="stock-note" aria-live="polite">
          {stockNote}
        </span>
      </div>

      <button className="button button-full" type="button" disabled={!canAdd} onClick={handleAdd}>
        {buttonText}
      </button>
    </form>
  );
}
WREN_EOF

cat > "src/app/cart/page.tsx" << 'WREN_EOF'
"use client";

import Link from "next/link";
import { useCart } from "@/components/CartProvider";
import { maxForLine } from "@/lib/cart-math";

export default function CartPage() {
  const { items, total, ready, updateQuantity, removeItem, clearCart } = useCart();

  if (!ready) {
    return (
      <section className="section">
        <div className="container">
          <h1 className="page-title">Your cart</h1>
          <p>Loading your cart...</p>
        </div>
      </section>
    );
  }

  if (items.length === 0) {
    return (
      <section className="section">
        <div className="container">
          <h1 className="page-title">Your cart</h1>
          <p>Your cart is empty.</p>
          <Link className="button" href="/shop">Browse the shop</Link>
        </div>
      </section>
    );
  }

  return (
    <section className="section">
      <div className="container">
        <h1 className="page-title">Your cart</h1>

        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Product</th>
                <th>Price</th>
                <th>Quantity</th>
                <th>Total</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              {items.map((item, index) => {
                const max = maxForLine(items, index);

                return (
                <tr key={`${item.id}-${item.scent}`}>
                  <td>
                    <Link href={`/products/${item.id}`}>{item.name}</Link>
                    <br />
                    <span className="cart-scent">{item.scent}</span>
                  </td>
                  <td>${item.price}</td>
                  <td>
                    <input
                      className="cart-qty"
                      type="number"
                      min="1"
                      max={max ?? undefined}
                      value={item.quantity}
                      aria-label={`Quantity for ${item.name}`}
                      onChange={(event) => updateQuantity(index, Number(event.target.value) || 1)}
                    />
                    {max !== null && item.quantity >= max && (
                      <span className="stock-note">That&apos;s all we have</span>
                    )}
                  </td>
                  <td>${item.price * item.quantity}</td>
                  <td>
                    <button className="link-button" type="button" onClick={() => removeItem(index)}>
                      Remove
                    </button>
                  </td>
                </tr>
                );
              })}
            </tbody>
          </table>
        </div>

        <p className="cart-total">
          Order total: <strong>${total}</strong>
        </p>
        <div className="cart-actions">
          <Link className="button" href="/checkout">Checkout</Link>
          <Link href="/shop">Continue shopping</Link>
          <button className="link-button" type="button" onClick={clearCart}>
            Clear cart
          </button>
        </div>
      </div>
    </section>
  );
}
WREN_EOF

grep -q "stock-note" src/app/globals.css || cat >> src/app/globals.css << 'WREN_EOF'

/* Stock messages beside quantity boxes */
.stock-note {
  display: block;
  color: var(--color-muted);
  font-size: 0.9rem;
}
WREN_EOF

npm run lint
npm test
echo
echo "Done. The dev server picks the changes up by itself."
