import "server-only";
import { connection } from "next/server";
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
