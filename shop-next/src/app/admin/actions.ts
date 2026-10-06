"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { setOrderStatus } from "@/lib/admin";
import { requireOwner } from "@/lib/auth";
import { sendEmail } from "@/lib/email";
import { testStripeConnection } from "@/lib/payments";
import { deleteProductImage, saveProductImage } from "@/lib/product-images";
import { addStock, createProduct, deleteProduct, updateProduct } from "@/lib/products";
import {
  clearSetting,
  encryptionReady,
  getSettings,
  saveSetting,
  settingKeys,
  validateSetting,
} from "@/lib/settings";
import type { SettingKey } from "@/lib/settings";

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

export interface ImageFormState {
  error: string;
  saved: boolean;
}

export async function uploadProductImageAction(
  _previous: ImageFormState,
  formData: FormData
): Promise<ImageFormState> {
  await requireOwner();

  const productId = String(formData.get("productId") ?? "");
  const result = await saveProductImage(productId, formData.get("photo"));
  if (!result.ok) {
    return { error: result.error, saved: false };
  }

  revalidatePath("/", "layout");
  return { error: "", saved: true };
}

export async function removeProductImageAction(formData: FormData): Promise<void> {
  await requireOwner();

  await deleteProductImage(String(formData.get("productId") ?? ""));
  revalidatePath("/", "layout");
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

export interface SettingsFormState {
  error: string;
  message: string;
}

export async function saveSettingsAction(
  _previous: SettingsFormState,
  formData: FormData
): Promise<SettingsFormState> {
  await requireOwner();

  if (!encryptionReady()) {
    return { error: "Settings can't be saved until SETTINGS_ENCRYPTION_KEY is set.", message: "" };
  }

  const changes: { key: SettingKey; value: string }[] = [];

  for (const key of settingKeys) {
    const value = String(formData.get(key) ?? "").trim();
    if (value === "") {
      continue;
    }

    const problem = validateSetting(key, value);
    if (problem) {
      return { error: problem, message: "" };
    }
    changes.push({ key, value });
  }

  if (changes.length === 0) {
    return { error: "", message: "Nothing to save: every box was empty." };
  }

  for (const change of changes) {
    await saveSetting(change.key, change.value);
  }

  revalidatePath("/", "layout");
  return {
    error: "",
    message: `Saved ${changes.length} ${changes.length === 1 ? "setting" : "settings"}.`,
  };
}

export async function clearSettingAction(formData: FormData): Promise<void> {
  await requireOwner();

  const key = String(formData.get("key") ?? "");
  if ((settingKeys as readonly string[]).includes(key)) {
    await clearSetting(key as SettingKey);
  }

  revalidatePath("/", "layout");
}

export async function testStripeAction(): Promise<SettingsFormState> {
  await requireOwner();

  const result = await testStripeConnection();
  return result.ok
    ? { error: "", message: result.message }
    : { error: result.message, message: "" };
}

export async function testEmailAction(): Promise<SettingsFormState> {
  const owner = await requireOwner();
  const settings = await getSettings();

  try {
    await sendEmail({
      to: owner.email,
      subject: "Test email from your Wren & Clover shop",
      text: "If you can read this, your shop's email settings are working.",
    });
  } catch (error) {
    const reason = error instanceof Error ? error.message : "Unknown error";
    return { error: `The email could not be sent: ${reason}`, message: "" };
  }

  return settings.smtpUrl
    ? { error: "", message: `Test email sent to ${owner.email}.` }
    : {
        error: "",
        message: "No email server is set, so the test email was printed in the server log instead.",
      };
}
