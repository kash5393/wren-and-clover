import { Link } from "react-router";
import ProductCard from "../components/ProductCard";
import { useProducts } from "../hooks/useProducts";

const featuredIds = ["lavender-oat-soap", "whipped-body-butter", "self-care-gift-box"];

function Home() {
  const { products } = useProducts();
  const featured = products.filter((product) => featuredIds.includes(product.id));

  return (
    <>
      <section className="hero">
        <div className="container hero-inner">
          <div>
            <h1>Small-batch organic soap and skincare</h1>
            <p>Handmade with simple ingredients you can pronounce.</p>
            <Link className="button" to="/shop">Shop now</Link>
          </div>
          <div className="photo hero-photo">Banner photo</div>
        </div>
      </section>

      <section className="section">
        <div className="container">
          <h2>Featured</h2>
          <div className="product-grid">
            {featured.map((product) => (
              <ProductCard key={product.id} product={product} />
            ))}
          </div>
        </div>
      </section>

      <section className="section story">
        <div className="container story-inner">
          <div className="photo">Photo of the maker</div>
          <div>
            <h2>Our story</h2>
            <p>
              Every bar is made by hand in small batches, using organic oils and
              botanicals from local growers.
            </p>
            <Link className="button" to="/about">Read more</Link>
          </div>
        </div>
      </section>
    </>
  );
}

export default Home;
