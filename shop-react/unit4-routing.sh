#!/usr/bin/env bash
# Unit 4: routing, layout, home page and product page for the React shop.
# Run from inside the shop-react folder:  bash unit4-routing.sh
set -e
if [ ! -f vite.config.ts ]; then echo "Run this inside the shop-react folder (vite.config.ts not found)."; exit 1; fi
npm install react-router
mkdir -p src/components src/pages src/hooks

cat > src/hooks/useProducts.ts << 'WREN_EOF'
import { useEffect, useState } from "react";
import type { Product } from "../types";

type Status = "loading" | "ready" | "error";

export function useProducts() {
  const [products, setProducts] = useState<Product[]>([]);
  const [status, setStatus] = useState<Status>("loading");

  useEffect(() => {
    let cancelled = false;

    async function loadProducts() {
      try {
        const response = await fetch("/data/products.json");
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`);
        }
        const data = (await response.json()) as Product[];
        if (!cancelled) {
          setProducts(data);
          setStatus("ready");
        }
      } catch (error) {
        console.error(error);
        if (!cancelled) {
          setStatus("error");
        }
      }
    }

    loadProducts();

    return () => {
      cancelled = true;
    };
  }, []);

  return { products, status };
}
WREN_EOF

cat > src/components/ProductCard.tsx << 'WREN_EOF'
import { Link } from "react-router";
import type { Product } from "../types";

interface ProductCardProps {
  product: Product;
}

function ProductCard({ product }: ProductCardProps) {
  return (
    <article className="product-card">
      <Link to={`/products/${product.id}`}>
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

export default ProductCard;
WREN_EOF

cat > src/components/Layout.tsx << 'WREN_EOF'
import { useState } from "react";
import { Link, Outlet } from "react-router";

function Layout() {
  const [menuOpen, setMenuOpen] = useState(false);
  const closeMenu = () => setMenuOpen(false);

  return (
    <>
      <header className="site-header">
        <div className="container header-inner">
          <Link className="logo" to="/" onClick={closeMenu}>
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
            <Link to="/shop" onClick={closeMenu}>Shop</Link>
            <Link to="/about" onClick={closeMenu}>About</Link>
            <Link to="/contact" onClick={closeMenu}>Contact</Link>
          </nav>

          <Link className="cart-link" to="/cart" onClick={closeMenu}>
            Cart (0)
          </Link>
        </div>
      </header>

      <main>
        <Outlet />
      </main>

      <footer className="site-footer">
        <div className="container">
          <nav className="footer-nav" aria-label="Footer">
            <Link to="/shop">Shop</Link>
            <Link to="/about">About</Link>
            <Link to="/contact">Contact</Link>
            <Link to="/shipping">Shipping and Returns</Link>
          </nav>
          <p>&copy; Wren &amp; Clover Botanicals</p>
        </div>
      </footer>
    </>
  );
}

export default Layout;
WREN_EOF

cat > src/pages/Home.tsx << 'WREN_EOF'
import { Link } from "react-router";
import ProductCard from "../components/ProductCard";
import { useProducts } from "../hooks/useProducts";

const featuredIds = ["lavender-oat-soap", "whipped-body-butter", "self-care-gift-box"];

function Home() {
  const { products } = useProducts();
  const featured = products.filter((product) => featuredIds.includes(product.id));

  return (
    <>
      <section className="hero">
        <div className="container hero-inner">
          <div>
            <h1>Small-batch organic soap and skincare</h1>
            <p>Handmade with simple ingredients you can pronounce.</p>
            <Link className="button" to="/shop">Shop now</Link>
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
            <Link className="button" to="/about">Read more</Link>
          </div>
        </div>
      </section>
    </>
  );
}

export default Home;
WREN_EOF

cat > src/pages/ProductPage.tsx << 'WREN_EOF'
import { Link, useParams } from "react-router";
import ProductCard from "../components/ProductCard";
import { useProducts } from "../hooks/useProducts";

function ProductPage() {
  const { id } = useParams();
  const { products, status } = useProducts();

  if (status === "loading") {
    return (
      <section className="section">
        <div className="container">
          <p>Loading product...</p>
        </div>
      </section>
    );
  }

  const product = products.find((item) => item.id === id);

  if (status === "error" || !product) {
    return (
      <section className="section">
        <div className="container">
          <h1 className="page-title">Product not found</h1>
          <Link className="button" to="/shop">Back to the shop</Link>
        </div>
      </section>
    );
  }

  const inStock = product.stock > 0;
  const related = products
    .filter((item) => item.category === product.category && item.id !== product.id)
    .slice(0, 3);

  return (
    <>
      <section className="section">
        <div className="container">
          <nav className="breadcrumb" aria-label="Breadcrumb">
            <Link to="/shop">Shop</Link> / {product.category} / {product.name}
          </nav>

          <div className="product-layout">
            <div className="photo product-photo">Large product photo</div>

            <div className="product-details">
              <h1>{product.name}</h1>
              <p className="product-price">${product.price}</p>
              <p>
                {product.description} {product.size}.
              </p>

              <form className="product-form">
                <div className="field">
                  <label htmlFor="scent">Scent</label>
                  <select id="scent" name="scent">
                    {product.scents.map((scent) => (
                      <option key={scent}>{scent}</option>
                    ))}
                  </select>
                </div>

                <div className="field">
                  <label htmlFor="quantity">Quantity</label>
                  <input id="quantity" name="quantity" type="number" min="1" defaultValue="1" />
                </div>

                <button className="button button-full" type="button" disabled={!inStock}>
                  {inStock ? "Add to cart" : "Out of stock"}
                </button>
              </form>
            </div>
          </div>
        </div>
      </section>

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
    </>
  );
}

export default ProductPage;
WREN_EOF

cat > src/pages/NotFound.tsx << 'WREN_EOF'
import { Link } from "react-router";

function NotFound() {
  return (
    <section className="section">
      <div className="container">
        <h1 className="page-title">Page not built yet</h1>
        <p>This page hasn't been added to the React version so far.</p>
        <Link className="button" to="/shop">Go to the shop</Link>
      </div>
    </section>
  );
}

export default NotFound;
WREN_EOF

cat > src/App.tsx << 'WREN_EOF'
import { Route, Routes } from "react-router";
import Layout from "./components/Layout";
import Home from "./pages/Home";
import NotFound from "./pages/NotFound";
import ProductPage from "./pages/ProductPage";
import Shop from "./pages/Shop";

function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route path="/" element={<Home />} />
        <Route path="/shop" element={<Shop />} />
        <Route path="/products/:id" element={<ProductPage />} />
        <Route path="*" element={<NotFound />} />
      </Route>
    </Routes>
  );
}

export default App;
WREN_EOF

cat > src/main.tsx << 'WREN_EOF'
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router";
import "./styles.css";
import App from "./App.tsx";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </StrictMode>
);
WREN_EOF

grep -q "product-size" src/styles.css || printf "
.product-size {
  margin: 0;
  font-size: 0.9rem;
  color: var(--color-muted);
}
" >> src/styles.css
echo
echo "Done. Start the app with: npm run dev"
