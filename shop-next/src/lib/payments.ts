import "server-only";
import Stripe from "stripe";
import type { CreatedOrder } from "./orders";
import { getSettings } from "./settings";

const stripeClients = new Map<string, Stripe>();

export async function paymentsEnabled(): Promise<boolean> {
  return Boolean((await getSettings()).stripeSecretKey);
}

export async function getStripe(): Promise<Stripe> {
  const secretKey = (await getSettings()).stripeSecretKey;
  if (!secretKey) {
    throw new Error("No Stripe secret key is set.");
  }

  let client = stripeClients.get(secretKey);
  if (!client) {
    client = new Stripe(secretKey);
    stripeClients.set(secretKey, client);
  }
  return client;
}

/** Tidies a site address so a small typo in the setting can't break payment links. */
export function tidySiteUrl(value: string | undefined): string {
  let url = (value ?? "").trim().replace(/^["']+|["']+$/g, "").trim();

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

export async function siteUrl(): Promise<string> {
  return tidySiteUrl((await getSettings()).siteUrl);
}

export async function createPaymentPage(
  order: CreatedOrder,
  customerEmail: string
): Promise<{ sessionId: string; url: string }> {
  const stripe = await getStripe();
  const base = await siteUrl();

  const session = await stripe.checkout.sessions.create({
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
    success_url: `${base}/checkout/success?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${base}/checkout/cancelled?token=${order.paymentToken}`,
  });

  if (!session.url) {
    throw new Error("Stripe did not return a payment page address.");
  }

  return { sessionId: session.id, url: session.url };
}

export async function isSessionPaid(sessionId: string): Promise<boolean> {
  const session = await (await getStripe()).checkout.sessions.retrieve(sessionId);
  return session.payment_status === "paid";
}

export async function closePaymentPage(sessionId: string): Promise<void> {
  try {
    await (await getStripe()).checkout.sessions.expire(sessionId);
  } catch (error) {
    console.error("Could not expire the Stripe session:", error);
  }
}

/** Checks that the saved Stripe key works, for the Test connection button. */
export async function testStripeConnection(): Promise<{ ok: boolean; message: string }> {
  try {
    const stripe = await getStripe();
    const balance = await stripe.balance.retrieve();
    return {
      ok: true,
      message: balance.livemode
        ? "Connected to Stripe in LIVE mode. Real cards will be charged."
        : "Connected to Stripe in test mode. No real money will move.",
    };
  } catch (error) {
    const reason = error instanceof Error ? error.message : "Unknown error";
    return { ok: false, message: `Stripe did not accept the key: ${reason}` };
  }
}
