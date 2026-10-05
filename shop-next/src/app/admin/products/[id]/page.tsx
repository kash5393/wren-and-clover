import type { Metadata } from "next";
import { notFound } from "next/navigation";
import ProductForm from "@/components/ProductForm";
import { requireOwner } from "@/lib/auth";
import { getProduct } from "@/lib/products";

export const metadata: Metadata = {
  title: "Edit product",
};

export default async function EditProductPage(props: PageProps<"/admin/products/[id]">) {
  await requireOwner();

  const { id } = await props.params;
  const product = await getProduct(id);
  if (!product) {
    notFound();
  }

  return (
    <div className="prose">
      <h1 className="page-title">Edit {product.name}</h1>
      <ProductForm product={product} />
    </div>
  );
}
