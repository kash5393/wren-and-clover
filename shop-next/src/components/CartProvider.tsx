"use client";

import { createContext, useContext, useEffect, useState } from "react";
import type { ReactNode } from "react";
import { addToCart, cartCount, cartTotal, removeFromCart, setQuantity } from "@/lib/cart-math";
import type { CartItem, Product } from "@/lib/types";

const CART_KEY = "wren-clover-cart";

interface CartContextValue {
  items: CartItem[];
  count: number;
  total: number;
  ready: boolean;
  addItem: (product: Product, scent: string, quantity: number) => void;
  updateQuantity: (index: number, quantity: number) => void;
  removeItem: (index: number) => void;
  clearCart: () => void;
}

const CartContext = createContext<CartContextValue | null>(null);

function loadCart(): CartItem[] {
  try {
    const saved = localStorage.getItem(CART_KEY);
    return saved ? (JSON.parse(saved) as CartItem[]) : [];
  } catch {
    return [];
  }
}

interface CartProviderProps {
  children: ReactNode;
}

export function CartProvider({ children }: CartProviderProps) {
  const [items, setItems] = useState<CartItem[]>([]);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const frame = requestAnimationFrame(() => {
      setItems(loadCart());
      setReady(true);
    });
    return () => cancelAnimationFrame(frame);
  }, []);

  useEffect(() => {
    if (ready) {
      localStorage.setItem(CART_KEY, JSON.stringify(items));
    }
  }, [items, ready]);

  function addItem(product: Product, scent: string, quantity: number) {
    setItems((current) => addToCart(current, product, scent, quantity));
  }

  function updateQuantity(index: number, quantity: number) {
    setItems((current) => setQuantity(current, index, quantity));
  }

  function removeItem(index: number) {
    setItems((current) => removeFromCart(current, index));
  }

  function clearCart() {
    setItems([]);
  }

  const count = cartCount(items);
  const total = cartTotal(items);

  return (
    <CartContext.Provider
      value={{ items, count, total, ready, addItem, updateQuantity, removeItem, clearCart }}
    >
      {children}
    </CartContext.Provider>
  );
}

export function useCart() {
  const context = useContext(CartContext);
  if (!context) {
    throw new Error("useCart must be used inside a CartProvider");
  }
  return context;
}
