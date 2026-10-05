type Category = "Soaps" | "Lotions" | "Bath" | "Gift sets";

interface Product {
  id: string;
  name: string;
  category: Category;
  price: number;
  size: string;
  scents: string[];
  description: string;
  stock: number;
}

interface CartItem {
  id: string;
  name: string;
  price: number;
  scent: string;
  quantity: number;
}

function getElement<T extends HTMLElement>(selector: string): T {
  const element = document.querySelector<T>(selector);
  if (!element) {
    throw new Error(`Missing element: ${selector}`);
  }
  return element;
}

async function fetchProducts(): Promise<Product[]> {
  const response = await fetch("data/products.json");
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }
  return (await response.json()) as Product[];
}

function productCard(product: Product): string {
  const badge =
    product.stock === 0 ? `<span class="badge">Out of stock</span>` : "";

  return `
    <article class="product-card">
      <a href="product.html?id=${product.id}">
        <div class="photo">Product photo${badge}</div>
        <h3>${product.name}</h3>
        <p class="price">$${product.price}</p>
      </a>
    </article>
  `;
}
