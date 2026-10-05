import { useState } from "react";
import type { FormEvent } from "react";
import { Link, useNavigate, useSearchParams } from "react-router";
import FormField from "../components/FormField";
import { useAuth } from "../context/AuthContext";

function Signup() {
  const { signup } = useAuth();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const requested = searchParams.get("next") ?? "/";
  const nextPage = requested.startsWith("/") && !requested.startsWith("//") ? requested : "/";
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (password.length < 8) {
      setError("Password must be at least 8 characters.");
      return;
    }

    setSubmitting(true);
    const problem = await signup(name.trim(), email.trim(), password);
    setSubmitting(false);

    if (problem) {
      setError(problem);
      return;
    }
    navigate(nextPage);
  }

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Create an account</h1>

        <form className="contact-form" noValidate onSubmit={handleSubmit}>
          <FormField id="name" label="Name" value={name} onChange={setName} />
          <FormField id="email" label="Email" type="email" value={email} onChange={setEmail} />
          <FormField
            id="password"
            label="Password (at least 8 characters)"
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
            {submitting ? "Creating account..." : "Create account"}
          </button>
        </form>

        <p>
          Already have an account? <Link to={`/login?next=${encodeURIComponent(nextPage)}`}>Sign in</Link>
        </p>
      </div>
    </section>
  );
}

export default Signup;
