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

  const inCart = quantityInCart(items, product.id);
  const available = availableToAdd(items, product);
  const soldOut = product.stock === 0;
  const canAdd = available > 0;
  const chosen = Math.min(quantity, Math.max(1, available));

  function handleAdd() {
    if (!canAdd) {
      return;
    }
    addItem(product, scent, chosen);
    setQuantity(1);
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

  let stockNote = "";
  if (!soldOut) {
    stockNote = product.stock <= 10 ? `Only ${product.stock} left in stock.` : `${product.stock} in stock.`;
    if (inCart > 0) {
      stockNote += ` You have ${inCart} in your cart.`;
    }
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
          max={Math.max(1, available)}
          value={chosen}
          disabled={!canAdd}
          aria-describedby="stock-note"
          onChange={(event) => {
            const typed = Math.floor(Number(event.target.value)) || 1;
            setQuantity(Math.min(Math.max(1, typed), Math.max(1, available)));
          }}
        />
        <span id="stock-note" className="stock-note" aria-live="polite">
          {stockNote}
        </span>
      </div>

      <button className="button button-full" type="button" disabled={!canAdd} onClick={handleAdd}>
        {buttonText}
      </button>
    </form>
  );
}
