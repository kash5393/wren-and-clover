import { readFile } from "node:fs/promises";
import type { Product } from "./types.js";

const dataFile = new URL("../data/products.json", import.meta.url);

export async function loadProducts(): Promise<Product[]> {
  const text = await readFile(dataFile, "utf-8");
  return JSON.parse(text) as Product[];
}
