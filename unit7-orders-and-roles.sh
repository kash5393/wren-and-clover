#!/usr/bin/env bash
# Unit 7, step 3: orders linked to accounts, My orders page, owner-only endpoints.
# Run from the wren-and-clover project folder:  bash unit7-orders-and-roles.sh
set -e
if [ ! -f server/src/auth.ts ] || [ ! -f shop-react/src/context/AuthContext.tsx ]; then echo "Run this inside the wren-and-clover folder, after the accounts and login pages steps."; exit 1; fi

# --- API ---
cat > server/src/auth.ts << 'WREN_EOF'
import { randomBytes } from "node:crypto";
import bcrypt from "bcryptjs";
import type { NextFunction, Request, Response } from "express";
import { z } from "zod";
import { pool } from "./db.js";

export const SESSION_COOKIE = "session";
const SESSION_DAYS = 7;
const SESSION_MS = SESSION_DAYS * 24 * 60 * 60 * 1000;

export interface User {
  id: number;
  email: string;
  name: string;
  role: "customer" | "owner";
}

interface UserRow extends User {
  password_hash: string;
}

type AuthResult =
  | { ok: true; user: User }
  | { ok: false; status: number; error: string };

const signupSchema = z.object({
  name: z.string().trim().min(1, "Name is required"),
  email: z.email("A valid email is required"),
  password: z.string().min(8, "Password must be at least 8 characters"),
});

const loginSchema = z.object({
  email: z.email("A valid email is required"),
  password: z.string().min(1, "Password is required"),
});

function toUser(row: UserRow): User {
  return { id: row.id, email: row.email, name: row.name, role: row.role };
}

export async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, 12);
}

export async function signUp(body: unknown): Promise<AuthResult> {
  const parsed = signupSchema.safeParse(body);
  if (!parsed.success) {
    return { ok: false, status: 400, error: parsed.error.issues[0]?.message ?? "Invalid details" };
  }

  const { name, password } = parsed.data;
  const email = parsed.data.email.toLowerCase();

  const existing = await pool.query("SELECT 1 FROM users WHERE email = $1", [email]);
  if (existing.rowCount && existing.rowCount > 0) {
    return { ok: false, status: 409, error: "An account with this email already exists" };
  }

  const result = await pool.query<UserRow>(
    `INSERT INTO users (email, name, password_hash)
     VALUES ($1, $2, $3)
     RETURNING id, email, name, role, password_hash`,
    [email, name, await hashPassword(password)]
  );

  return { ok: true, user: toUser(result.rows[0]!) };
}

export async function logIn(body: unknown): Promise<AuthResult> {
  const parsed = loginSchema.safeParse(body);
  const wrong: AuthResult = { ok: false, status: 401, error: "Email or password is incorrect" };
  if (!parsed.success) {
    return wrong;
  }

  const result = await pool.query<UserRow>(
    "SELECT id, email, name, role, password_hash FROM users WHERE email = $1",
    [parsed.data.email.toLowerCase()]
  );
  const row = result.rows[0];
  if (!row) {
    return wrong;
  }

  const matches = await bcrypt.compare(parsed.data.password, row.password_hash);
  return matches ? { ok: true, user: toUser(row) } : wrong;
}

export async function startSession(response: Response, userId: number): Promise<void> {
  const sessionId = randomBytes(32).toString("hex");
  const expiresAt = new Date(Date.now() + SESSION_MS);

  await pool.query("INSERT INTO sessions (id, user_id, expires_at) VALUES ($1, $2, $3)", [
    sessionId,
    userId,
    expiresAt,
  ]);

  response.cookie(SESSION_COOKIE, sessionId, {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    maxAge: SESSION_MS,
    path: "/",
  });
}

export async function endSession(request: Request, response: Response): Promise<void> {
  const sessionId: unknown = request.cookies?.[SESSION_COOKIE];
  if (typeof sessionId === "string") {
    await pool.query("DELETE FROM sessions WHERE id = $1", [sessionId]);
  }
  response.clearCookie(SESSION_COOKIE, { path: "/" });
}

export async function currentUser(request: Request): Promise<User | null> {
  const sessionId: unknown = request.cookies?.[SESSION_COOKIE];
  if (typeof sessionId !== "string") {
    return null;
  }

  const result = await pool.query<User>(
    `SELECT u.id, u.email, u.name, u.role
     FROM sessions s
     JOIN users u ON u.id = s.user_id
     WHERE s.id = $1 AND s.expires_at > now()`,
    [sessionId]
  );

  return result.rows[0] ?? null;
}

export async function requireUser(
  request: Request,
  response: Response,
  next: NextFunction
): Promise<void> {
  const user = await currentUser(request);

  if (!user) {
    response.status(401).json({ error: "Please sign in first" });
    return;
  }

  response.locals.user = user;
  next();
}

export async function requireOwner(
  request: Request,
  response: Response,
  next: NextFunction
): Promise<void> {
  const user = await currentUser(request);

  if (!user) {
    response.status(401).json({ error: "Please sign in first" });
    return;
  }
  if (user.role !== "owner") {
    response.status(403).json({ error: "Only the shop owner can do this" });
    return;
  }

  response.locals.user = user;
  next();
}
WREN_EOF

cat > server/src/orders.ts << 'WREN_EOF'
import { z } from "zod";
import { pool } from "./db.js";

const orderSchema = z.object({
  customer: z.object({
    name: z.string().trim().min(1, "Name is required"),
    email: z.email("A valid email is required"),
    phone: z.string().trim().min(7, "A valid phone number is required"),
    address: z.string().trim().min(1, "Street address is required"),
    city: z.string().trim().min(1, "City is required"),
    state: z.string().length(2, "State must be a two-letter code"),
    postcode: z.string().regex(/^\d{5}(-\d{4})?$/, "A valid ZIP code is required"),
  }),
  items: z
    .array(
      z.object({
        id: z.string(),
        scent: z.string(),
        quantity: z.number().int().min(1).max(99),
      })
    )
    .min(1, "The order has no items"),
});

interface OrderLine {
  productId: string;
  name: string;
  scent: string;
  quantity: number;
  unitPriceCents: number;
}

interface PlacedOrder {
  orderNumber: string;
  total: number;
}

type OrderResult =
  | { ok: true; order: PlacedOrder }
  | { ok: false; status: number; error: string };

interface StockRow {
  name: string;
  price_cents: number;
  scents: string[];
  stock: number;
}

export async function createOrder(
  body: unknown,
  userId: number | null
): Promise<OrderResult> {
  const parsed = orderSchema.safeParse(body);
  if (!parsed.success) {
    return { ok: false, status: 400, error: parsed.error.issues[0]?.message ?? "Invalid order" };
  }

  const { customer, items } = parsed.data;
  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    const lines: OrderLine[] = [];

    for (const item of items) {
      const found = await client.query<StockRow>(
        "SELECT name, price_cents, scents, stock FROM products WHERE id = $1 FOR UPDATE",
        [item.id]
      );
      const product = found.rows[0];

      let problem: { status: number; error: string } | null = null;
      if (!product) {
        problem = { status: 400, error: `Unknown product: ${item.id}` };
      } else if (!product.scents.includes(item.scent)) {
        problem = { status: 400, error: `${product.name} is not available in ${item.scent}` };
      } else if (product.stock < item.quantity) {
        problem = {
          status: 409,
          error: `Only ${product.stock} of ${product.name} left in stock`,
        };
      }

      if (problem || !product) {
        await client.query("ROLLBACK");
        return { ok: false, ...(problem ?? { status: 400, error: "Invalid order" }) };
      }

      await client.query("UPDATE products SET stock = stock - $1 WHERE id = $2", [
        item.quantity,
        item.id,
      ]);

      lines.push({
        productId: item.id,
        name: product.name,
        scent: item.scent,
        quantity: item.quantity,
        unitPriceCents: product.price_cents,
      });
    }

    const totalCents = lines.reduce(
      (sum, line) => sum + line.unitPriceCents * line.quantity,
      0
    );

    const inserted = await client.query<{ id: number; order_number: string }>(
      `INSERT INTO orders (user_id, customer_name, email, phone, address, city, state, postcode, total_cents)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING id, order_number`,
      [
        userId,
        customer.name,
        customer.email,
        customer.phone,
        customer.address,
        customer.city,
        customer.state,
        customer.postcode,
        totalCents,
      ]
    );
    const order = inserted.rows[0]!;

    for (const line of lines) {
      await client.query(
        `INSERT INTO order_items (order_id, product_id, product_name, scent, quantity, unit_price_cents)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [order.id, line.productId, line.name, line.scent, line.quantity, line.unitPriceCents]
      );
    }

    await client.query("COMMIT");

    return { ok: true, order: { orderNumber: order.order_number, total: totalCents / 100 } };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

async function queryOrders(userId: number | null): Promise<unknown[]> {
  const result = await pool.query(
    `SELECT
       o.order_number AS "orderNumber",
       o.created_at AS "createdAt",
       o.customer_name AS "customerName",
       o.email,
       o.city,
       o.state,
       o.user_id IS NULL AS "guest",
       o.total_cents / 100.0 AS total,
       json_agg(
         json_build_object(
           'name', i.product_name,
           'scent', i.scent,
           'quantity', i.quantity,
           'unitPrice', i.unit_price_cents / 100.0
         )
         ORDER BY i.id
       ) AS lines
     FROM orders o
     JOIN order_items i ON i.order_id = o.id
     WHERE $1::integer IS NULL OR o.user_id = $1
     GROUP BY o.id
     ORDER BY o.id DESC`,
    [userId]
  );

  return result.rows.map((row) => ({ ...row, total: Number(row.total) }));
}

export function listAllOrders(): Promise<unknown[]> {
  return queryOrders(null);
}

export function listOrdersForUser(userId: number): Promise<unknown[]> {
  return queryOrders(userId);
}
WREN_EOF

cat > server/src/index.ts << 'WREN_EOF'
import cookieParser from "cookie-parser";
import express from "express";
import type { NextFunction, Request, Response } from "express";
import { authRouter } from "./auth-routes.js";
import { currentUser, requireOwner, requireUser } from "./auth.js";
import type { User } from "./auth.js";
import { createOrder, listAllOrders, listOrdersForUser } from "./orders.js";
import {
  createProduct,
  deleteProduct,
  getProduct,
  listCategories,
  loadProducts,
  updateProduct,
} from "./products.js";

const app = express();
const port = Number(process.env.PORT) || 4000;

app.use(express.json());
app.use(cookieParser());

app.use("/api/auth", authRouter);

app.get("/api/health", (_request, response) => {
  response.json({ status: "ok" });
});

app.get("/api/products", async (request, response) => {
  const { category, search, inStock } = request.query;

  const products = await loadProducts({
    category: typeof category === "string" ? category : undefined,
    search: typeof search === "string" ? search.trim() : undefined,
    inStock: inStock === "true",
  });

  response.json(products);
});

app.get("/api/products/:id", async (request, response) => {
  const product = await getProduct(request.params.id);

  if (!product) {
    response.status(404).json({ error: "Product not found" });
    return;
  }

  response.json(product);
});

app.post("/api/products", requireOwner, async (request, response) => {
  const result = await createProduct(request.body);

  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  response.status(201).json(result.product);
});

app.patch("/api/products/:id", requireOwner, async (request, response) => {
  const result = await updateProduct(String(request.params.id), request.body);

  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  response.json(result.product);
});

app.delete("/api/products/:id", requireOwner, async (request, response) => {
  const outcome = await deleteProduct(String(request.params.id));

  if (outcome === "not-found") {
    response.status(404).json({ error: "Product not found" });
    return;
  }
  if (outcome === "in-use") {
    response
      .status(409)
      .json({ error: "This product appears in past orders, so it cannot be deleted" });
    return;
  }

  response.status(204).end();
});

app.get("/api/categories", async (_request, response) => {
  response.json(await listCategories());
});

app.post("/api/orders", async (request, response) => {
  const user = await currentUser(request);
  const result = await createOrder(request.body, user ? user.id : null);

  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  console.log(`New order ${result.order.orderNumber}: $${result.order.total}`);
  response.status(201).json(result.order);
});

app.get("/api/orders/mine", requireUser, async (_request, response) => {
  const user = response.locals.user as User;
  response.json(await listOrdersForUser(user.id));
});

app.get("/api/orders", requireOwner, async (_request, response) => {
  response.json(await listAllOrders());
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

# --- React shop ---
cat > shop-react/src/pages/MyOrders.tsx << 'WREN_EOF'
import { useEffect, useState } from "react";
import { Link } from "react-router";
import { useAuth } from "../context/AuthContext";

interface OrderLine {
  name: string;
  scent: string;
  quantity: number;
  unitPrice: number;
}

interface OrderSummary {
  orderNumber: string;
  createdAt: string;
  total: number;
  lines: OrderLine[];
}

type Status = "loading" | "ready" | "error";

function MyOrders() {
  const { user, loading: authLoading } = useAuth();
  const [orders, setOrders] = useState<OrderSummary[]>([]);
  const [status, setStatus] = useState<Status>("loading");

  useEffect(() => {
    if (!user) {
      return;
    }

    let cancelled = false;

    async function loadOrders() {
      try {
        const response = await fetch("/api/orders/mine");
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`);
        }
        const data = (await response.json()) as OrderSummary[];
        if (!cancelled) {
          setOrders(data);
          setStatus("ready");
        }
      } catch (error) {
        console.error(error);
        if (!cancelled) {
          setStatus("error");
        }
      }
    }

    loadOrders();

    return () => {
      cancelled = true;
    };
  }, [user]);

  if (authLoading) {
    return (
      <section className="section">
        <div className="container">
          <p>Loading...</p>
        </div>
      </section>
    );
  }

  if (!user) {
    return (
      <section className="section">
        <div className="container">
          <h1 className="page-title">My orders</h1>
          <p>Sign in to see the orders placed with your account.</p>
          <Link className="button" to="/login?next=/orders">Sign in</Link>
        </div>
      </section>
    );
  }

  return (
    <section className="section">
      <div className="container">
        <h1 className="page-title">My orders</h1>

        {status === "loading" && <p>Loading your orders...</p>}
        {status === "error" && <p>Sorry, your orders could not be loaded.</p>}

        {status === "ready" && orders.length === 0 && (
          <>
            <p>You haven't placed any orders with this account yet.</p>
            <Link className="button" to="/shop">Browse the shop</Link>
          </>
        )}

        {status === "ready" && orders.length > 0 && (
          <div className="order-list">
            {orders.map((order) => (
              <article className="order-card" key={order.orderNumber}>
                <header className="order-card-header">
                  <h2>{order.orderNumber}</h2>
                  <p>{new Date(order.createdAt).toLocaleDateString()}</p>
                </header>
                <ul>
                  {order.lines.map((line) => (
                    <li key={`${line.name}-${line.scent}`}>
                      <span>
                        {line.quantity} x {line.name} ({line.scent})
                      </span>
                      <span>${line.unitPrice * line.quantity}</span>
                    </li>
                  ))}
                </ul>
                <p className="order-summary-total">
                  <span>Total</span>
                  <strong>${order.total}</strong>
                </p>
              </article>
            ))}
          </div>
        )}
      </div>
    </section>
  );
}

export default MyOrders;
WREN_EOF

cat > shop-react/src/components/Layout.tsx << 'WREN_EOF'
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
            {user && <Link to="/orders" onClick={closeMenu}>My orders</Link>}
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

cat > shop-react/src/App.tsx << 'WREN_EOF'
import { Route, Routes } from "react-router";
import Layout from "./components/Layout";
import About from "./pages/About";
import CartPage from "./pages/CartPage";
import Checkout from "./pages/Checkout";
import Contact from "./pages/Contact";
import Home from "./pages/Home";
import Login from "./pages/Login";
import MyOrders from "./pages/MyOrders";
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
        <Route path="/orders" element={<MyOrders />} />
        <Route path="/login" element={<Login />} />
        <Route path="/signup" element={<Signup />} />
        <Route path="*" element={<NotFound />} />
      </Route>
    </Routes>
  );
}

export default App;
WREN_EOF

grep -q "order-card" shop-react/src/styles.css || cat >> shop-react/src/styles.css << 'WREN_EOF'

/* My orders */
.order-list {
  display: grid;
  gap: var(--space-3);
  max-width: 720px;
}

.order-card {
  display: grid;
  gap: var(--space-2);
  padding: var(--space-3);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius);
}

.order-card-header {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  justify-content: space-between;
  gap: var(--space-1);
}

.order-card-header h2,
.order-card-header p {
  margin: 0;
}

.order-card-header p {
  color: var(--color-muted);
}

.order-card ul {
  display: grid;
  gap: var(--space-1);
  margin: 0;
  padding: 0;
  list-style: none;
}

.order-card li {
  display: flex;
  justify-content: space-between;
  gap: var(--space-2);
}
WREN_EOF

echo
echo "Done. The API and the React app pick the changes up by themselves."
