"use client";

import Link from "next/link";
import { useActionState } from "react";
import { forgotPasswordAction } from "@/app/auth-actions";
import type { ForgotPasswordState } from "@/app/auth-actions";

const initialState: ForgotPasswordState = { sent: false };

export default function ForgotPasswordForm() {
  const [state, formAction, pending] = useActionState(forgotPasswordAction, initialState);

  if (state.sent) {
    return (
      <>
        <p className="form-status" role="status">
          If that email has an account, a reset link is on its way. It works for 60 minutes.
        </p>
        <p>
          <Link href="/login">Back to sign in</Link>
        </p>
      </>
    );
  }

  return (
    <>
      <p>Enter the email you signed up with and we&apos;ll send you a link to choose a new password.</p>
      <form className="contact-form" action={formAction}>
        <div className="field">
          <label htmlFor="email">Email</label>
          <input id="email" name="email" type="email" autoComplete="email" required />
        </div>
        <button className="button button-full" type="submit" disabled={pending}>
          {pending ? "Please wait..." : "Send reset link"}
        </button>
      </form>
      <p>
        <Link href="/login">Back to sign in</Link>
      </p>
    </>
  );
}
