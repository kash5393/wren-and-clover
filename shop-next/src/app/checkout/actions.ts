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
