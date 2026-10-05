const menuToggle = document.querySelector<HTMLButtonElement>(".menu-toggle");
const siteNav = document.querySelector<HTMLElement>("#site-nav");

if (menuToggle && siteNav) {
  menuToggle.addEventListener("click", () => {
    const isOpen = siteNav.classList.toggle("is-open");
    menuToggle.setAttribute("aria-expanded", String(isOpen));
    menuToggle.textContent = isOpen ? "Close" : "Menu";
  });
}
