#!/usr/bin/env bash
# Unit 7: make guest checkout explicit, and return to checkout after signing in.
# Run from inside the shop-react folder:  bash unit7-guest-checkout.sh
set -e
if [ ! -f src/context/AuthContext.tsx ]; then echo "Run this inside the shop-react folder, after the login pages step."; exit 1; fi
cat > src/pages/Checkout.tsx << 'WREN_EOF'
import { useState } from "react";
import type { FormEvent } from "react";
import { Link } from "react-router";
import FormField from "../components/FormField";
import { useAuth } from "../context/AuthContext";
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

interface PlacedOrder {
  orderNumber: string;
  total: number;
}

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
  const { user } = useAuth();
  const [form, setForm] = useState<CheckoutForm>({
    ...emptyForm,
    name: user?.name ?? "",
    email: user?.email ?? "",
  });
  const [errors, setErrors] = useState<CheckoutErrors>({});
  const [placedOrder, setPlacedOrder] = useState<PlacedOrder | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [serverError, setServerError] = useState("");

  function updateField(field: keyof CheckoutForm, value: string) {
    setForm((current) => ({ ...current, [field]: value }));
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const foundErrors = validate(form);
    setErrors(foundErrors);
    if (Object.keys(foundErrors).length > 0) {
      return;
    }

    setSubmitting(true);
    setServerError("");

    try {
      const response = await fetch("/api/orders", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          customer: form,
          items: items.map((item) => ({
            id: item.id,
            scent: item.scent,
            quantity: item.quantity,
          })),
        }),
      });

      if (!response.ok) {
        const problem = (await response.json()) as { error?: string };
        setServerError(problem.error ?? "The order could not be placed.");
        return;
      }

      setPlacedOrder((await response.json()) as PlacedOrder);
      clearCart();
    } catch (error) {
      console.error(error);
      setServerError("Could not reach the shop. Please try again.");
    } finally {
      setSubmitting(false);
    }
  }

  if (placedOrder) {
    return (
      <section className="section">
        <div className="container prose">
          <h1 className="page-title">Thank you, {form.name.trim()}</h1>
          <p>
            Your order <strong>{placedOrder.orderNumber}</strong> for{" "}
            <strong>${placedOrder.total}</strong> has been received. A
            confirmation will be sent to {form.email.trim()}.
          </p>
          <p>
            This is a practice checkout: no payment was taken and nothing will
            be shipped.
          </p>
          {!user && (
            <p>
              Want to see your orders in one place next time?{" "}
              <Link to="/signup">Create an account</Link>. It's optional.
            </p>
          )}
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

        {user ? (
          <p className="checkout-notice">
            Signed in as <strong>{user.name}</strong> ({user.email}).
          </p>
        ) : (
          <p className="checkout-notice">
            You're checking out as a guest, with no account needed. Have an
            account? <Link to="/login?next=/checkout">Sign in</Link> to fill in
            your details.
          </p>
        )}

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
            {serverError && (
              <p className="field-error" role="alert">
                {serverError}
              </p>
            )}
            <button className="button button-full" type="submit" disabled={submitting}>
              {submitting ? "Placing order..." : "Place order"}
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

cat > src/pages/Login.tsx << 'WREN_EOF'
import { useState } from "react";
import type { FormEvent } from "react";
import { Link, useNavigate, useSearchParams } from "react-router";
import FormField from "../components/FormField";
import { useAuth } from "../context/AuthContext";

function Login() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const requested = searchParams.get("next") ?? "/";
  const nextPage = requested.startsWith("/") && !requested.startsWith("//") ? requested : "/";
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    const problem = await login(email.trim(), password);
    setSubmitting(false);

    if (problem) {
      setError(problem);
      return;
    }
    navigate(nextPage);
  }

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Sign in</h1>

        <form className="contact-form" noValidate onSubmit={handleSubmit}>
          <FormField id="email" label="Email" type="email" value={email} onChange={setEmail} />
          <FormField
            id="password"
            label="Password"
            type="password"
            value={password}
            onChange={setPassword}
          />
          {error && (
            <p className="field-error" role="alert">
              {error}
            </p>
          )}
          <button className="button button-full" type="submit" disabled={submitting}>
            {submitting ? "Signing in..." : "Sign in"}
          </button>
        </form>

        <p>
          New here? <Link to={`/signup?next=${encodeURIComponent(nextPage)}`}>Create an account</Link>
        </p>
      </div>
    </section>
  );
}

export default Login;
WREN_EOF

cat > src/pages/Signup.tsx << 'WREN_EOF'
import { useState } from "react";
import type { FormEvent } from "react";
import { Link, useNavigate, useSearchParams } from "react-router";
import FormField from "../components/FormField";
import { useAuth } from "../context/AuthContext";

function Signup() {
  const { signup } = useAuth();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const requested = searchParams.get("next") ?? "/";
  const nextPage = requested.startsWith("/") && !requested.startsWith("//") ? requested : "/";
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (password.length < 8) {
      setError("Password must be at least 8 characters.");
      return;
    }

    setSubmitting(true);
    const problem = await signup(name.trim(), email.trim(), password);
    setSubmitting(false);

    if (problem) {
      setError(problem);
      return;
    }
    navigate(nextPage);
  }

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Create an account</h1>

        <form className="contact-form" noValidate onSubmit={handleSubmit}>
          <FormField id="name" label="Name" value={name} onChange={setName} />
          <FormField id="email" label="Email" type="email" value={email} onChange={setEmail} />
          <FormField
            id="password"
            label="Password (at least 8 characters)"
            type="password"
            value={password}
            onChange={setPassword}
          />
          {error && (
            <p className="field-error" role="alert">
              {error}
            </p>
          )}
          <button className="button button-full" type="submit" disabled={submitting}>
            {submitting ? "Creating account..." : "Create account"}
          </button>
        </form>

        <p>
          Already have an account? <Link to={`/login?next=${encodeURIComponent(nextPage)}`}>Sign in</Link>
        </p>
      </div>
    </section>
  );
}

export default Signup;
WREN_EOF

grep -q "checkout-notice" src/styles.css || cat >> src/styles.css << 'WREN_EOF'

/* Guest or signed-in notice on the checkout page */
.checkout-notice {
  margin: 0 0 var(--space-3);
  padding: var(--space-2);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius);
}
WREN_EOF

echo "Done. The dev server picks the changes up by itself."
