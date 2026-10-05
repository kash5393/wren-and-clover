import { readFile } from "node:fs/promises";
import { hashPassword } from "./auth.js";
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

  const ownerEmail = process.env.OWNER_EMAIL;
  const ownerPassword = process.env.OWNER_PASSWORD;

  if (ownerEmail && ownerPassword) {
    await pool.query(
      "INSERT INTO users (email, name, password_hash, role) VALUES ($1, $2, $3, 'owner')",
      [ownerEmail.toLowerCase(), "Shop Owner", await hashPassword(ownerPassword)]
    );
    console.log(`Created owner account ${ownerEmail}.`);
  } else {
    console.log("No owner account created: set OWNER_EMAIL and OWNER_PASSWORD in .env.");
  }
}

setup()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
