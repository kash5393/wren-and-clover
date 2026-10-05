import Link from "next/link";

export default function Footer() {
  return (
    <footer className="site-footer">
      <div className="container">
        <nav className="footer-nav" aria-label="Footer">
          <Link href="/shop">Shop</Link>
          <Link href="/about">About</Link>
          <Link href="/contact">Contact</Link>
          <Link href="/shipping">Shipping and Returns</Link>
        </nav>
        <p>&copy; Wren &amp; Clover Botanicals</p>
      </div>
    </footer>
  );
}
