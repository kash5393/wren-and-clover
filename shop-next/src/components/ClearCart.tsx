"use client";

import { useEffect } from "react";
import { useCart } from "@/components/CartProvider";

export default function ClearCart() {
  const { ready, count, clearCart } = useCart();

  useEffect(() => {
    if (ready && count > 0) {
      clearCart();
    }
  }, [ready, count, clearCart]);

  return null;
}
