import { Link } from "react-router";
import type { Product } from "../types";

interface ProductCardProps {
  product: Product;
}

function ProductCard({ product }: ProductCardProps) {
  return (
    <article className="product-card">
      <Link to={`/products/${product.id}`}>
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

export default ProductCard;
