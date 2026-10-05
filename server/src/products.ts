import { readFile, writeFile } from "node:fs/promises";
import { z } from "zod";
import type { Product } from "./types.js";

const dataFile = new URL("../data/products.json", import.meta.url);

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

export async function loadProducts(): Promise<Product[]> {
  const text = await readFile(dataFile, "utf-8");
  return JSON.parse(text) as Product[];
}

async function saveProducts(products: Product[]): Promise<void> {
  await writeFile(dataFile, JSON.stringify(products, null, 2) + "\n");
}

export async function createProduct(body: unknown): Promise<ProductResult> {
  const parsed = productSchema.safeParse(body);
  if (!parsed.success) {
    return { ok: false, status: 400, error: parsed.error.issues[0]?.message ?? "Invalid product" };
  }

  const products = await loadProducts();
  if (products.some((product) => product.id === parsed.data.id)) {
    return { ok: false, status: 409, error: `A product with id ${parsed.data.id} already exists` };
  }

  products.push(parsed.data);
  await saveProducts(products);
  return { ok: true, product: parsed.data };
}

export async function updateProduct(id: string, body: unknown): Promise<ProductResult> {
  const parsed = productUpdateSchema.safeParse(body);
  if (!parsed.success) {
    return { ok: false, status: 400, error: parsed.error.issues[0]?.message ?? "Invalid product" };
  }

  const products = await loadProducts();
  const existing = products.find((product) => product.id === id);
  if (!existing) {
    return { ok: false, status: 404, error: "Product not found" };
  }

  const updated: Product = { ...existing, ...parsed.data };
  await saveProducts(products.map((product) => (product.id === id ? updated : product)));
  return { ok: true, product: updated };
}

export async function deleteProduct(id: string): Promise<boolean> {
  const products = await loadProducts();
  const remaining = products.filter((product) => product.id !== id);
  if (remaining.length === products.length) {
    return false;
  }

  await saveProducts(remaining);
  return true;
}
