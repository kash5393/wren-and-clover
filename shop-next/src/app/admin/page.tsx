import Link from "next/link";
import { getDashboardStats } from "@/lib/admin";
import { requireOwner } from "@/lib/auth";

export default async function AdminDashboardPage() {
  await requireOwner();
  const stats = await getDashboardStats();

  return (
    <>
      <h1 className="page-title">Dashboard</h1>

      <div className="stat-grid">
        <div className="stat-card">
          <p className="stat-label">Total sales</p>
          <p className="stat-value">${stats.salesTotal}</p>
        </div>
        <div className="stat-card">
          <p className="stat-label">Orders</p>
          <p className="stat-value">{stats.orderCount}</p>
        </div>
        <div className="stat-card">
          <p className="stat-label">Waiting to ship</p>
          <p className="stat-value">{stats.newOrderCount}</p>
        </div>
        <div className="stat-card">
          <p className="stat-label">Messages</p>
          <p className="stat-value">{stats.messageCount}</p>
        </div>
      </div>

      <div className="admin-columns">
        <div>
          <h2>Low stock</h2>
          {stats.lowStock.length === 0 ? (
            <p>Every product has 10 or more in stock.</p>
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Product</th>
                    <th>In stock</th>
                  </tr>
                </thead>
                <tbody>
                  {stats.lowStock.map((product) => (
                    <tr key={product.id}>
                      <td>
                        <Link href={`/admin/products/${product.id}`}>{product.name}</Link>
                      </td>
                      <td>{product.stock}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

        <div>
          <h2>Best sellers</h2>
          {stats.bestSellers.length === 0 ? (
            <p>No sales yet.</p>
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Product</th>
                    <th>Units sold</th>
                    <th>Revenue</th>
                  </tr>
                </thead>
                <tbody>
                  {stats.bestSellers.map((product) => (
                    <tr key={product.name}>
                      <td>{product.name}</td>
                      <td>{product.unitsSold}</td>
                      <td>${product.revenue}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </>
  );
}
