"use client";

import { useActionState } from "react";
import { removeProductImageAction, uploadProductImageAction } from "@/app/admin/actions";
import type { ImageFormState } from "@/app/admin/actions";
import type { Product } from "@/lib/types";

interface ProductImageFormProps {
  product: Product;
}

const initialState: ImageFormState = { error: "", saved: false };

export default function ProductImageForm({ product }: ProductImageFormProps) {
  const [state, formAction, pending] = useActionState(uploadProductImageAction, initialState);

  return (
    <div className="image-manager">
      <h2>Photo</h2>

      {product.imageUrl ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img className="image-preview" src={product.imageUrl} alt={`Current photo of ${product.name}`} />
      ) : (
        <p>This product has no photo yet. Shoppers see a grey placeholder.</p>
      )}

      <form className="contact-form" action={formAction}>
        <input type="hidden" name="productId" value={product.id} />
        <div className="field">
          <label htmlFor="photo">
            {product.imageUrl ? "Replace the photo" : "Upload a photo"} (JPEG, PNG or WebP, under 2 MB;
            square photos look best)
          </label>
          <input id="photo" name="photo" type="file" accept="image/jpeg,image/png,image/webp" required />
        </div>

        {state.error && (
          <p className="field-error" role="alert">
            {state.error}
          </p>
        )}
        {state.saved && (
          <p className="form-status" role="status">
            Photo saved.
          </p>
        )}

        <div className="cart-actions">
          <button className="button" type="submit" disabled={pending}>
            {pending ? "Uploading..." : "Upload photo"}
          </button>
        </div>
      </form>

      {product.imageUrl && (
        <form action={removeProductImageAction}>
          <input type="hidden" name="productId" value={product.id} />
          <button className="link-button" type="submit">
            Remove the photo
          </button>
        </form>
      )}
    </div>
  );
}
