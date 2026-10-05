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
