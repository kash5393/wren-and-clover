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
