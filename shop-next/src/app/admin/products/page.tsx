import type { Metadata } from "next";
import Link from "next/link";
import { deleteProductAction } from "@/app/admin/actions";
import { requireOwner } from "@/lib/auth";
import { getProducts } from "@/lib/products";

export const metadata: Metadata = {
  title: "Products",
};

export default async function AdminProductsPage(props: PageProps<"/admin/products">) {
  await requireOwner();

  const query = await props.searchParams;
  const error = typeof query.error === "string" ? query.error : "";
  const products = await getProducts();

  return (
    <>
      <div className="admin-heading">
        <h1 className="page-title">Products</h1>
        <Link className="button" href="/admin/products/new">Add product</Link>
      </div>

      {error && (
        <p className="field-error" role="alert">
          {error}
        </p>
      )}

      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Product</th>
              <th>Category</th>
              <th>Price</th>
              <th>Stock</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {products.map((product) => (
              <tr key={product.id}>
                <td>{product.name}</td>
                <td>{product.category}</td>
                <td>${product.price}</td>
                <td>{product.stock === 0 ? "Out of stock" : product.stock}</td>
                <td>
                  <div className="row-actions">
                    <Link href={`/admin/products/${product.id}`}>Edit</Link>
                    <form action={deleteProductAction}>
                      <input type="hidden" name="id" value={product.id} />
                      <button className="link-button" type="submit">
                        Delete
                      </button>
                    </form>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
