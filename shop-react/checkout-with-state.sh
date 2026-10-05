#!/usr/bin/env bash
# Checkout with phone, state dropdown and ZIP code. Run inside shop-react:  bash checkout-with-state.sh
set -e
if [ ! -f vite.config.ts ]; then echo "Run this inside the shop-react folder."; exit 1; fi
cat > src/components/FormField.tsx << 'WREN_EOF'
interface FormFieldProps {
  id: string;
  label: string;
  value: string;
  onChange: (value: string) => void;
  error?: string;
  type?: string;
  multiline?: boolean;
  options?: string[];
}

function FormField({
  id,
  label,
  value,
  onChange,
  error,
  type = "text",
  multiline = false,
  options,
}: FormFieldProps) {
  const invalid = error ? true : undefined;
  let control;

  if (options) {
    control = (
      <select
        id={id}
        value={value}
        aria-invalid={invalid}
        onChange={(event) => onChange(event.target.value)}
      >
        <option value="">Select...</option>
        {options.map((option) => (
          <option key={option} value={option}>
            {option}
          </option>
        ))}
      </select>
    );
  } else if (multiline) {
    control = (
      <textarea
        id={id}
        rows={6}
        value={value}
        aria-invalid={invalid}
        onChange={(event) => onChange(event.target.value)}
      />
    );
  } else {
    control = (
      <input
        id={id}
        type={type}
        value={value}
        aria-invalid={invalid}
        onChange={(event) => onChange(event.target.value)}
      />
    );
  }

  return (
    <div className="field">
      <label htmlFor={id}>{label}</label>
      {control}
      {error && <span className="field-error">{error}</span>}
    </div>
  );
}

export default FormField;
WREN_EOF

cat > src/pages/Checkout.tsx << 'WREN_EOF'
import { useState } from "react";
import type { FormEvent } from "react";
import { Link } from "react-router";
import FormField from "../components/FormField";
import { useCart } from "../context/CartContext";

interface CheckoutForm {
  name: string;
  email: string;
  phone: string;
  address: string;
  city: string;
  state: string;
  postcode: string;
}

type CheckoutErrors = Partial<Record<keyof CheckoutForm, string>>;

const emptyForm: CheckoutForm = {
  name: "",
  email: "",
  phone: "",
  address: "",
  city: "",
  state: "",
  postcode: "",
};

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const phonePattern = /^[0-9+()\-\s]{7,}$/;
const zipPattern = /^\d{5}(-\d{4})?$/;

const usStates = [
  "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL",
  "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME",
  "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH",
  "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI",
  "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI",
  "WY",
];

function validate(form: CheckoutForm): CheckoutErrors {
  const errors: CheckoutErrors = {};

  if (form.name.trim() === "") {
    errors.name = "Please enter your name.";
  }
  if (!emailPattern.test(form.email.trim())) {
    errors.email = "Please enter a valid email address.";
  }
  if (!phonePattern.test(form.phone.trim())) {
    errors.phone = "Please enter a valid phone number.";
  }
  if (form.address.trim() === "") {
    errors.address = "Please enter your street address.";
  }
  if (form.city.trim() === "") {
    errors.city = "Please enter your city.";
  }
  if (!usStates.includes(form.state)) {
    errors.state = "Please choose your state.";
  }
  if (!zipPattern.test(form.postcode.trim())) {
    errors.postcode = "Please enter a valid ZIP code.";
  }

  return errors;
}

function Checkout() {
  const { items, total, clearCart } = useCart();
  const [form, setForm] = useState<CheckoutForm>(emptyForm);
  const [errors, setErrors] = useState<CheckoutErrors>({});
  const [orderNumber, setOrderNumber] = useState<string | null>(null);

  function updateField(field: keyof CheckoutForm, value: string) {
    setForm((current) => ({ ...current, [field]: value }));
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const foundErrors = validate(form);
    setErrors(foundErrors);
    if (Object.keys(foundErrors).length > 0) {
      return;
    }

    setOrderNumber(`WC-${Date.now().toString().slice(-6)}`);
    clearCart();
  }

  if (orderNumber) {
    return (
      <section className="section">
        <div className="container prose">
          <h1 className="page-title">Thank you, {form.name.trim()}</h1>
          <p>
            Your order <strong>{orderNumber}</strong> has been received. A
            confirmation will be sent to {form.email.trim()}.
          </p>
          <p>
            This is a practice checkout: no payment was taken and nothing will
            be shipped.
          </p>
          <Link className="button" to="/shop">Back to the shop</Link>
        </div>
      </section>
    );
  }

  if (items.length === 0) {
    return (
      <section className="section">
        <div className="container">
          <h1 className="page-title">Checkout</h1>
          <p>Your cart is empty, so there is nothing to check out.</p>
          <Link className="button" to="/shop">Browse the shop</Link>
        </div>
      </section>
    );
  }

  return (
    <section className="section">
      <div className="container">
        <h1 className="page-title">Checkout</h1>

        <div className="checkout-layout">
          <form className="contact-form" noValidate onSubmit={handleSubmit}>
            <h2>Shipping details</h2>
            <FormField
              id="name"
              label="Full name"
              value={form.name}
              error={errors.name}
              onChange={(value) => updateField("name", value)}
            />
            <FormField
              id="email"
              label="Email"
              type="email"
              value={form.email}
              error={errors.email}
              onChange={(value) => updateField("email", value)}
            />
            <FormField
              id="phone"
              label="Phone"
              type="tel"
              value={form.phone}
              error={errors.phone}
              onChange={(value) => updateField("phone", value)}
            />
            <FormField
              id="address"
              label="Street address"
              value={form.address}
              error={errors.address}
              onChange={(value) => updateField("address", value)}
            />
            <FormField
              id="city"
              label="City"
              value={form.city}
              error={errors.city}
              onChange={(value) => updateField("city", value)}
            />
            <FormField
              id="state"
              label="State"
              options={usStates}
              value={form.state}
              error={errors.state}
              onChange={(value) => updateField("state", value)}
            />
            <FormField
              id="postcode"
              label="ZIP code"
              value={form.postcode}
              error={errors.postcode}
              onChange={(value) => updateField("postcode", value)}
            />
            <button className="button button-full" type="submit">
              Place order
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
            <Link to="/cart">Edit cart</Link>
          </aside>
        </div>
      </div>
    </section>
  );
}

export default Checkout;
WREN_EOF

echo "Done. FormField.tsx and Checkout.tsx are updated."
