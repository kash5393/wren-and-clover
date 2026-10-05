"use client";

import Link from "next/link";
import { useState } from "react";
import type { FormEvent } from "react";
import { useCart } from "@/components/CartProvider";
import FormField from "@/components/FormField";
import { emptyCheckoutForm, usStates, validateCheckout } from "@/lib/checkout-validation";
import type { CheckoutErrors, CheckoutFields } from "@/lib/checkout-validation";
import type { ShippingDetails } from "@/lib/types";
import { placeOrder } from "./actions";

interface PlacedOrder {
  orderNumber: string;
  total: number;
}

interface CheckoutFormProps {
  user: { name: string; email: string } | null;
  savedShipping: ShippingDetails | null;
  paymentsOn: boolean;
}

export default function CheckoutForm({ user, savedShipping, paymentsOn }: CheckoutFormProps) {
  const { items, total, ready, clearCart } = useCart();
  const [form, setForm] = useState<CheckoutFields>({
    ...emptyCheckoutForm,
    ...(user ? { name: user.name, email: user.email } : {}),
    ...(savedShipping ?? {}),
  });
  const [errors, setErrors] = useState<CheckoutErrors>({});
  const [placedOrder, setPlacedOrder] = useState<PlacedOrder | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [serverError, setServerError] = useState("");

  function updateField(field: keyof CheckoutFields, value: string) {
    setForm((current) => ({ ...current, [field]: value }));
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const foundErrors = validateCheckout(form);
    setErrors(foundErrors);
    if (Object.keys(foundErrors).length > 0) {
      return;
    }

    setSubmitting(true);
    setServerError("");

    const result = await placeOrder({
      customer: form,
      items: items.map((item) => ({
        id: item.id,
        scent: item.scent,
        quantity: item.quantity,
      })),
    });

    if (!result.ok) {
      setSubmitting(false);
      setServerError(result.error);
      return;
    }

    if (result.kind === "payment") {
      window.location.assign(result.paymentUrl);
      return;
    }

    setSubmitting(false);
    setPlacedOrder({ orderNumber: result.orderNumber, total: result.total });
    clearCart();
  }

  if (placedOrder) {
    return (
      <div className="prose">
        <h1 className="page-title">Thank you, {form.name.trim()}</h1>
        <p>
          Your order <strong>{placedOrder.orderNumber}</strong> for{" "}
          <strong>${placedOrder.total}</strong> has been received. A confirmation
          will be sent to {form.email.trim()}.
        </p>
        <p>This is a practice checkout: no payment was taken and nothing will be shipped.</p>
        {user ? (
          <p>
            You can see this order under <Link href="/orders">My orders</Link>.
          </p>
        ) : (
          <p>
            Want to see your orders in one place next time?{" "}
            <Link href={`/signup?email=${encodeURIComponent(form.email.trim())}`}>
              Create an account
            </Link>
            . It&apos;s optional.
          </p>
        )}
        <Link className="button" href="/shop">Back to the shop</Link>
      </div>
    );
  }

  if (!ready) {
    return (
      <>
        <h1 className="page-title">Checkout</h1>
        <p>Loading your cart...</p>
      </>
    );
  }

  if (items.length === 0) {
    return (
      <>
        <h1 className="page-title">Checkout</h1>
        <p>Your cart is empty, so there is nothing to check out.</p>
        <Link className="button" href="/shop">Browse the shop</Link>
      </>
    );
  }

  return (
    <>
      <h1 className="page-title">Checkout</h1>

      {user ? (
        <p className="checkout-notice">
          Signed in as <strong>{user.name}</strong> ({user.email}).{" "}
          {savedShipping
            ? "We've filled in the details from your last order. Check them before you place this one."
            : "Your details will be remembered after your first order."}
        </p>
      ) : (
        <p className="checkout-notice">
          You&apos;re checking out as a guest, with no account needed. Have an
          account? <Link href="/login?next=/checkout">Sign in</Link> to fill in
          your details.
        </p>
      )}

      <div className="checkout-layout">
        <form className="contact-form" noValidate onSubmit={handleSubmit}>
          <h2>Shipping details</h2>
          <FormField
            id="name"
            label="Full name"
            autoComplete="name"
            value={form.name}
            error={errors.name}
            onChange={(value) => updateField("name", value)}
          />
          <FormField
            id="email"
            label="Email"
            type="email"
            autoComplete="email"
            value={form.email}
            error={errors.email}
            onChange={(value) => updateField("email", value)}
          />
          <FormField
            id="phone"
            label="Phone"
            type="tel"
            autoComplete="tel"
            value={form.phone}
            error={errors.phone}
            onChange={(value) => updateField("phone", value)}
          />
          <FormField
            id="address"
            label="Street address"
            autoComplete="street-address"
            value={form.address}
            error={errors.address}
            onChange={(value) => updateField("address", value)}
          />
          <FormField
            id="city"
            label="City"
            autoComplete="address-level2"
            value={form.city}
            error={errors.city}
            onChange={(value) => updateField("city", value)}
          />
          <FormField
            id="state"
            label="State"
            options={usStates}
            autoComplete="address-level1"
            value={form.state}
            error={errors.state}
            onChange={(value) => updateField("state", value)}
          />
          <FormField
            id="postcode"
            label="ZIP code"
            autoComplete="postal-code"
            value={form.postcode}
            error={errors.postcode}
            onChange={(value) => updateField("postcode", value)}
          />
          {serverError && (
            <p className="field-error" role="alert">
              {serverError}
            </p>
          )}
          <button className="button button-full" type="submit" disabled={submitting}>
            {submitting ? "Please wait..." : paymentsOn ? "Continue to payment" : "Place order"}
          </button>
        </form>

        <aside className="order-summary">
          <h2>Order summary</h2>
          <ul>
            {items.map((item) => (
              <li key={`${item.id}-${item.scent}`}>
                <span>
                  {item.quantity} x {item.name} ({item.scent})
                </span>
                <span>${item.price * item.quantity}</span>
              </li>
            ))}
          </ul>
          <p className="order-summary-total">
            <span>Total</span>
            <strong>${total}</strong>
          </p>
          <Link href="/cart">Edit cart</Link>
        </aside>
      </div>
    </>
  );
}
