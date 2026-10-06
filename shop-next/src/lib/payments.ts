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

/** The public address of the site, tidied up so a small typo in the setting can't break payments. */
export function siteUrl(): string {
  let url = (process.env.SITE_URL ?? "").trim().replace(/^["']+|["']+$/g, "").trim();

  if (!url && process.env.VERCEL_PROJECT_PRODUCTION_URL) {
    url = process.env.VERCEL_PROJECT_PRODUCTION_URL;
  }
  if (!url) {
    url = "http://localhost:3005";
  }
  if (!/^https?:\/\//i.test(url)) {
    url = `https://${url}`;
  }

  return url.replace(/\/+$/, "");
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
