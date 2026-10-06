import type { Product } from "@/lib/types";

interface ProductPhotoProps {
  product: Product;
  large?: boolean;
}

export default function ProductPhoto({ product, large = false }: ProductPhotoProps) {
  const outOfStock = product.stock === 0;

  if (!product.imageUrl) {
    return (
      <div className={large ? "photo product-photo" : "photo"}>
        {large ? "Photo coming soon" : "Product photo"}
        {outOfStock && !large && <span className="badge">Out of stock</span>}
      </div>
    );
  }

  return (
    <div className="photo-frame">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        className="photo-image"
        src={product.imageUrl}
        alt={product.name}
        loading={large ? "eager" : "lazy"}
      />
      {outOfStock && !large && <span className="badge">Out of stock</span>}
    </div>
  );
}
