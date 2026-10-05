import { Link } from "react-router";

function NotFound() {
  return (
    <section className="section">
      <div className="container">
        <h1 className="page-title">Page not found</h1>
        <p>Sorry, there is nothing at this address.</p>
        <Link className="button" to="/shop">Go to the shop</Link>
      </div>
    </section>
  );
}

export default NotFound;
