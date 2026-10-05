import Link from "next/link";

export default function NotFound() {
  return (
    <section className="section">
      <div className="container">
        <h1 className="page-title">Page not found</h1>
        <p>Sorry, there is nothing at this address yet.</p>
        <Link className="button" href="/shop">Go to the shop</Link>
      </div>
    </section>
  );
}
