import express from "express";
import type { NextFunction, Request, Response } from "express";
import { createOrder, listOrders } from "./orders.js";
import { createProduct, deleteProduct, loadProducts, updateProduct } from "./products.js";

const app = express();
const port = Number(process.env.PORT) || 4000;

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

app.post("/api/products", async (request, response) => {
  const result = await createProduct(request.body);

  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  response.status(201).json(result.product);
});

app.patch("/api/products/:id", async (request, response) => {
  const result = await updateProduct(request.params.id, request.body);

  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  response.json(result.product);
});

app.delete("/api/products/:id", async (request, response) => {
  const deleted = await deleteProduct(request.params.id);

  if (!deleted) {
    response.status(404).json({ error: "Product not found" });
    return;
  }

  response.status(204).end();
});

app.get("/api/categories", async (_request, response) => {
  const products = await loadProducts();
  const categories = [...new Set(products.map((product) => product.category))];
  response.json(categories);
});

app.post("/api/orders", async (request, response) => {
  const result = await createOrder(request.body);

  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  console.log(`New order ${result.order.orderNumber}: $${result.order.total}`);
  response.status(201).json({
    orderNumber: result.order.orderNumber,
    total: result.order.total,
  });
});

app.get("/api/orders", (_request, response) => {
  response.json(listOrders());
});

app.use((_request, response) => {
  response.status(404).json({ error: "Not found" });
});

app.use((error: unknown, _request: Request, response: Response, _next: NextFunction) => {
  if (error instanceof SyntaxError) {
    response.status(400).json({ error: "The request body is not valid JSON" });
    return;
  }

  console.error(error);
  response.status(500).json({ error: "Something went wrong on the server" });
});

app.listen(port, () => {
  console.log(`Shop API running at http://localhost:${port}`);
});
