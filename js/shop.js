const grid = document.querySelector("#product-grid");

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

async function loadProducts() {
  try {
    const response = await fetch("data/products.json");
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    const products = await response.json();
    grid.innerHTML = products.map(productCard).join("");
  } catch (error) {
    grid.innerHTML = "<p>Sorry, the products could not be loaded.</p>";
    console.error(error);
  }
}

loadProducts();