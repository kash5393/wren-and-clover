import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import AddToCartForm from "@/components/AddToCartForm";
import ProductCard from "@/components/ProductCard";
import { getProduct, getRelatedProducts } from "@/lib/products";

export async function generateMetadata(props: PageProps<"/products/[id]">): Promise<Metadata> {
  const { id } = await props.params;
  const product = await getProduct(id);

  if (!product) {
    return { title: "Product not found" };
  }

  return {
    title: product.name,
    description: product.description,
  };
}

export default async function ProductPage(props: PageProps<"/products/[id]">) {
  const { id } = await props.params;
  const product = await getProduct(id);

  if (!product) {
    notFound();
  }

  const related = await getRelatedProducts(product);

  return (
    <>
      <section className="section">
        <div className="container">
          <nav className="breadcrumb" aria-label="Breadcrumb">
            <Link href="/shop">Shop</Link> /{" "}
            <Link href={`/shop?category=${encodeURIComponent(product.category)}`}>
              {product.category}
            </Link>{" "}
            / {product.name}
          </nav>

          <div className="product-layout">
            <div className="photo product-photo">Large product photo</div>

            <div className="product-details">
              <h1>{product.name}</h1>
              <p className="product-price">${product.price}</p>
              <p>
                {product.description} {product.size}.
              </p>
              <AddToCartForm key={product.id} product={product} />
            </div>
          </div>
        </div>
      </section>

      {related.length > 0 && (
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
      )}
    </>
  );
}
