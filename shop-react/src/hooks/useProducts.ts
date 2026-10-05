import { useEffect, useState } from "react";
import type { Product } from "../types";

type Status = "loading" | "ready" | "error";

export function useProducts() {
  const [products, setProducts] = useState<Product[]>([]);
  const [status, setStatus] = useState<Status>("loading");

  useEffect(() => {
    let cancelled = false;

    async function loadProducts() {
      try {
        const response = await fetch("/api/products");
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`);
        }
        const data = (await response.json()) as Product[];
        if (!cancelled) {
          setProducts(data);
          setStatus("ready");
        }
      } catch (error) {
        console.error(error);
        if (!cancelled) {
          setStatus("error");
        }
      }
    }

    loadProducts();

    return () => {
      cancelled = true;
    };
  }, []);

  return { products, status };
}
