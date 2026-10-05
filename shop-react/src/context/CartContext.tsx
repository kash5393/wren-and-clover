import { createContext, useContext, useEffect, useState } from "react";
import type { ReactNode } from "react";
import type { CartItem, Product } from "../types";

const CART_KEY = "wren-clover-cart";

interface CartContextValue {
  items: CartItem[];
  count: number;
  total: number;
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
  const [items, setItems] = useState<CartItem[]>(loadCart);

  useEffect(() => {
    localStorage.setItem(CART_KEY, JSON.stringify(items));
  }, [items]);

  function addItem(product: Product, scent: string, quantity: number) {
    setItems((current) => {
      const exists = current.some(
        (item) => item.id === product.id && item.scent === scent
      );

      if (exists) {
        return current.map((item) =>
          item.id === product.id && item.scent === scent
            ? { ...item, quantity: item.quantity + quantity }
            : item
        );
      }

      return [
        ...current,
        {
          id: product.id,
          name: product.name,
          price: product.price,
          scent: scent,
          quantity: quantity,
        },
      ];
    });
  }

  function updateQuantity(index: number, quantity: number) {
    setItems((current) =>
      current.map((item, itemIndex) =>
        itemIndex === index ? { ...item, quantity: Math.max(1, quantity) } : item
      )
    );
  }

  function removeItem(index: number) {
    setItems((current) => current.filter((_, itemIndex) => itemIndex !== index));
  }

  function clearCart() {
    setItems([]);
  }

  const count = items.reduce((sum, item) => sum + item.quantity, 0);
  const total = items.reduce((sum, item) => sum + item.price * item.quantity, 0);

  return (
    <CartContext.Provider
      value={{ items, count, total, addItem, updateQuantity, removeItem, clearCart }}
    >
      {children}
    </CartContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components
export function useCart() {
  const context = useContext(CartContext);
  if (!context) {
    throw new Error("useCart must be used inside a CartProvider");
  }
  return context;
}
