"use strict";
function getElement(selector) {
    const element = document.querySelector(selector);
    if (!element) {
        throw new Error(`Missing element: ${selector}`);
    }
    return element;
}
async function fetchProducts() {
    const response = await fetch("data/products.json");
    if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
    }
    return (await response.json());
}
function productCard(product) {
    const badge = product.stock === 0 ? `<span class="badge">Out of stock</span>` : "";
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
