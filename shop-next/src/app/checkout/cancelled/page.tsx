import type { Metadata } from "next";
import Link from "next/link";
import { cancelPendingOrder, getReceiptByToken, getStripeSessionId } from "@/lib/orders";
import { closePaymentPage, isSessionPaid, paymentsEnabled } from "@/lib/payments";

export const metadata: Metadata = {
  title: "Payment cancelled",
};

export default async function CheckoutCancelledPage(props: PageProps<"/checkout/cancelled">) {
  const query = await props.searchParams;
  const token = typeof query.token === "string" ? query.token : "";

  if (token && paymentsEnabled()) {
    const order = await getReceiptByToken(token);

    if (order && order.status === "pending") {
      const sessionId = await getStripeSessionId(order.id);
      const paid = sessionId ? await isSessionPaid(sessionId) : false;

      if (!paid) {
        if (sessionId) {
          await closePaymentPage(sessionId);
        }
        await cancelPendingOrder(order.id);
      }
    }
  }

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Payment cancelled</h1>
        <p>
          You left the payment page, so no money was taken and the order was not placed. Your cart
          is still saved.
        </p>
        <div className="cart-actions">
          <Link className="button" href="/checkout">Try again</Link>
          <Link href="/cart">Edit cart</Link>
        </div>
      </div>
    </section>
  );
}
