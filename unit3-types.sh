#!/usr/bin/env bash
# Unit 3, step 2: typed versions of the shop scripts.
# Run from inside the wren-and-clover project folder:  bash unit3-types.sh
set -e
if [ ! -f tsconfig.json ] || [ ! -d src ]; then echo "Run this inside the wren-and-clover folder (tsconfig.json and src/ not found)."; exit 1; fi

cat > src/shared.ts << 'WREN_EOF'
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
WREN_EOF

cat > src/cart.ts << 'WREN_EOF'
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
WREN_EOF

cat > src/shop.ts << 'WREN_EOF'
const grid = getElement<HTMLDivElement>("#product-grid");
const chips = document.querySelectorAll<HTMLButtonElement>(".chip");
const searchInput = getElement<HTMLInputElement>("#search");
const sortSelect = getElement<HTMLSelectElement>("#sort");
const resultCount = getElement<HTMLParagraphElement>("#result-count");

let allProducts: Product[] = [];
let activeCategory: Category | "All" = "All";

function render(): void {
  const term = searchInput.value.trim().toLowerCase();

  const visible = allProducts.filter((product) => {
    const inCategory =
      activeCategory === "All" || product.category === activeCategory;
    const matchesSearch =
      product.name.toLowerCase().includes(term) ||
      product.description.toLowerCase().includes(term);
    return inCategory && matchesSearch;
  });

  const sortBy = sortSelect.value;
  if (sortBy === "price-low") {
    visible.sort((a, b) => a.price - b.price);
  } else if (sortBy === "price-high") {
    visible.sort((a, b) => b.price - a.price);
  } else if (sortBy === "name") {
    visible.sort((a, b) => a.name.localeCompare(b.name));
  }

  resultCount.textContent = `${visible.length} product${visible.length === 1 ? "" : "s"}`;

  if (visible.length === 0) {
    grid.innerHTML = "<p>No products match your search.</p>";
  } else {
    grid.innerHTML = visible.map(productCard).join("");
  }
}

chips.forEach((chip) => {
  chip.addEventListener("click", () => {
    activeCategory = (chip.dataset.category ?? "All") as Category | "All";
    chips.forEach((other) => {
      other.classList.toggle("chip-active", other === chip);
    });
    render();
  });
});

searchInput.addEventListener("input", render);
sortSelect.addEventListener("change", render);

async function loadProducts(): Promise<void> {
  try {
    allProducts = await fetchProducts();
    render();
  } catch (error) {
    grid.innerHTML = "<p>Sorry, the products could not be loaded.</p>";
    console.error(error);
  }
}

loadProducts();
WREN_EOF

cat > src/product.ts << 'WREN_EOF'
const params = new URLSearchParams(window.location.search);
const productId = params.get("id");

const productEl = getElement<HTMLDivElement>("#product");
const relatedEl = document.querySelector<HTMLDivElement>("#related");

function productDetails(product: Product): string {
  const options = product.scents
    .map((scent) => `<option>${scent}</option>`)
    .join("");
  const inStock = product.stock > 0;

  return `
    <nav class="breadcrumb" aria-label="Breadcrumb">
      <a href="shop.html">Shop</a> / ${product.category} / ${product.name}
    </nav>

    <div class="product-layout">
      <div class="photo product-photo">Large product photo</div>

      <div class="product-details">
        <h1>${product.name}</h1>
        <p class="product-price">$${product.price}</p>
        <p>${product.description} ${product.size}.</p>

        <form class="product-form">
          <div class="field">
            <label for="scent">Scent</label>
            <select id="scent" name="scent">${options}</select>
          </div>

          <div class="field">
            <label for="quantity">Quantity</label>
            <input id="quantity" name="quantity" type="number" min="1" value="1">
          </div>

          <button class="button button-full" type="button" ${inStock ? "" : "disabled"}>
            ${inStock ? "Add to cart" : "Out of stock"}
          </button>
        </form>
      </div>
    </div>
  `;
}

async function loadProduct(): Promise<void> {
  try {
    const products = await fetchProducts();
    const product = products.find((item) => item.id === productId);

    if (!product) {
      productEl.innerHTML = `
        <h1>Product not found</h1>
        <p><a href="shop.html">Back to the shop</a></p>
      `;
      return;
    }

    document.title = `${product.name} | Wren & Clover Botanicals`;
    productEl.innerHTML = productDetails(product);
    setupAddToCart(product);

    if (relatedEl) {
      const related = products
        .filter((item) => item.category === product.category && item.id !== product.id)
        .slice(0, 3);
      relatedEl.innerHTML = related.map(productCard).join("");
    }
  } catch (error) {
    productEl.innerHTML = "<p>Sorry, this product could not be loaded.</p>";
    console.error(error);
  }
}

loadProduct();
WREN_EOF

cat > src/cart-page.ts << 'WREN_EOF'
const cartEl = getElement<HTMLDivElement>("#cart");

function renderCart(): void {
  const cart = getCart();

  if (cart.length === 0) {
    cartEl.innerHTML = `
      <p>Your cart is empty.</p>
      <a class="button" href="shop.html">Browse the shop</a>
    `;
    return;
  }

  const rows = cart
    .map(
      (item, index) => `
        <tr>
          <td>
            <a href="product.html?id=${item.id}">${item.name}</a><br>
            <span class="cart-scent">${item.scent}</span>
          </td>
          <td>$${item.price}</td>
          <td>
            <input class="cart-qty" type="number" min="1" value="${item.quantity}"
              data-index="${index}" aria-label="Quantity for ${item.name}">
          </td>
          <td>$${item.price * item.quantity}</td>
          <td>
            <button class="link-button" type="button" data-remove="${index}">Remove</button>
          </td>
        </tr>
      `
    )
    .join("");

  const total = cart.reduce((sum, item) => sum + item.price * item.quantity, 0);

  cartEl.innerHTML = `
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Product</th>
            <th>Price</th>
            <th>Quantity</th>
            <th>Total</th>
            <th>Action</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>
    </div>
    <p class="cart-total">Order total: <strong>$${total}</strong></p>
    <a class="button" href="shop.html">Continue shopping</a>
  `;
}

cartEl.addEventListener("change", (event) => {
  const target = event.target;
  if (!(target instanceof HTMLInputElement) || !target.matches(".cart-qty")) {
    return;
  }
  const cart = getCart();
  const item = cart[Number(target.dataset.index)];
  if (!item) {
    return;
  }
  item.quantity = Math.max(1, Number(target.value) || 1);
  saveCart(cart);
  renderCart();
});

cartEl.addEventListener("click", (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement)) {
    return;
  }
  const removeIndex = target.dataset.remove;
  if (removeIndex === undefined) {
    return;
  }
  const cart = getCart();
  cart.splice(Number(removeIndex), 1);
  saveCart(cart);
  renderCart();
});

renderCart();
WREN_EOF

cat > src/site.ts << 'WREN_EOF'
const menuToggle = document.querySelector<HTMLButtonElement>(".menu-toggle");
const siteNav = document.querySelector<HTMLElement>("#site-nav");

if (menuToggle && siteNav) {
  menuToggle.addEventListener("click", () => {
    const isOpen = siteNav.classList.toggle("is-open");
    menuToggle.setAttribute("aria-expanded", String(isOpen));
    menuToggle.textContent = isOpen ? "Close" : "Menu";
  });
}
WREN_EOF

cat > src/contact.ts << 'WREN_EOF'
const contactForm = document.querySelector<HTMLFormElement>(".contact-form");

function showError(field: HTMLElement, message: string): void {
  const wrapper = field.parentElement;
  if (!wrapper) {
    return;
  }
  let error = wrapper.querySelector<HTMLSpanElement>(".field-error");
  if (!error) {
    error = document.createElement("span");
    error.className = "field-error";
    wrapper.append(error);
  }
  error.textContent = message;
  field.setAttribute("aria-invalid", message ? "true" : "false");
}

if (contactForm) {
  contactForm.noValidate = true;

  const formStatus = document.createElement("p");
  formStatus.className = "form-status";
  formStatus.setAttribute("role", "status");
  contactForm.append(formStatus);

  contactForm.addEventListener("submit", (event) => {
    event.preventDefault();

    const nameInput = contactForm.querySelector<HTMLInputElement>("#name");
    const emailInput = contactForm.querySelector<HTMLInputElement>("#email");
    const messageInput = contactForm.querySelector<HTMLTextAreaElement>("#message");
    if (!nameInput || !emailInput || !messageInput) {
      return;
    }

    const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    let isValid = true;

    if (nameInput.value.trim() === "") {
      showError(nameInput, "Please enter your name.");
      isValid = false;
    } else {
      showError(nameInput, "");
    }

    if (!emailPattern.test(emailInput.value.trim())) {
      showError(emailInput, "Please enter a valid email address.");
      isValid = false;
    } else {
      showError(emailInput, "");
    }

    if (messageInput.value.trim().length < 10) {
      showError(messageInput, "Please write at least 10 characters.");
      isValid = false;
    } else {
      showError(messageInput, "");
    }

    if (!isValid) {
      formStatus.textContent = "";
      return;
    }

    formStatus.textContent = `Thanks, ${nameInput.value.trim()}. Your message passed all the checks.`;
    contactForm.reset();
  });
}
WREN_EOF

# Load the shared script first on every page (skipped if already added).
for f in *.html; do
  grep -q 'js/shared.js' "$f" || perl -0pi -e 's|(\n[ \t]*<script src="js/)|\n  <script src="js/shared.js"></script>$1|' "$f"
done

npm run build
echo
echo "Done. src/ now holds the typed files and js/ has been rebuilt."
