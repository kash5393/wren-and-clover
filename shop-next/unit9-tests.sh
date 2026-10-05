#!/usr/bin/env bash
# Unit 9, step 1: automated tests for the cart, checkout validation and redirect logic.
# Run from inside the shop-next folder:  bash unit9-tests.sh
set -e
if [ ! -f src/lib/payments.ts ]; then echo "Run this inside the shop-next folder, after the payments step (src/lib/payments.ts not found)."; exit 1; fi
npm install -D vitest @types/node@22
npm pkg set scripts.test="vitest run" scripts.test:watch="vitest"

cat > vitest.config.ts << 'WREN_EOF'
import path from "node:path";
import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "src"),
    },
  },
  test: {
    include: ["src/**/*.test.ts"],
  },
});
WREN_EOF

cat > "src/lib/cart-math.ts" << 'WREN_EOF'
import type { CartItem, Product } from "./types";

export function addToCart(
  items: CartItem[],
  product: Product,
  scent: string,
  quantity: number
): CartItem[] {
  const exists = items.some((item) => item.id === product.id && item.scent === scent);

  if (exists) {
    return items.map((item) =>
      item.id === product.id && item.scent === scent
        ? { ...item, quantity: item.quantity + quantity }
        : item
    );
  }

  return [
    ...items,
    {
      id: product.id,
      name: product.name,
      price: product.price,
      scent: scent,
      quantity: quantity,
    },
  ];
}

export function setQuantity(items: CartItem[], index: number, quantity: number): CartItem[] {
  return items.map((item, itemIndex) =>
    itemIndex === index ? { ...item, quantity: Math.max(1, quantity) } : item
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

cat > "src/lib/checkout-validation.ts" << 'WREN_EOF'
export interface CheckoutFields {
  name: string;
  email: string;
  phone: string;
  address: string;
  city: string;
  state: string;
  postcode: string;
}

export type CheckoutErrors = Partial<Record<keyof CheckoutFields, string>>;

export const emptyCheckoutForm: CheckoutFields = {
  name: "",
  email: "",
  phone: "",
  address: "",
  city: "",
  state: "",
  postcode: "",
};

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const phonePattern = /^[0-9+()\-\s]{7,}$/;
const zipPattern = /^\d{5}(-\d{4})?$/;

export const usStates = [
  "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL",
  "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME",
  "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH",
  "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI",
  "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI",
  "WY",
];

export function validateCheckout(form: CheckoutFields): CheckoutErrors {
  const errors: CheckoutErrors = {};

  if (form.name.trim() === "") {
    errors.name = "Please enter your name.";
  }
  if (!emailPattern.test(form.email.trim())) {
    errors.email = "Please enter a valid email address.";
  }
  if (!phonePattern.test(form.phone.trim())) {
    errors.phone = "Please enter a valid phone number.";
  }
  if (form.address.trim() === "") {
    errors.address = "Please enter your street address.";
  }
  if (form.city.trim() === "") {
    errors.city = "Please enter your city.";
  }
  if (!usStates.includes(form.state)) {
    errors.state = "Please choose your state.";
  }
  if (!zipPattern.test(form.postcode.trim())) {
    errors.postcode = "Please enter a valid ZIP code.";
  }

  return errors;
}
WREN_EOF

cat > "src/lib/paths.ts" << 'WREN_EOF'
/** Only allows redirects to pages on this site, never to another website. */
export function safeNextPath(value: unknown): string {
  if (typeof value === "string" && value.startsWith("/") && !value.startsWith("//")) {
    return value;
  }
  return "/";
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

function tooManyAttempts(key: string): boolean {
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

cat > "src/components/CartProvider.tsx" << 'WREN_EOF'
"use client";

import { createContext, useContext, useEffect, useState } from "react";
import type { ReactNode } from "react";
import { addToCart, cartCount, cartTotal, removeFromCart, setQuantity } from "@/lib/cart-math";
import type { CartItem, Product } from "@/lib/types";

const CART_KEY = "wren-clover-cart";

interface CartContextValue {
  items: CartItem[];
  count: number;
  total: number;
  ready: boolean;
  addItem: (product: Product, scent: string, quantity: number) => void;
  updateQuantity: (index: number, quantity: number) => void;
  removeItem: (index: number) => void;
  clearCart: () => void;
}

const CartContext = createContext<CartContextValue | null>(null);

function loadCart(): CartItem[] {
  try {
    const saved = localStorage.getItem(CART_KEY);
    return saved ? (JSON.parse(saved) as CartItem[]) : [];
  } catch {
    return [];
  }
}

interface CartProviderProps {
  children: ReactNode;
}

export function CartProvider({ children }: CartProviderProps) {
  const [items, setItems] = useState<CartItem[]>([]);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const frame = requestAnimationFrame(() => {
      setItems(loadCart());
      setReady(true);
    });
    return () => cancelAnimationFrame(frame);
  }, []);

  useEffect(() => {
    if (ready) {
      localStorage.setItem(CART_KEY, JSON.stringify(items));
    }
  }, [items, ready]);

  function addItem(product: Product, scent: string, quantity: number) {
    setItems((current) => addToCart(current, product, scent, quantity));
  }

  function updateQuantity(index: number, quantity: number) {
    setItems((current) => setQuantity(current, index, quantity));
  }

  function removeItem(index: number) {
    setItems((current) => removeFromCart(current, index));
  }

  function clearCart() {
    setItems([]);
  }

  const count = cartCount(items);
  const total = cartTotal(items);

  return (
    <CartContext.Provider
      value={{ items, count, total, ready, addItem, updateQuantity, removeItem, clearCart }}
    >
      {children}
    </CartContext.Provider>
  );
}

export function useCart() {
  const context = useContext(CartContext);
  if (!context) {
    throw new Error("useCart must be used inside a CartProvider");
  }
  return context;
}
WREN_EOF

cat > "src/app/checkout/CheckoutForm.tsx" << 'WREN_EOF'
"use client";

import Link from "next/link";
import { useState } from "react";
import type { FormEvent } from "react";
import { useCart } from "@/components/CartProvider";
import FormField from "@/components/FormField";
import { emptyCheckoutForm, usStates, validateCheckout } from "@/lib/checkout-validation";
import type { CheckoutErrors, CheckoutFields } from "@/lib/checkout-validation";
import type { ShippingDetails } from "@/lib/types";
import { placeOrder } from "./actions";

interface PlacedOrder {
  orderNumber: string;
  total: number;
}

interface CheckoutFormProps {
  user: { name: string; email: string } | null;
  savedShipping: ShippingDetails | null;
  paymentsOn: boolean;
}

export default function CheckoutForm({ user, savedShipping, paymentsOn }: CheckoutFormProps) {
  const { items, total, ready, clearCart } = useCart();
  const [form, setForm] = useState<CheckoutFields>({
    ...emptyCheckoutForm,
    ...(user ? { name: user.name, email: user.email } : {}),
    ...(savedShipping ?? {}),
  });
  const [errors, setErrors] = useState<CheckoutErrors>({});
  const [placedOrder, setPlacedOrder] = useState<PlacedOrder | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [serverError, setServerError] = useState("");

  function updateField(field: keyof CheckoutFields, value: string) {
    setForm((current) => ({ ...current, [field]: value }));
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const foundErrors = validateCheckout(form);
    setErrors(foundErrors);
    if (Object.keys(foundErrors).length > 0) {
      return;
    }

    setSubmitting(true);
    setServerError("");

    const result = await placeOrder({
      customer: form,
      items: items.map((item) => ({
        id: item.id,
        scent: item.scent,
        quantity: item.quantity,
      })),
    });

    if (!result.ok) {
      setSubmitting(false);
      setServerError(result.error);
      return;
    }

    if (result.kind === "payment") {
      window.location.assign(result.paymentUrl);
      return;
    }

    setSubmitting(false);
    setPlacedOrder({ orderNumber: result.orderNumber, total: result.total });
    clearCart();
  }

  if (placedOrder) {
    return (
      <div className="prose">
        <h1 className="page-title">Thank you, {form.name.trim()}</h1>
        <p>
          Your order <strong>{placedOrder.orderNumber}</strong> for{" "}
          <strong>${placedOrder.total}</strong> has been received. A confirmation
          will be sent to {form.email.trim()}.
        </p>
        <p>This is a practice checkout: no payment was taken and nothing will be shipped.</p>
        {user ? (
          <p>
            You can see this order under <Link href="/orders">My orders</Link>.
          </p>
        ) : (
          <p>
            Want to see your orders in one place next time?{" "}
            <Link href={`/signup?email=${encodeURIComponent(form.email.trim())}`}>
              Create an account
            </Link>
            . It&apos;s optional.
          </p>
        )}
        <Link className="button" href="/shop">Back to the shop</Link>
      </div>
    );
  }

  if (!ready) {
    return (
      <>
        <h1 className="page-title">Checkout</h1>
        <p>Loading your cart...</p>
      </>
    );
  }

  if (items.length === 0) {
    return (
      <>
        <h1 className="page-title">Checkout</h1>
        <p>Your cart is empty, so there is nothing to check out.</p>
        <Link className="button" href="/shop">Browse the shop</Link>
      </>
    );
  }

  return (
    <>
      <h1 className="page-title">Checkout</h1>

      {user ? (
        <p className="checkout-notice">
          Signed in as <strong>{user.name}</strong> ({user.email}).{" "}
          {savedShipping
            ? "We've filled in the details from your last order. Check them before you place this one."
            : "Your details will be remembered after your first order."}
        </p>
      ) : (
        <p className="checkout-notice">
          You&apos;re checking out as a guest, with no account needed. Have an
          account? <Link href="/login?next=/checkout">Sign in</Link> to fill in
          your details.
        </p>
      )}

      <div className="checkout-layout">
        <form className="contact-form" noValidate onSubmit={handleSubmit}>
          <h2>Shipping details</h2>
          <FormField
            id="name"
            label="Full name"
            autoComplete="name"
            value={form.name}
            error={errors.name}
            onChange={(value) => updateField("name", value)}
          />
          <FormField
            id="email"
            label="Email"
            type="email"
            autoComplete="email"
            value={form.email}
            error={errors.email}
            onChange={(value) => updateField("email", value)}
          />
          <FormField
            id="phone"
            label="Phone"
            type="tel"
            autoComplete="tel"
            value={form.phone}
            error={errors.phone}
            onChange={(value) => updateField("phone", value)}
          />
          <FormField
            id="address"
            label="Street address"
            autoComplete="street-address"
            value={form.address}
            error={errors.address}
            onChange={(value) => updateField("address", value)}
          />
          <FormField
            id="city"
            label="City"
            autoComplete="address-level2"
            value={form.city}
            error={errors.city}
            onChange={(value) => updateField("city", value)}
          />
          <FormField
            id="state"
            label="State"
            options={usStates}
            autoComplete="address-level1"
            value={form.state}
            error={errors.state}
            onChange={(value) => updateField("state", value)}
          />
          <FormField
            id="postcode"
            label="ZIP code"
            autoComplete="postal-code"
            value={form.postcode}
            error={errors.postcode}
            onChange={(value) => updateField("postcode", value)}
          />
          {serverError && (
            <p className="field-error" role="alert">
              {serverError}
            </p>
          )}
          <button className="button button-full" type="submit" disabled={submitting}>
            {submitting ? "Please wait..." : paymentsOn ? "Continue to payment" : "Place order"}
          </button>
        </form>

        <aside className="order-summary">
          <h2>Order summary</h2>
          <ul>
            {items.map((item) => (
              <li key={`${item.id}-${item.scent}`}>
                <span>
                  {item.quantity} x {item.name} ({item.scent})
                </span>
                <span>${item.price * item.quantity}</span>
              </li>
            ))}
          </ul>
          <p className="order-summary-total">
            <span>Total</span>
            <strong>${total}</strong>
          </p>
          <Link href="/cart">Edit cart</Link>
        </aside>
      </div>
    </>
  );
}
WREN_EOF

cat > "src/lib/cart-math.test.ts" << 'WREN_EOF'
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
WREN_EOF

cat > "src/lib/checkout-validation.test.ts" << 'WREN_EOF'
import { describe, expect, it } from "vitest";
import { emptyCheckoutForm, validateCheckout } from "./checkout-validation";
import type { CheckoutFields } from "./checkout-validation";

const validForm: CheckoutFields = {
  name: "Ada Lovelace",
  email: "ada@example.com",
  phone: "401 555 0123",
  address: "1 Main Street",
  city: "Cranston",
  state: "RI",
  postcode: "02920",
};

describe("validateCheckout", () => {
  it("accepts a correctly filled form", () => {
    expect(validateCheckout(validForm)).toEqual({});
  });

  it("reports every field of an empty form", () => {
    const errors = validateCheckout(emptyCheckoutForm);

    expect(Object.keys(errors).sort()).toEqual(
      ["address", "city", "email", "name", "phone", "postcode", "state"]
    );
  });

  it("rejects an email without an @", () => {
    const errors = validateCheckout({ ...validForm, email: "ada.example.com" });

    expect(errors.email).toBe("Please enter a valid email address.");
  });

  it("rejects a phone number with letters", () => {
    expect(validateCheckout({ ...validForm, phone: "call me" }).phone).toBeDefined();
  });

  it("only accepts a known two-letter state", () => {
    expect(validateCheckout({ ...validForm, state: "Rhode Island" }).state).toBeDefined();
    expect(validateCheckout({ ...validForm, state: "ZZ" }).state).toBeDefined();
    expect(validateCheckout({ ...validForm, state: "CA" }).state).toBeUndefined();
  });

  it("accepts five-digit and nine-digit ZIP codes", () => {
    expect(validateCheckout({ ...validForm, postcode: "02920" }).postcode).toBeUndefined();
    expect(validateCheckout({ ...validForm, postcode: "02920-1234" }).postcode).toBeUndefined();
  });

  it("rejects a ZIP code of the wrong length", () => {
    expect(validateCheckout({ ...validForm, postcode: "2920" }).postcode).toBeDefined();
    expect(validateCheckout({ ...validForm, postcode: "029201" }).postcode).toBeDefined();
  });

  it("treats a name of only spaces as empty", () => {
    expect(validateCheckout({ ...validForm, name: "   " }).name).toBeDefined();
  });
});
WREN_EOF

cat > "src/lib/paths.test.ts" << 'WREN_EOF'
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
WREN_EOF

npm test
echo
echo "Done. Run the tests any time with:  npm test"
