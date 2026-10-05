import { useState } from "react";
import type { Category } from "../types";
import ProductCard from "../components/ProductCard";
import { useProducts } from "../hooks/useProducts";

type CategoryFilter = Category | "All";
type SortOption = "featured" | "price-low" | "price-high" | "name";


const categories: CategoryFilter[] = ["All", "Soaps", "Lotions", "Bath", "Gift sets"];

function Shop() {
  const { products, status } = useProducts();
  const [activeCategory, setActiveCategory] = useState<CategoryFilter>("All");
  const [search, setSearch] = useState("");
  const [sortBy, setSortBy] = useState<SortOption>("featured");
  
  const term = search.trim().toLowerCase();

  const visible = products.filter((product) => {
    const inCategory =
      activeCategory === "All" || product.category === activeCategory;
    const matchesSearch =
      product.name.toLowerCase().includes(term) ||
      product.description.toLowerCase().includes(term);
    return inCategory && matchesSearch;
  });

  if (sortBy === "price-low") {
    visible.sort((a, b) => a.price - b.price);
  } else if (sortBy === "price-high") {
    visible.sort((a, b) => b.price - a.price);
  } else if (sortBy === "name") {
    visible.sort((a, b) => a.name.localeCompare(b.name));
  }

  return (
    <section className="section">
      <div className="container">
        <h1 className="page-title">Shop</h1>

        <div className="shop-controls">
          <div className="field">
            <label htmlFor="search">Search</label>
            <input
              id="search"
              type="search"
              placeholder="Search products"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
          </div>
          <div className="field">
            <label htmlFor="sort">Sort by</label>
            <select
              id="sort"
              value={sortBy}
              onChange={(event) => setSortBy(event.target.value as SortOption)}
            >
              <option value="featured">Featured</option>
              <option value="price-low">Price: low to high</option>
              <option value="price-high">Price: high to low</option>
              <option value="name">Name: A to Z</option>
            </select>
          </div>
        </div>

        <div className="filters">
          {categories.map((category) => (
            <button
              key={category}
              type="button"
              className={category === activeCategory ? "chip chip-active" : "chip"}
              onClick={() => setActiveCategory(category)}
            >
              {category}
            </button>
          ))}
        </div>

        {status === "loading" && <p>Loading products...</p>}
        {status === "error" && <p>Sorry, the products could not be loaded.</p>}

        {status === "ready" && (
          <>
            <p className="result-count" aria-live="polite">
              {visible.length} {visible.length === 1 ? "product" : "products"}
            </p>
            <div className="product-grid product-grid-shop">
              {visible.length === 0 ? (
                <p>No products match your search.</p>
              ) : (
                visible.map((product) => (
                  <ProductCard key={product.id} product={product} />
                ))
              )}
            </div>
          </>
        )}
      </div>
    </section>
  );
}

export default Shop;
