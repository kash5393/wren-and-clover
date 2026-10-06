"use client";

import { useActionState } from "react";
import { resetPasswordAction } from "@/app/auth-actions";
import type { AuthFormState } from "@/app/auth-actions";

interface ResetPasswordFormProps {
  token: string;
}

const initialState: AuthFormState = { error: "" };

export default function ResetPasswordForm({ token }: ResetPasswordFormProps) {
  const [state, formAction, pending] = useActionState(resetPasswordAction, initialState);

  return (
    <form className="contact-form" action={formAction}>
      <input type="hidden" name="token" value={token} />

      <div className="field">
        <label htmlFor="password">New password (at least 8 characters)</label>
        <input
          id="password"
          name="password"
          type="password"
          autoComplete="new-password"
          minLength={8}
          required
        />
      </div>

      <div className="field">
        <label htmlFor="confirm">Type the new password again</label>
        <input
          id="confirm"
          name="confirm"
          type="password"
          autoComplete="new-password"
          minLength={8}
          required
        />
      </div>

      {state.error && (
        <p className="field-error" role="alert">
          {state.error}
        </p>
      )}

      <button className="button button-full" type="submit" disabled={pending}>
        {pending ? "Saving..." : "Change password"}
      </button>
    </form>
  );
}
