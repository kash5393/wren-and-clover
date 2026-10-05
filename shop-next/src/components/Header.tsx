"use client";

import Link from "next/link";
import { useState } from "react";
import { logoutAction } from "@/app/auth-actions";
import { useCart } from "@/components/CartProvider";

interface HeaderProps {
  userName: string | null;
}

export default function Header({ userName }: HeaderProps) {
  const { count } = useCart();
  const [menuOpen, setMenuOpen] = useState(false);
  const closeMenu = () => setMenuOpen(false);

  return (
    <header className="site-header">
      <div className="container header-inner">
        <Link className="logo" href="/" onClick={closeMenu}>
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
          <Link href="/shop" onClick={closeMenu}>Shop</Link>
          <Link href="/about" onClick={closeMenu}>About</Link>
          <Link href="/contact" onClick={closeMenu}>Contact</Link>
          {userName ? (
            <>
              <Link href="/orders" onClick={closeMenu}>My orders</Link>
              <form action={logoutAction}>
                <button className="nav-button" type="submit">
                  Log out ({userName})
                </button>
              </form>
            </>
          ) : (
            <Link href="/login" onClick={closeMenu}>Sign in</Link>
          )}
        </nav>

        <Link className="cart-link" href="/cart" onClick={closeMenu}>
          Cart ({count})
        </Link>
      </div>
    </header>
  );
}
