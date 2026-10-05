"use client";

import { useState } from "react";
import { useCart } from "@/components/CartProvider";
import type { Product } from "@/lib/types";

interface AddToCartFormProps {
  product: Product;
}

export default function AddToCartForm({ product }: AddToCartFormProps) {
  const { addItem } = useCart();
  const [scent, setScent] = useState(product.scents[0] ?? "");
  const [quantity, setQuantity] = useState(1);
  const [justAdded, setJustAdded] = useState(false);

  const inStock = product.stock > 0;

  function handleAdd() {
    addItem(product, scent, quantity);
    setJustAdded(true);
    setTimeout(() => setJustAdded(false), 1500);
  }

  let buttonText = "Add to cart";
  if (!inStock) {
    buttonText = "Out of stock";
  } else if (justAdded) {
    buttonText = "Added to cart";
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
          value={quantity}
          onChange={(event) => setQuantity(Math.max(1, Number(event.target.value) || 1))}
        />
      </div>

      <button className="button button-full" type="button" disabled={!inStock} onClick={handleAdd}>
        {buttonText}
      </button>
    </form>
  );
}
