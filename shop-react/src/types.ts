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
