import type { Metadata } from "next";
import { setOrderStatusAction } from "@/app/admin/actions";
import { getAllOrders } from "@/lib/admin";
import { requireOwner } from "@/lib/auth";

export const metadata: Metadata = {
  title: "Orders",
};

export default async function AdminOrdersPage() {
  await requireOwner();
  const orders = await getAllOrders();

  return (
    <>
      <h1 className="page-title">Orders</h1>

      {orders.length === 0 ? (
        <p>No orders yet.</p>
      ) : (
        <div className="order-list">
          {orders.map((order) => (
            <article className="order-card" key={order.id}>
              <header className="order-card-header">
                <h2>{order.orderNumber}</h2>
                <p>
                  {order.createdAt.slice(0, 10)} · {order.status === "shipped" ? "Shipped" : "Waiting to ship"}
                </p>
              </header>

              <p className="order-customer">
                <strong>{order.customerName}</strong> {order.guest ? "(guest)" : "(account)"}
                <br />
                {order.email} · {order.phone}
                <br />
                {order.address}
              </p>

              <ul>
                {order.lines.map((line) => (
                  <li key={`${line.name}-${line.scent}`}>
                    <span>
                      {line.quantity} x {line.name} ({line.scent})
                    </span>
                  </li>
                ))}
              </ul>

              <p className="order-summary-total">
                <span>Total</span>
                <strong>${order.total}</strong>
              </p>

              <form action={setOrderStatusAction}>
                <input type="hidden" name="orderId" value={order.id} />
                <input
                  type="hidden"
                  name="status"
                  value={order.status === "shipped" ? "new" : "shipped"}
                />
                <button className={order.status === "shipped" ? "link-button" : "button"} type="submit">
                  {order.status === "shipped" ? "Mark as not shipped" : "Mark as shipped"}
                </button>
              </form>
            </article>
          ))}
        </div>
      )}
    </>
  );
}
