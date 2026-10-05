#!/usr/bin/env bash
# Unit 7: remember a signed-in customer's shipping details and fill them in at checkout.
# Run from the wren-and-clover project folder:  bash unit7-saved-details.sh
set -e
if ! grep -q "requireOwner" server/src/index.ts 2>/dev/null; then echo "Run this inside the wren-and-clover folder, after the orders-and-roles step."; exit 1; fi
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

export interface ShippingDetails {
  name: string;
  email: string;
  phone: string;
  address: string;
  city: string;
  state: string;
  postcode: string;
}

export async function getSavedShipping(userId: number): Promise<ShippingDetails | null> {
  const result = await pool.query<ShippingDetails>(
    `SELECT customer_name AS name, email, phone, address, city, state, postcode
     FROM orders
     WHERE user_id = $1
     ORDER BY id DESC
     LIMIT 1`,
    [userId]
  );

  return result.rows[0] ?? null;
}
WREN_EOF

cat > server/src/index.ts << 'WREN_EOF'
import cookieParser from "cookie-parser";
import express from "express";
import type { NextFunction, Request, Response } from "express";
import { authRouter } from "./auth-routes.js";
import { currentUser, requireOwner, requireUser } from "./auth.js";
import type { User } from "./auth.js";
import { createOrder, getSavedShipping, listAllOrders, listOrdersForUser } from "./orders.js";
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

app.get("/api/account/shipping", requireUser, async (_request, response) => {
  const user = response.locals.user as User;
  response.json({ shipping: await getSavedShipping(user.id) });
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
cat > shop-react/src/pages/Checkout.tsx << 'WREN_EOF'
import { useEffect, useState } from "react";
import type { FormEvent } from "react";
import { Link } from "react-router";
import FormField from "../components/FormField";
import { useAuth } from "../context/AuthContext";
import { useCart } from "../context/CartContext";

interface CheckoutForm {
  name: string;
  email: string;
  phone: string;
  address: string;
  city: string;
  state: string;
  postcode: string;
}

type CheckoutErrors = Partial<Record<keyof CheckoutForm, string>>;

interface PlacedOrder {
  orderNumber: string;
  total: number;
}

const emptyForm: CheckoutForm = {
  name: "",
  email: "",
  phone: "",
  address: "",
  city: "",
  state: "",
  postcode: "",
};

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const phonePattern = /^[0-9+()\-\s]{7,}$/;
const zipPattern = /^\d{5}(-\d{4})?$/;

const usStates = [
  "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL",
  "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME",
  "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH",
  "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI",
  "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI",
  "WY",
];

function validate(form: CheckoutForm): CheckoutErrors {
  const errors: CheckoutErrors = {};

  if (form.name.trim() === "") {
    errors.name = "Please enter your name.";
  }
  if (!emailPattern.test(form.email.trim())) {
    errors.email = "Please enter a valid email address.";
  }
  if (!phonePattern.test(form.phone.trim())) {
    errors.phone = "Please enter a valid phone number.";
  }
  if (form.address.trim() === "") {
    errors.address = "Please enter your street address.";
  }
  if (form.city.trim() === "") {
    errors.city = "Please enter your city.";
  }
  if (!usStates.includes(form.state)) {
    errors.state = "Please choose your state.";
  }
  if (!zipPattern.test(form.postcode.trim())) {
    errors.postcode = "Please enter a valid ZIP code.";
  }

  return errors;
}

function Checkout() {
  const { items, total, clearCart } = useCart();
  const { user } = useAuth();
  const [form, setForm] = useState<CheckoutForm>({
    ...emptyForm,
    name: user?.name ?? "",
    email: user?.email ?? "",
  });
  const [errors, setErrors] = useState<CheckoutErrors>({});
  const [usedSavedDetails, setUsedSavedDetails] = useState(false);
  const [placedOrder, setPlacedOrder] = useState<PlacedOrder | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [serverError, setServerError] = useState("");

  useEffect(() => {
    if (!user) {
      return;
    }

    const account = user;
    let cancelled = false;

    async function loadSavedDetails() {
      try {
        const response = await fetch("/api/account/shipping");
        if (!response.ok) {
          return;
        }
        const data = (await response.json()) as { shipping: Partial<CheckoutForm> | null };
        if (cancelled) {
          return;
        }

        const saved = data.shipping ?? {};
        setForm((current) => ({
          name: current.name || saved.name || account.name,
          email: current.email || saved.email || account.email,
          phone: current.phone || saved.phone || "",
          address: current.address || saved.address || "",
          city: current.city || saved.city || "",
          state: current.state || saved.state || "",
          postcode: current.postcode || saved.postcode || "",
        }));
        setUsedSavedDetails(data.shipping !== null);
      } catch (error) {
        console.error(error);
      }
    }

    loadSavedDetails();

    return () => {
      cancelled = true;
    };
  }, [user]);

  function updateField(field: keyof CheckoutForm, value: string) {
    setForm((current) => ({ ...current, [field]: value }));
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const foundErrors = validate(form);
    setErrors(foundErrors);
    if (Object.keys(foundErrors).length > 0) {
      return;
    }

    setSubmitting(true);
    setServerError("");

    try {
      const response = await fetch("/api/orders", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          customer: form,
          items: items.map((item) => ({
            id: item.id,
            scent: item.scent,
            quantity: item.quantity,
          })),
        }),
      });

      if (!response.ok) {
        const problem = (await response.json()) as { error?: string };
        setServerError(problem.error ?? "The order could not be placed.");
        return;
      }

      setPlacedOrder((await response.json()) as PlacedOrder);
      clearCart();
    } catch (error) {
      console.error(error);
      setServerError("Could not reach the shop. Please try again.");
    } finally {
      setSubmitting(false);
    }
  }

  if (placedOrder) {
    return (
      <section className="section">
        <div className="container prose">
          <h1 className="page-title">Thank you, {form.name.trim()}</h1>
          <p>
            Your order <strong>{placedOrder.orderNumber}</strong> for{" "}
            <strong>${placedOrder.total}</strong> has been received. A
            confirmation will be sent to {form.email.trim()}.
          </p>
          <p>
            This is a practice checkout: no payment was taken and nothing will
            be shipped.
          </p>
          {!user && (
            <p>
              Want to see your orders in one place next time?{" "}
              <Link to="/signup">Create an account</Link>. It's optional.
            </p>
          )}
          <Link className="button" to="/shop">Back to the shop</Link>
        </div>
      </section>
    );
  }

  if (items.length === 0) {
    return (
      <section className="section">
        <div className="container">
          <h1 className="page-title">Checkout</h1>
          <p>Your cart is empty, so there is nothing to check out.</p>
          <Link className="button" to="/shop">Browse the shop</Link>
        </div>
      </section>
    );
  }

  return (
    <section className="section">
      <div className="container">
        <h1 className="page-title">Checkout</h1>

        {user ? (
          <p className="checkout-notice">
            Signed in as <strong>{user.name}</strong> ({user.email}).{" "}
            {usedSavedDetails
              ? "We've filled in the details from your last order. Check them before you place this one."
              : "Your details will be remembered after your first order."}
          </p>
        ) : (
          <p className="checkout-notice">
            You're checking out as a guest, with no account needed. Have an
            account? <Link to="/login?next=/checkout">Sign in</Link> to fill in
            your details.
          </p>
        )}

        <div className="checkout-layout">
          <form className="contact-form" noValidate onSubmit={handleSubmit}>
            <h2>Shipping details</h2>
            <FormField
              id="name"
              label="Full name"
              value={form.name}
              error={errors.name}
              onChange={(value) => updateField("name", value)}
            />
            <FormField
              id="email"
              label="Email"
              type="email"
              value={form.email}
              error={errors.email}
              onChange={(value) => updateField("email", value)}
            />
            <FormField
              id="phone"
              label="Phone"
              type="tel"
              value={form.phone}
              error={errors.phone}
              onChange={(value) => updateField("phone", value)}
            />
            <FormField
              id="address"
              label="Street address"
              value={form.address}
              error={errors.address}
              onChange={(value) => updateField("address", value)}
            />
            <FormField
              id="city"
              label="City"
              value={form.city}
              error={errors.city}
              onChange={(value) => updateField("city", value)}
            />
            <FormField
              id="state"
              label="State"
              options={usStates}
              value={form.state}
              error={errors.state}
              onChange={(value) => updateField("state", value)}
            />
            <FormField
              id="postcode"
              label="ZIP code"
              value={form.postcode}
              error={errors.postcode}
              onChange={(value) => updateField("postcode", value)}
            />
            {serverError && (
              <p className="field-error" role="alert">
                {serverError}
              </p>
            )}
            <button className="button button-full" type="submit" disabled={submitting}>
              {submitting ? "Placing order..." : "Place order"}
            </button>
          </form>

          <aside className="order-summary">
            <h2>Order summary</h2>
            <ul>
              {items.map((item) => (
                <li key={`${item.id}-${item.scent}`}>
                  <span>
                    {item.quantity} x {item.name} ({item.scent})
                  </span>
                  <span>${item.price * item.quantity}</span>
                </li>
              ))}
            </ul>
            <p className="order-summary-total">
              <span>Total</span>
              <strong>${total}</strong>
            </p>
            <Link to="/cart">Edit cart</Link>
          </aside>
        </div>
      </div>
    </section>
  );
}

export default Checkout;
WREN_EOF
echo
echo "Done. The API and the React app pick the changes up by themselves."
