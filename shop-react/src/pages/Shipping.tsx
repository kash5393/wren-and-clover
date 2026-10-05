import { Link } from "react-router";

const shippingOptions = [
  { method: "Standard", time: "3 to 5 working days", cost: "$5" },
  { method: "Express", time: "1 to 2 working days", cost: "$12" },
  { method: "Market pickup", time: "Next Saturday", cost: "Free" },
];

function Shipping() {
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
          something arrives damaged, contact us with a photo and we'll replace
          it.
        </p>
        <Link className="button" to="/contact">Contact us</Link>
      </div>
    </section>
  );
}

export default Shipping;
