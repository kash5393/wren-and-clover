import type { Metadata } from "next";
import ProductForm from "@/components/ProductForm";
import { requireOwner } from "@/lib/auth";

export const metadata: Metadata = {
  title: "Add product",
};

export default async function NewProductPage() {
  await requireOwner();

  return (
    <div className="prose">
      <h1 className="page-title">Add product</h1>
      <ProductForm />
    </div>
  );
}
