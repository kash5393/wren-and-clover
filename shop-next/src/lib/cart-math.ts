import type { CartItem, Product } from "./types";

export function addToCart(
  items: CartItem[],
  product: Product,
  scent: string,
  quantity: number
): CartItem[] {
  const exists = items.some((item) => item.id === product.id && item.scent === scent);

  if (exists) {
    return items.map((item) =>
      item.id === product.id && item.scent === scent
        ? { ...item, quantity: item.quantity + quantity }
        : item
    );
  }

  return [
    ...items,
    {
      id: product.id,
      name: product.name,
      price: product.price,
      scent: scent,
      quantity: quantity,
    },
  ];
}

export function setQuantity(items: CartItem[], index: number, quantity: number): CartItem[] {
  return items.map((item, itemIndex) =>
    itemIndex === index ? { ...item, quantity: Math.max(1, quantity) } : item
  );
}

export function removeFromCart(items: CartItem[], index: number): CartItem[] {
  return items.filter((_, itemIndex) => itemIndex !== index);
}

export function cartCount(items: CartItem[]): number {
  return items.reduce((sum, item) => sum + item.quantity, 0);
}

export function cartTotal(items: CartItem[]): number {
  return items.reduce((sum, item) => sum + item.price * item.quantity, 0);
}
