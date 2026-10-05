import type { Product } from "../types";

interface ProductCardProps {
  product: Product;
}

function ProductCard({ product }: ProductCardProps) {
  return (
    <article className="product-card">
      <a href={`/products/${product.id}`}>
        <div className="photo">
          Product photo
          {product.stock === 0 && <span className="badge">Out of stock</span>}
        </div>
        <h3>{product.name}</h3>
        <p className="price">${product.price}</p>
      </a>
    </article>
  );
}

export default ProductCard;
