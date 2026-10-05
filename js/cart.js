"use strict";
const CART_KEY = "wren-clover-cart";
function getCart() {
    try {
        return JSON.parse(localStorage.getItem(CART_KEY)) || [];
    }
    catch (error) {
        return [];
    }
}
function saveCart(cart) {
    localStorage.setItem(CART_KEY, JSON.stringify(cart));
    updateCartCount();
}
function addToCart(product, scent, quantity) {
    const cart = getCart();
    const existing = cart.find((item) => item.id === product.id && item.scent === scent);
    if (existing) {
        existing.quantity += quantity;
    }
    else {
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
function updateCartCount() {
    const countEl = document.querySelector("#cart-count");
    if (!countEl) {
        return;
    }
    const count = getCart().reduce((total, item) => total + item.quantity, 0);
    countEl.textContent = count;
}
function setupAddToCart(product) {
    const form = document.querySelector(".product-form");
    if (!form) {
        return;
    }
    const button = form.querySelector("button");
    button.addEventListener("click", () => {
        const scent = form.querySelector("#scent").value;
        const quantity = Number(form.querySelector("#quantity").value) || 1;
        addToCart(product, scent, quantity);
        button.textContent = "Added to cart";
        setTimeout(() => {
            button.textContent = "Add to cart";
        }, 1500);
    });
}
updateCartCount();
