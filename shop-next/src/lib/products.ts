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
