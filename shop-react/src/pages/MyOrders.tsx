import { useEffect, useState } from "react";
import { Link } from "react-router";
import { useAuth } from "../context/AuthContext";

interface OrderLine {
  name: string;
  scent: string;
  quantity: number;
  unitPrice: number;
}

interface OrderSummary {
  orderNumber: string;
  createdAt: string;
  total: number;
  lines: OrderLine[];
}

type Status = "loading" | "ready" | "error";

function MyOrders() {
  const { user, loading: authLoading } = useAuth();
  const [orders, setOrders] = useState<OrderSummary[]>([]);
  const [status, setStatus] = useState<Status>("loading");

  useEffect(() => {
    if (!user) {
      return;
    }

    let cancelled = false;

    async function loadOrders() {
      try {
        const response = await fetch("/api/orders/mine");
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`);
        }
        const data = (await response.json()) as OrderSummary[];
        if (!cancelled) {
          setOrders(data);
          setStatus("ready");
        }
      } catch (error) {
        console.error(error);
        if (!cancelled) {
          setStatus("error");
        }
      }
    }

    loadOrders();

    return () => {
      cancelled = true;
    };
  }, [user]);

  if (authLoading) {
    return (
      <section className="section">
        <div className="container">
          <p>Loading...</p>
        </div>
      </section>
    );
  }

  if (!user) {
    return (
      <section className="section">
        <div className="container">
          <h1 className="page-title">My orders</h1>
          <p>Sign in to see the orders placed with your account.</p>
          <Link className="button" to="/login?next=/orders">Sign in</Link>
        </div>
      </section>
    );
  }

  return (
    <section className="section">
      <div className="container">
        <h1 className="page-title">My orders</h1>

        {status === "loading" && <p>Loading your orders...</p>}
        {status === "error" && <p>Sorry, your orders could not be loaded.</p>}

        {status === "ready" && orders.length === 0 && (
          <>
            <p>You haven't placed any orders with this account yet.</p>
            <Link className="button" to="/shop">Browse the shop</Link>
          </>
        )}

        {status === "ready" && orders.length > 0 && (
          <div className="order-list">
            {orders.map((order) => (
              <article className="order-card" key={order.orderNumber}>
                <header className="order-card-header">
                  <h2>{order.orderNumber}</h2>
                  <p>{new Date(order.createdAt).toLocaleDateString()}</p>
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

export default MyOrders;
