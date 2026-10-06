#!/usr/bin/env bash
# Product photos: the owner can upload, replace and remove a photo for each product.
# Run from inside the shop-next folder:  bash unit10-images.sh
set -e
if [ ! -f src/lib/admin.ts ] || [ ! -f .env.local ]; then echo "Run this inside the shop-next folder (src/lib/admin.ts not found)."; exit 1; fi
mkdir -p db "src/app/product-images/[id]"

cat > db/images-migration.sql << 'WREN_EOF'
CREATE TABLE IF NOT EXISTS product_images (
  product_id TEXT PRIMARY KEY REFERENCES products (id) ON DELETE CASCADE,
  content_type TEXT NOT NULL,
  data BYTEA NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
WREN_EOF
DATABASE_URL=$(grep '^DATABASE_URL=' .env.local | cut -d= -f2-)
psql "$DATABASE_URL" -q -f db/images-migration.sql
echo "Local database updated: product photo table added."

SCHEMA=../server/db/schema.sql
if [ -f "$SCHEMA" ] && ! grep -q "CREATE TABLE product_images" "$SCHEMA"; then
  perl -0pi -e 's|^|DROP TABLE IF EXISTS product_images;\n|' "$SCHEMA"
  cat >> "$SCHEMA" << 'WREN_EOF'

CREATE TABLE product_images (
  product_id TEXT PRIMARY KEY REFERENCES products (id) ON DELETE CASCADE,
  content_type TEXT NOT NULL,
  data BYTEA NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
WREN_EOF
fi

cat > next.config.ts << 'WREN_EOF'
import path from "node:path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  turbopack: {
    root: path.resolve(__dirname),
  },
  experimental: {
    serverActions: {
      bodySizeLimit: "3mb",
    },
  },
};

export default nextConfig;
WREN_EOF

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
  image_version: string | null;
}

export type SortOption = "featured" | "price-low" | "price-high" | "name";

interface ProductFilters {
  category?: string;
  search?: string;
  sort?: SortOption;
}

const productColumns = `id, name, category, price_cents, size, scents, description, stock,
  (SELECT floor(extract(epoch FROM updated_at))::bigint
   FROM product_images
   WHERE product_images.product_id = products.id) AS image_version`;

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
    imageUrl: row.image_version ? `/product-images/${row.id}?v=${row.image_version}` : null,
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

export async function addStock(id: string, amount: number): Promise<void> {
  await pool.query("UPDATE products SET stock = stock + $1 WHERE id = $2", [amount, id]);
}
WREN_EOF

cat > "src/lib/product-images.ts" << 'WREN_EOF'
import "server-only";
import { pool } from "./db";

export const MAX_IMAGE_BYTES = 2 * 1024 * 1024;
const allowedTypes = ["image/jpeg", "image/png", "image/webp"];

export type ImageResult = { ok: true } | { ok: false; error: string };

export async function saveProductImage(productId: string, file: unknown): Promise<ImageResult> {
  if (!(file instanceof File) || file.size === 0) {
    return { ok: false, error: "Choose a photo to upload." };
  }
  if (!allowedTypes.includes(file.type)) {
    return { ok: false, error: "The photo must be a JPEG, PNG or WebP image." };
  }
  if (file.size > MAX_IMAGE_BYTES) {
    return { ok: false, error: "The photo is too large. Please use one under 2 MB." };
  }

  const product = await pool.query("SELECT 1 FROM products WHERE id = $1", [productId]);
  if (product.rows.length === 0) {
    return { ok: false, error: "Product not found." };
  }

  const data = Buffer.from(await file.arrayBuffer());

  await pool.query(
    `INSERT INTO product_images (product_id, content_type, data)
     VALUES ($1, $2, $3)
     ON CONFLICT (product_id)
     DO UPDATE SET content_type = EXCLUDED.content_type, data = EXCLUDED.data, updated_at = now()`,
    [productId, file.type, data]
  );

  return { ok: true };
}

export async function deleteProductImage(productId: string): Promise<void> {
  await pool.query("DELETE FROM product_images WHERE product_id = $1", [productId]);
}

export async function getProductImage(
  productId: string
): Promise<{ contentType: string; data: Buffer } | null> {
  const result = await pool.query<{ content_type: string; data: Buffer }>(
    "SELECT content_type, data FROM product_images WHERE product_id = $1",
    [productId]
  );
  const row = result.rows[0];
  return row ? { contentType: row.content_type, data: row.data } : null;
}
WREN_EOF

cat > "src/app/product-images/[id]/route.ts" << 'WREN_EOF'
import { getProductImage } from "@/lib/product-images";

export async function GET(
  _request: Request,
  context: RouteContext<"/product-images/[id]">
): Promise<Response> {
  const { id } = await context.params;
  const image = await getProductImage(id);

  if (!image) {
    return new Response("Not found", { status: 404 });
  }

  return new Response(new Uint8Array(image.data), {
    headers: {
      "Content-Type": image.contentType,
      "Content-Length": String(image.data.length),
      "Cache-Control": "public, max-age=31536000, immutable",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
WREN_EOF

cat > "src/components/ProductPhoto.tsx" << 'WREN_EOF'
import type { Product } from "@/lib/types";

interface ProductPhotoProps {
  product: Product;
  large?: boolean;
}

export default function ProductPhoto({ product, large = false }: ProductPhotoProps) {
  const outOfStock = product.stock === 0;

  if (!product.imageUrl) {
    return (
      <div className={large ? "photo product-photo" : "photo"}>
        {large ? "Photo coming soon" : "Product photo"}
        {outOfStock && !large && <span className="badge">Out of stock</span>}
      </div>
    );
  }

  return (
    <div className="photo-frame">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        className="photo-image"
        src={product.imageUrl}
        alt={product.name}
        loading={large ? "eager" : "lazy"}
      />
      {outOfStock && !large && <span className="badge">Out of stock</span>}
    </div>
  );
}
WREN_EOF

cat > "src/components/ProductCard.tsx" << 'WREN_EOF'
import Link from "next/link";
import ProductPhoto from "@/components/ProductPhoto";
import type { Product } from "@/lib/types";

interface ProductCardProps {
  product: Product;
}

export default function ProductCard({ product }: ProductCardProps) {
  return (
    <article className="product-card">
      <Link href={`/products/${product.id}`}>
        <ProductPhoto product={product} />
        <h3>{product.name}</h3>
        <p className="price">${product.price}</p>
        <p className="product-size">{product.size}</p>
      </Link>
    </article>
  );
}
WREN_EOF

cat > "src/components/ProductImageForm.tsx" << 'WREN_EOF'
"use client";

import { useActionState } from "react";
import { removeProductImageAction, uploadProductImageAction } from "@/app/admin/actions";
import type { ImageFormState } from "@/app/admin/actions";
import type { Product } from "@/lib/types";

interface ProductImageFormProps {
  product: Product;
}

const initialState: ImageFormState = { error: "", saved: false };

export default function ProductImageForm({ product }: ProductImageFormProps) {
  const [state, formAction, pending] = useActionState(uploadProductImageAction, initialState);

  return (
    <div className="image-manager">
      <h2>Photo</h2>

      {product.imageUrl ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img className="image-preview" src={product.imageUrl} alt={`Current photo of ${product.name}`} />
      ) : (
        <p>This product has no photo yet. Shoppers see a grey placeholder.</p>
      )}

      <form className="contact-form" action={formAction}>
        <input type="hidden" name="productId" value={product.id} />
        <div className="field">
          <label htmlFor="photo">
            {product.imageUrl ? "Replace the photo" : "Upload a photo"} (JPEG, PNG or WebP, under 2 MB;
            square photos look best)
          </label>
          <input id="photo" name="photo" type="file" accept="image/jpeg,image/png,image/webp" required />
        </div>

        {state.error && (
          <p className="field-error" role="alert">
            {state.error}
          </p>
        )}
        {state.saved && (
          <p className="form-status" role="status">
            Photo saved.
          </p>
        )}

        <div className="cart-actions">
          <button className="button" type="submit" disabled={pending}>
            {pending ? "Uploading..." : "Upload photo"}
          </button>
        </div>
      </form>

      {product.imageUrl && (
        <form action={removeProductImageAction}>
          <input type="hidden" name="productId" value={product.id} />
          <button className="link-button" type="submit">
            Remove the photo
          </button>
        </form>
      )}
    </div>
  );
}
WREN_EOF

cat > "src/app/products/[id]/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import AddToCartForm from "@/components/AddToCartForm";
import ProductCard from "@/components/ProductCard";
import ProductPhoto from "@/components/ProductPhoto";
import { getProduct, getRelatedProducts } from "@/lib/products";

export async function generateMetadata(props: PageProps<"/products/[id]">): Promise<Metadata> {
  const { id } = await props.params;
  const product = await getProduct(id);

  if (!product) {
    return { title: "Product not found" };
  }

  return {
    title: product.name,
    description: product.description,
  };
}

export default async function ProductPage(props: PageProps<"/products/[id]">) {
  const { id } = await props.params;
  const product = await getProduct(id);

  if (!product) {
    notFound();
  }

  const related = await getRelatedProducts(product);

  return (
    <>
      <section className="section">
        <div className="container">
          <nav className="breadcrumb" aria-label="Breadcrumb">
            <Link href="/shop">Shop</Link> /{" "}
            <Link href={`/shop?category=${encodeURIComponent(product.category)}`}>
              {product.category}
            </Link>{" "}
            / {product.name}
          </nav>

          <div className="product-layout">
            <ProductPhoto product={product} large />

            <div className="product-details">
              <h1>{product.name}</h1>
              <p className="product-price">${product.price}</p>
              <p>
                {product.description} {product.size}.
              </p>
              <AddToCartForm key={product.id} product={product} />
            </div>
          </div>
        </div>
      </section>

      {related.length > 0 && (
        <section className="section section-bordered">
          <div className="container">
            <h2>You may also like</h2>
            <div className="product-grid">
              {related.map((item) => (
                <ProductCard key={item.id} product={item} />
              ))}
            </div>
          </div>
        </section>
      )}
    </>
  );
}
WREN_EOF

cat > "src/app/admin/actions.ts" << 'WREN_EOF'
"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { setOrderStatus } from "@/lib/admin";
import { requireOwner } from "@/lib/auth";
import { deleteProductImage, saveProductImage } from "@/lib/product-images";
import { addStock, createProduct, deleteProduct, updateProduct } from "@/lib/products";

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

export interface ImageFormState {
  error: string;
  saved: boolean;
}

export async function uploadProductImageAction(
  _previous: ImageFormState,
  formData: FormData
): Promise<ImageFormState> {
  await requireOwner();

  const productId = String(formData.get("productId") ?? "");
  const result = await saveProductImage(productId, formData.get("photo"));
  if (!result.ok) {
    return { error: result.error, saved: false };
  }

  revalidatePath("/", "layout");
  return { error: "", saved: true };
}

export async function removeProductImageAction(formData: FormData): Promise<void> {
  await requireOwner();

  await deleteProductImage(String(formData.get("productId") ?? ""));
  revalidatePath("/", "layout");
}

export async function restockAction(formData: FormData): Promise<void> {
  await requireOwner();

  const id = String(formData.get("id") ?? "");
  const amount = Number(formData.get("amount"));

  if (id !== "" && Number.isInteger(amount) && amount > 0 && amount <= 1000) {
    await addStock(id, amount);
  }

  revalidatePath("/admin/products");
}
WREN_EOF

cat > "src/app/admin/products/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import Link from "next/link";
import { deleteProductAction, restockAction } from "@/app/admin/actions";
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
              <th>Photo</th>
              <th>Stock</th>
              <th>Add stock</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {products.map((product) => (
              <tr key={product.id}>
                <td>{product.name}</td>
                <td>{product.category}</td>
                <td>${product.price}</td>
                <td>{product.imageUrl ? "Yes" : "None"}</td>
                <td>{product.stock === 0 ? "Out of stock" : product.stock}</td>
                <td>
                  <form className="restock-form" action={restockAction}>
                    <input type="hidden" name="id" value={product.id} />
                    <input
                      className="cart-qty"
                      type="number"
                      name="amount"
                      min="1"
                      max="1000"
                      step="1"
                      defaultValue="10"
                      required
                      aria-label={`Amount of stock to add to ${product.name}`}
                    />
                    <button className="link-button" type="submit">
                      Add
                    </button>
                  </form>
                </td>
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

cat > "src/app/admin/products/[id]/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import ProductForm from "@/components/ProductForm";
import ProductImageForm from "@/components/ProductImageForm";
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
      <ProductImageForm product={product} />

      <h2>Details</h2>
      <ProductForm product={product} />
    </div>
  );
}
WREN_EOF

# The Product type gained an imageUrl field, so the test products need one too.
grep -q "imageUrl" src/lib/cart-math.test.ts || sed -i 's/^\(\s*\)stock: \([0-9]*\),$/\1stock: \2,\n\1imageUrl: null,/' src/lib/cart-math.test.ts

grep -q "photo-frame" src/app/globals.css || cat >> src/app/globals.css << 'WREN_EOF'

/* Product photos */
.photo-frame {
  position: relative;
}

.photo-image {
  display: block;
  width: 100%;
  aspect-ratio: 1 / 1;
  object-fit: cover;
  background: var(--color-border);
  border-radius: var(--radius);
}

.image-manager {
  display: grid;
  gap: var(--space-2);
  margin-bottom: var(--space-4);
}

.image-manager h2 {
  margin: 0;
}

.image-preview {
  width: 200px;
  aspect-ratio: 1 / 1;
  object-fit: cover;
  border: 1px solid var(--color-border);
  border-radius: var(--radius);
}

.restock-form {
  display: flex;
  align-items: center;
  gap: var(--space-1);
  margin: 0;
}
WREN_EOF

npm run lint
npm test
echo
echo "Done. Restart the dev server:  npm run dev"
