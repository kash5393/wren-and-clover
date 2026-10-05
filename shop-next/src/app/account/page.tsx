import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentUser } from "@/lib/auth";
import { countOrdersForUser } from "@/lib/orders";

export const metadata: Metadata = {
  title: "My account",
};

export default async function AccountPage() {
  const user = await getCurrentUser();
  if (!user) {
    redirect("/login?next=/account");
  }

  const orderCount = await countOrdersForUser(user.id);

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">My account</h1>

        <div className="table-wrap">
          <table>
            <tbody>
              <tr>
                <th scope="row">Name</th>
                <td>{user.name}</td>
              </tr>
              <tr>
                <th scope="row">Email</th>
                <td>{user.email}</td>
              </tr>
              <tr>
                <th scope="row">Orders placed</th>
                <td>{orderCount}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <p>
          <Link className="button" href="/orders">View my orders</Link>
        </p>
      </div>
    </section>
  );
}
