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
