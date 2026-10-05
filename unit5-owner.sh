#!/usr/bin/env bash
# Unit 5, step 3: owner endpoints to add, edit and delete products.
# Run from the wren-and-clover project folder:  bash unit5-owner.sh
set -e
if [ ! -f server/src/orders.ts ]; then echo "Run this inside the wren-and-clover folder, after the orders step (server/src/orders.ts not found)."; exit 1; fi
cat > server/src/products.ts << 'WREN_EOF'
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
WREN_EOF

cat > server/src/index.ts << 'WREN_EOF'
import express from "express";
import type { NextFunction, Request, Response } from "express";
import { createOrder, listOrders } from "./orders.js";
import { createProduct, deleteProduct, loadProducts, updateProduct } from "./products.js";

const app = express();
const port = Number(process.env.PORT) || 4000;

app.use(express.json());

app.get("/api/health", (_request, response) => {
  response.json({ status: "ok" });
});

app.get("/api/products", async (request, response) => {
  let products = await loadProducts();

  const category = request.query.category;
  if (typeof category === "string") {
    products = products.filter((product) => product.category === category);
  }

  const search = request.query.search;
  if (typeof search === "string") {
    const term = search.trim().toLowerCase();
    products = products.filter(
      (product) =>
        product.name.toLowerCase().includes(term) ||
        product.description.toLowerCase().includes(term)
    );
  }

  response.json(products);
});

app.get("/api/products/:id", async (request, response) => {
  const products = await loadProducts();
  const product = products.find((item) => item.id === request.params.id);

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
  const deleted = await deleteProduct(request.params.id);

  if (!deleted) {
    response.status(404).json({ error: "Product not found" });
    return;
  }

  response.status(204).end();
});

app.get("/api/categories", async (_request, response) => {
  const products = await loadProducts();
  const categories = [...new Set(products.map((product) => product.category))];
  response.json(categories);
});

app.post("/api/orders", async (request, response) => {
  const result = await createOrder(request.body);

  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  console.log(`New order ${result.order.orderNumber}: $${result.order.total}`);
  response.status(201).json({
    orderNumber: result.order.orderNumber,
    total: result.order.total,
  });
});

app.get("/api/orders", (_request, response) => {
  response.json(listOrders());
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

(cd server && npm run check)
echo
echo "Done. The API restarts by itself if it is running."
