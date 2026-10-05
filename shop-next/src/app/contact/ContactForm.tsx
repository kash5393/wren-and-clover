"use client";

import { useActionState } from "react";
import { sendMessage } from "./actions";
import type { ContactState } from "./actions";

const initialState: ContactState = { status: "idle" };

export default function ContactForm() {
  const [state, formAction, pending] = useActionState(sendMessage, initialState);
  const errors = state.errors ?? {};

  if (state.status === "sent") {
    return (
      <p className="form-status" role="status">
        Thanks, {state.sentTo}. Your message has been received.
      </p>
    );
  }

  return (
    <form className="contact-form" action={formAction} noValidate>
      <div className="field">
        <label htmlFor="name">Name</label>
        <input id="name" name="name" type="text" aria-invalid={errors.name ? true : undefined} />
        {errors.name && <span className="field-error">{errors.name}</span>}
      </div>

      <div className="field">
        <label htmlFor="email">Email</label>
        <input id="email" name="email" type="email" aria-invalid={errors.email ? true : undefined} />
        {errors.email && <span className="field-error">{errors.email}</span>}
      </div>

      <div className="field">
        <label htmlFor="message">Message</label>
        <textarea
          id="message"
          name="message"
          rows={6}
          aria-invalid={errors.message ? true : undefined}
        />
        {errors.message && <span className="field-error">{errors.message}</span>}
      </div>

      <button className="button button-full" type="submit" disabled={pending}>
        {pending ? "Sending..." : "Send message"}
      </button>
    </form>
  );
}
