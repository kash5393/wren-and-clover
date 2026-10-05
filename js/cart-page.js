const cartEl = document.querySelector("#cart");

function renderCart() {
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
  if (!event.target.matches(".cart-qty")) {
    return;
  }
  const cart = getCart();
  const index = Number(event.target.dataset.index);
  cart[index].quantity = Math.max(1, Number(event.target.value) || 1);
  saveCart(cart);
  renderCart();
});

cartEl.addEventListener("click", (event) => {
  const removeIndex = event.target.dataset.remove;
  if (removeIndex === undefined) {
    return;
  }
  const cart = getCart();
  cart.splice(Number(removeIndex), 1);
  saveCart(cart);
  renderCart();
});

renderCart();
