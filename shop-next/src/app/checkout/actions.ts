"use server";

import { getCurrentUser } from "@/lib/auth";
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
    const user = await getCurrentUser();
    const result = await createOrder(request, user ? user.id : null);
    if (result.ok) {
      console.log(`New order ${result.orderNumber}: $${result.total}`);
    }
    return result;
  } catch (error) {
    console.error(error);
    return { ok: false, error: "Something went wrong placing the order. Please try again." };
  }
}
