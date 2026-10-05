import { useState } from "react";
import type { FormEvent } from "react";
import FormField from "../components/FormField";

interface ContactErrors {
  name?: string;
  email?: string;
  message?: string;
}

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function Contact() {
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [message, setMessage] = useState("");
  const [errors, setErrors] = useState<ContactErrors>({});
  const [sentTo, setSentTo] = useState<string | null>(null);

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const foundErrors: ContactErrors = {};
    if (name.trim() === "") {
      foundErrors.name = "Please enter your name.";
    }
    if (!emailPattern.test(email.trim())) {
      foundErrors.email = "Please enter a valid email address.";
    }
    if (message.trim().length < 10) {
      foundErrors.message = "Please write at least 10 characters.";
    }

    setErrors(foundErrors);
    if (Object.keys(foundErrors).length > 0) {
      setSentTo(null);
      return;
    }

    setSentTo(name.trim());
    setName("");
    setEmail("");
    setMessage("");
  }

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Contact</h1>
        <p>
          Questions about an order or an ingredient? Send a message and we'll
          reply within two working days.
        </p>

        <form className="contact-form" noValidate onSubmit={handleSubmit}>
          <FormField id="name" label="Name" value={name} error={errors.name} onChange={setName} />
          <FormField
            id="email"
            label="Email"
            type="email"
            value={email}
            error={errors.email}
            onChange={setEmail}
          />
          <FormField
            id="message"
            label="Message"
            multiline
            value={message}
            error={errors.message}
            onChange={setMessage}
          />
          <button className="button button-full" type="submit">
            Send message
          </button>
          {sentTo && (
            <p className="form-status" role="status">
              Thanks, {sentTo}. Your message passed all the checks.
            </p>
          )}
        </form>
      </div>
    </section>
  );
}

export default Contact;
