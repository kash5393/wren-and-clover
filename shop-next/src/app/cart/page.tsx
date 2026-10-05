"use client";

import Link from "next/link";
import { useCart } from "@/components/CartProvider";

export default function CartPage() {
  const { items, total, ready, updateQuantity, removeItem, clearCart } = useCart();

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
              {items.map((item, index) => (
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
                      onChange={(event) => updateQuantity(index, Number(event.target.value) || 1)}
                    />
                  </td>
                  <td>${item.price * item.quantity}</td>
                  <td>
                    <button className="link-button" type="button" onClick={() => removeItem(index)}>
                      Remove
                    </button>
                  </td>
                </tr>
              ))}
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
