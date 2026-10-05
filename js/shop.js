const grid = document.querySelector("#product-grid");
const chips = document.querySelectorAll(".chip");
const searchInput = document.querySelector("#search");
const sortSelect = document.querySelector("#sort");
const countEl = document.querySelector("#result-count");

let products = [];
let activeCategory = "All";

function productCard(product) {
  return `
    <article class="product-card">
      <a href="product.html?id=${product.id}">
        <div class="photo">Product photo</div>
        <h3>${product.name}</h3>
        <p class="price">$${product.price}</p>
      </a>
    </article>
  `;
}

function render() {
  const term = searchInput.value.trim().toLowerCase();

  const visible = products.filter((product) => {
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

  countEl.textContent = `${visible.length} product${visible.length === 1 ? "" : "s"}`;

  if (visible.length === 0) {
    grid.innerHTML = "<p>No products match your search.</p>";
  } else {
    grid.innerHTML = visible.map(productCard).join("");
  }
}

chips.forEach((chip) => {
  chip.addEventListener("click", () => {
    activeCategory = chip.dataset.category;
    chips.forEach((other) => {
      other.classList.toggle("chip-active", other === chip);
    });
    render();
  });
});

searchInput.addEventListener("input", render);
sortSelect.addEventListener("change", render);

async function loadProducts() {
  try {
    const response = await fetch("data/products.json");
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    products = await response.json();
    render();
  } catch (error) {
    grid.innerHTML = "<p>Sorry, the products could not be loaded.</p>";
    console.error(error);
  }
}

loadProducts();
