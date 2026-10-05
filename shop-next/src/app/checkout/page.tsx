import type { Metadata } from "next";
import CheckoutForm from "./CheckoutForm";

export const metadata: Metadata = {
  title: "Checkout",
};

export default function CheckoutPage() {
  return (
    <section className="section">
      <div className="container">
        <CheckoutForm />
      </div>
    </section>
  );
}
