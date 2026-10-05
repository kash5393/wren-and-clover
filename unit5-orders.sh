#!/usr/bin/env bash
# Unit 5, step 2: orders endpoint, and the React shop connected to the API.
# Run from the wren-and-clover project folder:  bash unit5-orders.sh
set -e
if [ ! -d server/src ] || [ ! -d shop-react/src ]; then echo "Run this inside the wren-and-clover folder (server/ and shop-react/ not found)."; exit 1; fi

# --- API ---
(cd server && npm install zod)
cat > server/src/orders.ts << 'WREN_EOF'
import { z } from "zod";
import { loadProducts } from "./products.js";

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

type OrderInput = z.infer<typeof orderSchema>;

interface OrderLine {
  id: string;
  name: string;
  scent: string;
  quantity: number;
  unitPrice: number;
  lineTotal: number;
}

export interface Order {
  orderNumber: string;
  createdAt: string;
  customer: OrderInput["customer"];
  lines: OrderLine[];
  total: number;
}

type OrderResult =
  | { ok: true; order: Order }
  | { ok: false; status: number; error: string };

const orders: Order[] = [];
let nextOrderNumber = 1001;

export function listOrders(): Order[] {
  return orders;
}

export async function createOrder(body: unknown): Promise<OrderResult> {
  const parsed = orderSchema.safeParse(body);
  if (!parsed.success) {
    const firstIssue = parsed.error.issues[0];
    return {
      ok: false,
      status: 400,
      error: firstIssue ? firstIssue.message : "Invalid order",
    };
  }

  const { customer, items } = parsed.data;
  const products = await loadProducts();
  const lines: OrderLine[] = [];

  for (const item of items) {
    const product = products.find((candidate) => candidate.id === item.id);

    if (!product) {
      return { ok: false, status: 400, error: `Unknown product: ${item.id}` };
    }
    if (!product.scents.includes(item.scent)) {
      return {
        ok: false,
        status: 400,
        error: `${product.name} is not available in ${item.scent}`,
      };
    }
    if (product.stock < item.quantity) {
      return {
        ok: false,
        status: 409,
        error: `Only ${product.stock} of ${product.name} left in stock`,
      };
    }

    lines.push({
      id: product.id,
      name: product.name,
      scent: item.scent,
      quantity: item.quantity,
      unitPrice: product.price,
      lineTotal: product.price * item.quantity,
    });
  }

  const order: Order = {
    orderNumber: `WC-${nextOrderNumber}`,
    createdAt: new Date().toISOString(),
    customer,
    lines,
    total: lines.reduce((sum, line) => sum + line.lineTotal, 0),
  };

  nextOrderNumber += 1;
  orders.push(order);

  return { ok: true, order };
}
WREN_EOF

cat > server/src/index.ts << 'WREN_EOF'
import express from "express";
import type { NextFunction, Request, Response } from "express";
import { createOrder, listOrders } from "./orders.js";
import { loadProducts } from "./products.js";

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

# --- React shop ---
cat > shop-react/src/hooks/useProducts.ts << 'WREN_EOF'
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
        const response = await fetch("/api/products");
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

cat > shop-react/src/pages/Checkout.tsx << 'WREN_EOF'
import { useState } from "react";
import type { FormEvent } from "react";
import { Link } from "react-router";
import FormField from "../components/FormField";
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
  const [form, setForm] = useState<CheckoutForm>(emptyForm);
  const [errors, setErrors] = useState<CheckoutErrors>({});
  const [placedOrder, setPlacedOrder] = useState<PlacedOrder | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [serverError, setServerError] = useState("");

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

# Send the React dev server's /api requests on to the API (added once).
grep -q 'proxy' shop-react/vite.config.ts || perl -0pi -e 's|(plugins: \[[^\]]*\]),?|$1,\n  server: {\n    proxy: {\n      "/api": "http://localhost:4000",\n    },\n  },|' shop-react/vite.config.ts

echo
echo "Done. Restart both servers:"
echo "  Terminal 1:  cd server && npm run dev"
echo "  Terminal 2:  cd shop-react && npm run dev"
