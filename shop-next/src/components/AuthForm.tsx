"use client";

import Link from "next/link";
import { useActionState } from "react";
import { loginAction, signupAction } from "@/app/auth-actions";
import type { AuthFormState } from "@/app/auth-actions";

interface AuthFormProps {
  mode: "login" | "signup";
  nextPath: string;
  defaultEmail?: string;
}

const initialState: AuthFormState = { error: "" };

export default function AuthForm({ mode, nextPath, defaultEmail = "" }: AuthFormProps) {
  const isSignup = mode === "signup";
  const [state, formAction, pending] = useActionState(
    isSignup ? signupAction : loginAction,
    initialState
  );
  const nextQuery = `?next=${encodeURIComponent(nextPath)}`;

  return (
    <>
      <form className="contact-form" action={formAction}>
        <input type="hidden" name="next" value={nextPath} />

        {isSignup && (
          <div className="field">
            <label htmlFor="name">Name</label>
            <input id="name" name="name" type="text" autoComplete="name" required />
          </div>
        )}

        <div className="field">
          <label htmlFor="email">Email</label>
          <input
            id="email"
            name="email"
            type="email"
            autoComplete="email"
            defaultValue={defaultEmail}
            required
          />
        </div>

        <div className="field">
          <label htmlFor="password">
            {isSignup ? "Password (at least 8 characters)" : "Password"}
          </label>
          <input
            id="password"
            name="password"
            type="password"
            autoComplete={isSignup ? "new-password" : "current-password"}
            minLength={isSignup ? 8 : undefined}
            required
          />
        </div>

        {state.error && (
          <p className="field-error" role="alert">
            {state.error}
          </p>
        )}

        <button className="button button-full" type="submit" disabled={pending}>
          {pending ? "Please wait..." : isSignup ? "Create account" : "Sign in"}
        </button>
      </form>

      {isSignup ? (
        <p>
          Already have an account? <Link href={`/login${nextQuery}`}>Sign in</Link>
        </p>
      ) : (
        <p>
          New here? <Link href={`/signup${nextQuery}`}>Create an account</Link>
        </p>
      )}
    </>
  );
}
