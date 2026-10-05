#!/usr/bin/env bash
# Unit 8, step 1: the shop in Next.js (layout, home, shop and product pages from the database).
# Run from the wren-and-clover project folder:  bash unit8-next.sh
set -e
if [ ! -f shop-react/src/styles.css ] || [ ! -f server/.env ]; then echo "Run this inside the wren-and-clover folder (shop-react/ and server/.env not found)."; exit 1; fi

if [ ! -d shop-next ]; then
  npx --yes create-next-app@latest shop-next --ts --eslint --app --src-dir --no-tailwind --import-alias "@/*" --use-npm --yes
fi
cd shop-next
npm install pg server-only
npm install -D @types/pg
npm pkg set scripts.dev="next dev -p 3001"
grep "^DATABASE_URL=" ../server/.env > .env.local
rm -f src/app/page.module.css
mkdir -p src/lib src/components src/app/shop "src/app/products/[id]"
cp ../shop-react/src/styles.css src/app/globals.css
cat >> src/app/globals.css << 'WREN_EOF'

/* Next.js version: category chips are links, and the shop controls have an Apply button */
a.chip {
  display: inline-block;
  text-decoration: none;
}

.shop-controls {
  align-items: end;
}

@media (min-width: 768px) {
  .shop-controls {
    grid-template-columns: 2fr 1fr auto;
  }
}
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
}

export interface CartItem {
  id: string;
  name: string;
  price: number;
  scent: string;
  quantity: number;
}
WREN_EOF

cat > "src/lib/db.ts" << 'WREN_EOF'
import "server-only";
import { Pool } from "pg";

const globalForDb = globalThis as unknown as { pool?: Pool };

function createPool(): Pool {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    throw new Error("DATABASE_URL is not set. Check .env.local in the shop-next folder.");
  }
  return new Pool({ connectionString });
}

export const pool = globalForDb.pool ?? createPool();

if (process.env.NODE_ENV !== "production") {
  globalForDb.pool = pool;
}
WREN_EOF

cat > "src/lib/products.ts" << 'WREN_EOF'
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
WREN_EOF

cat > "src/components/ProductCard.tsx" << 'WREN_EOF'
import Link from "next/link";
import type { Product } from "@/lib/types";

interface ProductCardProps {
  product: Product;
}

export default function ProductCard({ product }: ProductCardProps) {
  return (
    <article className="product-card">
      <Link href={`/products/${product.id}`}>
        <div className="photo">
          Product photo
          {product.stock === 0 && <span className="badge">Out of stock</span>}
        </div>
        <h3>{product.name}</h3>
        <p className="price">${product.price}</p>
        <p className="product-size">{product.size}</p>
      </Link>
    </article>
  );
}
WREN_EOF

cat > "src/components/Header.tsx" << 'WREN_EOF'
"use client";

import Link from "next/link";
import { useState } from "react";

export default function Header() {
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
        </nav>

        <Link className="cart-link" href="/cart" onClick={closeMenu}>
          Cart (0)
        </Link>
      </div>
    </header>
  );
}
WREN_EOF

cat > "src/components/Footer.tsx" << 'WREN_EOF'
import Link from "next/link";

export default function Footer() {
  return (
    <footer className="site-footer">
      <div className="container">
        <nav className="footer-nav" aria-label="Footer">
          <Link href="/shop">Shop</Link>
          <Link href="/about">About</Link>
          <Link href="/contact">Contact</Link>
          <Link href="/shipping">Shipping and Returns</Link>
        </nav>
        <p>&copy; Wren &amp; Clover Botanicals</p>
      </div>
    </footer>
  );
}
WREN_EOF

cat > "src/app/layout.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import type { ReactNode } from "react";
import Footer from "@/components/Footer";
import Header from "@/components/Header";
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

export default function RootLayout({ children }: RootLayoutProps) {
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
        <Header />
        <main>{children}</main>
        <Footer />
      </body>
    </html>
  );
}
WREN_EOF

cat > "src/app/page.tsx" << 'WREN_EOF'
import Link from "next/link";
import ProductCard from "@/components/ProductCard";
import { getProductsByIds } from "@/lib/products";

const featuredIds = ["lavender-oat-soap", "whipped-body-butter", "self-care-gift-box"];

export default async function HomePage() {
  const featured = await getProductsByIds(featuredIds);

  return (
    <>
      <section className="hero">
        <div className="container hero-inner">
          <div>
            <h1>Small-batch organic soap and skincare</h1>
            <p>Handmade with simple ingredients you can pronounce.</p>
            <Link className="button" href="/shop">Shop now</Link>
          </div>
          <div className="photo hero-photo">Banner photo</div>
        </div>
      </section>

      <section className="section">
        <div className="container">
          <h2>Featured</h2>
          <div className="product-grid">
            {featured.map((product) => (
              <ProductCard key={product.id} product={product} />
            ))}
          </div>
        </div>
      </section>

      <section className="section story">
        <div className="container story-inner">
          <div className="photo">Photo of the maker</div>
          <div>
            <h2>Our story</h2>
            <p>
              Every bar is made by hand in small batches, using organic oils and
              botanicals from local growers.
            </p>
            <Link className="button" href="/about">Read more</Link>
          </div>
        </div>
      </section>
    </>
  );
}
WREN_EOF

cat > "src/app/shop/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import Link from "next/link";
import ProductCard from "@/components/ProductCard";
import { getProducts } from "@/lib/products";
import type { SortOption } from "@/lib/products";
import { categories } from "@/lib/types";

export const metadata: Metadata = {
  title: "Shop",
};

const sortOptions: { value: SortOption; label: string }[] = [
  { value: "featured", label: "Featured" },
  { value: "price-low", label: "Price: low to high" },
  { value: "price-high", label: "Price: high to low" },
  { value: "name", label: "Name: A to Z" },
];

function first(value: string | string[] | undefined): string {
  return Array.isArray(value) ? (value[0] ?? "") : (value ?? "");
}

function shopLink(category: string, search: string, sort: string): string {
  const params = new URLSearchParams();
  if (category) params.set("category", category);
  if (search) params.set("search", search);
  if (sort && sort !== "featured") params.set("sort", sort);
  const query = params.toString();
  return query ? `/shop?${query}` : "/shop";
}

export default async function ShopPage(props: PageProps<"/shop">) {
  const query = await props.searchParams;

  const category = first(query.category);
  const search = first(query.search).trim();
  const requestedSort = first(query.sort);
  const sort = sortOptions.some((option) => option.value === requestedSort)
    ? (requestedSort as SortOption)
    : "featured";

  const products = await getProducts({ category, search, sort });

  return (
    <section className="section">
      <div className="container">
        <h1 className="page-title">Shop</h1>

        <form className="shop-controls" action="/shop">
          {category && <input type="hidden" name="category" value={category} />}
          <div className="field">
            <label htmlFor="search">Search</label>
            <input
              id="search"
              name="search"
              type="search"
              placeholder="Search products"
              defaultValue={search}
            />
          </div>
          <div className="field">
            <label htmlFor="sort">Sort by</label>
            <select id="sort" name="sort" defaultValue={sort}>
              {sortOptions.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </div>
          <button className="button" type="submit">Apply</button>
        </form>

        <nav className="filters" aria-label="Categories">
          <Link className={category ? "chip" : "chip chip-active"} href={shopLink("", search, sort)}>
            All
          </Link>
          {categories.map((name) => (
            <Link
              key={name}
              className={name === category ? "chip chip-active" : "chip"}
              href={shopLink(name, search, sort)}
            >
              {name}
            </Link>
          ))}
        </nav>

        <p className="result-count">
          {products.length} {products.length === 1 ? "product" : "products"}
        </p>

        <div className="product-grid product-grid-shop">
          {products.length === 0 ? (
            <p>No products match your search.</p>
          ) : (
            products.map((product) => <ProductCard key={product.id} product={product} />)
          )}
        </div>
      </div>
    </section>
  );
}
WREN_EOF

cat > "src/app/products/[id]/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import ProductCard from "@/components/ProductCard";
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
  const inStock = product.stock > 0;

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
            <div className="photo product-photo">Large product photo</div>

            <div className="product-details">
              <h1>{product.name}</h1>
              <p className="product-price">${product.price}</p>
              <p>
                {product.description} {product.size}.
              </p>
              <p>
                <strong>Scents:</strong> {product.scents.join(", ")}
              </p>
              <p>{inStock ? `${product.stock} in stock` : "Out of stock"}</p>
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

cat > "src/app/not-found.tsx" << 'WREN_EOF'
import Link from "next/link";

export default function NotFound() {
  return (
    <section className="section">
      <div className="container">
        <h1 className="page-title">Page not found</h1>
        <p>Sorry, there is nothing at this address yet.</p>
        <Link className="button" href="/shop">Go to the shop</Link>
      </div>
    </section>
  );
}
WREN_EOF

echo
echo "Done. Start it with:  cd shop-next && npm run dev   then open http://localhost:3001"
