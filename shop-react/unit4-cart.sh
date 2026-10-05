#!/usr/bin/env bash
# Unit 4: shared cart (context), add-to-cart form and cart page for the React shop.
# Run from inside the shop-react folder:  bash unit4-cart.sh
set -e
if [ ! -f vite.config.ts ]; then echo "Run this inside the shop-react folder (vite.config.ts not found)."; exit 1; fi
mkdir -p src/components src/pages src/context

cat > src/context/CartContext.tsx << 'WREN_EOF'
import { createContext, useContext, useEffect, useState } from "react";
import type { ReactNode } from "react";
import type { CartItem, Product } from "../types";

const CART_KEY = "wren-clover-cart";

interface CartContextValue {
  items: CartItem[];
  count: number;
  total: number;
  addItem: (product: Product, scent: string, quantity: number) => void;
  updateQuantity: (index: number, quantity: number) => void;
  removeItem: (index: number) => void;
}

const CartContext = createContext<CartContextValue | null>(null);

function loadCart(): CartItem[] {
  try {
    const saved = localStorage.getItem(CART_KEY);
    return saved ? (JSON.parse(saved) as CartItem[]) : [];
  } catch {
    return [];
  }
}

interface CartProviderProps {
  children: ReactNode;
}

export function CartProvider({ children }: CartProviderProps) {
  const [items, setItems] = useState<CartItem[]>(loadCart);

  useEffect(() => {
    localStorage.setItem(CART_KEY, JSON.stringify(items));
  }, [items]);

  function addItem(product: Product, scent: string, quantity: number) {
    setItems((current) => {
      const exists = current.some(
        (item) => item.id === product.id && item.scent === scent
      );

      if (exists) {
        return current.map((item) =>
          item.id === product.id && item.scent === scent
            ? { ...item, quantity: item.quantity + quantity }
            : item
        );
      }

      return [
        ...current,
        {
          id: product.id,
          name: product.name,
          price: product.price,
          scent: scent,
          quantity: quantity,
        },
      ];
    });
  }

  function updateQuantity(index: number, quantity: number) {
    setItems((current) =>
      current.map((item, itemIndex) =>
        itemIndex === index ? { ...item, quantity: Math.max(1, quantity) } : item
      )
    );
  }

  function removeItem(index: number) {
    setItems((current) => current.filter((_, itemIndex) => itemIndex !== index));
  }

  const count = items.reduce((sum, item) => sum + item.quantity, 0);
  const total = items.reduce((sum, item) => sum + item.price * item.quantity, 0);

  return (
    <CartContext.Provider
      value={{ items, count, total, addItem, updateQuantity, removeItem }}
    >
      {children}
    </CartContext.Provider>
  );
}

export function useCart() {
  const context = useContext(CartContext);
  if (!context) {
    throw new Error("useCart must be used inside a CartProvider");
  }
  return context;
}
WREN_EOF

cat > src/components/AddToCartForm.tsx << 'WREN_EOF'
import { useState } from "react";
import { useCart } from "../context/CartContext";
import type { Product } from "../types";

interface AddToCartFormProps {
  product: Product;
}

function AddToCartForm({ product }: AddToCartFormProps) {
  const { addItem } = useCart();
  const [scent, setScent] = useState(product.scents[0] ?? "");
  const [quantity, setQuantity] = useState(1);
  const [justAdded, setJustAdded] = useState(false);

  const inStock = product.stock > 0;

  function handleAdd() {
    addItem(product, scent, quantity);
    setJustAdded(true);
    setTimeout(() => setJustAdded(false), 1500);
  }

  let buttonText = "Add to cart";
  if (!inStock) {
    buttonText = "Out of stock";
  } else if (justAdded) {
    buttonText = "Added to cart";
  }

  return (
    <form className="product-form">
      <div className="field">
        <label htmlFor="scent">Scent</label>
        <select
          id="scent"
          name="scent"
          value={scent}
          onChange={(event) => setScent(event.target.value)}
        >
          {product.scents.map((option) => (
            <option key={option}>{option}</option>
          ))}
        </select>
      </div>

      <div className="field">
        <label htmlFor="quantity">Quantity</label>
        <input
          id="quantity"
          name="quantity"
          type="number"
          min="1"
          value={quantity}
          onChange={(event) => setQuantity(Math.max(1, Number(event.target.value) || 1))}
        />
      </div>

      <button
        className="button button-full"
        type="button"
        disabled={!inStock}
        onClick={handleAdd}
      >
        {buttonText}
      </button>
    </form>
  );
}

export default AddToCartForm;
WREN_EOF

cat > src/components/Layout.tsx << 'WREN_EOF'
import { useState } from "react";
import { Link, Outlet } from "react-router";
import { useCart } from "../context/CartContext";

function Layout() {
  const { count } = useCart();
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
            Cart ({count})
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

cat > src/pages/ProductPage.tsx << 'WREN_EOF'
import { Link, useParams } from "react-router";
import AddToCartForm from "../components/AddToCartForm";
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

              <AddToCartForm key={product.id} product={product} />
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

cat > src/pages/CartPage.tsx << 'WREN_EOF'
import { Link } from "react-router";
import { useCart } from "../context/CartContext";

function CartPage() {
  const { items, total, updateQuantity, removeItem } = useCart();

  if (items.length === 0) {
    return (
      <section className="section">
        <div className="container">
          <h1 className="page-title">Your cart</h1>
          <p>Your cart is empty.</p>
          <Link className="button" to="/shop">Browse the shop</Link>
        </div>
      </section>
    );
  }

  return (
    <section className="section">
      <div className="container">
        <h1 className="page-title">Your cart</h1>

        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Product</th>
                <th>Price</th>
                <th>Quantity</th>
                <th>Total</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              {items.map((item, index) => (
                <tr key={`${item.id}-${item.scent}`}>
                  <td>
                    <Link to={`/products/${item.id}`}>{item.name}</Link>
                    <br />
                    <span className="cart-scent">{item.scent}</span>
                  </td>
                  <td>${item.price}</td>
                  <td>
                    <input
                      className="cart-qty"
                      type="number"
                      min="1"
                      value={item.quantity}
                      aria-label={`Quantity for ${item.name}`}
                      onChange={(event) =>
                        updateQuantity(index, Number(event.target.value) || 1)
                      }
                    />
                  </td>
                  <td>${item.price * item.quantity}</td>
                  <td>
                    <button
                      className="link-button"
                      type="button"
                      onClick={() => removeItem(index)}
                    >
                      Remove
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <p className="cart-total">
          Order total: <strong>${total}</strong>
        </p>
        <Link className="button" to="/shop">Continue shopping</Link>
      </div>
    </section>
  );
}

export default CartPage;
WREN_EOF

cat > src/App.tsx << 'WREN_EOF'
import { Route, Routes } from "react-router";
import Layout from "./components/Layout";
import CartPage from "./pages/CartPage";
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
        <Route path="/cart" element={<CartPage />} />
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
import { CartProvider } from "./context/CartContext";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <BrowserRouter>
      <CartProvider>
        <App />
      </CartProvider>
    </BrowserRouter>
  </StrictMode>
);
WREN_EOF

echo "Done. The dev server picks the changes up by itself."
