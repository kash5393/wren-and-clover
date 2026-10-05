#!/usr/bin/env bash
# Unit 6, step 2: move products and orders into PostgreSQL.
# Run from the wren-and-clover project folder:  bash unit6-database.sh
set -e
if [ ! -f server/src/orders.ts ]; then echo "Run this inside the wren-and-clover folder (server/src/orders.ts not found)."; exit 1; fi
cd server
npm install pg
npm install -D @types/pg
npm pkg set scripts.dev="tsx watch --env-file=.env src/index.ts" scripts.db:setup="tsx --env-file=.env src/setup-db.ts"
mkdir -p db

cat > .env << 'WREN_EOF'
DATABASE_URL=postgresql://wren:wren_dev_password@localhost:5432/wren_clover
WREN_EOF
cat > .env.example << 'WREN_EOF'
DATABASE_URL=postgresql://USER:PASSWORD@localhost:5432/DATABASE
WREN_EOF
grep -qx ".env" ../.gitignore 2>/dev/null || echo ".env" >> ../.gitignore

cat > db/schema.sql << 'WREN_EOF'
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;

CREATE TABLE products (
  id TEXT PRIMARY KEY,
  position SERIAL,
  name TEXT NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('Soaps', 'Lotions', 'Bath', 'Gift sets')),
  price_cents INTEGER NOT NULL CHECK (price_cents > 0),
  size TEXT NOT NULL,
  scents TEXT[] NOT NULL,
  description TEXT NOT NULL,
  stock INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0)
);

CREATE TABLE orders (
  id SERIAL PRIMARY KEY,
  order_number TEXT GENERATED ALWAYS AS ('WC-' || (1000 + id)) STORED,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  customer_name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT NOT NULL,
  address TEXT NOT NULL,
  city TEXT NOT NULL,
  state TEXT NOT NULL,
  postcode TEXT NOT NULL,
  total_cents INTEGER NOT NULL
);

CREATE TABLE order_items (
  id SERIAL PRIMARY KEY,
  order_id INTEGER NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
  product_id TEXT NOT NULL REFERENCES products (id),
  product_name TEXT NOT NULL,
  scent TEXT NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price_cents INTEGER NOT NULL
);

CREATE INDEX order_items_order_id_idx ON order_items (order_id);
WREN_EOF

cat > src/db.ts << 'WREN_EOF'
import pg from "pg";

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
  throw new Error("DATABASE_URL is not set. Check the .env file in the server folder.");
}

export const pool = new pg.Pool({ connectionString });
WREN_EOF

cat > src/setup-db.ts << 'WREN_EOF'
import { readFile } from "node:fs/promises";
import { pool } from "./db.js";
import type { Product } from "./types.js";

const schemaFile = new URL("../db/schema.sql", import.meta.url);
const seedFile = new URL("../data/products.json", import.meta.url);

async function setup(): Promise<void> {
  const schema = await readFile(schemaFile, "utf-8");
  await pool.query(schema);
  console.log("Tables created.");

  const products = JSON.parse(await readFile(seedFile, "utf-8")) as Product[];

  for (const product of products) {
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
  }

  console.log(`Added ${products.length} products.`);
}

setup()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
WREN_EOF

cat > src/products.ts << 'WREN_EOF'
import { z } from "zod";
import { pool } from "./db.js";
import type { Category, Product } from "./types.js";

const productSchema = z.object({
  id: z
    .string()
    .regex(/^[a-z0-9]+(-[a-z0-9]+)*$/, "id must be lowercase words joined by hyphens"),
  name: z.string().trim().min(1, "name is required"),
  category: z.enum(["Soaps", "Lotions", "Bath", "Gift sets"], "category is not valid"),
  price: z.number().positive("price must be more than 0"),
  size: z.string().trim().min(1, "size is required"),
  scents: z.array(z.string().trim().min(1)).min(1, "at least one scent is required"),
  description: z.string().trim().min(1, "description is required"),
  stock: z.number().int().min(0, "stock cannot be negative"),
});

const productUpdateSchema = productSchema.omit({ id: true }).partial();

type ProductResult =
  | { ok: true; product: Product }
  | { ok: false; status: number; error: string };

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

interface ProductFilters {
  category?: string;
  search?: string;
  inStock?: boolean;
}

const productColumns = "id, name, category, price_cents, size, scents, description, stock";

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

function isDatabaseError(error: unknown, code: string): boolean {
  return typeof error === "object" && error !== null && "code" in error && error.code === code;
}

export async function loadProducts(filters: ProductFilters = {}): Promise<Product[]> {
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
  if (filters.inStock) {
    conditions.push("stock > 0");
  }

  const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
  const result = await pool.query<ProductRow>(
    `SELECT ${productColumns} FROM products ${where} ORDER BY position`,
    values
  );

  return result.rows.map(toProduct);
}

export async function getProduct(id: string): Promise<Product | null> {
  const result = await pool.query<ProductRow>(
    `SELECT ${productColumns} FROM products WHERE id = $1`,
    [id]
  );
  const row = result.rows[0];
  return row ? toProduct(row) : null;
}

export async function listCategories(): Promise<string[]> {
  const result = await pool.query<{ category: string }>(
    "SELECT category FROM products GROUP BY category ORDER BY MIN(position)"
  );
  return result.rows.map((row) => row.category);
}

export async function createProduct(body: unknown): Promise<ProductResult> {
  const parsed = productSchema.safeParse(body);
  if (!parsed.success) {
    return { ok: false, status: 400, error: parsed.error.issues[0]?.message ?? "Invalid product" };
  }

  const product = parsed.data;

  try {
    const result = await pool.query<ProductRow>(
      `INSERT INTO products (id, name, category, price_cents, size, scents, description, stock)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING ${productColumns}`,
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
    return { ok: true, product: toProduct(result.rows[0]!) };
  } catch (error) {
    if (isDatabaseError(error, "23505")) {
      return { ok: false, status: 409, error: `A product with id ${product.id} already exists` };
    }
    throw error;
  }
}

export async function updateProduct(id: string, body: unknown): Promise<ProductResult> {
  const parsed = productUpdateSchema.safeParse(body);
  if (!parsed.success) {
    return { ok: false, status: 400, error: parsed.error.issues[0]?.message ?? "Invalid product" };
  }

  const changes = parsed.data;
  const assignments: string[] = [];
  const values: unknown[] = [];

  function set(column: string, value: unknown) {
    values.push(value);
    assignments.push(`${column} = $${values.length}`);
  }

  if (changes.name !== undefined) set("name", changes.name);
  if (changes.category !== undefined) set("category", changes.category);
  if (changes.price !== undefined) set("price_cents", Math.round(changes.price * 100));
  if (changes.size !== undefined) set("size", changes.size);
  if (changes.scents !== undefined) set("scents", changes.scents);
  if (changes.description !== undefined) set("description", changes.description);
  if (changes.stock !== undefined) set("stock", changes.stock);

  if (assignments.length === 0) {
    const existing = await getProduct(id);
    return existing
      ? { ok: true, product: existing }
      : { ok: false, status: 404, error: "Product not found" };
  }

  values.push(id);
  const result = await pool.query<ProductRow>(
    `UPDATE products SET ${assignments.join(", ")} WHERE id = $${values.length}
     RETURNING ${productColumns}`,
    values
  );

  const row = result.rows[0];
  if (!row) {
    return { ok: false, status: 404, error: "Product not found" };
  }
  return { ok: true, product: toProduct(row) };
}

export async function deleteProduct(id: string): Promise<"deleted" | "not-found" | "in-use"> {
  try {
    const result = await pool.query("DELETE FROM products WHERE id = $1", [id]);
    return result.rowCount === 0 ? "not-found" : "deleted";
  } catch (error) {
    if (isDatabaseError(error, "23503")) {
      return "in-use";
    }
    throw error;
  }
}
WREN_EOF

cat > src/orders.ts << 'WREN_EOF'
import { z } from "zod";
import { pool } from "./db.js";

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

interface PlacedOrder {
  orderNumber: string;
  total: number;
}

type OrderResult =
  | { ok: true; order: PlacedOrder }
  | { ok: false; status: number; error: string };

interface StockRow {
  name: string;
  price_cents: number;
  scents: string[];
  stock: number;
}

export async function createOrder(body: unknown): Promise<OrderResult> {
  const parsed = orderSchema.safeParse(body);
  if (!parsed.success) {
    return { ok: false, status: 400, error: parsed.error.issues[0]?.message ?? "Invalid order" };
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

      let problem: { status: number; error: string } | null = null;
      if (!product) {
        problem = { status: 400, error: `Unknown product: ${item.id}` };
      } else if (!product.scents.includes(item.scent)) {
        problem = { status: 400, error: `${product.name} is not available in ${item.scent}` };
      } else if (product.stock < item.quantity) {
        problem = {
          status: 409,
          error: `Only ${product.stock} of ${product.name} left in stock`,
        };
      }

      if (problem || !product) {
        await client.query("ROLLBACK");
        return { ok: false, ...(problem ?? { status: 400, error: "Invalid order" }) };
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
      `INSERT INTO orders (customer_name, email, phone, address, city, state, postcode, total_cents)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING id, order_number`,
      [
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

    return { ok: true, order: { orderNumber: order.order_number, total: totalCents / 100 } };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function listOrders(): Promise<unknown[]> {
  const result = await pool.query(
    `SELECT
       o.order_number AS "orderNumber",
       o.created_at AS "createdAt",
       o.customer_name AS "customerName",
       o.email,
       o.city,
       o.state,
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
     GROUP BY o.id
     ORDER BY o.id DESC`
  );

  return result.rows.map((row) => ({ ...row, total: Number(row.total) }));
}
WREN_EOF

cat > src/index.ts << 'WREN_EOF'
import express from "express";
import type { NextFunction, Request, Response } from "express";
import { createOrder, listOrders } from "./orders.js";
import {
  createProduct,
  deleteProduct,
  getProduct,
  listCategories,
  loadProducts,
  updateProduct,
} from "./products.js";

const app = express();
const port = Number(process.env.PORT) || 4000;

app.use(express.json());

app.get("/api/health", (_request, response) => {
  response.json({ status: "ok" });
});

app.get("/api/products", async (request, response) => {
  const { category, search, inStock } = request.query;

  const products = await loadProducts({
    category: typeof category === "string" ? category : undefined,
    search: typeof search === "string" ? search.trim() : undefined,
    inStock: inStock === "true",
  });

  response.json(products);
});

app.get("/api/products/:id", async (request, response) => {
  const product = await getProduct(request.params.id);

  if (!product) {
    response.status(404).json({ error: "Product not found" });
    return;
  }

  response.json(product);
});

app.post("/api/products", async (request, response) => {
  const result = await createProduct(request.body);

  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  response.status(201).json(result.product);
});

app.patch("/api/products/:id", async (request, response) => {
  const result = await updateProduct(request.params.id, request.body);

  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  response.json(result.product);
});

app.delete("/api/products/:id", async (request, response) => {
  const outcome = await deleteProduct(request.params.id);

  if (outcome === "not-found") {
    response.status(404).json({ error: "Product not found" });
    return;
  }
  if (outcome === "in-use") {
    response
      .status(409)
      .json({ error: "This product appears in past orders, so it cannot be deleted" });
    return;
  }

  response.status(204).end();
});

app.get("/api/categories", async (_request, response) => {
  response.json(await listCategories());
});

app.post("/api/orders", async (request, response) => {
  const result = await createOrder(request.body);

  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  console.log(`New order ${result.order.orderNumber}: $${result.order.total}`);
  response.status(201).json(result.order);
});

app.get("/api/orders", async (_request, response) => {
  response.json(await listOrders());
});

app.use((_request, response) => {
  response.status(404).json({ error: "Not found" });
});

app.use((error: unknown, _request: Request, response: Response, _next: NextFunction) => {
  if (error instanceof SyntaxError) {
    response.status(400).json({ error: "The request body is not valid JSON" });
    return;
  }

  console.error(error);
  response.status(500).json({ error: "Something went wrong on the server" });
});

app.listen(port, () => {
  console.log(`Shop API running at http://localhost:${port}`);
});
WREN_EOF

npm run check
npm run db:setup
echo
echo "Done. Restart the API:  cd server && npm run dev"
