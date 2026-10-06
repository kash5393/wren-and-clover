import { sendOrderEmails } from "@/lib/email";
import { cancelPendingOrder, getReceiptBySession, markOrderPaid } from "@/lib/orders";
import { getStripe, paymentsEnabled } from "@/lib/payments";
import { getSettings } from "@/lib/settings";

export async function POST(request: Request): Promise<Response> {
  const webhookSecret = (await getSettings()).stripeWebhookSecret;
  if (!webhookSecret || !(await paymentsEnabled())) {
    return new Response("Webhook is not configured", { status: 400 });
  }

  const signature = request.headers.get("stripe-signature") ?? "";
  const body = await request.text();

  let event;
  try {
    event = (await getStripe()).webhooks.constructEvent(body, signature, webhookSecret);
  } catch {
    return new Response("Invalid signature", { status: 400 });
  }

  if (
    event.type === "checkout.session.completed" ||
    event.type === "checkout.session.async_payment_succeeded"
  ) {
    const session = event.data.object;

    if (session.payment_status === "paid") {
      const order = await getReceiptBySession(session.id);

      if (order && order.status === "pending") {
        const firstTime = await markOrderPaid(order.id);
        if (firstTime) {
          console.log(`Order ${order.orderNumber} paid (confirmed by Stripe webhook)`);
          await sendOrderEmails(order);
        }
      }
    }
  }

  if (event.type === "checkout.session.expired") {
    const order = await getReceiptBySession(event.data.object.id);

    if (order && order.status === "pending") {
      await cancelPendingOrder(order.id);
      console.log(`Order ${order.orderNumber} cancelled: its payment page expired`);
    }
  }

  return Response.json({ received: true });
}
