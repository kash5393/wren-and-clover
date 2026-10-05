import Shop from "./pages/Shop";

function App() {
  return (
    <>
      <header className="site-header">
        <div className="container header-inner">
          <a className="logo" href="/">Wren &amp; Clover</a>
          <a className="cart-link" href="#">Cart (0)</a>
        </div>
      </header>

      <main>
        <Shop />
      </main>
    </>
  );
}

export default App;
