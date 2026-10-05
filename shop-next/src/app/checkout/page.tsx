import type { Metadata } from "next";
import { getCurrentUser } from "@/lib/auth";
import { getSavedShipping } from "@/lib/orders";
import { paymentsEnabled } from "@/lib/payments";
import CheckoutForm from "./CheckoutForm";

export const metadata: Metadata = {
  title: "Checkout",
};

export default async function CheckoutPage() {
  const user = await getCurrentUser();
  const savedShipping = user ? await getSavedShipping(user.id) : null;

  return (
    <section className="section">
      <div className="container">
        <CheckoutForm
          user={user ? { name: user.name, email: user.email } : null}
          savedShipping={savedShipping}
          paymentsOn={paymentsEnabled()}
        />
      </div>
    </section>
  );
}
