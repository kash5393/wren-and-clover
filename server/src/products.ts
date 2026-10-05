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
