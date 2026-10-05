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
  status: "new" | "shipped";
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
       FROM orders`
    ),
    pool.query<{ count: string }>("SELECT COUNT(*) AS count FROM contact_messages"),
    pool.query<{ id: string; name: string; stock: number }>(
      "SELECT id, name, stock FROM products WHERE stock < 10 ORDER BY stock, name"
    ),
    pool.query<{ name: string; units_sold: string; revenue_cents: string }>(
      `SELECT
         product_name AS name,
         SUM(quantity) AS units_sold,
         SUM(quantity * unit_price_cents) AS revenue_cents
       FROM order_items
       GROUP BY product_name
       ORDER BY SUM(quantity) DESC
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
  await pool.query("UPDATE orders SET status = $1 WHERE id = $2", [status, orderId]);
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
