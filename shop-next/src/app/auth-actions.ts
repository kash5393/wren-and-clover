"use server";

import { redirect } from "next/navigation";
import { endSession, logIn, safeNextPath, signUp, startSession } from "@/lib/auth";
import { requestPasswordReset, resetPassword } from "@/lib/password-reset";

export interface AuthFormState {
  error: string;
}

export async function loginAction(
  _previous: AuthFormState,
  formData: FormData
): Promise<AuthFormState> {
  const result = await logIn({
    email: formData.get("email"),
    password: formData.get("password"),
  });

  if (!result.ok) {
    return { error: result.error };
  }

  await startSession(result.user.id);
  redirect(safeNextPath(formData.get("next")));
}

export async function signupAction(
  _previous: AuthFormState,
  formData: FormData
): Promise<AuthFormState> {
  const result = await signUp({
    name: formData.get("name"),
    email: formData.get("email"),
    password: formData.get("password"),
  });

  if (!result.ok) {
    return { error: result.error };
  }

  await startSession(result.user.id);
  redirect(safeNextPath(formData.get("next")));
}

export async function logoutAction(): Promise<void> {
  await endSession();
  redirect("/");
}

export interface ForgotPasswordState {
  sent: boolean;
}

export async function forgotPasswordAction(
  _previous: ForgotPasswordState,
  formData: FormData
): Promise<ForgotPasswordState> {
  await requestPasswordReset(String(formData.get("email") ?? ""));
  return { sent: true };
}

export async function resetPasswordAction(
  _previous: AuthFormState,
  formData: FormData
): Promise<AuthFormState> {
  const password = String(formData.get("password") ?? "");
  const confirm = String(formData.get("confirm") ?? "");

  if (password !== confirm) {
    return { error: "The two passwords do not match." };
  }

  const result = await resetPassword(String(formData.get("token") ?? ""), password);
  if (!result.ok) {
    return { error: result.error };
  }

  redirect("/login?reset=done");
}
