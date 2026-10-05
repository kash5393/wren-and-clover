#!/usr/bin/env bash
# Unit 8, step 4: the admin portal (dashboard, products, orders, messages).
# Run from inside the shop-next folder:  bash unit8-admin.sh
set -e
if [ ! -f src/lib/auth.ts ] || [ ! -f .env.local ]; then echo "Run this inside the shop-next folder, after step 3 (src/lib/auth.ts not found)."; exit 1; fi
mkdir -p db src/app/admin/products/new "src/app/admin/products/[id]" src/app/admin/orders src/app/admin/messages src/app/account

cat > db/admin-migration.sql << 'WREN_EOF'
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'new';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'orders_status_check') THEN
    ALTER TABLE orders ADD CONSTRAINT orders_status_check CHECK (status IN ('new', 'shipped'));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS contact_messages (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
WREN_EOF
DATABASE_URL=$(grep '^DATABASE_URL=' .env.local | cut -d= -f2-)
psql "$DATABASE_URL" -q -f db/admin-migration.sql
echo "Database updated: orders have a status, and contact messages have a table."

# Keep the shared schema file in step, so a database rebuild includes these changes.
SCHEMA=../server/db/schema.sql
if [ -f "$SCHEMA" ]; then
  grep -q "status TEXT NOT NULL DEFAULT 'new'" "$SCHEMA" || perl -0pi -e "s|total_cents INTEGER NOT NULL\n\);|total_cents INTEGER NOT NULL,\n  status TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'shipped'))\n);|" "$SCHEMA"
  if ! grep -q "CREATE TABLE contact_messages" "$SCHEMA"; then
    perl -0pi -e 's|^|DROP TABLE IF EXISTS contact_messages;\n|' "$SCHEMA"
    cat >> "$SCHEMA" << 'WREN_EOF'

CREATE TABLE contact_messages (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
WREN_EOF
  fi
fi

grep -q countOrdersForUser src/lib/orders.ts || cat >> src/lib/orders.ts << 'WREN_EOF'

export async function countOrdersForUser(userId: number): Promise<number> {
  const result = await pool.query<{ count: string }>(
    "SELECT COUNT(*) AS count FROM orders WHERE user_id = $1",
    [userId]
  );

  return Number(result.rows[0]?.count ?? 0);
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
WREN_EOF

cat > "src/lib/products.ts" << 'WREN_EOF'
import "server-only";
import { connection } from "next/server";
import { z } from "zod";
import { pool } from "./db";
import type { Category, Product } from "./types";

interface ProductRow {
  id: string;
  name: string;
  category: Category;
  price_cents: number;
  size: string;
  scents: string[];
  description: string;
  stock: number;
}

export type SortOption = "featured" | "price-low" | "price-high" | "name";

interface ProductFilters {
  category?: string;
  search?: string;
  sort?: SortOption;
}

const productColumns = "id, name, category, price_cents, size, scents, description, stock";

const sortClauses: Record<SortOption, string> = {
  featured: "position",
  "price-low": "price_cents ASC, position",
  "price-high": "price_cents DESC, position",
  name: "name",
};

function toProduct(row: ProductRow): Product {
  return {
    id: row.id,
    name: row.name,
    category: row.category,
    price: row.price_cents / 100,
    size: row.size,
    scents: row.scents,
    description: row.description,
    stock: row.stock,
  };
}

export async function getProducts(filters: ProductFilters = {}): Promise<Product[]> {
  await connection();

  const conditions: string[] = [];
  const values: unknown[] = [];

  if (filters.category) {
    values.push(filters.category);
    conditions.push(`category = $${values.length}`);
  }
  if (filters.search) {
    values.push(`%${filters.search}%`);
    conditions.push(`(name ILIKE $${values.length} OR description ILIKE $${values.length})`);
  }

  const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
  const orderBy = sortClauses[filters.sort ?? "featured"];

  const result = await pool.query<ProductRow>(
    `SELECT ${productColumns} FROM products ${where} ORDER BY ${orderBy}`,
    values
  );

  return result.rows.map(toProduct);
}

export async function getProduct(id: string): Promise<Product | null> {
  await connection();

  const result = await pool.query<ProductRow>(
    `SELECT ${productColumns} FROM products WHERE id = $1`,
    [id]
  );
  const row = result.rows[0];
  return row ? toProduct(row) : null;
}

export async function getProductsByIds(ids: string[]): Promise<Product[]> {
  await connection();

  const result = await pool.query<ProductRow>(
    `SELECT ${productColumns} FROM products WHERE id = ANY($1) ORDER BY position`,
    [ids]
  );
  return result.rows.map(toProduct);
}

export async function getRelatedProducts(product: Product): Promise<Product[]> {
  await connection();

  const result = await pool.query<ProductRow>(
    `SELECT ${productColumns} FROM products
     WHERE category = $1 AND id <> $2
     ORDER BY position
     LIMIT 3`,
    [product.category, product.id]
  );
  return result.rows.map(toProduct);
}

const productSchema = z.object({
  id: z
    .string()
    .trim()
    .regex(/^[a-z0-9]+(-[a-z0-9]+)*$/, "The id must be lowercase words joined by hyphens."),
  name: z.string().trim().min(1, "Name is required."),
  category: z.enum(["Soaps", "Lotions", "Bath", "Gift sets"], "Choose a category."),
  price: z.number("Price must be a number.").positive("Price must be more than 0."),
  size: z.string().trim().min(1, "Size is required."),
  scents: z.array(z.string().trim().min(1)).min(1, "Enter at least one scent."),
  description: z.string().trim().min(1, "Description is required."),
  stock: z.number("Stock must be a number.").int("Stock must be a whole number.").min(0, "Stock cannot be negative."),
});

export type SaveResult = { ok: true } | { ok: false; error: string };

function isDatabaseError(error: unknown, code: string): boolean {
  return typeof error === "object" && error !== null && "code" in error && error.code === code;
}

export async function createProduct(input: unknown): Promise<SaveResult> {
  const parsed = productSchema.safeParse(input);
  if (!parsed.success) {
    return { ok: false, error: parsed.error.issues[0]?.message ?? "Please check the product details." };
  }

  const product = parsed.data;

  try {
    await pool.query(
      `INSERT INTO products (id, name, category, price_cents, size, scents, description, stock)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        product.id,
        product.name,
        product.category,
        Math.round(product.price * 100),
        product.size,
        product.scents,
        product.description,
        product.stock,
      ]
    );
    return { ok: true };
  } catch (error) {
    if (isDatabaseError(error, "23505")) {
      return { ok: false, error: `A product with the id "${product.id}" already exists.` };
    }
    throw error;
  }
}

export async function updateProduct(id: string, input: unknown): Promise<SaveResult> {
  const parsed = productSchema.omit({ id: true }).safeParse(input);
  if (!parsed.success) {
    return { ok: false, error: parsed.error.issues[0]?.message ?? "Please check the product details." };
  }

  const product = parsed.data;
  const result = await pool.query(
    `UPDATE products
     SET name = $1, category = $2, price_cents = $3, size = $4, scents = $5, description = $6, stock = $7
     WHERE id = $8`,
    [
      product.name,
      product.category,
      Math.round(product.price * 100),
      product.size,
      product.scents,
      product.description,
      product.stock,
      id,
    ]
  );

  return result.rowCount === 0 ? { ok: false, error: "Product not found." } : { ok: true };
}

export async function deleteProduct(id: string): Promise<SaveResult> {
  try {
    const result = await pool.query("DELETE FROM products WHERE id = $1", [id]);
    return result.rowCount === 0 ? { ok: false, error: "Product not found." } : { ok: true };
  } catch (error) {
    if (isDatabaseError(error, "23503")) {
      return {
        ok: false,
        error: "This product appears in past orders, so it cannot be deleted. Set its stock to 0 instead.",
      };
    }
    throw error;
  }
}
WREN_EOF

cat > "src/lib/admin.ts" << 'WREN_EOF'
import "server-only";
import { connection } from "next/server";
import { pool } from "./db";

export interface DashboardStats {
  orderCount: number;
  newOrderCount: number;
  salesTotal: number;
  messageCount: number;
  lowStock: { id: string; name: string; stock: number }[];
  bestSellers: { name: string; unitsSold: number; revenue: number }[];
}

export interface AdminOrder {
  id: number;
  orderNumber: string;
  createdAt: string;
  status: "new" | "shipped";
  customerName: string;
  email: string;
  phone: string;
  address: string;
  guest: boolean;
  total: number;
  lines: { name: string; scent: string; quantity: number }[];
}

export interface ContactMessage {
  id: number;
  name: string;
  email: string;
  message: string;
  createdAt: string;
}

export async function getDashboardStats(): Promise<DashboardStats> {
  await connection();

  const [orders, messages, lowStock, bestSellers] = await Promise.all([
    pool.query<{ order_count: string; new_count: string; sales_cents: string | null }>(
      `SELECT
         COUNT(*) AS order_count,
         COUNT(*) FILTER (WHERE status = 'new') AS new_count,
         SUM(total_cents) AS sales_cents
       FROM orders`
    ),
    pool.query<{ count: string }>("SELECT COUNT(*) AS count FROM contact_messages"),
    pool.query<{ id: string; name: string; stock: number }>(
      "SELECT id, name, stock FROM products WHERE stock < 10 ORDER BY stock, name"
    ),
    pool.query<{ name: string; units_sold: string; revenue_cents: string }>(
      `SELECT
         product_name AS name,
         SUM(quantity) AS units_sold,
         SUM(quantity * unit_price_cents) AS revenue_cents
       FROM order_items
       GROUP BY product_name
       ORDER BY SUM(quantity) DESC
       LIMIT 5`
    ),
  ]);

  const totals = orders.rows[0];

  return {
    orderCount: Number(totals?.order_count ?? 0),
    newOrderCount: Number(totals?.new_count ?? 0),
    salesTotal: Number(totals?.sales_cents ?? 0) / 100,
    messageCount: Number(messages.rows[0]?.count ?? 0),
    lowStock: lowStock.rows,
    bestSellers: bestSellers.rows.map((row) => ({
      name: row.name,
      unitsSold: Number(row.units_sold),
      revenue: Number(row.revenue_cents) / 100,
    })),
  };
}

export async function getAllOrders(): Promise<AdminOrder[]> {
  await connection();

  const result = await pool.query(
    `SELECT
       o.id,
       o.order_number,
       o.created_at,
       o.status,
       o.customer_name,
       o.email,
       o.phone,
       o.address || ', ' || o.city || ', ' || o.state || ' ' || o.postcode AS address,
       o.user_id IS NULL AS guest,
       o.total_cents,
       json_agg(
         json_build_object('name', i.product_name, 'scent', i.scent, 'quantity', i.quantity)
         ORDER BY i.id
       ) AS lines
     FROM orders o
     JOIN order_items i ON i.order_id = o.id
     GROUP BY o.id
     ORDER BY o.id DESC`
  );

  return result.rows.map((row) => ({
    id: row.id,
    orderNumber: row.order_number,
    createdAt: new Date(row.created_at).toISOString(),
    status: row.status,
    customerName: row.customer_name,
    email: row.email,
    phone: row.phone,
    address: row.address,
    guest: row.guest,
    total: row.total_cents / 100,
    lines: row.lines,
  }));
}

export async function setOrderStatus(orderId: number, status: "new" | "shipped"): Promise<void> {
  await pool.query("UPDATE orders SET status = $1 WHERE id = $2", [status, orderId]);
}

export async function getMessages(): Promise<ContactMessage[]> {
  await connection();

  const result = await pool.query(
    "SELECT id, name, email, message, created_at FROM contact_messages ORDER BY id DESC"
  );

  return result.rows.map((row) => ({
    id: row.id,
    name: row.name,
    email: row.email,
    message: row.message,
    createdAt: new Date(row.created_at).toISOString(),
  }));
}
WREN_EOF

cat > "src/app/admin/actions.ts" << 'WREN_EOF'
"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { setOrderStatus } from "@/lib/admin";
import { requireOwner } from "@/lib/auth";
import { createProduct, deleteProduct, updateProduct } from "@/lib/products";

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
        </nav>
        {children}
      </div>
    </section>
  );
}
WREN_EOF

cat > "src/app/admin/page.tsx" << 'WREN_EOF'
import Link from "next/link";
import { getDashboardStats } from "@/lib/admin";
import { requireOwner } from "@/lib/auth";

export default async function AdminDashboardPage() {
  await requireOwner();
  const stats = await getDashboardStats();

  return (
    <>
      <h1 className="page-title">Dashboard</h1>

      <div className="stat-grid">
        <div className="stat-card">
          <p className="stat-label">Total sales</p>
          <p className="stat-value">${stats.salesTotal}</p>
        </div>
        <div className="stat-card">
          <p className="stat-label">Orders</p>
          <p className="stat-value">{stats.orderCount}</p>
        </div>
        <div className="stat-card">
          <p className="stat-label">Waiting to ship</p>
          <p className="stat-value">{stats.newOrderCount}</p>
        </div>
        <div className="stat-card">
          <p className="stat-label">Messages</p>
          <p className="stat-value">{stats.messageCount}</p>
        </div>
      </div>

      <div className="admin-columns">
        <div>
          <h2>Low stock</h2>
          {stats.lowStock.length === 0 ? (
            <p>Every product has 10 or more in stock.</p>
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Product</th>
                    <th>In stock</th>
                  </tr>
                </thead>
                <tbody>
                  {stats.lowStock.map((product) => (
                    <tr key={product.id}>
                      <td>
                        <Link href={`/admin/products/${product.id}`}>{product.name}</Link>
                      </td>
                      <td>{product.stock}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

        <div>
          <h2>Best sellers</h2>
          {stats.bestSellers.length === 0 ? (
            <p>No sales yet.</p>
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Product</th>
                    <th>Units sold</th>
                    <th>Revenue</th>
                  </tr>
                </thead>
                <tbody>
                  {stats.bestSellers.map((product) => (
                    <tr key={product.name}>
                      <td>{product.name}</td>
                      <td>{product.unitsSold}</td>
                      <td>${product.revenue}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </>
  );
}
WREN_EOF

cat > "src/app/admin/products/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import Link from "next/link";
import { deleteProductAction } from "@/app/admin/actions";
import { requireOwner } from "@/lib/auth";
import { getProducts } from "@/lib/products";

export const metadata: Metadata = {
  title: "Products",
};

export default async function AdminProductsPage(props: PageProps<"/admin/products">) {
  await requireOwner();

  const query = await props.searchParams;
  const error = typeof query.error === "string" ? query.error : "";
  const products = await getProducts();

  return (
    <>
      <div className="admin-heading">
        <h1 className="page-title">Products</h1>
        <Link className="button" href="/admin/products/new">Add product</Link>
      </div>

      {error && (
        <p className="field-error" role="alert">
          {error}
        </p>
      )}

      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Product</th>
              <th>Category</th>
              <th>Price</th>
              <th>Stock</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {products.map((product) => (
              <tr key={product.id}>
                <td>{product.name}</td>
                <td>{product.category}</td>
                <td>${product.price}</td>
                <td>{product.stock === 0 ? "Out of stock" : product.stock}</td>
                <td>
                  <div className="row-actions">
                    <Link href={`/admin/products/${product.id}`}>Edit</Link>
                    <form action={deleteProductAction}>
                      <input type="hidden" name="id" value={product.id} />
                      <button className="link-button" type="submit">
                        Delete
                      </button>
                    </form>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
WREN_EOF

cat > "src/app/admin/products/new/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import ProductForm from "@/components/ProductForm";
import { requireOwner } from "@/lib/auth";

export const metadata: Metadata = {
  title: "Add product",
};

export default async function NewProductPage() {
  await requireOwner();

  return (
    <div className="prose">
      <h1 className="page-title">Add product</h1>
      <ProductForm />
    </div>
  );
}
WREN_EOF

cat > "src/app/admin/products/[id]/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import ProductForm from "@/components/ProductForm";
import { requireOwner } from "@/lib/auth";
import { getProduct } from "@/lib/products";

export const metadata: Metadata = {
  title: "Edit product",
};

export default async function EditProductPage(props: PageProps<"/admin/products/[id]">) {
  await requireOwner();

  const { id } = await props.params;
  const product = await getProduct(id);
  if (!product) {
    notFound();
  }

  return (
    <div className="prose">
      <h1 className="page-title">Edit {product.name}</h1>
      <ProductForm product={product} />
    </div>
  );
}
WREN_EOF

cat > "src/app/admin/orders/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import { setOrderStatusAction } from "@/app/admin/actions";
import { getAllOrders } from "@/lib/admin";
import { requireOwner } from "@/lib/auth";

export const metadata: Metadata = {
  title: "Orders",
};

export default async function AdminOrdersPage() {
  await requireOwner();
  const orders = await getAllOrders();

  return (
    <>
      <h1 className="page-title">Orders</h1>

      {orders.length === 0 ? (
        <p>No orders yet.</p>
      ) : (
        <div className="order-list">
          {orders.map((order) => (
            <article className="order-card" key={order.id}>
              <header className="order-card-header">
                <h2>{order.orderNumber}</h2>
                <p>
                  {order.createdAt.slice(0, 10)} · {order.status === "shipped" ? "Shipped" : "Waiting to ship"}
                </p>
              </header>

              <p className="order-customer">
                <strong>{order.customerName}</strong> {order.guest ? "(guest)" : "(account)"}
                <br />
                {order.email} · {order.phone}
                <br />
                {order.address}
              </p>

              <ul>
                {order.lines.map((line) => (
                  <li key={`${line.name}-${line.scent}`}>
                    <span>
                      {line.quantity} x {line.name} ({line.scent})
                    </span>
                  </li>
                ))}
              </ul>

              <p className="order-summary-total">
                <span>Total</span>
                <strong>${order.total}</strong>
              </p>

              <form action={setOrderStatusAction}>
                <input type="hidden" name="orderId" value={order.id} />
                <input
                  type="hidden"
                  name="status"
                  value={order.status === "shipped" ? "new" : "shipped"}
                />
                <button className={order.status === "shipped" ? "link-button" : "button"} type="submit">
                  {order.status === "shipped" ? "Mark as not shipped" : "Mark as shipped"}
                </button>
              </form>
            </article>
          ))}
        </div>
      )}
    </>
  );
}
WREN_EOF

cat > "src/app/admin/messages/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import { getMessages } from "@/lib/admin";
import { requireOwner } from "@/lib/auth";

export const metadata: Metadata = {
  title: "Messages",
};

export default async function AdminMessagesPage() {
  await requireOwner();
  const messages = await getMessages();

  return (
    <>
      <h1 className="page-title">Messages</h1>

      {messages.length === 0 ? (
        <p>No messages yet.</p>
      ) : (
        <div className="order-list">
          {messages.map((message) => (
            <article className="order-card" key={message.id}>
              <header className="order-card-header">
                <h2>{message.name}</h2>
                <p>{message.createdAt.slice(0, 10)}</p>
              </header>
              <p className="order-customer">
                <a href={`mailto:${message.email}`}>{message.email}</a>
              </p>
              <p className="order-customer">{message.message}</p>
            </article>
          ))}
        </div>
      )}
    </>
  );
}
WREN_EOF

cat > "src/components/ProductForm.tsx" << 'WREN_EOF'
"use client";

import Link from "next/link";
import { useActionState } from "react";
import { createProductAction, updateProductAction } from "@/app/admin/actions";
import type { ProductFormState } from "@/app/admin/actions";
import { categories } from "@/lib/types";
import type { Product } from "@/lib/types";

interface ProductFormProps {
  product?: Product;
}

const initialState: ProductFormState = { error: "" };

export default function ProductForm({ product }: ProductFormProps) {
  const isEditing = product !== undefined;
  const [state, formAction, pending] = useActionState(
    isEditing ? updateProductAction : createProductAction,
    initialState
  );

  return (
    <form className="contact-form" action={formAction}>
      <div className="field">
        <label htmlFor="id">Id (used in the web address, such as rose-clay-soap)</label>
        <input id="id" name="id" type="text" defaultValue={product?.id} readOnly={isEditing} required />
      </div>

      <div className="field">
        <label htmlFor="name">Name</label>
        <input id="name" name="name" type="text" defaultValue={product?.name} required />
      </div>

      <div className="field">
        <label htmlFor="category">Category</label>
        <select id="category" name="category" defaultValue={product?.category ?? ""} required>
          <option value="">Select...</option>
          {categories.map((category) => (
            <option key={category} value={category}>
              {category}
            </option>
          ))}
        </select>
      </div>

      <div className="field">
        <label htmlFor="price">Price in dollars</label>
        <input
          id="price"
          name="price"
          type="number"
          min="0.01"
          step="0.01"
          defaultValue={product?.price}
          required
        />
      </div>

      <div className="field">
        <label htmlFor="stock">Stock</label>
        <input id="stock" name="stock" type="number" min="0" step="1" defaultValue={product?.stock ?? 0} required />
      </div>

      <div className="field">
        <label htmlFor="size">Size (such as 4.5 oz bar)</label>
        <input id="size" name="size" type="text" defaultValue={product?.size} required />
      </div>

      <div className="field">
        <label htmlFor="scents">Scents, separated by commas</label>
        <input id="scents" name="scents" type="text" defaultValue={product?.scents.join(", ")} required />
      </div>

      <div className="field">
        <label htmlFor="description">Description</label>
        <textarea id="description" name="description" rows={4} defaultValue={product?.description} required />
      </div>

      {state.error && (
        <p className="field-error" role="alert">
          {state.error}
        </p>
      )}

      <div className="cart-actions">
        <button className="button" type="submit" disabled={pending}>
          {pending ? "Saving..." : isEditing ? "Save changes" : "Add product"}
        </button>
        <Link href="/admin/products">Cancel</Link>
      </div>
    </form>
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
  isOwner: boolean;
}

export default function Header({ userName, isOwner }: HeaderProps) {
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
          {isOwner && <Link href="/admin" onClick={closeMenu}>Admin</Link>}
          {userName ? (
            <>
              <Link href="/orders" onClick={closeMenu}>My orders</Link>
              <Link href="/account" onClick={closeMenu}>My account</Link>
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
          <Header userName={user ? user.name : null} isOwner={user?.role === "owner"} />
          <main>{children}</main>
          <Footer />
        </CartProvider>
      </body>
    </html>
  );
}
WREN_EOF

cat > "src/app/contact/actions.ts" << 'WREN_EOF'
"use server";

import { z } from "zod";
import { pool } from "@/lib/db";

const messageSchema = z.object({
  name: z.string().trim().min(1, "Please enter your name."),
  email: z.email("Please enter a valid email address."),
  message: z.string().trim().min(10, "Please write at least 10 characters."),
});

export interface ContactState {
  status: "idle" | "sent" | "error";
  sentTo?: string;
  errors?: { name?: string; email?: string; message?: string };
}

export async function sendMessage(
  _previous: ContactState,
  formData: FormData
): Promise<ContactState> {
  const parsed = messageSchema.safeParse({
    name: formData.get("name"),
    email: formData.get("email"),
    message: formData.get("message"),
  });

  if (!parsed.success) {
    const errors: ContactState["errors"] = {};
    for (const issue of parsed.error.issues) {
      const field = issue.path[0];
      if (field === "name" || field === "email" || field === "message") {
        errors[field] ??= issue.message;
      }
    }
    return { status: "error", errors };
  }

  await pool.query(
    "INSERT INTO contact_messages (name, email, message) VALUES ($1, $2, $3)",
    [parsed.data.name, parsed.data.email, parsed.data.message]
  );

  return { status: "sent", sentTo: parsed.data.name };
}
WREN_EOF

cat > "src/app/account/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentUser } from "@/lib/auth";
import { countOrdersForUser } from "@/lib/orders";

export const metadata: Metadata = {
  title: "My account",
};

export default async function AccountPage() {
  const user = await getCurrentUser();
  if (!user) {
    redirect("/login?next=/account");
  }

  const orderCount = await countOrdersForUser(user.id);

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">My account</h1>

        <div className="table-wrap">
          <table>
            <tbody>
              <tr>
                <th scope="row">Name</th>
                <td>{user.name}</td>
              </tr>
              <tr>
                <th scope="row">Email</th>
                <td>{user.email}</td>
              </tr>
              <tr>
                <th scope="row">Orders placed</th>
                <td>{orderCount}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <p>
          <Link className="button" href="/orders">View my orders</Link>
        </p>
      </div>
    </section>
  );
}
WREN_EOF

grep -q "stat-grid" src/app/globals.css || cat >> src/app/globals.css << 'WREN_EOF'

/* Admin portal */
.admin-signed-in {
  margin: 0 0 var(--space-2);
  color: var(--color-muted);
  font-size: 0.9rem;
}

.admin-heading {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-2);
  margin-bottom: var(--space-3);
}

.admin-heading .page-title {
  margin: 0;
}

.stat-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: var(--space-2);
  margin-bottom: var(--space-4);
}

.stat-card {
  padding: var(--space-3);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius);
}

.stat-label {
  margin: 0;
  color: var(--color-muted);
  font-size: 0.9rem;
}

.stat-value {
  margin: 0;
  font-family: var(--font-heading);
  font-size: 2rem;
}

.admin-columns {
  display: grid;
  gap: var(--space-4);
}

.row-actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-2);
}

.row-actions form {
  margin: 0;
}

.order-customer {
  margin: 0;
}

@media (min-width: 768px) {
  .stat-grid {
    grid-template-columns: repeat(4, 1fr);
  }

  .admin-columns {
    grid-template-columns: 1fr 1fr;
  }
}
WREN_EOF

echo
echo "Done. Restart the dev server:  npm run dev"
