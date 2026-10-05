import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentUser } from "@/lib/auth";
import { getOrdersForUser } from "@/lib/orders";

export const metadata: Metadata = {
  title: "My orders",
};

export default async function OrdersPage() {
  const user = await getCurrentUser();
  if (!user) {
    redirect("/login?next=/orders");
  }

  const orders = await getOrdersForUser(user.id);

  return (
    <section className="section">
      <div className="container">
        <h1 className="page-title">My orders</h1>

        {orders.length === 0 ? (
          <>
            <p>You haven&apos;t placed any orders with this account yet.</p>
            <Link className="button" href="/shop">Browse the shop</Link>
          </>
        ) : (
          <div className="order-list">
            {orders.map((order) => (
              <article className="order-card" key={order.orderNumber}>
                <header className="order-card-header">
                  <h2>{order.orderNumber}</h2>
                  <p>
                    {order.createdAt.slice(0, 10)} ·{" "}
                    {order.status === "shipped"
                      ? "Shipped"
                      : order.status === "pending"
                        ? "Awaiting payment"
                        : "Being prepared"}
                  </p>
                </header>
                <ul>
                  {order.lines.map((line) => (
                    <li key={`${line.name}-${line.scent}`}>
                      <span>
                        {line.quantity} x {line.name} ({line.scent})
                      </span>
                      <span>${line.unitPrice * line.quantity}</span>
                    </li>
                  ))}
                </ul>
                <p className="order-summary-total">
                  <span>Total</span>
                  <strong>${order.total}</strong>
                </p>
              </article>
            ))}
          </div>
        )}
      </div>
    </section>
  );
}
