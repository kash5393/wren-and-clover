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
