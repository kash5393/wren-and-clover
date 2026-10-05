import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Shipping and Returns",
};

const shippingOptions = [
  { method: "Standard", time: "3 to 5 working days", cost: "$5" },
  { method: "Express", time: "1 to 2 working days", cost: "$12" },
  { method: "Market pickup", time: "Next Saturday", cost: "Free" },
];

export default function ShippingPage() {
  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Shipping and Returns</h1>

        <h2>Shipping</h2>
        <p>Orders are packed within two working days.</p>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Method</th>
                <th>Delivery time</th>
                <th>Cost</th>
              </tr>
            </thead>
            <tbody>
              {shippingOptions.map((option) => (
                <tr key={option.method}>
                  <td>{option.method}</td>
                  <td>{option.time}</td>
                  <td>{option.cost}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p>Standard shipping is free on orders over $50.</p>

        <h2>Returns</h2>
        <p>
          Unopened products can be returned within 30 days for a refund. If
          something arrives damaged, contact us with a photo and we&apos;ll
          replace it.
        </p>
        <Link className="button" href="/contact">Contact us</Link>
      </div>
    </section>
  );
}
