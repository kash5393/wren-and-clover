"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { setOrderStatus } from "@/lib/admin";
import { requireOwner } from "@/lib/auth";
import { addStock, createProduct, deleteProduct, updateProduct } from "@/lib/products";

export interface ProductFormState {
  error: string;
}

function readProduct(formData: FormData) {
  return {
    id: String(formData.get("id") ?? ""),
    name: String(formData.get("name") ?? ""),
    category: String(formData.get("category") ?? ""),
    price: Number(formData.get("price")),
    size: String(formData.get("size") ?? ""),
    scents: String(formData.get("scents") ?? "")
      .split(",")
      .map((scent) => scent.trim())
      .filter((scent) => scent !== ""),
    description: String(formData.get("description") ?? ""),
    stock: Number(formData.get("stock")),
  };
}

export async function createProductAction(
  _previous: ProductFormState,
  formData: FormData
): Promise<ProductFormState> {
  await requireOwner();

  const result = await createProduct(readProduct(formData));
  if (!result.ok) {
    return { error: result.error };
  }

  revalidatePath("/admin/products");
  redirect("/admin/products");
}

export async function updateProductAction(
  _previous: ProductFormState,
  formData: FormData
): Promise<ProductFormState> {
  await requireOwner();

  const product = readProduct(formData);
  const result = await updateProduct(product.id, product);
  if (!result.ok) {
    return { error: result.error };
  }

  revalidatePath("/admin/products");
  redirect("/admin/products");
}

export async function deleteProductAction(formData: FormData): Promise<void> {
  await requireOwner();

  const id = String(formData.get("id") ?? "");
  const result = await deleteProduct(id);

  revalidatePath("/admin/products");
  if (!result.ok) {
    redirect(`/admin/products?error=${encodeURIComponent(result.error)}`);
  }
  redirect("/admin/products");
}

export async function setOrderStatusAction(formData: FormData): Promise<void> {
  await requireOwner();

  const orderId = Number(formData.get("orderId"));
  const status = formData.get("status") === "shipped" ? "shipped" : "new";

  if (Number.isInteger(orderId)) {
    await setOrderStatus(orderId, status);
  }

  revalidatePath("/admin/orders");
}

export async function restockAction(formData: FormData): Promise<void> {
  await requireOwner();

  const id = String(formData.get("id") ?? "");
  const amount = Number(formData.get("amount"));

  if (id !== "" && Number.isInteger(amount) && amount > 0 && amount <= 1000) {
    await addStock(id, amount);
  }

  revalidatePath("/admin/products");
}
