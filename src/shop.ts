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
