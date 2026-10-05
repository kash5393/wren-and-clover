import { Link } from "react-router";

function NotFound() {
  return (
    <section className="section">
      <div className="container">
        <h1 className="page-title">Page not built yet</h1>
        <p>This page hasn't been added to the React version so far.</p>
        <Link className="button" to="/shop">Go to the shop</Link>
      </div>
    </section>
  );
}

export default NotFound;
