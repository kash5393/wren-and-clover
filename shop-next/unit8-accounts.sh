#!/usr/bin/env bash
# Unit 8, step 3: accounts in the Next.js shop (sign in, sign up, My orders, checkout prefill).
# Run from inside the shop-next folder:  bash unit8-accounts.sh
set -e
if [ ! -f src/lib/orders.ts ]; then echo "Run this inside the shop-next folder, after step 2 (src/lib/orders.ts not found)."; exit 1; fi
npm install bcryptjs
mkdir -p src/app/login src/app/signup src/app/orders

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
}

export interface CartItem {
  id: string;
  name: string;
  price: number;
  scent: string;
  quantity: number;
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

cat > "src/lib/auth.ts" << 'WREN_EOF'
import "server-only";
import { randomBytes } from "node:crypto";
import bcrypt from "bcryptjs";
import { cookies } from "next/headers";
import { cache } from "react";
import { z } from "zod";
import { pool } from "./db";
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

export function safeNextPath(value: unknown): string {
  if (typeof value === "string" && value.startsWith("/") && !value.startsWith("//")) {
    return value;
  }
  return "/";
}
WREN_EOF

cat > "src/lib/orders.ts" << 'WREN_EOF'
import "server-only";
import { z } from "zod";
import { pool } from "./db";
import type { ShippingDetails } from "./types";

const orderSchema = z.object({
  customer: z.object({
    name: z.string().trim().min(1, "Name is required"),
    email: z.email("A valid email is required"),
    phone: z.string().trim().min(7, "A valid phone number is required"),
    address: z.string().trim().min(1, "Street address is required"),
    city: z.string().trim().min(1, "City is required"),
    state: z.string().length(2, "State must be a two-letter code"),
    postcode: z.string().regex(/^\d{5}(-\d{4})?$/, "A valid ZIP code is required"),
  }),
  items: z
    .array(
      z.object({
        id: z.string(),
        scent: z.string(),
        quantity: z.number().int().min(1).max(99),
      })
    )
    .min(1, "The order has no items"),
});

interface OrderLine {
  productId: string;
  name: string;
  scent: string;
  quantity: number;
  unitPriceCents: number;
}

export type OrderResult =
  | { ok: true; orderNumber: string; total: number }
  | { ok: false; error: string };

interface StockRow {
  name: string;
  price_cents: number;
  scents: string[];
  stock: number;
}

export async function createOrder(input: unknown, userId: number | null): Promise<OrderResult> {
  const parsed = orderSchema.safeParse(input);
  if (!parsed.success) {
    return { ok: false, error: parsed.error.issues[0]?.message ?? "Invalid order" };
  }

  const { customer, items } = parsed.data;
  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    const lines: OrderLine[] = [];

    for (const item of items) {
      const found = await client.query<StockRow>(
        "SELECT name, price_cents, scents, stock FROM products WHERE id = $1 FOR UPDATE",
        [item.id]
      );
      const product = found.rows[0];

      let problem = "";
      if (!product) {
        problem = `Unknown product: ${item.id}`;
      } else if (!product.scents.includes(item.scent)) {
        problem = `${product.name} is not available in ${item.scent}`;
      } else if (product.stock < item.quantity) {
        problem = `Only ${product.stock} of ${product.name} left in stock`;
      }

      if (problem || !product) {
        await client.query("ROLLBACK");
        return { ok: false, error: problem || "Invalid order" };
      }

      await client.query("UPDATE products SET stock = stock - $1 WHERE id = $2", [
        item.quantity,
        item.id,
      ]);

      lines.push({
        productId: item.id,
        name: product.name,
        scent: item.scent,
        quantity: item.quantity,
        unitPriceCents: product.price_cents,
      });
    }

    const totalCents = lines.reduce(
      (sum, line) => sum + line.unitPriceCents * line.quantity,
      0
    );

    const inserted = await client.query<{ id: number; order_number: string }>(
      `INSERT INTO orders (user_id, customer_name, email, phone, address, city, state, postcode, total_cents)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING id, order_number`,
      [
        userId,
        customer.name,
        customer.email,
        customer.phone,
        customer.address,
        customer.city,
        customer.state,
        customer.postcode,
        totalCents,
      ]
    );
    const order = inserted.rows[0]!;

    for (const line of lines) {
      await client.query(
        `INSERT INTO order_items (order_id, product_id, product_name, scent, quantity, unit_price_cents)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [order.id, line.productId, line.name, line.scent, line.quantity, line.unitPriceCents]
      );
    }

    await client.query("COMMIT");

    return { ok: true, orderNumber: order.order_number, total: totalCents / 100 };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export interface OrderSummary {
  orderNumber: string;
  createdAt: string;
  total: number;
  lines: { name: string; scent: string; quantity: number; unitPrice: number }[];
}

export async function getOrdersForUser(userId: number): Promise<OrderSummary[]> {
  const result = await pool.query(
    `SELECT
       o.order_number AS "orderNumber",
       o.created_at AS "createdAt",
       o.total_cents / 100.0 AS total,
       json_agg(
         json_build_object(
           'name', i.product_name,
           'scent', i.scent,
           'quantity', i.quantity,
           'unitPrice', i.unit_price_cents / 100.0
         )
         ORDER BY i.id
       ) AS lines
     FROM orders o
     JOIN order_items i ON i.order_id = o.id
     WHERE o.user_id = $1
     GROUP BY o.id
     ORDER BY o.id DESC`,
    [userId]
  );

  return result.rows.map((row) => ({
    orderNumber: row.orderNumber,
    createdAt: new Date(row.createdAt).toISOString(),
    total: Number(row.total),
    lines: row.lines,
  }));
}

export async function getSavedShipping(userId: number): Promise<ShippingDetails | null> {
  const result = await pool.query<ShippingDetails>(
    `SELECT customer_name AS name, email, phone, address, city, state, postcode
     FROM orders
     WHERE user_id = $1
     ORDER BY id DESC
     LIMIT 1`,
    [userId]
  );

  return result.rows[0] ?? null;
}
WREN_EOF

cat > "src/app/auth-actions.ts" << 'WREN_EOF'
"use server";

import { redirect } from "next/navigation";
import { endSession, logIn, safeNextPath, signUp, startSession } from "@/lib/auth";

export interface AuthFormState {
  error: string;
}

export async function loginAction(
  _previous: AuthFormState,
  formData: FormData
): Promise<AuthFormState> {
  const result = await logIn({
    email: formData.get("email"),
    password: formData.get("password"),
  });

  if (!result.ok) {
    return { error: result.error };
  }

  await startSession(result.user.id);
  redirect(safeNextPath(formData.get("next")));
}

export async function signupAction(
  _previous: AuthFormState,
  formData: FormData
): Promise<AuthFormState> {
  const result = await signUp({
    name: formData.get("name"),
    email: formData.get("email"),
    password: formData.get("password"),
  });

  if (!result.ok) {
    return { error: result.error };
  }

  await startSession(result.user.id);
  redirect(safeNextPath(formData.get("next")));
}

export async function logoutAction(): Promise<void> {
  await endSession();
  redirect("/");
}
WREN_EOF

cat > "src/components/AuthForm.tsx" << 'WREN_EOF'
"use client";

import Link from "next/link";
import { useActionState } from "react";
import { loginAction, signupAction } from "@/app/auth-actions";
import type { AuthFormState } from "@/app/auth-actions";

interface AuthFormProps {
  mode: "login" | "signup";
  nextPath: string;
  defaultEmail?: string;
}

const initialState: AuthFormState = { error: "" };

export default function AuthForm({ mode, nextPath, defaultEmail = "" }: AuthFormProps) {
  const isSignup = mode === "signup";
  const [state, formAction, pending] = useActionState(
    isSignup ? signupAction : loginAction,
    initialState
  );
  const nextQuery = `?next=${encodeURIComponent(nextPath)}`;

  return (
    <>
      <form className="contact-form" action={formAction}>
        <input type="hidden" name="next" value={nextPath} />

        {isSignup && (
          <div className="field">
            <label htmlFor="name">Name</label>
            <input id="name" name="name" type="text" autoComplete="name" required />
          </div>
        )}

        <div className="field">
          <label htmlFor="email">Email</label>
          <input
            id="email"
            name="email"
            type="email"
            autoComplete="email"
            defaultValue={defaultEmail}
            required
          />
        </div>

        <div className="field">
          <label htmlFor="password">
            {isSignup ? "Password (at least 8 characters)" : "Password"}
          </label>
          <input
            id="password"
            name="password"
            type="password"
            autoComplete={isSignup ? "new-password" : "current-password"}
            minLength={isSignup ? 8 : undefined}
            required
          />
        </div>

        {state.error && (
          <p className="field-error" role="alert">
            {state.error}
          </p>
        )}

        <button className="button button-full" type="submit" disabled={pending}>
          {pending ? "Please wait..." : isSignup ? "Create account" : "Sign in"}
        </button>
      </form>

      {isSignup ? (
        <p>
          Already have an account? <Link href={`/login${nextQuery}`}>Sign in</Link>
        </p>
      ) : (
        <p>
          New here? <Link href={`/signup${nextQuery}`}>Create an account</Link>
        </p>
      )}
    </>
  );
}
WREN_EOF

cat > "src/components/Header.tsx" << 'WREN_EOF'
"use client";

import Link from "next/link";
import { useState } from "react";
import { logoutAction } from "@/app/auth-actions";
import { useCart } from "@/components/CartProvider";

interface HeaderProps {
  userName: string | null;
}

export default function Header({ userName }: HeaderProps) {
  const { count } = useCart();
  const [menuOpen, setMenuOpen] = useState(false);
  const closeMenu = () => setMenuOpen(false);

  return (
    <header className="site-header">
      <div className="container header-inner">
        <Link className="logo" href="/" onClick={closeMenu}>
          Wren &amp; Clover
        </Link>

        <button
          className="menu-toggle"
          type="button"
          aria-expanded={menuOpen}
          aria-controls="site-nav"
          onClick={() => setMenuOpen(!menuOpen)}
        >
          {menuOpen ? "Close" : "Menu"}
        </button>

        <nav
          id="site-nav"
          className={menuOpen ? "site-nav is-open" : "site-nav"}
          aria-label="Main"
        >
          <Link href="/shop" onClick={closeMenu}>Shop</Link>
          <Link href="/about" onClick={closeMenu}>About</Link>
          <Link href="/contact" onClick={closeMenu}>Contact</Link>
          {userName ? (
            <>
              <Link href="/orders" onClick={closeMenu}>My orders</Link>
              <form action={logoutAction}>
                <button className="nav-button" type="submit">
                  Log out ({userName})
                </button>
              </form>
            </>
          ) : (
            <Link href="/login" onClick={closeMenu}>Sign in</Link>
          )}
        </nav>

        <Link className="cart-link" href="/cart" onClick={closeMenu}>
          Cart ({count})
        </Link>
      </div>
    </header>
  );
}
WREN_EOF

cat > "src/app/layout.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import type { ReactNode } from "react";
import { CartProvider } from "@/components/CartProvider";
import Footer from "@/components/Footer";
import Header from "@/components/Header";
import { getCurrentUser } from "@/lib/auth";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "Wren & Clover Botanicals",
    template: "%s | Wren & Clover Botanicals",
  },
  description: "Small-batch organic soap and skincare, made by hand.",
};

interface RootLayoutProps {
  children: ReactNode;
}

export default async function RootLayout({ children }: RootLayoutProps) {
  const user = await getCurrentUser();

  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        {/* eslint-disable-next-line @next/next/no-page-custom-font */}
        <link
          href="https://fonts.googleapis.com/css2?family=DM+Serif+Display&family=Work+Sans:wght@400;600&display=swap"
          rel="stylesheet"
        />
      </head>
      <body>
        <CartProvider>
          <Header userName={user ? user.name : null} />
          <main>{children}</main>
          <Footer />
        </CartProvider>
      </body>
    </html>
  );
}
WREN_EOF

cat > "src/app/login/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import { redirect } from "next/navigation";
import AuthForm from "@/components/AuthForm";
import { getCurrentUser, safeNextPath } from "@/lib/auth";

export const metadata: Metadata = {
  title: "Sign in",
};

function first(value: string | string[] | undefined): string {
  return Array.isArray(value) ? (value[0] ?? "") : (value ?? "");
}

export default async function LoginPage(props: PageProps<"/login">) {
  const query = await props.searchParams;
  const nextPath = safeNextPath(first(query.next));

  if (await getCurrentUser()) {
    redirect(nextPath);
  }

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Sign in</h1>
        <AuthForm mode="login" nextPath={nextPath} defaultEmail={first(query.email)} />
      </div>
    </section>
  );
}
WREN_EOF

cat > "src/app/signup/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import { redirect } from "next/navigation";
import AuthForm from "@/components/AuthForm";
import { getCurrentUser, safeNextPath } from "@/lib/auth";

export const metadata: Metadata = {
  title: "Create an account",
};

function first(value: string | string[] | undefined): string {
  return Array.isArray(value) ? (value[0] ?? "") : (value ?? "");
}

export default async function SignupPage(props: PageProps<"/signup">) {
  const query = await props.searchParams;
  const nextPath = safeNextPath(first(query.next));

  if (await getCurrentUser()) {
    redirect(nextPath);
  }

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Create an account</h1>
        <AuthForm mode="signup" nextPath={nextPath} defaultEmail={first(query.email)} />
      </div>
    </section>
  );
}
WREN_EOF

cat > "src/app/orders/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentUser } from "@/lib/auth";
import { getOrdersForUser } from "@/lib/orders";

export const metadata: Metadata = {
  title: "My orders",
};

export default async function OrdersPage() {
  const user = await getCurrentUser();
  if (!user) {
    redirect("/login?next=/orders");
  }

  const orders = await getOrdersForUser(user.id);

  return (
    <section className="section">
      <div className="container">
        <h1 className="page-title">My orders</h1>

        {orders.length === 0 ? (
          <>
            <p>You haven&apos;t placed any orders with this account yet.</p>
            <Link className="button" href="/shop">Browse the shop</Link>
          </>
        ) : (
          <div className="order-list">
            {orders.map((order) => (
              <article className="order-card" key={order.orderNumber}>
                <header className="order-card-header">
                  <h2>{order.orderNumber}</h2>
                  <p>{order.createdAt.slice(0, 10)}</p>
                </header>
                <ul>
                  {order.lines.map((line) => (
                    <li key={`${line.name}-${line.scent}`}>
                      <span>
                        {line.quantity} x {line.name} ({line.scent})
                      </span>
                      <span>${line.unitPrice * line.quantity}</span>
                    </li>
                  ))}
                </ul>
                <p className="order-summary-total">
                  <span>Total</span>
                  <strong>${order.total}</strong>
                </p>
              </article>
            ))}
          </div>
        )}
      </div>
    </section>
  );
}
WREN_EOF

cat > "src/app/checkout/actions.ts" << 'WREN_EOF'
"use server";

import { getCurrentUser } from "@/lib/auth";
import { createOrder } from "@/lib/orders";
import type { OrderResult } from "@/lib/orders";

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

export async function placeOrder(request: OrderRequest): Promise<OrderResult> {
  try {
    const user = await getCurrentUser();
    const result = await createOrder(request, user ? user.id : null);
    if (result.ok) {
      console.log(`New order ${result.orderNumber}: $${result.total}`);
    }
    return result;
  } catch (error) {
    console.error(error);
    return { ok: false, error: "Something went wrong placing the order. Please try again." };
  }
}
WREN_EOF

cat > "src/app/checkout/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import { getCurrentUser } from "@/lib/auth";
import { getSavedShipping } from "@/lib/orders";
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
        />
      </div>
    </section>
  );
}
WREN_EOF

cat > "src/app/checkout/CheckoutForm.tsx" << 'WREN_EOF'
"use client";

import Link from "next/link";
import { useState } from "react";
import type { FormEvent } from "react";
import { useCart } from "@/components/CartProvider";
import FormField from "@/components/FormField";
import type { ShippingDetails } from "@/lib/types";
import { placeOrder } from "./actions";

interface CheckoutFields {
  name: string;
  email: string;
  phone: string;
  address: string;
  city: string;
  state: string;
  postcode: string;
}

type CheckoutErrors = Partial<Record<keyof CheckoutFields, string>>;

interface PlacedOrder {
  orderNumber: string;
  total: number;
}

const emptyForm: CheckoutFields = {
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

const usStates = [
  "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL",
  "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME",
  "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH",
  "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI",
  "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI",
  "WY",
];

function validate(form: CheckoutFields): CheckoutErrors {
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

interface CheckoutFormProps {
  user: { name: string; email: string } | null;
  savedShipping: ShippingDetails | null;
}

export default function CheckoutForm({ user, savedShipping }: CheckoutFormProps) {
  const { items, total, ready, clearCart } = useCart();
  const [form, setForm] = useState<CheckoutFields>({
    ...emptyForm,
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

    const foundErrors = validate(form);
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

    setSubmitting(false);

    if (!result.ok) {
      setServerError(result.error);
      return;
    }

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
            {submitting ? "Placing order..." : "Place order"}
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

grep -q "site-nav form" src/app/globals.css || cat >> src/app/globals.css << 'WREN_EOF'

/* The log out button sits in a small form inside the navigation */
.site-nav form {
  display: flex;
  flex-direction: column;
  margin: 0;
}
WREN_EOF

echo
echo "Done. Restart the dev server:  npm run dev"
