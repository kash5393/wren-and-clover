import Link from "next/link";
import type { Product } from "@/lib/types";

interface ProductCardProps {
  product: Product;
}

export default function ProductCard({ product }: ProductCardProps) {
  return (
    <article className="product-card">
      <Link href={`/products/${product.id}`}>
        <div className="photo">
          Product photo
          {product.stock === 0 && <span className="badge">Out of stock</span>}
        </div>
        <h3>{product.name}</h3>
        <p className="price">${product.price}</p>
        <p className="product-size">{product.size}</p>
      </Link>
    </article>
  );
}
