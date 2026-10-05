#!/usr/bin/env bash
# Unit 8, step 5: payments in test mode and order emails.
# Run from inside the shop-next folder:  bash unit8-payments.sh
set -e
if [ ! -f src/lib/admin.ts ] || [ ! -f .env.local ]; then echo "Run this inside the shop-next folder, after the admin step (src/lib/admin.ts not found)."; exit 1; fi
npm install stripe nodemailer
npm install -D @types/nodemailer
mkdir -p db src/app/checkout/success src/app/checkout/cancelled

cat > db/payments-migration.sql << 'WREN_EOF'
ALTER TABLE orders ADD COLUMN IF NOT EXISTS stripe_session_id TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_token TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;

ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE orders
  ADD CONSTRAINT orders_status_check
  CHECK (status IN ('pending', 'new', 'shipped', 'cancelled'));

UPDATE orders SET paid_at = created_at WHERE paid_at IS NULL AND status IN ('new', 'shipped');
WREN_EOF
DATABASE_URL=$(grep '^DATABASE_URL=' .env.local | cut -d= -f2-)
psql "$DATABASE_URL" -q -f db/payments-migration.sql
echo "Database updated: orders can now be pending, paid, shipped or cancelled."

# Settings used by this step.
grep -q '^OWNER_EMAIL=' .env.local || { grep '^OWNER_EMAIL=' ../server/.env >> .env.local 2>/dev/null || echo 'OWNER_EMAIL=owner@wrenandclover.test' >> .env.local; }
grep -q '^SITE_URL=' .env.local || echo 'SITE_URL=http://localhost:3005' >> .env.local
grep -q 'STRIPE_SECRET_KEY' .env.local || cat >> .env.local << 'WREN_EOF'

# Payments: paste your Stripe TEST secret key (it starts with sk_test_) and remove the # to switch payments on.
#STRIPE_SECRET_KEY=

# Email: set an SMTP address to send real emails. Without it, emails are printed in the terminal.
#SMTP_URL=
WREN_EOF

# Keep the shared schema file in step.
SCHEMA=../server/db/schema.sql
if [ -f "$SCHEMA" ] && ! grep -q "payment_token" "$SCHEMA"; then
  perl -0pi -e "s|status TEXT NOT NULL DEFAULT 'new' CHECK \(status IN \('new', 'shipped'\)\)|status TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('pending', 'new', 'shipped', 'cancelled')),\n  stripe_session_id TEXT,\n  payment_token TEXT,\n  paid_at TIMESTAMPTZ|" "$SCHEMA"
fi

cat > "src/lib/orders.ts" << 'WREN_EOF'
import "server-only";
import { randomBytes } from "node:crypto";
import { z } from "zod";
import { pool } from "./db";
import type { ShippingDetails } from "./types";

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

export interface OrderLine {
  productId: string;
  name: string;
  scent: string;
  quantity: number;
  unitPriceCents: number;
}

export interface CreatedOrder {
  id: number;
  orderNumber: string;
  total: number;
  paymentToken: string;
  lines: OrderLine[];
}

export type CreateOrderResult = { ok: true; order: CreatedOrder } | { ok: false; error: string };

interface StockRow {
  name: string;
  price_cents: number;
  scents: string[];
  stock: number;
}

export async function createOrder(
  input: unknown,
  userId: number | null,
  status: "pending" | "new"
): Promise<CreateOrderResult> {
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

    const paymentToken = randomBytes(24).toString("hex");

    const totalCents = lines.reduce(
      (sum, line) => sum + line.unitPriceCents * line.quantity,
      0
    );

    const inserted = await client.query<{ id: number; order_number: string }>(
      `INSERT INTO orders
         (user_id, customer_name, email, phone, address, city, state, postcode, total_cents,
          status, payment_token, paid_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
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
        status,
        paymentToken,
        status === "new" ? new Date() : null,
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

    return {
      ok: true,
      order: {
        id: order.id,
        orderNumber: order.order_number,
        total: totalCents / 100,
        paymentToken,
        lines,
      },
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export interface OrderSummary {
  orderNumber: string;
  createdAt: string;
  status: "pending" | "new" | "shipped";
  total: number;
  lines: { name: string; scent: string; quantity: number; unitPrice: number }[];
}

export async function getOrdersForUser(userId: number): Promise<OrderSummary[]> {
  const result = await pool.query(
    `SELECT
       o.order_number AS "orderNumber",
       o.created_at AS "createdAt",
       o.status,
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
     WHERE o.user_id = $1 AND o.status <> 'cancelled'
     GROUP BY o.id
     ORDER BY o.id DESC`,
    [userId]
  );

  return result.rows.map((row) => ({
    orderNumber: row.orderNumber,
    createdAt: new Date(row.createdAt).toISOString(),
    status: row.status,
    total: Number(row.total),
    lines: row.lines,
  }));
}

export async function getSavedShipping(userId: number): Promise<ShippingDetails | null> {
  const result = await pool.query<ShippingDetails>(
    `SELECT customer_name AS name, email, phone, address, city, state, postcode
     FROM orders
     WHERE user_id = $1 AND status <> 'cancelled'
     ORDER BY id DESC
     LIMIT 1`,
    [userId]
  );

  return result.rows[0] ?? null;
}

export async function countOrdersForUser(userId: number): Promise<number> {
  const result = await pool.query<{ count: string }>(
    "SELECT COUNT(*) AS count FROM orders WHERE user_id = $1 AND status IN ('new', 'shipped')",
    [userId]
  );

  return Number(result.rows[0]?.count ?? 0);
}

export interface OrderReceipt {
  id: number;
  orderNumber: string;
  status: "pending" | "new" | "shipped" | "cancelled";
  customerName: string;
  email: string;
  address: string;
  total: number;
  lines: { name: string; scent: string; quantity: number; unitPrice: number }[];
}

async function findReceipt(column: "id" | "stripe_session_id" | "payment_token", value: number | string): Promise<OrderReceipt | null> {
  const result = await pool.query(
    `SELECT
       o.id,
       o.order_number,
       o.status,
       o.customer_name,
       o.email,
       o.address || ', ' || o.city || ', ' || o.state || ' ' || o.postcode AS address,
       o.total_cents,
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
     WHERE o.${column} = $1
     GROUP BY o.id`,
    [value]
  );

  const row = result.rows[0];
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    orderNumber: row.order_number,
    status: row.status,
    customerName: row.customer_name,
    email: row.email,
    address: row.address,
    total: row.total_cents / 100,
    lines: row.lines,
  };
}

export function getReceiptById(orderId: number): Promise<OrderReceipt | null> {
  return findReceipt("id", orderId);
}

export function getReceiptBySession(sessionId: string): Promise<OrderReceipt | null> {
  return findReceipt("stripe_session_id", sessionId);
}

export function getReceiptByToken(token: string): Promise<OrderReceipt | null> {
  return findReceipt("payment_token", token);
}

export async function attachStripeSession(orderId: number, sessionId: string): Promise<void> {
  await pool.query("UPDATE orders SET stripe_session_id = $1 WHERE id = $2", [sessionId, orderId]);
}

export async function getStripeSessionId(orderId: number): Promise<string | null> {
  const result = await pool.query<{ stripe_session_id: string | null }>(
    "SELECT stripe_session_id FROM orders WHERE id = $1",
    [orderId]
  );
  return result.rows[0]?.stripe_session_id ?? null;
}

/** Marks a pending order as paid. Returns true only the first time, so emails are sent once. */
export async function markOrderPaid(orderId: number): Promise<boolean> {
  const result = await pool.query(
    "UPDATE orders SET status = 'new', paid_at = now() WHERE id = $1 AND status = 'pending'",
    [orderId]
  );
  return result.rowCount === 1;
}

/** Cancels an unpaid order and puts its items back into stock. */
export async function cancelPendingOrder(orderId: number): Promise<boolean> {
  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    const updated = await client.query(
      "UPDATE orders SET status = 'cancelled' WHERE id = $1 AND status = 'pending'",
      [orderId]
    );
    if (updated.rowCount !== 1) {
      await client.query("ROLLBACK");
      return false;
    }

    await client.query(
      `UPDATE products p
       SET stock = p.stock + i.quantity
       FROM order_items i
       WHERE i.order_id = $1 AND i.product_id = p.id`,
      [orderId]
    );

    await client.query("COMMIT");
    return true;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
WREN_EOF

cat > "src/lib/payments.ts" << 'WREN_EOF'
import "server-only";
import Stripe from "stripe";
import type { CreatedOrder } from "./orders";

let stripeClient: Stripe | null = null;

export function paymentsEnabled(): boolean {
  return Boolean(process.env.STRIPE_SECRET_KEY);
}

export function getStripe(): Stripe {
  const secretKey = process.env.STRIPE_SECRET_KEY;
  if (!secretKey) {
    throw new Error("STRIPE_SECRET_KEY is not set.");
  }
  stripeClient ??= new Stripe(secretKey);
  return stripeClient;
}

function siteUrl(): string {
  return (process.env.SITE_URL ?? "http://localhost:3005").replace(/\/$/, "");
}

export async function createPaymentPage(
  order: CreatedOrder,
  customerEmail: string
): Promise<{ sessionId: string; url: string }> {
  const session = await getStripe().checkout.sessions.create({
    mode: "payment",
    customer_email: customerEmail,
    client_reference_id: order.orderNumber,
    line_items: order.lines.map((line) => ({
      quantity: line.quantity,
      price_data: {
        currency: "usd",
        unit_amount: line.unitPriceCents,
        product_data: { name: `${line.name} (${line.scent})` },
      },
    })),
    success_url: `${siteUrl()}/checkout/success?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${siteUrl()}/checkout/cancelled?token=${order.paymentToken}`,
  });

  if (!session.url) {
    throw new Error("Stripe did not return a payment page address.");
  }

  return { sessionId: session.id, url: session.url };
}

export async function isSessionPaid(sessionId: string): Promise<boolean> {
  const session = await getStripe().checkout.sessions.retrieve(sessionId);
  return session.payment_status === "paid";
}

export async function closePaymentPage(sessionId: string): Promise<void> {
  try {
    await getStripe().checkout.sessions.expire(sessionId);
  } catch (error) {
    console.error("Could not expire the Stripe session:", error);
  }
}
WREN_EOF

cat > "src/lib/email.ts" << 'WREN_EOF'
import "server-only";
import nodemailer from "nodemailer";
import type { OrderReceipt } from "./orders";

interface Email {
  to: string;
  subject: string;
  text: string;
}

async function sendEmail(email: Email): Promise<void> {
  const smtpUrl = process.env.SMTP_URL;
  const from = process.env.EMAIL_FROM ?? "Wren & Clover <orders@wrenandclover.test>";

  if (!smtpUrl) {
    console.log(
      [
        "",
        "----- Email preview (not sent: SMTP_URL is not set) -----",
        `From: ${from}`,
        `To: ${email.to}`,
        `Subject: ${email.subject}`,
        "",
        email.text,
        "--------------------------------------------------------",
        "",
      ].join("\n")
    );
    return;
  }

  const transport = nodemailer.createTransport(smtpUrl);
  await transport.sendMail({ from, ...email });
}

function describeLines(order: OrderReceipt): string {
  return order.lines
    .map((line) => `  ${line.quantity} x ${line.name} (${line.scent})  $${line.unitPrice * line.quantity}`)
    .join("\n");
}

export async function sendOrderEmails(order: OrderReceipt): Promise<void> {
  const emails: Email[] = [
    {
      to: order.email,
      subject: `Your Wren & Clover order ${order.orderNumber}`,
      text: [
        `Hi ${order.customerName},`,
        "",
        `Thank you for your order ${order.orderNumber}.`,
        "",
        describeLines(order),
        "",
        `Total: $${order.total}`,
        "",
        `Shipping to: ${order.address}`,
        "",
        "We'll pack it within two working days.",
        "",
        "Wren & Clover Botanicals",
      ].join("\n"),
    },
  ];

  const ownerEmail = process.env.OWNER_EMAIL;
  if (ownerEmail) {
    emails.push({
      to: ownerEmail,
      subject: `New order ${order.orderNumber} ($${order.total})`,
      text: [
        `${order.customerName} <${order.email}> placed order ${order.orderNumber}.`,
        "",
        describeLines(order),
        "",
        `Total: $${order.total}`,
        `Ship to: ${order.address}`,
      ].join("\n"),
    });
  }

  for (const email of emails) {
    try {
      await sendEmail(email);
    } catch (error) {
      console.error(`Could not send email to ${email.to}:`, error);
    }
  }
}
WREN_EOF

cat > "src/lib/admin.ts" << 'WREN_EOF'
import "server-only";
import { connection } from "next/server";
import { pool } from "./db";

export interface DashboardStats {
  orderCount: number;
  newOrderCount: number;
  salesTotal: number;
  messageCount: number;
  lowStock: { id: string; name: string; stock: number }[];
  bestSellers: { name: string; unitsSold: number; revenue: number }[];
}

export interface AdminOrder {
  id: number;
  orderNumber: string;
  createdAt: string;
  status: "pending" | "new" | "shipped" | "cancelled";
  customerName: string;
  email: string;
  phone: string;
  address: string;
  guest: boolean;
  total: number;
  lines: { name: string; scent: string; quantity: number }[];
}

export interface ContactMessage {
  id: number;
  name: string;
  email: string;
  message: string;
  createdAt: string;
}

export async function getDashboardStats(): Promise<DashboardStats> {
  await connection();

  const [orders, messages, lowStock, bestSellers] = await Promise.all([
    pool.query<{ order_count: string; new_count: string; sales_cents: string | null }>(
      `SELECT
         COUNT(*) AS order_count,
         COUNT(*) FILTER (WHERE status = 'new') AS new_count,
         SUM(total_cents) AS sales_cents
       FROM orders
       WHERE status IN ('new', 'shipped')`
    ),
    pool.query<{ count: string }>("SELECT COUNT(*) AS count FROM contact_messages"),
    pool.query<{ id: string; name: string; stock: number }>(
      "SELECT id, name, stock FROM products WHERE stock < 10 ORDER BY stock, name"
    ),
    pool.query<{ name: string; units_sold: string; revenue_cents: string }>(
      `SELECT
         i.product_name AS name,
         SUM(i.quantity) AS units_sold,
         SUM(i.quantity * i.unit_price_cents) AS revenue_cents
       FROM order_items i
       JOIN orders o ON o.id = i.order_id
       WHERE o.status IN ('new', 'shipped')
       GROUP BY i.product_name
       ORDER BY SUM(i.quantity) DESC
       LIMIT 5`
    ),
  ]);

  const totals = orders.rows[0];

  return {
    orderCount: Number(totals?.order_count ?? 0),
    newOrderCount: Number(totals?.new_count ?? 0),
    salesTotal: Number(totals?.sales_cents ?? 0) / 100,
    messageCount: Number(messages.rows[0]?.count ?? 0),
    lowStock: lowStock.rows,
    bestSellers: bestSellers.rows.map((row) => ({
      name: row.name,
      unitsSold: Number(row.units_sold),
      revenue: Number(row.revenue_cents) / 100,
    })),
  };
}

export async function getAllOrders(): Promise<AdminOrder[]> {
  await connection();

  const result = await pool.query(
    `SELECT
       o.id,
       o.order_number,
       o.created_at,
       o.status,
       o.customer_name,
       o.email,
       o.phone,
       o.address || ', ' || o.city || ', ' || o.state || ' ' || o.postcode AS address,
       o.user_id IS NULL AS guest,
       o.total_cents,
       json_agg(
         json_build_object('name', i.product_name, 'scent', i.scent, 'quantity', i.quantity)
         ORDER BY i.id
       ) AS lines
     FROM orders o
     JOIN order_items i ON i.order_id = o.id
     GROUP BY o.id
     ORDER BY o.id DESC`
  );

  return result.rows.map((row) => ({
    id: row.id,
    orderNumber: row.order_number,
    createdAt: new Date(row.created_at).toISOString(),
    status: row.status,
    customerName: row.customer_name,
    email: row.email,
    phone: row.phone,
    address: row.address,
    guest: row.guest,
    total: row.total_cents / 100,
    lines: row.lines,
  }));
}

export async function setOrderStatus(orderId: number, status: "new" | "shipped"): Promise<void> {
  await pool.query(
    "UPDATE orders SET status = $1 WHERE id = $2 AND status IN ('new', 'shipped')",
    [status, orderId]
  );
}

export async function getMessages(): Promise<ContactMessage[]> {
  await connection();

  const result = await pool.query(
    "SELECT id, name, email, message, created_at FROM contact_messages ORDER BY id DESC"
  );

  return result.rows.map((row) => ({
    id: row.id,
    name: row.name,
    email: row.email,
    message: row.message,
    createdAt: new Date(row.created_at).toISOString(),
  }));
}
WREN_EOF

cat > "src/app/checkout/actions.ts" << 'WREN_EOF'
"use server";

import { getCurrentUser } from "@/lib/auth";
import { sendOrderEmails } from "@/lib/email";
import { attachStripeSession, cancelPendingOrder, createOrder, getReceiptById } from "@/lib/orders";
import { createPaymentPage, paymentsEnabled } from "@/lib/payments";

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

export type PlaceOrderResult =
  | { ok: true; kind: "placed"; orderNumber: string; total: number }
  | { ok: true; kind: "payment"; paymentUrl: string }
  | { ok: false; error: string };

export async function placeOrder(request: OrderRequest): Promise<PlaceOrderResult> {
  try {
    const user = await getCurrentUser();
    const takePayment = paymentsEnabled();

    const result = await createOrder(request, user ? user.id : null, takePayment ? "pending" : "new");
    if (!result.ok) {
      return result;
    }
    const order = result.order;

    if (!takePayment) {
      console.log(`New order ${order.orderNumber}: $${order.total} (payments are switched off)`);
      const receipt = await getReceiptById(order.id);
      if (receipt) {
        await sendOrderEmails(receipt);
      }
      return { ok: true, kind: "placed", orderNumber: order.orderNumber, total: order.total };
    }

    try {
      const payment = await createPaymentPage(order, request.customer.email);
      await attachStripeSession(order.id, payment.sessionId);
      return { ok: true, kind: "payment", paymentUrl: payment.url };
    } catch (error) {
      console.error(error);
      await cancelPendingOrder(order.id);
      return { ok: false, error: "The payment page could not be opened. Please try again." };
    }
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
import type { ShippingDetails } from "@/lib/types";
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

interface CheckoutFormProps {
  user: { name: string; email: string } | null;
  savedShipping: ShippingDetails | null;
  paymentsOn: boolean;
}

export default function CheckoutForm({ user, savedShipping, paymentsOn }: CheckoutFormProps) {
  const { items, total, ready, clearCart } = useCart();
  const [form, setForm] = useState<CheckoutFields>({
    ...emptyForm,
    ...(user ? { name: user.name, email: user.email } : {}),
    ...(savedShipping ?? {}),
  });
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

    if (!result.ok) {
      setSubmitting(false);
      setServerError(result.error);
      return;
    }

    if (result.kind === "payment") {
      window.location.assign(result.paymentUrl);
      return;
    }

    setSubmitting(false);
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
        {user ? (
          <p>
            You can see this order under <Link href="/orders">My orders</Link>.
          </p>
        ) : (
          <p>
            Want to see your orders in one place next time?{" "}
            <Link href={`/signup?email=${encodeURIComponent(form.email.trim())}`}>
              Create an account
            </Link>
            . It&apos;s optional.
          </p>
        )}
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

      {user ? (
        <p className="checkout-notice">
          Signed in as <strong>{user.name}</strong> ({user.email}).{" "}
          {savedShipping
            ? "We've filled in the details from your last order. Check them before you place this one."
            : "Your details will be remembered after your first order."}
        </p>
      ) : (
        <p className="checkout-notice">
          You&apos;re checking out as a guest, with no account needed. Have an
          account? <Link href="/login?next=/checkout">Sign in</Link> to fill in
          your details.
        </p>
      )}

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
            {submitting ? "Please wait..." : paymentsOn ? "Continue to payment" : "Place order"}
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
import { getCurrentUser } from "@/lib/auth";
import { getSavedShipping } from "@/lib/orders";
import { paymentsEnabled } from "@/lib/payments";
import CheckoutForm from "./CheckoutForm";

export const metadata: Metadata = {
  title: "Checkout",
};

export default async function CheckoutPage() {
  const user = await getCurrentUser();
  const savedShipping = user ? await getSavedShipping(user.id) : null;

  return (
    <section className="section">
      <div className="container">
        <CheckoutForm
          user={user ? { name: user.name, email: user.email } : null}
          savedShipping={savedShipping}
          paymentsOn={paymentsEnabled()}
        />
      </div>
    </section>
  );
}
WREN_EOF

cat > "src/components/ClearCart.tsx" << 'WREN_EOF'
"use client";

import { useEffect } from "react";
import { useCart } from "@/components/CartProvider";

export default function ClearCart() {
  const { ready, count, clearCart } = useCart();

  useEffect(() => {
    if (ready && count > 0) {
      clearCart();
    }
  }, [ready, count, clearCart]);

  return null;
}
WREN_EOF

cat > "src/app/checkout/success/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import Link from "next/link";
import ClearCart from "@/components/ClearCart";
import { sendOrderEmails } from "@/lib/email";
import { getReceiptBySession, markOrderPaid } from "@/lib/orders";
import { isSessionPaid, paymentsEnabled } from "@/lib/payments";

export const metadata: Metadata = {
  title: "Order confirmed",
};

function Problem({ message }: { message: string }) {
  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">We couldn&apos;t confirm that payment</h1>
        <p>{message}</p>
        <Link className="button" href="/cart">Back to your cart</Link>
      </div>
    </section>
  );
}

export default async function CheckoutSuccessPage(props: PageProps<"/checkout/success">) {
  const query = await props.searchParams;
  const sessionId = typeof query.session_id === "string" ? query.session_id : "";

  if (!sessionId || !paymentsEnabled()) {
    return <Problem message="This page is only shown after a payment." />;
  }

  const order = await getReceiptBySession(sessionId);
  if (!order) {
    return <Problem message="No order matches this payment." />;
  }

  if (order.status === "cancelled") {
    return <Problem message="This order was cancelled. If you were charged, please contact us." />;
  }

  if (order.status === "pending") {
    if (!(await isSessionPaid(sessionId))) {
      return <Problem message="The payment has not completed. You have not been charged." />;
    }

    const firstTime = await markOrderPaid(order.id);
    if (firstTime) {
      console.log(`Order ${order.orderNumber} paid: $${order.total}`);
      await sendOrderEmails(order);
    }
  }

  return (
    <section className="section">
      <div className="container prose">
        <ClearCart />
        <h1 className="page-title">Thank you, {order.customerName}</h1>
        <p>
          Your payment went through and order <strong>{order.orderNumber}</strong> for{" "}
          <strong>${order.total}</strong> is confirmed. A confirmation has been sent to {order.email}.
        </p>
        <ul>
          {order.lines.map((line) => (
            <li key={`${line.name}-${line.scent}`}>
              {line.quantity} x {line.name} ({line.scent})
            </li>
          ))}
        </ul>
        <p>Shipping to: {order.address}</p>
        <Link className="button" href="/shop">Back to the shop</Link>
      </div>
    </section>
  );
}
WREN_EOF

cat > "src/app/checkout/cancelled/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import Link from "next/link";
import { cancelPendingOrder, getReceiptByToken, getStripeSessionId } from "@/lib/orders";
import { closePaymentPage, isSessionPaid, paymentsEnabled } from "@/lib/payments";

export const metadata: Metadata = {
  title: "Payment cancelled",
};

export default async function CheckoutCancelledPage(props: PageProps<"/checkout/cancelled">) {
  const query = await props.searchParams;
  const token = typeof query.token === "string" ? query.token : "";

  if (token && paymentsEnabled()) {
    const order = await getReceiptByToken(token);

    if (order && order.status === "pending") {
      const sessionId = await getStripeSessionId(order.id);
      const paid = sessionId ? await isSessionPaid(sessionId) : false;

      if (!paid) {
        if (sessionId) {
          await closePaymentPage(sessionId);
        }
        await cancelPendingOrder(order.id);
      }
    }
  }

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Payment cancelled</h1>
        <p>
          You left the payment page, so no money was taken and the order was not placed. Your cart
          is still saved.
        </p>
        <div className="cart-actions">
          <Link className="button" href="/checkout">Try again</Link>
          <Link href="/cart">Edit cart</Link>
        </div>
      </div>
    </section>
  );
}
WREN_EOF

cat > "src/app/admin/orders/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import { setOrderStatusAction } from "@/app/admin/actions";
import { getAllOrders } from "@/lib/admin";
import { requireOwner } from "@/lib/auth";

export const metadata: Metadata = {
  title: "Orders",
};

const statusLabels = {
  pending: "Awaiting payment",
  new: "Paid, waiting to ship",
  shipped: "Shipped",
  cancelled: "Cancelled (not paid)",
};

export default async function AdminOrdersPage() {
  await requireOwner();
  const orders = await getAllOrders();

  return (
    <>
      <h1 className="page-title">Orders</h1>

      {orders.length === 0 ? (
        <p>No orders yet.</p>
      ) : (
        <div className="order-list">
          {orders.map((order) => (
            <article className="order-card" key={order.id}>
              <header className="order-card-header">
                <h2>{order.orderNumber}</h2>
                <p>
                  {order.createdAt.slice(0, 10)} · {statusLabels[order.status]}
                </p>
              </header>

              <p className="order-customer">
                <strong>{order.customerName}</strong> {order.guest ? "(guest)" : "(account)"}
                <br />
                {order.email} · {order.phone}
                <br />
                {order.address}
              </p>

              <ul>
                {order.lines.map((line) => (
                  <li key={`${line.name}-${line.scent}`}>
                    <span>
                      {line.quantity} x {line.name} ({line.scent})
                    </span>
                  </li>
                ))}
              </ul>

              <p className="order-summary-total">
                <span>Total</span>
                <strong>${order.total}</strong>
              </p>

              {(order.status === "new" || order.status === "shipped") && (
                <form action={setOrderStatusAction}>
                  <input type="hidden" name="orderId" value={order.id} />
                  <input
                    type="hidden"
                    name="status"
                    value={order.status === "shipped" ? "new" : "shipped"}
                  />
                  <button className={order.status === "shipped" ? "link-button" : "button"} type="submit">
                    {order.status === "shipped" ? "Mark as not shipped" : "Mark as shipped"}
                  </button>
                </form>
              )}
            </article>
          ))}
        </div>
      )}
    </>
  );
}
WREN_EOF

cat > "src/app/orders/page.tsx" << 'WREN_EOF'
import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentUser } from "@/lib/auth";
import { getOrdersForUser } from "@/lib/orders";

export const metadata: Metadata = {
  title: "My orders",
};

export default async function OrdersPage() {
  const user = await getCurrentUser();
  if (!user) {
    redirect("/login?next=/orders");
  }

  const orders = await getOrdersForUser(user.id);

  return (
    <section className="section">
      <div className="container">
        <h1 className="page-title">My orders</h1>

        {orders.length === 0 ? (
          <>
            <p>You haven&apos;t placed any orders with this account yet.</p>
            <Link className="button" href="/shop">Browse the shop</Link>
          </>
        ) : (
          <div className="order-list">
            {orders.map((order) => (
              <article className="order-card" key={order.orderNumber}>
                <header className="order-card-header">
                  <h2>{order.orderNumber}</h2>
                  <p>
                    {order.createdAt.slice(0, 10)} ·{" "}
                    {order.status === "shipped"
                      ? "Shipped"
                      : order.status === "pending"
                        ? "Awaiting payment"
                        : "Being prepared"}
                  </p>
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
WREN_EOF

echo
echo "Done. Restart the dev server:  npm run dev"
