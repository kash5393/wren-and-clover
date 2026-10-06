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
