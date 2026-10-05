import { useState } from "react";
import { Link, Outlet } from "react-router";
import { useAuth } from "../context/AuthContext";
import { useCart } from "../context/CartContext";

function Layout() {
  const { count } = useCart();
  const { user, logout } = useAuth();
  const [menuOpen, setMenuOpen] = useState(false);
  const closeMenu = () => setMenuOpen(false);

  return (
    <>
      <header className="site-header">
        <div className="container header-inner">
          <Link className="logo" to="/" onClick={closeMenu}>
            Wren &amp; Clover
          </Link>

          <button
            className="menu-toggle"
            type="button"
            aria-expanded={menuOpen}
            aria-controls="site-nav"
            onClick={() => setMenuOpen(!menuOpen)}
          >
            {menuOpen ? "Close" : "Menu"}
          </button>

          <nav
            id="site-nav"
            className={menuOpen ? "site-nav is-open" : "site-nav"}
            aria-label="Main"
          >
            <Link to="/shop" onClick={closeMenu}>Shop</Link>
            <Link to="/about" onClick={closeMenu}>About</Link>
            <Link to="/contact" onClick={closeMenu}>Contact</Link>
            {user ? (
              <button
                className="nav-button"
                type="button"
                onClick={() => {
                  closeMenu();
                  logout();
                }}
              >
                Log out ({user.name})
              </button>
            ) : (
              <Link to="/login" onClick={closeMenu}>Sign in</Link>
            )}
          </nav>

          <Link className="cart-link" to="/cart" onClick={closeMenu}>
            Cart ({count})
          </Link>
        </div>
      </header>

      <main>
        <Outlet />
      </main>

      <footer className="site-footer">
        <div className="container">
          <nav className="footer-nav" aria-label="Footer">
            <Link to="/shop">Shop</Link>
            <Link to="/about">About</Link>
            <Link to="/contact">Contact</Link>
            <Link to="/shipping">Shipping and Returns</Link>
          </nav>
          <p>&copy; Wren &amp; Clover Botanicals</p>
        </div>
      </footer>
    </>
  );
}

export default Layout;
