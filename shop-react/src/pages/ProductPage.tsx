import { Link, useParams } from "react-router";
import ProductCard from "../components/ProductCard";
import { useProducts } from "../hooks/useProducts";

function ProductPage() {
  const { id } = useParams();
  const { products, status } = useProducts();

  if (status === "loading") {
    return (
      <section className="section">
        <div className="container">
          <p>Loading product...</p>
        </div>
      </section>
    );
  }

  const product = products.find((item) => item.id === id);

  if (status === "error" || !product) {
    return (
      <section className="section">
        <div className="container">
          <h1 className="page-title">Product not found</h1>
          <Link className="button" to="/shop">Back to the shop</Link>
        </div>
      </section>
    );
  }

  const inStock = product.stock > 0;
  const related = products
    .filter((item) => item.category === product.category && item.id !== product.id)
    .slice(0, 3);

  return (
    <>
      <section className="section">
        <div className="container">
          <nav className="breadcrumb" aria-label="Breadcrumb">
            <Link to="/shop">Shop</Link> / {product.category} / {product.name}
          </nav>

          <div className="product-layout">
            <div className="photo product-photo">Large product photo</div>

            <div className="product-details">
              <h1>{product.name}</h1>
              <p className="product-price">${product.price}</p>
              <p>
                {product.description} {product.size}.
              </p>

              <form className="product-form">
                <div className="field">
                  <label htmlFor="scent">Scent</label>
                  <select id="scent" name="scent">
                    {product.scents.map((scent) => (
                      <option key={scent}>{scent}</option>
                    ))}
                  </select>
                </div>

                <div className="field">
                  <label htmlFor="quantity">Quantity</label>
                  <input id="quantity" name="quantity" type="number" min="1" defaultValue="1" />
                </div>

                <button className="button button-full" type="button" disabled={!inStock}>
                  {inStock ? "Add to cart" : "Out of stock"}
                </button>
              </form>
            </div>
          </div>
        </div>
      </section>

      <section className="section section-bordered">
        <div className="container">
          <h2>You may also like</h2>
          <div className="product-grid">
            {related.map((item) => (
              <ProductCard key={item.id} product={item} />
            ))}
          </div>
        </div>
      </section>
    </>
  );
}

export default ProductPage;
