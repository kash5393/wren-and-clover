#!/usr/bin/env bash
# Unit 7, step 2: sign-in and sign-up pages for the React shop.
# Run from inside the shop-react folder:  bash unit7-login-pages.sh
set -e
if [ ! -f vite.config.ts ]; then echo "Run this inside the shop-react folder (vite.config.ts not found)."; exit 1; fi
mkdir -p src/context src/pages src/components

grep -q "interface User" src/types.ts || cat >> src/types.ts << 'WREN_EOF'

export interface User {
  id: number;
  email: string;
  name: string;
  role: "customer" | "owner";
}
WREN_EOF

cat > src/context/AuthContext.tsx << 'WREN_EOF'
import { createContext, useContext, useEffect, useState } from "react";
import type { ReactNode } from "react";
import type { User } from "../types";

interface AuthContextValue {
  user: User | null;
  loading: boolean;
  login: (email: string, password: string) => Promise<string | null>;
  signup: (name: string, email: string, password: string) => Promise<string | null>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

interface AuthResponse {
  user?: User;
  error?: string;
}

async function postJson(url: string, body: unknown): Promise<AuthResponse> {
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    return (await response.json()) as AuthResponse;
  } catch (error) {
    console.error(error);
    return { error: "Could not reach the shop. Please try again." };
  }
}

interface AuthProviderProps {
  children: ReactNode;
}

export function AuthProvider({ children }: AuthProviderProps) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    async function loadCurrentUser() {
      try {
        const response = await fetch("/api/auth/me");
        const data = (await response.json()) as AuthResponse;
        if (!cancelled) {
          setUser(response.ok && data.user ? data.user : null);
        }
      } catch (error) {
        console.error(error);
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    loadCurrentUser();

    return () => {
      cancelled = true;
    };
  }, []);

  async function login(email: string, password: string) {
    const data = await postJson("/api/auth/login", { email, password });
    if (data.user) {
      setUser(data.user);
      return null;
    }
    return data.error ?? "Could not sign in.";
  }

  async function signup(name: string, email: string, password: string) {
    const data = await postJson("/api/auth/signup", { name, email, password });
    if (data.user) {
      setUser(data.user);
      return null;
    }
    return data.error ?? "Could not create the account.";
  }

  async function logout() {
    try {
      await fetch("/api/auth/logout", { method: "POST" });
    } catch (error) {
      console.error(error);
    }
    setUser(null);
  }

  return (
    <AuthContext.Provider value={{ user, loading, login, signup, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components
export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error("useAuth must be used inside an AuthProvider");
  }
  return context;
}
WREN_EOF

cat > src/pages/Login.tsx << 'WREN_EOF'
import { useState } from "react";
import type { FormEvent } from "react";
import { Link, useNavigate } from "react-router";
import FormField from "../components/FormField";
import { useAuth } from "../context/AuthContext";

function Login() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    const problem = await login(email.trim(), password);
    setSubmitting(false);

    if (problem) {
      setError(problem);
      return;
    }
    navigate("/");
  }

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Sign in</h1>

        <form className="contact-form" noValidate onSubmit={handleSubmit}>
          <FormField id="email" label="Email" type="email" value={email} onChange={setEmail} />
          <FormField
            id="password"
            label="Password"
            type="password"
            value={password}
            onChange={setPassword}
          />
          {error && (
            <p className="field-error" role="alert">
              {error}
            </p>
          )}
          <button className="button button-full" type="submit" disabled={submitting}>
            {submitting ? "Signing in..." : "Sign in"}
          </button>
        </form>

        <p>
          New here? <Link to="/signup">Create an account</Link>
        </p>
      </div>
    </section>
  );
}

export default Login;
WREN_EOF

cat > src/pages/Signup.tsx << 'WREN_EOF'
import { useState } from "react";
import type { FormEvent } from "react";
import { Link, useNavigate } from "react-router";
import FormField from "../components/FormField";
import { useAuth } from "../context/AuthContext";

function Signup() {
  const { signup } = useAuth();
  const navigate = useNavigate();
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (password.length < 8) {
      setError("Password must be at least 8 characters.");
      return;
    }

    setSubmitting(true);
    const problem = await signup(name.trim(), email.trim(), password);
    setSubmitting(false);

    if (problem) {
      setError(problem);
      return;
    }
    navigate("/");
  }

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Create an account</h1>

        <form className="contact-form" noValidate onSubmit={handleSubmit}>
          <FormField id="name" label="Name" value={name} onChange={setName} />
          <FormField id="email" label="Email" type="email" value={email} onChange={setEmail} />
          <FormField
            id="password"
            label="Password (at least 8 characters)"
            type="password"
            value={password}
            onChange={setPassword}
          />
          {error && (
            <p className="field-error" role="alert">
              {error}
            </p>
          )}
          <button className="button button-full" type="submit" disabled={submitting}>
            {submitting ? "Creating account..." : "Create account"}
          </button>
        </form>

        <p>
          Already have an account? <Link to="/login">Sign in</Link>
        </p>
      </div>
    </section>
  );
}

export default Signup;
WREN_EOF

cat > src/components/Layout.tsx << 'WREN_EOF'
import { useState } from "react";
import { Link, Outlet } from "react-router";
import { useAuth } from "../context/AuthContext";
import { useCart } from "../context/CartContext";

function Layout() {
  const { count } = useCart();
  const { user, logout } = useAuth();
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
            {user ? (
              <button
                className="nav-button"
                type="button"
                onClick={() => {
                  closeMenu();
                  logout();
                }}
              >
                Log out ({user.name})
              </button>
            ) : (
              <Link to="/login" onClick={closeMenu}>Sign in</Link>
            )}
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

cat > src/App.tsx << 'WREN_EOF'
import { Route, Routes } from "react-router";
import Layout from "./components/Layout";
import About from "./pages/About";
import CartPage from "./pages/CartPage";
import Checkout from "./pages/Checkout";
import Contact from "./pages/Contact";
import Home from "./pages/Home";
import Login from "./pages/Login";
import NotFound from "./pages/NotFound";
import ProductPage from "./pages/ProductPage";
import Shipping from "./pages/Shipping";
import Shop from "./pages/Shop";
import Signup from "./pages/Signup";

function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route path="/" element={<Home />} />
        <Route path="/shop" element={<Shop />} />
        <Route path="/products/:id" element={<ProductPage />} />
        <Route path="/cart" element={<CartPage />} />
        <Route path="/checkout" element={<Checkout />} />
        <Route path="/about" element={<About />} />
        <Route path="/contact" element={<Contact />} />
        <Route path="/shipping" element={<Shipping />} />
        <Route path="/login" element={<Login />} />
        <Route path="/signup" element={<Signup />} />
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
import { AuthProvider } from "./context/AuthContext";
import { CartProvider } from "./context/CartContext";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <BrowserRouter>
      <AuthProvider>
        <CartProvider>
          <App />
        </CartProvider>
      </AuthProvider>
    </BrowserRouter>
  </StrictMode>
);
WREN_EOF

grep -q "nav-button" src/styles.css || cat >> src/styles.css << 'WREN_EOF'

/* Log out button in the navigation */
.nav-button {
  padding: 0.75rem 0;
  font: inherit;
  color: var(--color-text);
  text-align: left;
  background: none;
  border: none;
  border-top: 1px solid var(--color-border);
  cursor: pointer;
}

.nav-button:hover {
  color: var(--color-primary);
}

@media (min-width: 768px) {
  .nav-button {
    padding: 0.5rem 0;
    border-top: none;
  }
}
WREN_EOF

echo "Done. The dev server picks the changes up by itself."
