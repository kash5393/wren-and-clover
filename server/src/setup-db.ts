import { readFile } from "node:fs/promises";
import { pool } from "./db.js";
import type { Product } from "./types.js";

const schemaFile = new URL("../db/schema.sql", import.meta.url);
const seedFile = new URL("../data/products.json", import.meta.url);

async function setup(): Promise<void> {
  const schema = await readFile(schemaFile, "utf-8");
  await pool.query(schema);
  console.log("Tables created.");

  const products = JSON.parse(await readFile(seedFile, "utf-8")) as Product[];

  for (const product of products) {
    await pool.query(
      `INSERT INTO products (id, name, category, price_cents, size, scents, description, stock)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        product.id,
        product.name,
        product.category,
        Math.round(product.price * 100),
        product.size,
        product.scents,
        product.description,
        product.stock,
      ]
    );
  }

  console.log(`Added ${products.length} products.`);
}

setup()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
