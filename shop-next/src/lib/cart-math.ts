import type { CartItem, Product } from "./types";

/** How many of one product are in the cart, across all its scents. */
export function quantityInCart(items: CartItem[], productId: string): number {
  return items
    .filter((item) => item.id === productId)
    .reduce((sum, item) => sum + item.quantity, 0);
}

/** How many more of a product can still be added before the cart holds all the stock. */
export function availableToAdd(items: CartItem[], product: Product): number {
  return Math.max(0, product.stock - quantityInCart(items, product.id));
}

/** The largest quantity one cart line may have, given the stock and the product's other lines. */
export function maxForLine(items: CartItem[], index: number): number | null {
  const line = items[index];
  if (!line || line.stock === undefined) {
    return null;
  }

  const onOtherLines = quantityInCart(items, line.id) - line.quantity;
  return Math.max(1, line.stock - onOtherLines);
}

export function addToCart(
  items: CartItem[],
  product: Product,
  scent: string,
  quantity: number
): CartItem[] {
  const toAdd = Math.min(quantity, availableToAdd(items, product));
  if (toAdd <= 0) {
    return items;
  }

  const exists = items.some((item) => item.id === product.id && item.scent === scent);

  const updated = items.map((item) => {
    if (item.id !== product.id) {
      return item;
    }
    return {
      ...item,
      stock: product.stock,
      quantity: item.scent === scent ? item.quantity + toAdd : item.quantity,
    };
  });

  if (exists) {
    return updated;
  }

  return [
    ...updated,
    {
      id: product.id,
      name: product.name,
      price: product.price,
      scent: scent,
      quantity: toAdd,
      stock: product.stock,
    },
  ];
}

export function setQuantity(items: CartItem[], index: number, quantity: number): CartItem[] {
  const max = maxForLine(items, index);
  const wanted = Math.max(1, Math.floor(quantity) || 1);
  const allowed = max === null ? wanted : Math.min(wanted, max);

  return items.map((item, itemIndex) =>
    itemIndex === index ? { ...item, quantity: allowed } : item
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
