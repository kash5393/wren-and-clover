const CART_KEY = "wren-clover-cart";

function getCart(): CartItem[] {
  try {
    const saved = localStorage.getItem(CART_KEY);
    return saved ? (JSON.parse(saved) as CartItem[]) : [];
  } catch {
    return [];
  }
}

function saveCart(cart: CartItem[]): void {
  localStorage.setItem(CART_KEY, JSON.stringify(cart));
  updateCartCount();
}

function addToCart(product: Product, scent: string, quantity: number): void {
  const cart = getCart();
  const existing = cart.find(
    (item) => item.id === product.id && item.scent === scent
  );

  if (existing) {
    existing.quantity += quantity;
  } else {
    cart.push({
      id: product.id,
      name: product.name,
      price: product.price,
      scent: scent,
      quantity: quantity,
    });
  }

  saveCart(cart);
}

function updateCartCount(): void {
  const countEl = document.querySelector("#cart-count");
  if (!countEl) {
    return;
  }
  const count = getCart().reduce((total, item) => total + item.quantity, 0);
  countEl.textContent = String(count);
}

function setupAddToCart(product: Product): void {
  const form = document.querySelector<HTMLFormElement>(".product-form");
  if (!form) {
    return;
  }
  const button = form.querySelector("button");
  const scentSelect = form.querySelector<HTMLSelectElement>("#scent");
  const quantityInput = form.querySelector<HTMLInputElement>("#quantity");
  if (!button || !scentSelect || !quantityInput) {
    return;
  }

  button.addEventListener("click", () => {
    const quantity = Number(quantityInput.value) || 1;
    addToCart(product, scentSelect.value, quantity);

    button.textContent = "Added to cart";
    setTimeout(() => {
      button.textContent = "Add to cart";
    }, 1500);
  });
}

updateCartCount();
