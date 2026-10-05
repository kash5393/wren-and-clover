import { Link } from "react-router";

function About() {
  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">About</h1>
        <div className="photo">Photo of the maker at work</div>
        <h2>How it started</h2>
        <p>
          Wren &amp; Clover began at a kitchen table, with a batch of lavender
          soap made for a family member with sensitive skin. Friends asked for
          more, and a market stall followed.
        </p>
        <h2>How it's made</h2>
        <p>
          Every product is made by hand in small batches, using organic oils,
          butters and botanicals. Nothing has synthetic fragrance or colouring.
        </p>
        <h2>Find us in person</h2>
        <p>We're at the farmers' market most Saturdays. Come and say hello.</p>
        <Link className="button" to="/shop">Browse the shop</Link>
      </div>
    </section>
  );
}

export default About;
