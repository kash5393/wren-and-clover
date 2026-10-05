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
