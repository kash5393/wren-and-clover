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
