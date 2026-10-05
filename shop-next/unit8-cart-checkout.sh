#!/usr/bin/env bash
# Unit 8, step 2: About, Shipping, Contact, cart and checkout in the Next.js shop.
# Run from inside the shop-next folder:  bash unit8-cart-checkout.sh
set -e
if [ ! -f src/lib/products.ts ]; then echo "Run this inside the shop-next folder, after step 1 (src/lib/products.ts not found)."; exit 1; fi
npm install zod
mkdir -p src/app/about src/app/shipping src/app/contact src/app/cart src/app/checkout

cat > "src/components/FormField.tsx" << 'WREN_EOF'
interface FormFieldProps {
  id: string;
  label: string;
  value: string;
  onChange: (value: string) => void;
  error?: string;
  type?: string;
  multiline?: boolean;
  options?: string[];
  autoComplete?: string;
}

export default function FormField({
  id,
  label,
  value,
  onChange,
  error,
  type = "text",
  multiline = false,
  options,
  autoComplete,
}: FormFieldProps) {
  const invalid = error ? true : undefined;
  let control;

  if (options) {
    control = (
      <select
        id={id}
        name={id}
        value={value}
        aria-invalid={invalid}
        autoComplete={autoComplete}
        onChange={(event) => onChange(event.target.value)}
      >
        <option value="">Select...</option>
        {options.map((option) => (
          <option key={option} value={option}>
            {option}
          </option>
        ))}
      </select>
    );
  } else if (multiline) {
    control = (
      <textarea
        id={id}
        name={id}
        rows={6}
        value={value}
        aria-invalid={invalid}
        autoComplete={autoComplete}
        onChange={(event) => onChange(event.target.value)}
      />
    );
  } else {
    control = (
      <input
        id={id}
        name={id}
        type={type}
        value={value}
        aria-invalid={invalid}
        autoComplete={autoComplete}
        onChange={(event) => onChange(event.target.value)}
      />
    );
  }

  return (
    <div className="field">
      <label htmlFor={id}>{label}</label>
      {control}
      {error && <span className="field-error">{error}</span>}
    </div>
  );
}
WREN_EOF

cat > "src/components/CartProvider.tsx" << 'WREN_EOF'
"use client";

import { createContext, useContext, useEffect, useState } from "react";
import type { ReactNode } from "react";
import type { CartItem, Product } from "@/lib/types";

const CART_KEY = "wren-clover-cart";

interface CartContextValue {
  items: CartItem[];
  count: number;
  total: number;
  ready: boolean;
  addItem: (product: Product, scent: string, quantity: number) => void;
  updateQuantity: (index: number, quantity: number) => void;
  removeItem: (index: number) => void;
  clearCart: () => void;
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
  const [items, setItems] = useState<CartItem[]>([]);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const frame = requestAnimationFrame(() => {
      setItems(loadCart());
      setReady(true);
    });
    return () => cancelAnimationFrame(frame);
  }, []);

  useEffect(() => {
    if (ready) {
      localStorage.setItem(CART_KEY, JSON.stringify(items));
    }
  }, [items, ready]);

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

  function clearCart() {
    setItems([]);
  }

  const count = items.reduce((sum, item) => sum + item.quantity, 0);
  const total = items.reduce((sum, item) => sum + item.price * item.quantity, 0);

  return (
    <CartContext.Provider
      value={{ items, count, total, ready, addItem, updateQuantity, removeItem, clearCart }}
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

cat > "src/components/AddToCartForm.tsx" << 'WREN_EOF'
"use client";

import { useState } from "react";
import { useCart } from "@/components/CartProvider";
import type { Product } from "@/lib/types";

interface AddToCartFormProps {
  product: Product;
}

export default function AddToCartForm({ product }: AddToCartFormProps) {
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
        <select id="scent" value={scent} onChange={(event) => setScent(event.target.value)}>
          {product.scents.map((option) => (
            <option key={option}>{option}</option>
          ))}
        </select>
      </div>

      <div className="field">
        <label htmlFor="quantity">Quantity</label>
        <input
          id="quantity"
          type="number"
          min="1"
          value={quantity}
          onChange={(event) => setQuantity(Math.max(1, Number(event.target.value) || 1))}
        />
      </div>

      <button className="button button-full" type="button" disabled={!inStock} onClick={handleAdd}>
        {buttonText}
      </button>
    </form>
  );
}
WREN_EOF

cat > "src/components/Header.tsx" << 'WREN_EOF'
"use client";

import Link from "next/link";
import { useState } from "react";
import { useCart } from "@/components/CartProvider";

export default function Header() {
  const { count } = useCart();
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
          Cart ({count})
        </Link>
      </div>
    </header>
  );
}
WREN_EOF

cat > "src/app/layout.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import type { ReactNode } from "react";
import { CartProvider } from "@/components/CartProvider";
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
        <CartProvider>
          <Header />
          <main>{children}</main>
          <Footer />
        </CartProvider>
      </body>
    </html>
  );
}
WREN_EOF

cat > "src/app/products/[id]/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import AddToCartForm from "@/components/AddToCartForm";
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

cat > "src/app/cart/page.tsx" << 'WREN_EOF'
"use client";

import Link from "next/link";
import { useCart } from "@/components/CartProvider";

export default function CartPage() {
  const { items, total, ready, updateQuantity, removeItem, clearCart } = useCart();

  if (!ready) {
    return (
      <section className="section">
        <div className="container">
          <h1 className="page-title">Your cart</h1>
          <p>Loading your cart...</p>
        </div>
      </section>
    );
  }

  if (items.length === 0) {
    return (
      <section className="section">
        <div className="container">
          <h1 className="page-title">Your cart</h1>
          <p>Your cart is empty.</p>
          <Link className="button" href="/shop">Browse the shop</Link>
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
                    <Link href={`/products/${item.id}`}>{item.name}</Link>
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
                      onChange={(event) => updateQuantity(index, Number(event.target.value) || 1)}
                    />
                  </td>
                  <td>${item.price * item.quantity}</td>
                  <td>
                    <button className="link-button" type="button" onClick={() => removeItem(index)}>
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
        <div className="cart-actions">
          <Link className="button" href="/checkout">Checkout</Link>
          <Link href="/shop">Continue shopping</Link>
          <button className="link-button" type="button" onClick={clearCart}>
            Clear cart
          </button>
        </div>
      </div>
    </section>
  );
}
WREN_EOF

cat > "src/app/about/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "About",
};

export default function AboutPage() {
  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">About</h1>
        <div className="photo">Photo of the maker at work</div>
        <h2>How it started</h2>
        <p>
          Wren &amp; Clover began at a kitchen table, with a batch of lavender
          soap made for a family member with sensitive skin. Friends asked for
          more, and a market stall followed.
        </p>
        <h2>How it&apos;s made</h2>
        <p>
          Every product is made by hand in small batches, using organic oils,
          butters and botanicals. Nothing has synthetic fragrance or colouring.
        </p>
        <h2>Find us in person</h2>
        <p>We&apos;re at the farmers&apos; market most Saturdays. Come and say hello.</p>
        <Link className="button" href="/shop">Browse the shop</Link>
      </div>
    </section>
  );
}
WREN_EOF

cat > "src/app/shipping/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Shipping and Returns",
};

const shippingOptions = [
  { method: "Standard", time: "3 to 5 working days", cost: "$5" },
  { method: "Express", time: "1 to 2 working days", cost: "$12" },
  { method: "Market pickup", time: "Next Saturday", cost: "Free" },
];

export default function ShippingPage() {
  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Shipping and Returns</h1>

        <h2>Shipping</h2>
        <p>Orders are packed within two working days.</p>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Method</th>
                <th>Delivery time</th>
                <th>Cost</th>
              </tr>
            </thead>
            <tbody>
              {shippingOptions.map((option) => (
                <tr key={option.method}>
                  <td>{option.method}</td>
                  <td>{option.time}</td>
                  <td>{option.cost}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p>Standard shipping is free on orders over $50.</p>

        <h2>Returns</h2>
        <p>
          Unopened products can be returned within 30 days for a refund. If
          something arrives damaged, contact us with a photo and we&apos;ll
          replace it.
        </p>
        <Link className="button" href="/contact">Contact us</Link>
      </div>
    </section>
  );
}
WREN_EOF

cat > "src/app/contact/actions.ts" << 'WREN_EOF'
"use server";

import { z } from "zod";

const messageSchema = z.object({
  name: z.string().trim().min(1, "Please enter your name."),
  email: z.email("Please enter a valid email address."),
  message: z.string().trim().min(10, "Please write at least 10 characters."),
});

export interface ContactState {
  status: "idle" | "sent" | "error";
  sentTo?: string;
  errors?: { name?: string; email?: string; message?: string };
}

export async function sendMessage(
  _previous: ContactState,
  formData: FormData
): Promise<ContactState> {
  const parsed = messageSchema.safeParse({
    name: formData.get("name"),
    email: formData.get("email"),
    message: formData.get("message"),
  });

  if (!parsed.success) {
    const errors: ContactState["errors"] = {};
    for (const issue of parsed.error.issues) {
      const field = issue.path[0];
      if (field === "name" || field === "email" || field === "message") {
        errors[field] ??= issue.message;
      }
    }
    return { status: "error", errors };
  }

  console.log(
    `New contact message from ${parsed.data.name} <${parsed.data.email}>: ${parsed.data.message}`
  );

  return { status: "sent", sentTo: parsed.data.name };
}
WREN_EOF

cat > "src/app/contact/ContactForm.tsx" << 'WREN_EOF'
"use client";

import { useActionState } from "react";
import { sendMessage } from "./actions";
import type { ContactState } from "./actions";

const initialState: ContactState = { status: "idle" };

export default function ContactForm() {
  const [state, formAction, pending] = useActionState(sendMessage, initialState);
  const errors = state.errors ?? {};

  if (state.status === "sent") {
    return (
      <p className="form-status" role="status">
        Thanks, {state.sentTo}. Your message has been received.
      </p>
    );
  }

  return (
    <form className="contact-form" action={formAction} noValidate>
      <div className="field">
        <label htmlFor="name">Name</label>
        <input id="name" name="name" type="text" aria-invalid={errors.name ? true : undefined} />
        {errors.name && <span className="field-error">{errors.name}</span>}
      </div>

      <div className="field">
        <label htmlFor="email">Email</label>
        <input id="email" name="email" type="email" aria-invalid={errors.email ? true : undefined} />
        {errors.email && <span className="field-error">{errors.email}</span>}
      </div>

      <div className="field">
        <label htmlFor="message">Message</label>
        <textarea
          id="message"
          name="message"
          rows={6}
          aria-invalid={errors.message ? true : undefined}
        />
        {errors.message && <span className="field-error">{errors.message}</span>}
      </div>

      <button className="button button-full" type="submit" disabled={pending}>
        {pending ? "Sending..." : "Send message"}
      </button>
    </form>
  );
}
WREN_EOF

cat > "src/app/contact/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import ContactForm from "./ContactForm";

export const metadata: Metadata = {
  title: "Contact",
};

export default function ContactPage() {
  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Contact</h1>
        <p>
          Questions about an order or an ingredient? Send a message and
          we&apos;ll reply within two working days.
        </p>
        <ContactForm />
      </div>
    </section>
  );
}
WREN_EOF

cat > "src/lib/orders.ts" << 'WREN_EOF'
import "server-only";
import { z } from "zod";
import { pool } from "./db";

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

export type OrderResult =
  | { ok: true; orderNumber: string; total: number }
  | { ok: false; error: string };

interface StockRow {
  name: string;
  price_cents: number;
  scents: string[];
  stock: number;
}

export async function createOrder(input: unknown, userId: number | null): Promise<OrderResult> {
  const parsed = orderSchema.safeParse(input);
  if (!parsed.success) {
    return { ok: false, error: parsed.error.issues[0]?.message ?? "Invalid order" };
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

      let problem = "";
      if (!product) {
        problem = `Unknown product: ${item.id}`;
      } else if (!product.scents.includes(item.scent)) {
        problem = `${product.name} is not available in ${item.scent}`;
      } else if (product.stock < item.quantity) {
        problem = `Only ${product.stock} of ${product.name} left in stock`;
      }

      if (problem || !product) {
        await client.query("ROLLBACK");
        return { ok: false, error: problem || "Invalid order" };
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

    return { ok: true, orderNumber: order.order_number, total: totalCents / 100 };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
WREN_EOF

cat > "src/app/checkout/actions.ts" << 'WREN_EOF'
"use server";

import { createOrder } from "@/lib/orders";
import type { OrderResult } from "@/lib/orders";

export interface OrderRequest {
  customer: {
    name: string;
    email: string;
    phone: string;
    address: string;
    city: string;
    state: string;
    postcode: string;
  };
  items: { id: string; scent: string; quantity: number }[];
}

export async function placeOrder(request: OrderRequest): Promise<OrderResult> {
  try {
    const result = await createOrder(request, null);
    if (result.ok) {
      console.log(`New order ${result.orderNumber}: $${result.total}`);
    }
    return result;
  } catch (error) {
    console.error(error);
    return { ok: false, error: "Something went wrong placing the order. Please try again." };
  }
}
WREN_EOF

cat > "src/app/checkout/CheckoutForm.tsx" << 'WREN_EOF'
"use client";

import Link from "next/link";
import { useState } from "react";
import type { FormEvent } from "react";
import { useCart } from "@/components/CartProvider";
import FormField from "@/components/FormField";
import { placeOrder } from "./actions";

interface CheckoutFields {
  name: string;
  email: string;
  phone: string;
  address: string;
  city: string;
  state: string;
  postcode: string;
}

type CheckoutErrors = Partial<Record<keyof CheckoutFields, string>>;

interface PlacedOrder {
  orderNumber: string;
  total: number;
}

const emptyForm: CheckoutFields = {
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

function validate(form: CheckoutFields): CheckoutErrors {
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

export default function CheckoutForm() {
  const { items, total, ready, clearCart } = useCart();
  const [form, setForm] = useState<CheckoutFields>(emptyForm);
  const [errors, setErrors] = useState<CheckoutErrors>({});
  const [placedOrder, setPlacedOrder] = useState<PlacedOrder | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [serverError, setServerError] = useState("");

  function updateField(field: keyof CheckoutFields, value: string) {
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

    const result = await placeOrder({
      customer: form,
      items: items.map((item) => ({
        id: item.id,
        scent: item.scent,
        quantity: item.quantity,
      })),
    });

    setSubmitting(false);

    if (!result.ok) {
      setServerError(result.error);
      return;
    }

    setPlacedOrder({ orderNumber: result.orderNumber, total: result.total });
    clearCart();
  }

  if (placedOrder) {
    return (
      <div className="prose">
        <h1 className="page-title">Thank you, {form.name.trim()}</h1>
        <p>
          Your order <strong>{placedOrder.orderNumber}</strong> for{" "}
          <strong>${placedOrder.total}</strong> has been received. A confirmation
          will be sent to {form.email.trim()}.
        </p>
        <p>This is a practice checkout: no payment was taken and nothing will be shipped.</p>
        <Link className="button" href="/shop">Back to the shop</Link>
      </div>
    );
  }

  if (!ready) {
    return (
      <>
        <h1 className="page-title">Checkout</h1>
        <p>Loading your cart...</p>
      </>
    );
  }

  if (items.length === 0) {
    return (
      <>
        <h1 className="page-title">Checkout</h1>
        <p>Your cart is empty, so there is nothing to check out.</p>
        <Link className="button" href="/shop">Browse the shop</Link>
      </>
    );
  }

  return (
    <>
      <h1 className="page-title">Checkout</h1>

      <p className="checkout-notice">
        You&apos;re checking out as a guest, with no account needed.
      </p>

      <div className="checkout-layout">
        <form className="contact-form" noValidate onSubmit={handleSubmit}>
          <h2>Shipping details</h2>
          <FormField
            id="name"
            label="Full name"
            autoComplete="name"
            value={form.name}
            error={errors.name}
            onChange={(value) => updateField("name", value)}
          />
          <FormField
            id="email"
            label="Email"
            type="email"
            autoComplete="email"
            value={form.email}
            error={errors.email}
            onChange={(value) => updateField("email", value)}
          />
          <FormField
            id="phone"
            label="Phone"
            type="tel"
            autoComplete="tel"
            value={form.phone}
            error={errors.phone}
            onChange={(value) => updateField("phone", value)}
          />
          <FormField
            id="address"
            label="Street address"
            autoComplete="street-address"
            value={form.address}
            error={errors.address}
            onChange={(value) => updateField("address", value)}
          />
          <FormField
            id="city"
            label="City"
            autoComplete="address-level2"
            value={form.city}
            error={errors.city}
            onChange={(value) => updateField("city", value)}
          />
          <FormField
            id="state"
            label="State"
            options={usStates}
            autoComplete="address-level1"
            value={form.state}
            error={errors.state}
            onChange={(value) => updateField("state", value)}
          />
          <FormField
            id="postcode"
            label="ZIP code"
            autoComplete="postal-code"
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
          <Link href="/cart">Edit cart</Link>
        </aside>
      </div>
    </>
  );
}
WREN_EOF

cat > "src/app/checkout/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import CheckoutForm from "./CheckoutForm";

export const metadata: Metadata = {
  title: "Checkout",
};

export default function CheckoutPage() {
  return (
    <section className="section">
      <div className="container">
        <CheckoutForm />
      </div>
    </section>
  );
}
WREN_EOF

grep -q "cart-actions" src/app/globals.css || cat >> src/app/globals.css << 'WREN_EOF'

.cart-actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-3);
}
WREN_EOF

echo
echo "Done. The dev server picks the changes up by itself."
