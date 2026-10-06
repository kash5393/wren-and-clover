#!/usr/bin/env bash
# Only mention the stock level when a customer asks for more than is available.
# Run from inside the shop-next folder:  bash unit10-stock-message.sh
set -e
if ! grep -q "availableToAdd" src/lib/cart-math.ts 2>/dev/null; then echo "Run this inside the shop-next folder, after the stock limit fix."; exit 1; fi
cat > "src/components/AddToCartForm.tsx" << 'WREN_EOF'
"use client";

import { useState } from "react";
import { useCart } from "@/components/CartProvider";
import { availableToAdd, quantityInCart } from "@/lib/cart-math";
import type { Product } from "@/lib/types";

interface AddToCartFormProps {
  product: Product;
}

export default function AddToCartForm({ product }: AddToCartFormProps) {
  const { items, addItem } = useCart();
  const [scent, setScent] = useState(product.scents[0] ?? "");
  const [quantity, setQuantity] = useState(1);
  const [justAdded, setJustAdded] = useState(false);
  const [overLimit, setOverLimit] = useState(false);

  const inCart = quantityInCart(items, product.id);
  const available = availableToAdd(items, product);
  const soldOut = product.stock === 0;
  const canAdd = available > 0;
  const chosen = Math.min(quantity, Math.max(1, available));

  function handleQuantityChange(value: string) {
    const typed = Math.max(1, Math.floor(Number(value)) || 1);
    setOverLimit(typed > available);
    setQuantity(Math.min(typed, Math.max(1, available)));
  }

  function handleAdd() {
    if (!canAdd) {
      return;
    }
    addItem(product, scent, chosen);
    setQuantity(1);
    setOverLimit(false);
    setJustAdded(true);
    setTimeout(() => setJustAdded(false), 1500);
  }

  let buttonText = "Add to cart";
  if (soldOut) {
    buttonText = "Out of stock";
  } else if (justAdded) {
    buttonText = "Added to cart";
  } else if (!canAdd) {
    buttonText = "All available stock is in your cart";
  }

  // The stock figure is only mentioned when the customer asks for more than there is.
  let limitNote = "";
  if (overLimit && canAdd) {
    limitNote =
      inCart > 0
        ? `Sorry, only ${available} more available. You already have ${inCart} in your cart.`
        : `Sorry, only ${available} available.`;
  }

  return (
    <form className="product-form">
      <div className="field">
        <label htmlFor="scent">Scent</label>
        <select id="scent" value={scent} onChange={(event) => setScent(event.target.value)}>
          {product.scents.map((option) => (
            <option key={option}>{option}</option>
          ))}
        </select>
      </div>

      <div className="field">
        <label htmlFor="quantity">Quantity</label>
        <input
          id="quantity"
          type="number"
          min="1"
          value={chosen}
          disabled={!canAdd}
          aria-describedby="limit-note"
          onChange={(event) => handleQuantityChange(event.target.value)}
        />
        <span id="limit-note" className="stock-note stock-note-limit" role="status">
          {limitNote}
        </span>
      </div>

      <button className="button button-full" type="button" disabled={!canAdd} onClick={handleAdd}>
        {buttonText}
      </button>
    </form>
  );
}
WREN_EOF

cat > "src/app/cart/page.tsx" << 'WREN_EOF'
"use client";

import Link from "next/link";
import { useState } from "react";
import { useCart } from "@/components/CartProvider";
import { maxForLine } from "@/lib/cart-math";

export default function CartPage() {
  const { items, total, ready, updateQuantity, removeItem, clearCart } = useCart();
  const [limitedLine, setLimitedLine] = useState<number | null>(null);

  if (!ready) {
    return (
      <section className="section">
        <div className="container">
          <h1 className="page-title">Your cart</h1>
          <p>Loading your cart...</p>
        </div>
      </section>
    );
  }

  if (items.length === 0) {
    return (
      <section className="section">
        <div className="container">
          <h1 className="page-title">Your cart</h1>
          <p>Your cart is empty.</p>
          <Link className="button" href="/shop">Browse the shop</Link>
        </div>
      </section>
    );
  }

  return (
    <section className="section">
      <div className="container">
        <h1 className="page-title">Your cart</h1>

        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Product</th>
                <th>Price</th>
                <th>Quantity</th>
                <th>Total</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              {items.map((item, index) => {
                const max = maxForLine(items, index);

                return (
                <tr key={`${item.id}-${item.scent}`}>
                  <td>
                    <Link href={`/products/${item.id}`}>{item.name}</Link>
                    <br />
                    <span className="cart-scent">{item.scent}</span>
                  </td>
                  <td>${item.price}</td>
                  <td>
                    <input
                      className="cart-qty"
                      type="number"
                      min="1"
                      value={item.quantity}
                      aria-label={`Quantity for ${item.name}`}
                      onChange={(event) => {
                        const wanted = Number(event.target.value) || 1;
                        setLimitedLine(max !== null && wanted > max ? index : null);
                        updateQuantity(index, wanted);
                      }}
                    />
                    {limitedLine === index && max !== null && (
                      <span className="stock-note stock-note-limit" role="status">
                        Sorry, only {max} available.
                      </span>
                    )}
                  </td>
                  <td>${item.price * item.quantity}</td>
                  <td>
                    <button
                      className="link-button"
                      type="button"
                      onClick={() => {
                        setLimitedLine(null);
                        removeItem(index);
                      }}
                    >
                      Remove
                    </button>
                  </td>
                </tr>
                );
              })}
            </tbody>
          </table>
        </div>

        <p className="cart-total">
          Order total: <strong>${total}</strong>
        </p>
        <div className="cart-actions">
          <Link className="button" href="/checkout">Checkout</Link>
          <Link href="/shop">Continue shopping</Link>
          <button className="link-button" type="button" onClick={clearCart}>
            Clear cart
          </button>
        </div>
      </div>
    </section>
  );
}
WREN_EOF

grep -q "stock-note-limit" src/app/globals.css || cat >> src/app/globals.css << 'WREN_EOF'

.stock-note {
  display: block;
  color: var(--color-muted);
  font-size: 0.9rem;
}

.stock-note-limit {
  color: #8c1d18;
  font-weight: 600;
}
WREN_EOF

npm run lint
npm test
echo
echo "Done. The dev server picks the changes up by itself."
