import "server-only";
import { pool } from "./db";

export const MAX_IMAGE_BYTES = 2 * 1024 * 1024;
const allowedTypes = ["image/jpeg", "image/png", "image/webp"];

export type ImageResult = { ok: true } | { ok: false; error: string };

export async function saveProductImage(productId: string, file: unknown): Promise<ImageResult> {
  if (!(file instanceof File) || file.size === 0) {
    return { ok: false, error: "Choose a photo to upload." };
  }
  if (!allowedTypes.includes(file.type)) {
    return { ok: false, error: "The photo must be a JPEG, PNG or WebP image." };
  }
  if (file.size > MAX_IMAGE_BYTES) {
    return { ok: false, error: "The photo is too large. Please use one under 2 MB." };
  }

  const product = await pool.query("SELECT 1 FROM products WHERE id = $1", [productId]);
  if (product.rows.length === 0) {
    return { ok: false, error: "Product not found." };
  }

  const data = Buffer.from(await file.arrayBuffer());

  await pool.query(
    `INSERT INTO product_images (product_id, content_type, data)
     VALUES ($1, $2, $3)
     ON CONFLICT (product_id)
     DO UPDATE SET content_type = EXCLUDED.content_type, data = EXCLUDED.data, updated_at = now()`,
    [productId, file.type, data]
  );

  return { ok: true };
}

export async function deleteProductImage(productId: string): Promise<void> {
  await pool.query("DELETE FROM product_images WHERE product_id = $1", [productId]);
}

export async function getProductImage(
  productId: string
): Promise<{ contentType: string; data: Buffer } | null> {
  const result = await pool.query<{ content_type: string; data: Buffer }>(
    "SELECT content_type, data FROM product_images WHERE product_id = $1",
    [productId]
  );
  const row = result.rows[0];
  return row ? { contentType: row.content_type, data: row.data } : null;
}
