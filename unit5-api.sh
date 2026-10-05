#!/usr/bin/env bash
# Unit 5, step 1: the shop API (Node, Express, TypeScript).
# Run from the wren-and-clover project folder:  bash unit5-api.sh
set -e
if [ ! -f data/products.json ]; then echo "Run this inside the wren-and-clover folder (data/products.json not found)."; exit 1; fi
mkdir -p server/src server/data
cp data/products.json server/data/products.json
cd server
[ -f package.json ] || npm init -y > /dev/null
npm pkg set type=module scripts.dev="tsx watch src/index.ts" scripts.check="tsc --noEmit"
npm install express
npm install -D typescript tsx @types/express @types/node

cat > tsconfig.json << 'WREN_EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "noEmit": true,
    "skipLibCheck": true,
    "types": ["node"]
  },
  "include": ["src"]
}
WREN_EOF

cat > src/types.ts << 'WREN_EOF'
export type Category = "Soaps" | "Lotions" | "Bath" | "Gift sets";

export interface Product {
  id: string;
  name: string;
  category: Category;
  price: number;
  size: string;
  scents: string[];
  description: string;
  stock: number;
}
WREN_EOF

cat > src/products.ts << 'WREN_EOF'
import { readFile } from "node:fs/promises";
import type { Product } from "./types.js";

const dataFile = new URL("../data/products.json", import.meta.url);

export async function loadProducts(): Promise<Product[]> {
  const text = await readFile(dataFile, "utf-8");
  return JSON.parse(text) as Product[];
}
WREN_EOF

cat > src/index.ts << 'WREN_EOF'
import express from "express";
import { loadProducts } from "./products.js";

const app = express();
const port = Number(process.env.PORT) || 3000;

app.use(express.json());

app.get("/api/health", (_request, response) => {
  response.json({ status: "ok" });
});

app.get("/api/products", async (request, response) => {
  let products = await loadProducts();

  const category = request.query.category;
  if (typeof category === "string") {
    products = products.filter((product) => product.category === category);
  }

  const search = request.query.search;
  if (typeof search === "string") {
    const term = search.trim().toLowerCase();
    products = products.filter(
      (product) =>
        product.name.toLowerCase().includes(term) ||
        product.description.toLowerCase().includes(term)
    );
  }

  response.json(products);
});

app.get("/api/products/:id", async (request, response) => {
  const products = await loadProducts();
  const product = products.find((item) => item.id === request.params.id);

  if (!product) {
    response.status(404).json({ error: "Product not found" });
    return;
  }

  response.json(product);
});

app.get("/api/categories", async (_request, response) => {
  const products = await loadProducts();
  const categories = [...new Set(products.map((product) => product.category))];
  response.json(categories);
});

app.use((_request, response) => {
  response.status(404).json({ error: "Not found" });
});

app.listen(port, () => {
  console.log(`Shop API running at http://localhost:${port}`);
});
WREN_EOF

npm run check
echo
echo "Done. Start the API with:  cd server && npm run dev"
