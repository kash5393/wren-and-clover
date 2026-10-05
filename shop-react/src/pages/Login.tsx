import { useState } from "react";
import type { FormEvent } from "react";
import { Link, useNavigate } from "react-router";
import FormField from "../components/FormField";
import { useAuth } from "../context/AuthContext";

function Login() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    const problem = await login(email.trim(), password);
    setSubmitting(false);

    if (problem) {
      setError(problem);
      return;
    }
    navigate("/");
  }

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Sign in</h1>

        <form className="contact-form" noValidate onSubmit={handleSubmit}>
          <FormField id="email" label="Email" type="email" value={email} onChange={setEmail} />
          <FormField
            id="password"
            label="Password"
            type="password"
            value={password}
            onChange={setPassword}
          />
          {error && (
            <p className="field-error" role="alert">
              {error}
            </p>
          )}
          <button className="button button-full" type="submit" disabled={submitting}>
            {submitting ? "Signing in..." : "Sign in"}
          </button>
        </form>

        <p>
          New here? <Link to="/signup">Create an account</Link>
        </p>
      </div>
    </section>
  );
}

export default Login;
