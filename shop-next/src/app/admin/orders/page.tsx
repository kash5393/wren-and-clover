import type { Metadata } from "next";
import Link from "next/link";
import { setOrderStatusAction } from "@/app/admin/actions";
import { getAllOrders } from "@/lib/admin";
import { requireOwner } from "@/lib/auth";

export const metadata: Metadata = {
  title: "Orders",
};

const statusLabels = {
  pending: "Awaiting payment",
  new: "Paid, waiting to ship",
  shipped: "Shipped",
  cancelled: "Cancelled (not paid)",
};

export default async function AdminOrdersPage(props: PageProps<"/admin/orders">) {
  await requireOwner();

  const query = await props.searchParams;
  const search = typeof query.search === "string" ? query.search.trim() : "";
  const term = search.toLowerCase();

  const allOrders = await getAllOrders();
  const orders = term
    ? allOrders.filter(
        (order) =>
          order.orderNumber.toLowerCase().includes(term) ||
          order.customerName.toLowerCase().includes(term) ||
          order.email.toLowerCase().includes(term)
      )
    : allOrders;

  return (
    <>
      <h1 className="page-title">Orders</h1>

      <form className="order-search" action="/admin/orders">
        <div className="field">
          <label htmlFor="search">Search by order number, customer name or email</label>
          <input id="search" name="search" type="search" defaultValue={search} />
        </div>
        <button className="button" type="submit">Search</button>
        {search && <Link href="/admin/orders">Clear</Link>}
      </form>

      <p className="result-count">
        {orders.length} of {allOrders.length} {allOrders.length === 1 ? "order" : "orders"}
      </p>

      {orders.length === 0 ? (
        <p>{search ? "No orders match that search." : "No orders yet."}</p>
      ) : (
        <div className="order-list">
          {orders.map((order) => (
            <article className="order-card" key={order.id}>
              <header className="order-card-header">
                <h2>{order.orderNumber}</h2>
                <p>
                  {order.createdAt.slice(0, 10)} · {statusLabels[order.status]}
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

              {(order.status === "new" || order.status === "shipped") && (
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
              )}
            </article>
          ))}
        </div>
      )}
    </>
  );
}
