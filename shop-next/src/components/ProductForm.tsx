"use client";

import Link from "next/link";
import { useActionState } from "react";
import { createProductAction, updateProductAction } from "@/app/admin/actions";
import type { ProductFormState } from "@/app/admin/actions";
import { categories } from "@/lib/types";
import type { Product } from "@/lib/types";

interface ProductFormProps {
  product?: Product;
}

const initialState: ProductFormState = { error: "" };

export default function ProductForm({ product }: ProductFormProps) {
  const isEditing = product !== undefined;
  const [state, formAction, pending] = useActionState(
    isEditing ? updateProductAction : createProductAction,
    initialState
  );

  return (
    <form className="contact-form" action={formAction}>
      <div className="field">
        <label htmlFor="id">Id (used in the web address, such as rose-clay-soap)</label>
        <input id="id" name="id" type="text" defaultValue={product?.id} readOnly={isEditing} required />
      </div>

      <div className="field">
        <label htmlFor="name">Name</label>
        <input id="name" name="name" type="text" defaultValue={product?.name} required />
      </div>

      <div className="field">
        <label htmlFor="category">Category</label>
        <select id="category" name="category" defaultValue={product?.category ?? ""} required>
          <option value="">Select...</option>
          {categories.map((category) => (
            <option key={category} value={category}>
              {category}
            </option>
          ))}
        </select>
      </div>

      <div className="field">
        <label htmlFor="price">Price in dollars</label>
        <input
          id="price"
          name="price"
          type="number"
          min="0.01"
          step="0.01"
          defaultValue={product?.price}
          required
        />
      </div>

      <div className="field">
        <label htmlFor="stock">Stock</label>
        <input id="stock" name="stock" type="number" min="0" step="1" defaultValue={product?.stock ?? 0} required />
      </div>

      <div className="field">
        <label htmlFor="size">Size (such as 4.5 oz bar)</label>
        <input id="size" name="size" type="text" defaultValue={product?.size} required />
      </div>

      <div className="field">
        <label htmlFor="scents">Scents, separated by commas</label>
        <input id="scents" name="scents" type="text" defaultValue={product?.scents.join(", ")} required />
      </div>

      <div className="field">
        <label htmlFor="description">Description</label>
        <textarea id="description" name="description" rows={4} defaultValue={product?.description} required />
      </div>

      {state.error && (
        <p className="field-error" role="alert">
          {state.error}
        </p>
      )}

      <div className="cart-actions">
        <button className="button" type="submit" disabled={pending}>
          {pending ? "Saving..." : isEditing ? "Save changes" : "Add product"}
        </button>
        <Link href="/admin/products">Cancel</Link>
      </div>
    </form>
  );
}
