#!/usr/bin/env bash
# Unit 4, last step: checkout, contact, about and shipping pages for the React shop.
# Run from inside the shop-react folder:  bash unit4-checkout.sh
set -e
if [ ! -f vite.config.ts ]; then echo "Run this inside the shop-react folder (vite.config.ts not found)."; exit 1; fi
if ! grep -q "clearCart" src/context/CartContext.tsx; then echo "src/context/CartContext.tsx has no clearCart yet. Finish the Clear cart step first."; exit 1; fi
mkdir -p src/components src/pages

cat > src/components/FormField.tsx << 'WREN_EOF'
interface FormFieldProps {
  id: string;
  label: string;
  value: string;
  onChange: (value: string) => void;
  error?: string;
  type?: string;
  multiline?: boolean;
}

function FormField({
  id,
  label,
  value,
  onChange,
  error,
  type = "text",
  multiline = false,
}: FormFieldProps) {
  return (
    <div className="field">
      <label htmlFor={id}>{label}</label>
      {multiline ? (
        <textarea
          id={id}
          rows={6}
          value={value}
          aria-invalid={error ? true : undefined}
          onChange={(event) => onChange(event.target.value)}
        />
      ) : (
        <input
          id={id}
          type={type}
          value={value}
          aria-invalid={error ? true : undefined}
          onChange={(event) => onChange(event.target.value)}
        />
      )}
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
  address: string;
  city: string;
  postcode: string;
}

type CheckoutErrors = Partial<Record<keyof CheckoutForm, string>>;

const emptyForm: CheckoutForm = {
  name: "",
  email: "",
  address: "",
  city: "",
  postcode: "",
};

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function validate(form: CheckoutForm): CheckoutErrors {
  const errors: CheckoutErrors = {};

  if (form.name.trim() === "") {
    errors.name = "Please enter your name.";
  }
  if (!emailPattern.test(form.email.trim())) {
    errors.email = "Please enter a valid email address.";
  }
  if (form.address.trim() === "") {
    errors.address = "Please enter your street address.";
  }
  if (form.city.trim() === "") {
    errors.city = "Please enter your city.";
  }
  if (form.postcode.trim() === "") {
    errors.postcode = "Please enter your postcode.";
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
              id="postcode"
              label="Postcode"
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

cat > src/pages/Contact.tsx << 'WREN_EOF'
import { useState } from "react";
import type { FormEvent } from "react";
import FormField from "../components/FormField";

interface ContactErrors {
  name?: string;
  email?: string;
  message?: string;
}

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function Contact() {
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [message, setMessage] = useState("");
  const [errors, setErrors] = useState<ContactErrors>({});
  const [sentTo, setSentTo] = useState<string | null>(null);

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const foundErrors: ContactErrors = {};
    if (name.trim() === "") {
      foundErrors.name = "Please enter your name.";
    }
    if (!emailPattern.test(email.trim())) {
      foundErrors.email = "Please enter a valid email address.";
    }
    if (message.trim().length < 10) {
      foundErrors.message = "Please write at least 10 characters.";
    }

    setErrors(foundErrors);
    if (Object.keys(foundErrors).length > 0) {
      setSentTo(null);
      return;
    }

    setSentTo(name.trim());
    setName("");
    setEmail("");
    setMessage("");
  }

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Contact</h1>
        <p>
          Questions about an order or an ingredient? Send a message and we'll
          reply within two working days.
        </p>

        <form className="contact-form" noValidate onSubmit={handleSubmit}>
          <FormField id="name" label="Name" value={name} error={errors.name} onChange={setName} />
          <FormField
            id="email"
            label="Email"
            type="email"
            value={email}
            error={errors.email}
            onChange={setEmail}
          />
          <FormField
            id="message"
            label="Message"
            multiline
            value={message}
            error={errors.message}
            onChange={setMessage}
          />
          <button className="button button-full" type="submit">
            Send message
          </button>
          {sentTo && (
            <p className="form-status" role="status">
              Thanks, {sentTo}. Your message passed all the checks.
            </p>
          )}
        </form>
      </div>
    </section>
  );
}

export default Contact;
WREN_EOF

cat > src/pages/About.tsx << 'WREN_EOF'
import { Link } from "react-router";

function About() {
  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">About</h1>
        <div className="photo">Photo of the maker at work</div>
        <h2>How it started</h2>
        <p>
          Wren &amp; Clover began at a kitchen table, with a batch of lavender
          soap made for a family member with sensitive skin. Friends asked for
          more, and a market stall followed.
        </p>
        <h2>How it's made</h2>
        <p>
          Every product is made by hand in small batches, using organic oils,
          butters and botanicals. Nothing has synthetic fragrance or colouring.
        </p>
        <h2>Find us in person</h2>
        <p>We're at the farmers' market most Saturdays. Come and say hello.</p>
        <Link className="button" to="/shop">Browse the shop</Link>
      </div>
    </section>
  );
}

export default About;
WREN_EOF

cat > src/pages/Shipping.tsx << 'WREN_EOF'
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
WREN_EOF

cat > src/pages/NotFound.tsx << 'WREN_EOF'
import { Link } from "react-router";

function NotFound() {
  return (
    <section className="section">
      <div className="container">
        <h1 className="page-title">Page not found</h1>
        <p>Sorry, there is nothing at this address.</p>
        <Link className="button" to="/shop">Go to the shop</Link>
      </div>
    </section>
  );
}

export default NotFound;
WREN_EOF

cat > src/App.tsx << 'WREN_EOF'
import { Route, Routes } from "react-router";
import Layout from "./components/Layout";
import About from "./pages/About";
import CartPage from "./pages/CartPage";
import Checkout from "./pages/Checkout";
import Contact from "./pages/Contact";
import Home from "./pages/Home";
import NotFound from "./pages/NotFound";
import ProductPage from "./pages/ProductPage";
import Shipping from "./pages/Shipping";
import Shop from "./pages/Shop";

function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route path="/" element={<Home />} />
        <Route path="/shop" element={<Shop />} />
        <Route path="/products/:id" element={<ProductPage />} />
        <Route path="/cart" element={<CartPage />} />
        <Route path="/checkout" element={<Checkout />} />
        <Route path="/about" element={<About />} />
        <Route path="/contact" element={<Contact />} />
        <Route path="/shipping" element={<Shipping />} />
        <Route path="*" element={<NotFound />} />
      </Route>
    </Routes>
  );
}

export default App;
WREN_EOF

# Add a Checkout button to the cart page, keeping your own edits to that file.
grep -q 'to="/checkout"' src/pages/CartPage.tsx || perl -pi -e 's|^(\s*)<Link className="button" to="/shop">Continue shopping</Link>|$1<Link className="button" to="/checkout">Checkout</Link>\n$1<Link to="/shop">Continue shopping</Link>|' src/pages/CartPage.tsx

# Checkout styles (added once).
grep -q 'checkout-layout' src/styles.css || cat >> src/styles.css << 'WREN_EOF'

/* Checkout */
.checkout-layout {
  display: grid;
  gap: var(--space-4);
}

.contact-form h2,
.order-summary h2 {
  margin: 0;
}

.order-summary {
  display: grid;
  gap: var(--space-2);
  align-self: start;
  padding: var(--space-3);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius);
}

.order-summary ul {
  display: grid;
  gap: var(--space-1);
  margin: 0;
  padding: 0;
  list-style: none;
}

.order-summary li,
.order-summary-total {
  display: flex;
  justify-content: space-between;
  gap: var(--space-2);
}

.order-summary-total {
  margin: 0;
  padding-top: var(--space-2);
  border-top: 1px solid var(--color-border);
  font-size: 1.15rem;
}

@media (min-width: 768px) {
  .checkout-layout {
    grid-template-columns: 3fr 2fr;
  }
}
WREN_EOF

echo "Done. The dev server picks the changes up by itself."
