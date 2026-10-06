export type Category = "Soaps" | "Lotions" | "Bath" | "Gift sets";

export const categories: Category[] = ["Soaps", "Lotions", "Bath", "Gift sets"];

export interface Product {
  id: string;
  name: string;
  category: Category;
  price: number;
  size: string;
  scents: string[];
  description: string;
  stock: number;
  imageUrl: string | null;
}

export interface CartItem {
  id: string;
  name: string;
  price: number;
  scent: string;
  quantity: number;
}

export interface User {
  id: number;
  email: string;
  name: string;
  role: "customer" | "owner";
}

export interface ShippingDetails {
  name: string;
  email: string;
  phone: string;
  address: string;
  city: string;
  state: string;
  postcode: string;
}
