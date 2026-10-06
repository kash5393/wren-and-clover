import type { Metadata } from "next";
import Link from "next/link";
import ClearCart from "@/components/ClearCart";
import { sendOrderEmails } from "@/lib/email";
import { getReceiptBySession, markOrderPaid } from "@/lib/orders";
import { isSessionPaid, paymentsEnabled } from "@/lib/payments";

export const metadata: Metadata = {
  title: "Order confirmed",
};

function Problem({ message }: { message: string }) {
  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">We couldn&apos;t confirm that payment</h1>
        <p>{message}</p>
        <Link className="button" href="/cart">Back to your cart</Link>
      </div>
    </section>
  );
}

export default async function CheckoutSuccessPage(props: PageProps<"/checkout/success">) {
  const query = await props.searchParams;
  const sessionId = typeof query.session_id === "string" ? query.session_id : "";

  if (!sessionId || !(await paymentsEnabled())) {
    return <Problem message="This page is only shown after a payment." />;
  }

  const order = await getReceiptBySession(sessionId);
  if (!order) {
    return <Problem message="No order matches this payment." />;
  }

  if (order.status === "cancelled") {
    return <Problem message="This order was cancelled. If you were charged, please contact us." />;
  }

  if (order.status === "pending") {
    if (!(await isSessionPaid(sessionId))) {
      return <Problem message="The payment has not completed. You have not been charged." />;
    }

    const firstTime = await markOrderPaid(order.id);
    if (firstTime) {
      console.log(`Order ${order.orderNumber} paid: $${order.total}`);
      await sendOrderEmails(order);
    }
  }

  return (
    <section className="section">
      <div className="container prose">
        <ClearCart />
        <h1 className="page-title">Thank you, {order.customerName}</h1>
        <p>
          Your payment went through and order <strong>{order.orderNumber}</strong> for{" "}
          <strong>${order.total}</strong> is confirmed. A confirmation has been sent to {order.email}.
        </p>
        <ul>
          {order.lines.map((line) => (
            <li key={`${line.name}-${line.scent}`}>
              {line.quantity} x {line.name} ({line.scent})
            </li>
          ))}
        </ul>
        <p>Shipping to: {order.address}</p>
        <Link className="button" href="/shop">Back to the shop</Link>
      </div>
    </section>
  );
}
