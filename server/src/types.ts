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
